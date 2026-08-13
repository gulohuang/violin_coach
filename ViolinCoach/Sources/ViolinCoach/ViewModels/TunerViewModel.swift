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

    public var cents: Int {
        detector.note?.cents ?? 0
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
