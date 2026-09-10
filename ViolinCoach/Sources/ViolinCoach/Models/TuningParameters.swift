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
    /// `sampleRate / tapBufferFrames` analyses per second. Since every
    /// reading is only as fresh as the buffer that triggered it, this is
    /// also the detector's share of the display latency.
    ///
    /// Bigger is *slower*: 4096 frames at 48 kHz was 85 ms between readings,
    /// which read as the pitch display trailing the instrument. 1024 is
    /// ~21 ms, comfortably under what feels laggy — affordable because
    /// `SampleRing` pools buffers, so shrinking the hop no longer shrinks
    /// the analysis window below. It's a request, not a guarantee — the
    /// hardware I/O buffer is a floor under it, and the tap may hand back a
    /// different size.
    public var tapBufferFrames: Int = 1024

    /// Samples each analysis actually looks at — always the newest this-many,
    /// pooled across tap buffers by `SampleRing`, so it's independent of
    /// `tapBufferFrames`. 2048 samples is ~43 ms — about six periods of the
    /// lowest note YIN looks for, so more buys no accuracy in the violin's
    /// range. It is also an honest floor on latency: a reading is the
    /// average pitch over this span, whatever the hop.
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

    /// Decodes leniently, and clamps the two sizes to the choices actually on
    /// offer. Both matter for a store that has already been written to disk:
    ///
    /// - A key added after a blob was saved decodes to its default instead of
    ///   throwing. The synthesized initializer throws on *any* missing key,
    ///   which `TuningStore`'s `try?` turns into "discard every setting" — so
    ///   adding one parameter silently reset all twelve.
    /// - A value saved when the choice list was wider is snapped back into it.
    ///   `analysisWindow` was offered at 512 until it turned out YIN reserves
    ///   ~320 samples for its longest lag and wants 256 more to compare over:
    ///   a 512-sample window fails that guard on every buffer, so anyone who
    ///   had dialled it there would keep a permanently silent detector across
    ///   launches, with the slider showing a value it no longer held.
    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decode<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            guard let decoded = try? container.decodeIfPresent(T.self, forKey: key) else { return fallback }
            return decoded ?? fallback
        }
        tapBufferFrames = Self.nearest(decode(.tapBufferFrames, tapBufferFrames), in: Self.bufferSizeChoices)
        analysisWindow = Self.nearest(decode(.analysisWindow, analysisWindow), in: Self.analysisWindowChoices)
        minimumClarity = decode(.minimumClarity, minimumClarity)
        minimumRMS = decode(.minimumRMS, minimumRMS)
        centsTolerance = decode(.centsTolerance, centsTolerance)
        holdFraction = decode(.holdFraction, holdFraction)
        minimumHold = decode(.minimumHold, minimumHold)
        maximumHold = decode(.maximumHold, maximumHold)
        holdGrace = decode(.holdGrace, holdGrace)
        refractoryFraction = decode(.refractoryFraction, refractoryFraction)
        minimumRefractory = decode(.minimumRefractory, minimumRefractory)
        maximumRefractory = decode(.maximumRefractory, maximumRefractory)
    }

    /// The offered size closest to `value`, so a stored setting lands on a
    /// slider position rather than between two.
    static func nearest(_ value: Int, in choices: [Int]) -> Int {
        choices.min { abs($0 - value) < abs($1 - value) } ?? value
    }

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
    public static let bufferSizeChoices = [256, 512, 1024, 2048, 4096, 8192]
    /// No 512 here: YIN reserves ~320 samples for its longest lag and wants
    /// a 256-sample comparison window on top, so a 512-sample window fails
    /// its own guard on every buffer — the detector goes permanently silent,
    /// which on the Fine Tune tab looked like a slider that killed the mic.
    public static let analysisWindowChoices = [1024, 2048, 4096]
}
