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

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            guard let self, let channelData = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
            let sampleRate = format.sampleRate
            Task { @MainActor in
                self.process(samples: samples, sampleRate: sampleRate)
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
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isListening = false
        frequency = nil
        note = nil
    }

    private func process(samples: [Float], sampleRate: Double) {
        guard let detected = PitchMath.autoCorrelate(samples, sampleRate: sampleRate) else {
            frequency = nil
            note = nil
            return
        }
        frequency = detected
        note = PitchMath.frequencyToNote(detected, a4: a4Reference)
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
