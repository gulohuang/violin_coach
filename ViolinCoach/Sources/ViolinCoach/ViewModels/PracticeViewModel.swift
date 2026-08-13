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
/// The cents tolerance and stable-reading count mirror the values already
/// proven out in this project's violin-adventure-derived web research
/// (±38 cents, ~3 consecutive in-tune analyses ≈ 100–150ms of held pitch):
/// loose enough not to punish natural bow/vibrato wobble, tight enough to
/// mean something, and short enough to feel responsive rather than laggy.
@MainActor
public final class PracticeViewModel: ObservableObject {
    @Published public private(set) var score: Score?
    @Published public private(set) var loadError: String?
    /// Index into `score.playableNotes` of the note we're waiting for. -1 = not started.
    @Published public private(set) var currentIndex = -1
    @Published public private(set) var direction: PitchDirection?
    @Published public private(set) var isComplete = false
    @Published public private(set) var isActive = false

    public let detector: PitchDetector

    private let centsTolerance = 38.0
    private let requiredStableReadings = 3

    private var stableCount = 0
    private var cancellable: AnyCancellable?

    public init(detector: PitchDetector = PitchDetector()) {
        self.detector = detector
        load()
        cancellable = detector.$frequency.sink { [weak self] frequency in
            self?.handle(frequency: frequency)
        }
    }

    public func load() {
        switch ScoreLibrary.loadBundledSample() {
        case .success(let score):
            self.score = score
            loadError = nil
        case .failure(let error):
            loadError = error.localizedDescription
        }
    }

    public func start() {
        guard let score, !score.playableNotes.isEmpty else { return }
        currentIndex = 0
        direction = nil
        isComplete = false
        stableCount = 0
        isActive = true
        Task { await detector.start() }
    }

    public func stop() {
        isActive = false
        detector.stop()
        currentIndex = -1
        direction = nil
        stableCount = 0
    }

    public var expectedNote: ScoreNote? {
        guard let score, currentIndex >= 0, currentIndex < score.playableNotes.count else { return nil }
        return score.playableNotes[currentIndex]
    }

    public var expectedNoteLabel: String {
        guard let expected = expectedNote else { return "—" }
        return PitchMath.frequencyToNote(PitchMath.midiToFrequency(expected.midi, a4: detector.a4Reference), a4: detector.a4Reference).label
    }

    private func handle(frequency: Double?) {
        guard isActive, let expected = expectedNote, let frequency else {
            direction = nil
            stableCount = 0
            return
        }

        let targetFrequency = PitchMath.midiToFrequency(expected.midi, a4: detector.a4Reference)
        let cents = PitchMath.cents(from: frequency, to: targetFrequency)

        if cents > centsTolerance {
            direction = .tooHigh
            stableCount = 0
        } else if cents < -centsTolerance {
            direction = .tooLow
            stableCount = 0
        } else {
            direction = .inTune
            stableCount += 1
            if stableCount >= requiredStableReadings {
                advance()
            }
        }
    }

    private func advance() {
        stableCount = 0
        guard let score else { return }
        let nextIndex = currentIndex + 1
        if nextIndex >= score.playableNotes.count {
            currentIndex = score.playableNotes.count - 1
            isComplete = true
            isActive = false
            detector.stop()
        } else {
            currentIndex = nextIndex
            direction = nil
        }
    }
}
