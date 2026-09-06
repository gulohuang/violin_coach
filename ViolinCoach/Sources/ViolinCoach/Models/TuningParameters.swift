import Foundation

/// Every constant that decides how note-by-note detection *feels*, gathered
/// into one value type so the Fine Tune tab can drive them live.
///
/// These were `private let`s scattered across `PitchDetector` and
/// `PracticeViewModel`. They still have exactly the same defaults — see
/// `TuningParameters.default`, which is the behaviour the app shipped with —
/// but they're now settable, because the right value for a bow, a room and a
/// device can't be found by reasoning about it in a container with no
/// microphone. It has to be dialled in against a real violin.
///
/// A plain `Codable` struct rather than a pile of `UserDefaults` keys: the
/// whole set round-trips as one blob, so adding a parameter can't leave a
/// half-migrated state behind.
public struct TuningParameters: Equatable, Sendable, Codable {

    // MARK: - Detection

    /// Frames the microphone tap delivers per callback — the hop between
    /// analyses, and so the thing that sets the detection rate:
    /// `sampleRate / tapBufferFrames` analyses per second.
    ///
    /// Bigger is *slower*: 4096 frames at 48 kHz is 85 ms, about 12 readings a
    /// second. It's a request, not a guarantee — the hardware I/O buffer is a
    /// floor under it, and the tap may hand back a different size.
    public var tapBufferFrames: Int = 4096

    /// Samples each analysis actually looks at.
    ///
    /// Capped below `tapBufferFrames` today, which means anything beyond this
    /// in each buffer is discarded. 2048 samples is ~43 ms — about six periods
    /// of the lowest note YIN looks for, so more buys no accuracy in the
    /// violin's range.
    public var analysisWindow: Int = 2048

    /// How periodic a signal must be to count as a note, 0...1. This is the
    /// real sensitivity control; the RMS floor below is only an early-out.
    public var minimumClarity: Double = 0.30

    /// Amplitude floor, applied before the expensive analysis.
    public var minimumRMS: Double = 0.001

    // MARK: - Matching

    /// Cents either side of the written pitch that count as in tune. The
    /// `MatchTolerance` presets write into this; the slider is the fine control.
    public var centsTolerance: Double = 35

    // MARK: - Hold

    /// Fraction of a note's written duration it must be sustained for.
    public var holdFraction: Double = 0.6
    /// Floor on that, so fast notes stay responsive.
    public var minimumHold: TimeInterval = 0.18
    /// Ceiling, so a whole note at a slow tempo isn't a stamina test.
    public var maximumHold: TimeInterval = 1.2
    /// How long a wrong or missing reading is forgiven before the hold clock
    /// restarts — real detection flickers across a bow change.
    public var holdGrace: TimeInterval = 0.15

    // MARK: - Gate between notes

    /// Fraction of the completed note's written length to ignore input for,
    /// so one sustained bow can't satisfy two notes in a row.
    public var refractoryFraction: Double = 0.5
    public var minimumRefractory: TimeInterval = 0.06
    public var maximumRefractory: TimeInterval = 0.6

    public init() {}

    /// The values the app shipped with. `Reset` on the Fine Tune tab restores
    /// exactly this, so a session of experimenting can always be undone.
    public static let `default` = TuningParameters()

    // MARK: - Derived

    /// Analyses per second at a given sample rate — what the buffer slider is
    /// really choosing, and the number worth showing next to it.
    public func analysesPerSecond(sampleRate: Double) -> Double {
        guard tapBufferFrames > 0, sampleRate > 0 else { return 0 }
        return sampleRate / Double(tapBufferFrames)
    }

    /// Sizes the buffer slider steps through. Powers of two because that's
    /// what CoreAudio deals in; anything else is rounded by the system anyway.
    public static let bufferSizeChoices = [512, 1024, 2048, 4096, 8192]
    public static let analysisWindowChoices = [512, 1024, 2048, 4096]
}
