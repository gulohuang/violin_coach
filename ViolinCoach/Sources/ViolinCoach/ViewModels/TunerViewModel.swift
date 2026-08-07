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

    public init(detector: PitchDetector = PitchDetector()) {
        self.detector = detector
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
            Task { await detector.start() }
        }
    }
}
