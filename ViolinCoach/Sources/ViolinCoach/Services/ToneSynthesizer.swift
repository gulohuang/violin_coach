import AVFoundation

/// Renders a short, decaying, harmonically-rich tone for a given MIDI pitch
/// — reads as a plucked/bowed note rather than a flat sine beep. There's no
/// bundled sampled violin audio (keeps the app dependency-free and
/// lightweight, matching the "lightweight Violy" brief); this synth stands
/// in for it everywhere a note needs to be heard: score playback, and the
/// reference-note button in the tuner/practice tabs.
///
/// The harmonic-stack + exponential-decay approach mirrors the proven
/// pattern from the Claveo app's ShortIntervalNotePlayer (a real, published
/// SwiftUI/AVFoundation violin practice app) — decaying sine harmonics with
/// a short attack read convincingly as a plucked pitch.
public enum ToneSynthesizer {
    public static func renderBuffer(midi: Int, seconds: Double, sampleRate: Double, a4: Double = 440) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return nil }
        let frameCount = max(1, Int(sampleRate * seconds))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let channels = buffer.floatChannelData else { return nil }

        let frequency = PitchMath.midiToFrequency(midi, a4: a4)
        let harmonics: [(multiplier: Double, gain: Double)] = [
            (1, 1.0), (2, 0.35), (3, 0.15), (4, 0.08),
        ]
        let attackSeconds = 0.015
        let attackSamples = max(1, Int(sampleRate * attackSeconds))
        let releaseSeconds = min(0.12, seconds * 0.3)
        let releaseStartSample = max(attackSamples, frameCount - Int(sampleRate * releaseSeconds))

        var phase = [Double](repeating: 0, count: harmonics.count)
        let increments = harmonics.map { 2 * Double.pi * frequency * $0.multiplier / sampleRate }

        for i in 0..<frameCount {
            var sample = 0.0
            for h in 0..<harmonics.count {
                sample += sin(phase[h]) * harmonics[h].gain
                phase[h] += increments[h]
                if phase[h] >= 2 * Double.pi { phase[h] -= 2 * Double.pi }
            }
            sample *= 0.5 / Double(harmonics.count)

            let envelope: Double
            if i < attackSamples {
                envelope = Double(i + 1) / Double(attackSamples)
            } else if i > releaseStartSample {
                let releaseProgress = Double(i - releaseStartSample) / Double(max(1, frameCount - releaseStartSample))
                envelope = max(0, 1 - releaseProgress)
            } else {
                envelope = 1
            }

            let value = Float(sample * envelope)
            channels[0][i] = value
            channels[1][i] = value
        }

        return buffer
    }
}
