import AVFoundation
import Combine

/// Listens to the microphone via `AVAudioEngine` and publishes the detected
/// pitch, using `PitchMath.yin` for the actual DSP. Kept separate from
/// `PitchMath` so the math can be unit tested without touching audio hardware
/// (which XCTest can't reliably do in CI/simulator anyway).
@MainActor
public final class PitchDetector: ObservableObject {
    /// How readily the detector accepts a reading as a pitch.
    /// Defined primarily by **confidence**, not loudness. YIN reports how
    /// periodic the signal was at the chosen lag, and `minimumClarity` is how
    /// periodic it has to be before the reading counts as a note.
    ///
    /// This is a better question than the old amplitude-only gate could ask.
    /// A loud but ambiguous sound — bow scratch, two strings ringing, a chair
    /// scraping — passes any loudness test, but scores badly on periodicity
    /// and is now correctly rejected. `minimumRMS` remains as a cheap first
    /// pass so silent buffers cost almost nothing.
    public enum Sensitivity: String, CaseIterable, Identifiable, Sendable {
        case lowest, low, medium, high, highest

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .lowest: return "Lowest"
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            case .highest: return "Highest"
            }
        }

        /// How periodic a signal must be to count as a note, 0...1.
        /// Lower = more permissive = more sensitive.
        ///
        /// Values chosen by measuring YIN's clarity on a synthetic violin
        /// timbre at increasing noise levels: clean and lightly noisy signals
        /// score above 0.95, a badly degraded one around 0.34, and white noise
        /// only 0.05–0.07 — so even the loosest setting rejects noise by a
        /// wide margin.
        public var minimumClarity: Double {
            switch self {
            case .lowest: return 0.90
            case .low: return 0.78
            case .medium: return 0.65
            case .high: return 0.50
            case .highest: return 0.30
            }
        }

        /// Amplitude floor, applied before the expensive analysis.
        ///
        /// Deliberately low across the board — roughly 6-8dB below where these
        /// started. Since `minimumClarity` now does the real filtering, this
        /// only needs to skip buffers not worth analyzing at all; setting it
        /// high just makes the detector deaf to quiet playing for no benefit.
        /// The cost of lowering it is CPU on near-silent buffers, which the
        /// drop-if-busy backpressure already bounds.
        public var minimumRMS: Double {
            switch self {
            case .lowest: return 0.015   // -36.5 dBFS
            case .low: return 0.008      // -42 dBFS
            case .medium: return PitchMath.defaultMinimumRMS // 0.004, -48 dBFS
            case .high: return 0.002     // -54 dBFS
            case .highest: return 0.001  // -60 dBFS, the meter floor
            }
        }

        public var detail: String {
            switch self {
            case .lowest: return "Only clear, strong notes. Best in a noisy room."
            case .low: return "Strict. Rejects most bow noise."
            case .medium: return "Balanced for normal practice."
            case .high: return "Picks up faint playing."
            case .highest: return "Most responsive. May track bow noise between notes."
            }
        }
    }

    @Published public private(set) var frequency: Double?
    @Published public private(set) var note: PitchMath.NoteMatch?
    @Published public private(set) var isListening = false
    @Published public var a4Reference: Double = 440

    /// Input level, 0...1 on a decibel scale, smoothed for display.
    @Published public private(set) var level: Double = 0

    /// How confidently periodic the last accepted reading was, 0...1.
    /// Distinct from `level`: a loud bow scratch is high level, low clarity.
    @Published public private(set) var clarity: Double = 0

    public var sensitivity: Sensitivity = .medium {
        didSet {
            guard sensitivity != oldValue else { return }
            objectWillChange.send()
            // Written on the same serial queue that reads it, which is what
            // keeps the gate's `@unchecked` conformance honest.
            let rmsFloor = sensitivity.minimumRMS
            let clarityFloor = sensitivity.minimumClarity
            analysisQueue.async { [gate] in
                gate.minimumRMS = rmsFloor
                gate.minimumClarity = clarityFloor
            }
        }
    }

    /// The engine lives off the main actor. `AVAudioSession.setActive`,
    /// `AVAudioEngine.prepare()` and `.start()` are synchronous CoreAudio
    /// calls that routinely block for hundreds of milliseconds — longer the
    /// first time, while the hardware route is set up. Running them on the
    /// main thread froze the UI on every button press.
    ///
    /// Only ever touched on `audioQueue`, which is serial; that discipline is
    /// what makes the `@unchecked` conformance honest.
    private final class EngineBox: @unchecked Sendable {
        let engine = AVAudioEngine()
    }

    private nonisolated let engineBox = EngineBox()
    private nonisolated let audioQueue = DispatchQueue(label: "com.violincoach.audio-engine")
    private let bufferSize: AVAudioFrameCount = 4096

    /// Pitch detection is far too expensive to run on the main thread: YIN's
    /// difference function costs hundreds of thousands of operations per
    /// buffer, and buffers arrive ~12 times a second. Doing that on the
    /// MainActor starved the UI badly enough that tab switches and button
    /// taps stopped registering. It doesn't belong on the tap's thread either
    /// — that's a real-time audio callback, and blocking it causes glitches —
    /// so analysis gets a queue of its own and only the result hops back.
    /// `nonisolated` because the audio tap reaches it from its own thread;
    /// a `let` of a Sendable type is safe to read from anywhere.
    private nonisolated let analysisQueue = DispatchQueue(label: "com.violincoach.pitch-analysis", qos: .userInitiated)

    /// Samples analyzed per buffer. More than this buys no accuracy in the
    /// violin's range, and YIN needs room for its longest lag on top.
    private let analysisWindow = 2048

    /// Drop-if-busy flag. Buffers arriving while an analysis is in flight are
    /// dropped rather than queued: a tuner wants the *latest* reading, and an
    /// unbounded backlog is what made the original stall unrecoverable.
    ///
    /// It lives off the actor in a box because it is touched from
    /// `analysisQueue`, not the main thread. That queue is serial, so every
    /// access to `isBusy` is already serialized with respect to every other —
    /// which is what makes the `@unchecked` conformance honest rather than a
    /// papering-over.
    private final class AnalysisGate: @unchecked Sendable {
        var isBusy = false
        /// Mirrors `sensitivity.minimumRMS`. Kept here so a change takes
        /// effect on the next buffer without tearing down and restarting the
        /// engine — the tap closure captures the gate, not the value.
        var minimumRMS = PitchMath.defaultMinimumRMS
        var minimumClarity = 0.65
    }

    private nonisolated let gate = AnalysisGate()

    /// Incremented on every start/stop. Results carrying a stale token are
    /// discarded, so readings dispatched before a stop can't write themselves
    /// back after it — the reason Stop appeared to do nothing.
    private var runToken = 0

    public init() {}

    public func start() async {
        guard !isListening else { return }

        let granted = await requestMicPermission()
        guard granted else { return }

        runToken += 1
        let token = runToken
        let window = analysisWindow
        let bufferSize = self.bufferSize

        // Everything that can block goes to the audio queue; the main actor
        // only waits on the continuation, which doesn't hold up the run loop.
        let started = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            audioQueue.async { [engineBox, analysisQueue, gate] in
                let engine = engineBox.engine
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers])
                    try session.setActive(true)
                } catch {
                    #if DEBUG
                    print("PitchDetector: failed to configure audio session: \(error)")
                    #endif
                    continuation.resume(returning: false)
                    return
                }

                let input = engine.inputNode
                let format = input.outputFormat(forBus: 0)
                guard format.sampleRate > 0 else {
                    continuation.resume(returning: false)
                    return
                }
                // Read off the format up front: AVAudioFormat is a reference
                // type, and capturing it in the tap closure would drag a
                // non-Sendable class across a concurrency boundary.
                let sampleRate = format.sampleRate

                input.removeTap(onBus: 0)
                input.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
                    guard let self, let channelData = buffer.floatChannelData else { return }
                    // Keep this callback cheap — it runs on a real-time audio
                    // thread. Copy what's needed and get off it immediately.
                    let frameCount = min(Int(buffer.frameLength), window)
                    let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))

                    analysisQueue.async {
                        guard !gate.isBusy else { return } // drop, don't queue
                        gate.isBusy = true
                        defer { gate.isBusy = false }

                        // The level meter reads the raw input, so it's
                        // computed regardless of whether the gate lets the
                        // pitch analysis proceed — that's what lets the meter
                        // show signal arriving while sensitivity is set too
                        // low to detect it.
                        let rms = PitchMath.rms(samples, maxWindow: window)
                        let estimate = PitchMath.yin(
                            samples,
                            sampleRate: sampleRate,
                            maxWindow: window,
                            minimumClarity: gate.minimumClarity,
                            minimumRMS: gate.minimumRMS
                        )
                        Task { @MainActor in
                            self.publish(estimate: estimate, rms: rms, token: token)
                        }
                    }
                }

                do {
                    engine.prepare()
                    try engine.start()
                    continuation.resume(returning: true)
                } catch {
                    #if DEBUG
                    print("PitchDetector: failed to start engine: \(error)")
                    #endif
                    input.removeTap(onBus: 0)
                    continuation.resume(returning: false)
                }
            }
        }

        // A stop may have landed while the engine was spinning up.
        guard token == runToken else { return }
        isListening = started
    }

    public func stop() {
        guard isListening else { return }
        // Published state changes right now so the button flips immediately —
        // the user should never wait on CoreAudio to see a tap register.
        // Bumping the token first also invalidates analyses already in flight,
        // so none of them can repopulate the readout after this.
        runToken += 1
        isListening = false
        frequency = nil
        note = nil
        level = 0
        clarity = 0

        // Teardown is the slow part; let it happen off the main thread.
        audioQueue.async { [engineBox] in
            engineBox.engine.inputNode.removeTap(onBus: 0)
            engineBox.engine.stop()
        }
    }

    /// Applies a completed analysis, ignoring anything from a previous run.
    private func publish(estimate: PitchMath.PitchEstimate?, rms: Double, token: Int) {
        guard token == runToken, isListening else { return }

        // Meter ballistics: rise quickly so an attack registers, fall slowly
        // so the bar stays readable instead of flickering between buffers.
        let target = PitchMath.meterLevel(rms: rms)
        let smoothing = target > level ? 0.6 : 0.15
        let newLevel = level + (target - level) * smoothing
        if abs(newLevel - level) > 0.005 { level = newLevel }

        guard let estimate else {
            if frequency != nil { frequency = nil }
            if note != nil { note = nil }
            if clarity != 0 { clarity = 0 }
            return
        }
        let detected = estimate.frequency
        if abs(estimate.clarity - clarity) > 0.02 { clarity = estimate.clarity }

        let match = PitchMath.frequencyToNote(detected, a4: a4Reference)
        // Every assignment to a @Published fires objectWillChange, which the
        // view models relay and SwiftUI turns into a re-render. Skip readings
        // that would render identically. Compare on what's actually shown —
        // the note (name, octave, whole-number cents) and the frequency at the
        // one decimal place the readout displays — so nothing visible goes
        // stale, which comparing the note alone would have allowed.
        let sameNote = note == match
        let sameDisplayedHz = frequency.map { ($0 * 10).rounded() == (detected * 10).rounded() } ?? false
        guard !(sameNote && sameDisplayedHz) else { return }

        frequency = detected
        note = match
    }

    private func requestMicPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted:
                continuation.resume(returning: true)
            case .denied:
                continuation.resume(returning: false)
            case .undetermined:
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            @unknown default:
                continuation.resume(returning: false)
            }
        }
    }
}
