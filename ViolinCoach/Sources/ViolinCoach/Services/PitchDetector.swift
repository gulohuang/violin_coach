import AVFoundation
import Combine

/// Listens to the microphone via `AVAudioEngine` and publishes the detected
/// pitch, using `PitchMath.autoCorrelate` for the actual DSP. Kept separate
/// from `PitchMath` so the math can be unit tested without touching audio
/// hardware (which XCTest can't reliably do in CI/simulator anyway).
@MainActor
public final class PitchDetector: ObservableObject {
    @Published public private(set) var frequency: Double?
    @Published public private(set) var note: PitchMath.NoteMatch?
    @Published public private(set) var isListening = false
    @Published public var a4Reference: Double = 440

    private let engine = AVAudioEngine()
    private let bufferSize: AVAudioFrameCount = 4096

    /// Autocorrelation is far too expensive to run on the main thread: at
    /// 48kHz a 4096-frame buffer costs on the order of a million
    /// multiply-adds, and buffers arrive ~12 times a second. Doing that on the
    /// MainActor starved the UI badly enough that tab switches and button
    /// taps stopped registering. It doesn't belong on the tap's thread either
    /// — that's a real-time audio callback, and blocking it causes glitches —
    /// so analysis gets a queue of its own and only the result hops back.
    /// `nonisolated` because the audio tap reaches it from its own thread;
    /// a `let` of a Sendable type is safe to read from anywhere.
    private nonisolated let analysisQueue = DispatchQueue(label: "com.violincoach.pitch-analysis", qos: .userInitiated)

    /// Samples analyzed per buffer. See `PitchMath.autoCorrelate(_:sampleRate:maxWindow:)`
    /// — more than this buys no accuracy in the violin's range.
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

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("PitchDetector: failed to configure audio session: \(error)")
            #endif
            return
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }

        runToken += 1
        let token = runToken
        let window = analysisWindow
        // Read off the format up front: AVAudioFormat is a reference type, and
        // capturing it in the tap closure would drag a non-Sendable class
        // across a concurrency boundary. A Double crosses cleanly.
        let sampleRate = format.sampleRate

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            guard let self, let channelData = buffer.floatChannelData else { return }
            // Keep this callback cheap — it runs on a real-time audio thread.
            // Copy the samples we need and get off it immediately.
            let frameCount = min(Int(buffer.frameLength), window)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))

            self.analysisQueue.async {
                guard !self.gate.isBusy else { return } // drop, don't queue
                self.gate.isBusy = true
                defer { self.gate.isBusy = false }

                let detected = PitchMath.autoCorrelate(samples, sampleRate: sampleRate, maxWindow: window)
                Task { @MainActor in
                    self.publish(frequency: detected, token: token)
                }
            }
        }

        do {
            engine.prepare()
            try engine.start()
            isListening = true
        } catch {
            #if DEBUG
            print("PitchDetector: failed to start engine: \(error)")
            #endif
        }
    }

    public func stop() {
        guard isListening else { return }
        // Bumping the token first invalidates any analysis already dispatched,
        // so an in-flight reading can't repopulate the display after this.
        runToken += 1
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isListening = false
        frequency = nil
        note = nil
    }

    /// Applies a completed analysis, ignoring anything from a previous run.
    private func publish(frequency detected: Double?, token: Int) {
        guard token == runToken, isListening else { return }

        guard let detected else {
            if frequency != nil { frequency = nil }
            if note != nil { note = nil }
            return
        }

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
