import Combine
import Foundation

/// View-facing wrapper around `PitchDetector` for Tab 1 (the tuner). Keeps
/// the "is this in tune" threshold and display formatting out of the view.
@MainActor
public final class TunerViewModel: ObservableObject {
    public let detector: PitchDetector
    /// Cents within which a note is considered "in tune" (matches the
    /// tolerance violin-adventure's play-along mode uses for the same judgment).
    public static let inTuneCentsThreshold = 10

    private var cancellables = Set<AnyCancellable>()

    public init(detector: PitchDetector = PitchDetector()) {
        self.detector = detector
        // A nested ObservableObject does not propagate its changes to the
        // object holding it: SwiftUI subscribes to this view model's
        // objectWillChange, not the detector's. Without this relay the view
        // renders once and then never updates, so the tuner looks frozen even
        // though pitch detection is running fine underneath.
        detector.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Detector passthrough
    //
    // Views go through these rather than reaching into `detector` directly,
    // per the layering rule in CLAUDE.md (no view touches a Service except
    // through its ViewModel). `a4Reference` also needs to be settable *on
    // this object* for SwiftUI to form a binding — `detector` is a `let`, so
    // `$viewModel.detector.a4Reference` cannot produce a writable key path.

    public var a4Reference: Double {
        get { detector.a4Reference }
        set { detector.a4Reference = newValue }
    }

    public var isListening: Bool {
        detector.isListening
    }

    /// MIDI number of the detected pitch, if any — used to highlight the
    /// nearest open string.
    public var detectedMIDI: Int? {
        detector.note?.midi
    }

    public func stop() {
        detector.stop()
    }

    public var noteLabel: String {
        detector.note?.label ?? "—"
    }

    public var frequencyLabel: String {
        guard let frequency = detector.frequency else { return "" }
        return String(format: "%.1f Hz", frequency)
    }

    // MARK: - Reference string

    /// One of the four open violin strings, for locking the tuner to a
    /// specific target instead of chromatic auto-detection.
    public struct OpenString: Identifiable, Equatable, Sendable {
        public let name: String
        public let midi: Int
        public var id: Int { midi }
    }

    public static let openStrings: [OpenString] = [
        OpenString(name: "G", midi: 55),
        OpenString(name: "D", midi: 62),
        OpenString(name: "A", midi: 69),
        OpenString(name: "E", midi: 76),
    ]

    /// The string being tuned, or nil for chromatic auto-detect (the default).
    @Published public private(set) var targetMIDI: Int?

    /// Tapping the selected string again clears it and returns to auto-detect.
    public func selectString(midi: Int) {
        targetMIDI = (targetMIDI == midi) ? nil : midi
    }

    public var targetFrequency: Double? {
        targetMIDI.map { PitchMath.midiToFrequency($0, a4: detector.a4Reference) }
    }

    public var targetLabel: String? {
        guard let targetMIDI, let targetFrequency else { return nil }
        let label = PitchMath.frequencyToNote(
            PitchMath.midiToFrequency(targetMIDI, a4: detector.a4Reference),
            a4: detector.a4Reference
        ).label
        return String(format: "Tuning to %@ · %.1f Hz", label, targetFrequency)
    }

    /// Nearest open string to what's sounding, within three semitones — a hint
    /// in auto mode, so the row still orients you when nothing is locked.
    public var nearestStringMIDI: Int? {
        guard let detected = detectedMIDI else { return nil }
        let nearest = Self.openStrings.min {
            abs($0.midi - detected) < abs($1.midi - detected)
        }
        guard let nearest, abs(nearest.midi - detected) <= 3 else { return nil }
        return nearest.midi
    }

    // MARK: - Readings

    /// Deviation in cents. Measured against the locked string when there is
    /// one, so a badly flat A reads as a very flat A rather than snapping to a
    /// nearly in-tune G#; otherwise against the nearest chromatic note.
    public var cents: Int {
        guard let targetFrequency, let frequency = detector.frequency else {
            return detector.note?.cents ?? 0
        }
        return Int(PitchMath.cents(from: frequency, to: targetFrequency).rounded())
    }

    public var hasSignal: Bool {
        detector.note != nil
    }

    public var isInTune: Bool {
        hasSignal && abs(cents) <= Self.inTuneCentsThreshold
    }

    public func toggleListening() {
        if detector.isListening {
            detector.stop()
        } else {
            Task { [detector] in await detector.start() }
        }
    }
}
