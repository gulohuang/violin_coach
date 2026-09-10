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

    /// Sets the detection floors directly, bypassing the `Sensitivity`
    /// presets. The gate is read on the analysis queue and written on it, so
    /// a change lands on the next buffer without restarting the engine.
    public func setDetectionFloors(minimumClarity: Double, minimumRMS: Double) {
        objectWillChange.send()
        analysisQueue.async { [gate] in
            gate.minimumClarity = minimumClarity
            gate.minimumRMS = minimumRMS
        }
    }

    /// Applies the tunable parameters. Buffer and window are only read when
    /// the tap is installed, so changing either restarts the engine — which
    /// is why it's `async` and why the caller gets told nothing happened if
    /// the detector wasn't running.
    public func applyTuning(_ parameters: TuningParameters) async {
        let needsRestart = tapBufferFrames != parameters.tapBufferFrames
            || analysisWindow != parameters.analysisWindow
        tapBufferFrames = parameters.tapBufferFrames
        analysisWindow = parameters.analysisWindow
        setDetectionFloors(
            minimumClarity: parameters.minimumClarity,
            minimumRMS: parameters.minimumRMS
        )
        guard needsRestart, isListening else { return }
        stop()
        await start()
    }

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

    /// Frames per tap callback — the hop between analyses, so this is what
    /// sets the detection rate. Read at `start()`, because changing it means
    /// reinstalling the tap; `applyTuning` restarts for you.
    public var tapBufferFrames: Int = TuningParameters.default.tapBufferFrames

    /// Pitch detection is far too expensive to run on the main thread: YIN's
    /// difference function costs hundreds of thousands of operations per
    /// buffer, and buffers arrive ~47 times a second at the default hop.
    /// Doing that on the MainActor starved the UI badly enough that button
    /// taps and tab switches stopped registering. It doesn't belong on the
    /// tap's thread either
    /// — that's a real-time audio callback, and blocking it causes glitches —
    /// so analysis gets a queue of its own and only the result hops back.
    /// `nonisolated` because the audio tap reaches it from its own thread;
    /// a `let` of a Sendable type is safe to read from anywhere.
    private nonisolated let analysisQueue = DispatchQueue(label: "com.violincoach.pitch-analysis", qos: .userInitiated)

    /// Samples per analysis — always the newest `analysisWindow` of them,
    /// pooled across tap buffers by the ring below. More than this buys no
    /// accuracy in the violin's range, and YIN needs room for its longest
    /// lag on top. Also read at `start()`.
    public var analysisWindow: Int = TuningParameters.default.analysisWindow

    /// Accumulates the newest `analysisWindow` samples across tap callbacks,
    /// which is what lets the tap buffer (the hop) be small while the window
    /// stays long — see `SampleRing` for why that split is the fix for the
    /// pitch display trailing the instrument. Allocated once at the largest
    /// window on offer; `reset` only moves indices, so it never reallocates
    /// under a live tap.
    private nonisolated let ring = SampleRing(
        maximumWindow: TuningParameters.analysisWindowChoices.max() ?? 4096
    )

    /// Drop-if-busy gate. Buffers arriving while an analysis is in flight are
    /// dropped rather than queued: a tuner wants the *latest* reading, and an
    /// unbounded backlog is what made the original stall unrecoverable.
    ///
    /// The test-and-set has to happen **at the tap, before dispatching**, and
    /// it has to be atomic. The first version put a plain `isBusy` check
    /// *inside* the queued block, which cannot ever drop anything: the queue is
    /// serial, so by the time a block runs the previous one has already
    /// finished and cleared the flag. Every buffer was therefore queued and
    /// analysed in order, and whenever an analysis outlasted a buffer period —
    /// which a debug build easily does — the backlog grew without bound and the
    /// displayed note fell further and further behind the played one. That is
    /// the "played D4 then A4, saw D4 for three seconds" bug.
    ///
    /// A semaphore with a zero timeout is a non-blocking try-acquire, safe to
    /// call from the tap's thread; the queued block signals it when done.
    private final class AnalysisGate: @unchecked Sendable {
        private let inFlight = DispatchSemaphore(value: 1)

        /// True if this buffer may proceed; false means one is already being
        /// analysed and this buffer is discarded.
        func tryBegin() -> Bool { inFlight.wait(timeout: .now()) == .success }
        func end() { inFlight.signal() }

        /// So the buffer-size report below is printed once per run rather than
        /// a dozen times a second.
        var hasReportedBufferSize = false
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

    /// When the level meter last moved, for its time-based ballistics.
    private var lastMeterUpdate: Date?

    public init() {}

    public func start() async {
        guard !isListening else { return }

        let granted = await requestMicPermission()
        guard granted else { return }

        runToken += 1
        let token = runToken
        let window = analysisWindow
        let bufferSize = AVAudioFrameCount(max(64, tapBufferFrames))

        // Everything that can block goes to the audio queue; the main actor
        // only waits on the continuation, which doesn't hold up the run loop.
        let started = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            audioQueue.async { [engineBox, analysisQueue, gate, ring] in
                let engine = engineBox.engine
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers])
                    // The hardware I/O buffer is a floor under the tap: the
                    // tap can never fire more often than the hardware hands
                    // audio over, and the default for .playAndRecord can be
                    // ~23 ms. Ask for one hop's worth. A request, not a
                    // command — iOS clamps it to what the route supports,
                    // which is why the DEBUG line below reports what was
                    // actually granted. Failure to grant is not failure to
                    // run, hence try?.
                    let hardwareRate = max(8_000, session.sampleRate)
                    try? session.setPreferredIOBufferDuration(Double(bufferSize) / hardwareRate)
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

                #if DEBUG
                // What the *hardware* granted, which is the floor on how small
                // a tap buffer can be. `setPreferredIOBufferDuration` is a
                // request that iOS silently clamps, so the only honest source
                // for the real limits on a given device is reading them back.
                let session = AVAudioSession.sharedInstance()
                print("""
                PitchDetector: sampleRate \(sampleRate) Hz, \
                ioBufferDuration \(String(format: "%.2f", session.ioBufferDuration * 1000)) ms \
                (\(Int((session.ioBufferDuration * sampleRate).rounded())) frames), \
                requested tap \(bufferSize) frames
                """)
                #endif

                input.removeTap(onBus: 0)
                ring.reset(window: window)
                input.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
                    guard let self, let channelData = buffer.floatChannelData else { return }
                    // What the tap *actually* delivers, which is not
                    // necessarily what was asked for: `bufferSize` is a hint,
                    // and the implementation is free to pick another size —
                    // it can never go below the hardware I/O buffer above.
                    // This is the number that sets the detection rate.
                    let deliveredFrames = Int(buffer.frameLength)
                    guard deliveredFrames > 0 else { return }

                    // Every buffer lands in the ring, including ones the
                    // gate is about to drop: a dropped *analysis* is fine,
                    // but a hole in the audio is not — the next reading would
                    // describe two disjoint moments stitched together. The
                    // append is a bounded memcpy, cheap enough for the
                    // real-time audio thread this callback runs on.
                    ring.append(channelData[0], count: deliveredFrames)

                    // Dropped here, before dispatching — the only place a
                    // buffer *can* be dropped, see `AnalysisGate`.
                    guard gate.tryBegin() else { return }

                    // The newest `window` samples, which usually span several
                    // buffers — decoupling the window from the hop is what
                    // lets the hop (and so the display latency) be small.
                    // Nil only right after a start, before one full window
                    // has been heard.
                    guard let samples = ring.latest() else {
                        gate.end()
                        return
                    }

                    analysisQueue.async {
                        defer { gate.end() }

                        #if DEBUG
                        if !gate.hasReportedBufferSize {
                            gate.hasReportedBufferSize = true
                            let period = Double(deliveredFrames) / sampleRate
                            print("""
                            PitchDetector: tap delivers \(deliveredFrames) frames \
                            (\(String(format: "%.1f", period * 1000)) ms) -> \
                            \(String(format: "%.1f", 1 / period)) analyses/sec
                            """)
                        }
                        #endif

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
        lastMeterUpdate = nil

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
        // Expressed as time constants rather than per-reading fractions
        // because the reading rate is user-tunable now — fixed fractions
        // made the meter's feel change with the buffer-size slider. The
        // constants reproduce the shipped feel at the old 85 ms rate.
        let now = Date()
        let dt = min(1, lastMeterUpdate.map { now.timeIntervalSince($0) } ?? 1)
        lastMeterUpdate = now
        let target = PitchMath.meterLevel(rms: rms)
        let tau = target > level ? 0.09 : 0.52
        let smoothing = 1 - exp(-dt / tau)
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
