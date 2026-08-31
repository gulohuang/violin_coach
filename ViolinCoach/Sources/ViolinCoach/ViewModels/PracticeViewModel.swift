import Combine
import Foundation

public enum PitchDirection: Equatable {
    case tooLow
    case tooHigh
    case inTune
}

/// Tab 3: note-by-note practice. Compares the live mic pitch directly
/// against the *target* note's frequency (rather than snapping to the
/// nearest chromatic note first) so feedback stays meaningful even when
/// you're a full semitone off, and auto-advances the expected note once
/// you've held the correct pitch for a moment.
///
/// Advancing requires the right pitch *held for long enough*, where "long
/// enough" scales with the note's written duration — so a half note has to be
/// sustained and a sixteenth doesn't. Pitch alone would let you skate through
/// a slow passage at any speed you liked.
///
/// Once a note is satisfied a short gate closes — half the length that note
/// was written to sound for — before the next one starts being graded, so one
/// long bow can't be counted twice. How close counts as "the right pitch" is
/// the player's own choice, see `MatchTolerance`.
@MainActor
public final class PracticeViewModel: ObservableObject {

    /// How close to the written pitch counts as playing the note.
    ///
    /// The values are chosen against what a violinist can actually hear and
    /// control: 50 cents is "nearer this note than either neighbour", which is
    /// the loosest setting that still means anything; 20 is around where a
    /// trained ear starts calling a note out of tune in context; 10 is inside
    /// the width of an ordinary vibrato, so it demands a genuinely centred,
    /// steady note.
    public enum MatchTolerance: String, CaseIterable, Identifiable, Sendable {
        case easy, medium, hard, professional

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .easy: return "Easy"
            case .medium: return "Medium"
            case .hard: return "Hard"
            case .professional: return "Professional"
            }
        }

        /// Cents either side of the written pitch that still count as in tune.
        public var cents: Double {
            switch self {
            case .easy: return 50
            case .medium: return 35
            case .hard: return 20
            case .professional: return 10
            }
        }
    }

    @Published public private(set) var score: Score?
    @Published public private(set) var loadError: String?
    /// Index into `score.playableNotes` of the note we're waiting for. -1 = not started.
    @Published public private(set) var currentIndex = -1
    @Published public private(set) var direction: PitchDirection?
    @Published public private(set) var isComplete = false
    @Published public private(set) var isActive = false

    /// Bars chosen for repeat practice, or nil for the whole piece.
    ///
    /// Selection is by *measure* rather than by note because that is how
    /// players talk about it ("bars 5 to 8"), and it means a tap anywhere in a
    /// bar selects the whole bar rather than an arbitrary note inside it.
    @Published public private(set) var sectionMeasures: ClosedRange<Int>?
    /// True while waiting for the taps that define a section.
    @Published public private(set) var isSelectingSection = false
    /// First tap of a pending selection.
    @Published public private(set) var pendingSectionStart: Int?
    /// Times round a looping section, so the player can see it repeating.
    @Published public private(set) var loopCount = 0

    /// Tempo the sustain requirement is measured against. Slowing this down
    /// gives more time per note, which is exactly what practising slowly means.
    @Published public var tempoBPM: Double = 120
    @Published public var noteSize: ScoreRenderer.NoteSize = .mediumSmall
    /// Keep the row being practised centred on screen.
    @Published public var autoScroll = true

    /// How strict the pitch match is. The player's choice, so a beginner can
    /// get through a piece and an advanced player can be held to intonation
    /// that would actually pass in a lesson.
    @Published public var matchTolerance: MatchTolerance = .medium

    public let detector: PitchDetector

    /// How far off pitch still counts, in cents either side of the written note.
    private var centsTolerance: Double { matchTolerance.cents }

    /// Fraction of a note's written duration you must sustain it for.
    /// Demanding the full value would punish the normal gap between bows;
    /// demanding a fixed short time (the old behavior) ignored duration
    /// altogether.
    private let holdFraction = 0.6
    /// Floor and ceiling on that. The floor keeps fast notes responsive; the
    /// ceiling stops a whole note at a slow tempo from becoming a stamina test.
    private let minimumHold: TimeInterval = 0.18
    private let maximumHold: TimeInterval = 1.2
    /// A single dropped reading mid-note shouldn't restart the clock — real
    /// detection flickers, especially across a bow change.
    private let holdGrace: TimeInterval = 0.15

    /// After a note is satisfied, input is ignored for half the length that
    /// note was written to sound for.
    ///
    /// Without it a single sustained bow can satisfy two notes in a row — most
    /// obviously on a repeated pitch, where the sound that completed one note
    /// is still going and immediately completes the next. The gate makes the
    /// player re-articulate. Half the written value is the request; the clamp
    /// is so a whole note doesn't lock the screen for two seconds and a
    /// sixteenth isn't gated by a time too short to matter.
    private let refractoryFraction = 0.5
    private let minimumRefractory: TimeInterval = 0.06
    private let maximumRefractory: TimeInterval = 0.6
    /// When the gate opens. Nil means input is being accepted.
    private var acceptInputAfter: Date?

    private var holdStart: Date?
    private var lastInTuneAt: Date?
    /// Last pitch the detector reported, held so the hold clock can keep
    /// evaluating between readings — see `tickCancellable`.
    private var latestFrequency: Double?
    private var cancellable: AnyCancellable?
    /// Drives the hold clock independently of reading arrival.
    ///
    /// The hold cannot be checked only when a new pitch arrives: the detector
    /// suppresses readings identical to the last one, so a perfectly steady
    /// note would stop publishing and the hold would never complete. A ticker
    /// also keeps the progress bar moving smoothly between readings.
    private var tickCancellable: AnyCancellable?

    /// Which score is loaded, so coming back to the same piece from the folder
    /// keeps your place in it and switching pieces starts clean.
    private var loadedEntryID: String?

    public init(detector: PitchDetector = PitchDetector()) {
        self.detector = detector
        // Practice leans permissive on purpose. Here the app already knows
        // which note it's waiting for, and the cents window plus the
        // sustain requirement filter out spurious detections anyway — so the
        // cost of a marginal reading is low, while missing a real note the
        // player did sound is the failure that actually feels broken.
        detector.sensitivity = .highest
        cancellable = detector.$frequency.sink { [weak self] frequency in
            self?.handle(frequency: frequency)
        }
    }

    /// Whether `score` is this entry's — see `ScorePlayerViewModel.isLoaded`.
    public func isLoaded(_ entry: ScoreEntry) -> Bool { loadedEntryID == entry.id }

    public func load(_ entry: ScoreEntry) {
        guard loadedEntryID != entry.id else { return }
        stop()
        loadedEntryID = entry.id
        // A section, a cursor position and a loop count all belong to the
        // piece they were chosen in; carrying them into a different score
        // would point them at bars that mean something else.
        clearSection()
        currentIndex = -1
        isComplete = false
        switch ScoreLibrary.load(entry) {
        case .success(let score):
            self.score = score
            self.tempoBPM = score.tempoBPM
            loadError = nil
        case .failure(let error):
            self.score = nil
            loadError = error.localizedDescription
        }
    }

    // MARK: - Section selection

    /// Playable-note indices covered by `sectionMeasures`.
    public var sectionNoteRange: ClosedRange<Int>? {
        guard let sectionMeasures, let score else { return nil }
        let playable = score.playableNotes
        guard let first = playable.firstIndex(where: { sectionMeasures.contains($0.measureNumber) }),
              let last = playable.lastIndex(where: { sectionMeasures.contains($0.measureNumber) })
        else { return nil }
        return first...last
    }

    public var sectionLabel: String? {
        guard let sectionMeasures else { return nil }
        return sectionMeasures.lowerBound == sectionMeasures.upperBound
            ? "Bar \(sectionMeasures.lowerBound)"
            : "Bars \(sectionMeasures.lowerBound)–\(sectionMeasures.upperBound)"
    }

    /// Enters selection mode, or cancels it / clears an existing section.
    public func toggleSectionSelection() {
        if isSelectingSection {
            isSelectingSection = false
            pendingSectionStart = nil
        } else if sectionMeasures != nil {
            clearSection()
        } else {
            isSelectingSection = true
            pendingSectionStart = nil
        }
    }

    public func clearSection() {
        sectionMeasures = nil
        isSelectingSection = false
        pendingSectionStart = nil
        loopCount = 0
    }

    /// Jumps the cursor to a note, so practice can start anywhere in the piece
    /// rather than only from the top. Works whether or not practice is running:
    /// tapping mid-session moves on immediately, and tapping while stopped
    /// chooses where the next Start begins.
    ///
    /// In selection mode the same taps define a section instead — first tap
    /// sets one end, second sets the other, and the range is normalized so it
    /// doesn't matter which order they're tapped in.
    public func moveCursor(to index: Int) {
        guard let score, !score.playableNotes.isEmpty else { return }
        let clamped = max(0, min(score.playableNotes.count - 1, index))

        if isSelectingSection {
            let measure = score.playableNotes[clamped].measureNumber
            guard let start = pendingSectionStart else {
                pendingSectionStart = measure
                return
            }
            sectionMeasures = min(start, measure)...max(start, measure)
            pendingSectionStart = nil
            isSelectingSection = false
            loopCount = 0
            // Drop the cursor at the start of what was just chosen, so Start
            // begins the section rather than wherever the cursor happened to be.
            if let range = sectionNoteRange { currentIndex = range.lowerBound }
            direction = nil
            resetHold()
            // A deliberate jump isn't a note that just finished sounding, so
            // there's nothing to wait out — start listening immediately.
            acceptInputAfter = nil
            isComplete = false
            return
        }

        currentIndex = clamped
        direction = nil
        resetHold()
        acceptInputAfter = nil
        isComplete = false
    }

    public func start() {
        guard let score, !score.playableNotes.isEmpty else { return }
        if let range = sectionNoteRange {
            // A section always starts at its own beginning, wherever the
            // cursor was left.
            if !range.contains(currentIndex) { currentIndex = range.lowerBound }
        } else if currentIndex < 0 || currentIndex >= score.playableNotes.count {
            // Keeps a spot chosen by tapping the score; only falls back to the
            // beginning when no position has been picked.
            currentIndex = 0
        }
        direction = nil
        isComplete = false
        resetHold()
        acceptInputAfter = nil
        latestFrequency = nil
        loopCount = 0
        isActive = true
        tickCancellable = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
        Task { await detector.start() }
    }

    public func stop() {
        isActive = false
        tickCancellable = nil
        detector.stop()
        resetHold()
        acceptInputAfter = nil
        latestFrequency = nil
        // The cursor stays where it is rather than resetting to -1, so a spot
        // chosen by tapping — or simply where you got to — survives a stop and
        // Start resumes from there.
        direction = nil
    }

    public var expectedNote: ScoreNote? {
        guard let score, currentIndex >= 0, currentIndex < score.playableNotes.count else { return nil }
        return score.playableNotes[currentIndex]
    }

    public var expectedNoteLabel: String {
        guard let expected = expectedNote else { return "—" }
        return PitchMath.frequencyToNote(PitchMath.midiToFrequency(expected.midi, a4: detector.a4Reference), a4: detector.a4Reference).label
    }

    /// Seconds the current note must be sustained before the cursor advances.
    public var requiredHold: TimeInterval {
        guard let score, let expected = expectedNote else { return minimumHold }
        let written = score.seconds(forBeats: expected.beatsInQuarters, tempoBPM: tempoBPM)
        return min(maximumHold, max(minimumHold, written * holdFraction))
    }

    /// 0...1 progress through that hold, for the view to show a filling meter.
    /// Without this the wait on a long note just looks like nothing happening.
    public var holdProgress: Double {
        guard isActive, let holdStart else { return 0 }
        return max(0, min(1, Date().timeIntervalSince(holdStart) / requiredHold))
    }

    private func handle(frequency: Double?) {
        latestFrequency = frequency
        evaluate()
    }

    private func tick() {
        guard isActive else { return }
        objectWillChange.send() // keeps holdProgress live
        // Re-run the comparison on every tick, not only when a reading
        // arrives. Two things depend on it: the detector suppresses readings
        // identical to the last one, so a steady note stops publishing; and
        // the refractory gate opens on a clock, so nothing would notice it had
        // opened if the player were already holding the next note.
        evaluate()
        guard let holdStart, direction == .inTune else { return }
        if Date().timeIntervalSince(holdStart) >= requiredHold {
            advance()
        }
    }

    /// Compares the last known pitch against the note the cursor is on.
    private func evaluate() {
        guard isActive, let expected = expectedNote else {
            direction = nil
            resetHold()
            return
        }

        let now = Date()

        // Still inside the gap after the previous note. Report nothing rather
        // than "too high"/"too low": the player hasn't been asked for this
        // note yet, so grading them on it would be noise.
        if let gateEnd = acceptInputAfter {
            if now < gateEnd {
                direction = nil
                resetHold()
                return
            }
            acceptInputAfter = nil
        }

        guard let frequency = latestFrequency else {
            direction = nil
            resetHold()
            return
        }

        let targetFrequency = PitchMath.midiToFrequency(expected.midi, a4: detector.a4Reference)
        let cents = PitchMath.cents(from: frequency, to: targetFrequency)

        guard abs(cents) <= centsTolerance else {
            direction = cents > 0 ? .tooHigh : .tooLow
            // Only give up on the hold once the pitch has been wrong for
            // longer than the grace window, so one bad reading inside a long
            // note doesn't send the player back to the start of it.
            if let last = lastInTuneAt, now.timeIntervalSince(last) > holdGrace {
                resetHold()
            } else if lastInTuneAt == nil {
                resetHold()
            }
            objectWillChange.send()
            return
        }

        direction = .inTune
        lastInTuneAt = now
        if holdStart == nil { holdStart = now }
        // Completion is decided by the ticker, not here — see tickCancellable.
    }

    private func resetHold() {
        holdStart = nil
        lastInTuneAt = nil
    }

    /// True while the gate after a completed note is still shut. The view uses
    /// it to say why nothing is being graded rather than looking frozen.
    public var isWaitingForNextNote: Bool {
        guard let gateEnd = acceptInputAfter else { return false }
        return Date() < gateEnd
    }

    /// `direction` in the form the notation layer draws. Nothing is marked for
    /// an in-tune note: the cursor already says where you are, and a marker
    /// that's always present stops meaning anything.
    public var cursorDeviation: ScoreRenderer.CursorDeviation? {
        switch direction {
        case .tooHigh: return .sharp
        case .tooLow: return .flat
        case .inTune, nil: return nil
        }
    }

    private func advance() {
        // The gate is measured against the note being *left*: that's the one
        // still sounding, and its written length is how long it's expected to
        // go on sounding for.
        if let score, let finished = expectedNote {
            let written = score.seconds(forBeats: finished.beatsInQuarters, tempoBPM: tempoBPM)
            let gate = min(maximumRefractory, max(minimumRefractory, written * refractoryFraction))
            acceptInputAfter = Date().addingTimeInterval(gate)
        }
        resetHold()
        guard let score else { return }
        let nextIndex = currentIndex + 1

        // A chosen section loops rather than ending, which is the whole point
        // of drilling one: you play it repeatedly without reaching for a
        // button between passes.
        if let range = sectionNoteRange {
            if nextIndex > range.upperBound {
                currentIndex = range.lowerBound
                loopCount += 1
            } else {
                currentIndex = nextIndex
            }
            direction = nil
            return
        }

        if nextIndex >= score.playableNotes.count {
            currentIndex = score.playableNotes.count - 1
            isComplete = true
            isActive = false
            tickCancellable = nil
            detector.stop()
        } else {
            currentIndex = nextIndex
            direction = nil
        }
    }
}
