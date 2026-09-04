import Combine
import Foundation

/// Tab 2: scales. Holds which scale is selected and builds it as a `Score`.
///
/// Deliberately does *not* implement practice: the generated score is handed
/// to a `PracticeViewModel`, so the hold clock, the gate between notes, the
/// matching standard and the intonation bars are the same code the Practice
/// tab runs. A second copy would drift on the first change to either.
///
/// The selection is `private(set)` with explicit `select` methods rather than
/// freely writable `@Published` properties. Two of the choices constrain each
/// other — switching between major and minor respells the tonic, and a tonic
/// low enough for three octaves may not stay that way — so the changes have to
/// settle together before the score is rebuilt. A `didSet` on each property
/// would rebuild it once per assignment and could bounce between them.
@MainActor
public final class ScaleViewModel: ObservableObject {
    @Published public private(set) var root = ScaleRoot("G")
    @Published public private(set) var type: ScaleType = .major
    /// Two octaves by default: the standard scale a violinist runs daily, and
    /// what "up to the octave above and back" means in practice.
    @Published public private(set) var octaves = 2
    @Published public private(set) var direction: ScaleDirection = .ascendingDescending
    @Published public private(set) var score: Score?

    /// Playback of the scale, for hearing the target before playing it. Kept
    /// strictly exclusive with practice: the synth would otherwise sound into
    /// the microphone the detector is listening to.
    public let player: ScoreAudioPlayer
    public var a4Reference: Double = 440

    public static let defaultTempoBPM: Double = 80

    private var cancellables = Set<AnyCancellable>()

    public init(player: ScoreAudioPlayer = ScoreAudioPlayer()) {
        self.player = player
        // See TunerViewModel: a nested ObservableObject's changes don't reach
        // the object holding it, so without this relay the play button would
        // never flip to stop.
        player.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        regenerate()
    }

    // MARK: - Selection

    public var availableRoots: [ScaleRoot] { ScaleGenerator.roots(for: type) }
    public var maximumOctaves: Int { ScaleGenerator.maximumOctaves(root: root) }

    /// What the practice view model uses to tell one exercise from another, so
    /// changing key starts a clean session and coming back to the same scale
    /// keeps your place.
    public var scoreIdentity: String {
        "scale-\(root.id)-\(type.rawValue)-\(octaves)-\(direction.rawValue)"
    }

    public func select(root: ScaleRoot) {
        guard root != self.root else { return }
        self.root = root
        clampOctaves()
        regenerate()
    }

    public func select(type: ScaleType) {
        guard type != self.type else { return }
        self.type = type
        // The same pitch is spelled differently in the two modes — C♯ minor
        // against D♭ major — so the tonic is carried across by sound rather
        // than by name, and the picker never shows a key nobody writes.
        let wanted = root.pitchClass
        if let match = ScaleGenerator.roots(for: type).first(where: { $0.pitchClass == wanted }) {
            root = match
        }
        clampOctaves()
        regenerate()
    }

    public func select(octaves: Int) {
        let clamped = max(1, min(maximumOctaves, octaves))
        guard clamped != self.octaves else { return }
        self.octaves = clamped
        regenerate()
    }

    public func select(direction: ScaleDirection) {
        guard direction != self.direction else { return }
        self.direction = direction
        regenerate()
    }

    private func clampOctaves() {
        octaves = max(1, min(maximumOctaves, octaves))
    }

    private func regenerate() {
        // Rebuilding the score invalidates where playback had got to, so it
        // stops rather than carrying a cursor into a different set of notes.
        player.stop()
        score = ScaleGenerator.score(
            root: root,
            type: type,
            octaves: octaves,
            direction: direction,
            tempoBPM: Self.defaultTempoBPM
        )
    }

    // MARK: - Listening

    public var isPlaying: Bool { player.isPlaying }
    public var currentPlayableIndex: Int { player.currentIndex }

    /// Plays the scale so you can hear it. `tempoBPM` comes from the practice
    /// view model's control, so the one speed setting governs both.
    public func play(tempoBPM: Double) {
        guard let score else { return }
        if player.isPlaying {
            player.stop()
        } else {
            player.play(score: score, a4: a4Reference, tempoBPM: tempoBPM)
        }
    }

    public func stop() {
        player.stop()
    }

    // MARK: - Summary

    /// "G3 – G5 · 29 notes", so the range and length are visible before you
    /// play — which is how you tell a two-octave scale you can reach from a
    /// three-octave one you can't.
    public var rangeSummary: String? {
        guard let score,
              let first = score.playableNotes.first,
              let highest = score.playableNotes.max(by: { $0.midi < $1.midi })
        else { return nil }
        let count = score.playableNotes.count
        return "\(Self.noteName(first)) – \(Self.noteName(highest)) · \(count) notes"
    }

    private static func noteName(_ note: ScoreNote) -> String {
        let accidental: String
        switch note.alter {
        case 2: accidental = "𝄪"
        case 1: accidental = "♯"
        case -1: accidental = "♭"
        case -2: accidental = "𝄫"
        default: accidental = ""
        }
        return "\(note.step)\(accidental)\(note.octave)"
    }
}
