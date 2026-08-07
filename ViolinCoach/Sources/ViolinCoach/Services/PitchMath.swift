import Foundation

/// Pure pitch-detection math, kept free of AVFoundation so it can be unit
/// tested against synthetic sine waves without touching the microphone —
/// this is a direct port of the same algorithm already validated (12 passing
/// unit tests against synthetic violin-range sine waves) in this project's
/// web prototype at app/src/lib/pitchDetection.ts.
public enum PitchMath {
    private static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// Detects the fundamental frequency of a monophonic audio buffer via
    /// normalized autocorrelation. Returns nil when no clear periodicity is
    /// found (silence, noise, or a signal too quiet to trust).
    ///
    /// Autocorrelation (rather than FFT peak-picking) is used because a
    /// bowed string's fundamental is often weaker than its overtones, which
    /// throws off naive spectral peak detection; autocorrelation finds the
    /// lag that best repeats the whole waveform, tracking the true
    /// fundamental more reliably for sustained monophonic tones.
    public static func autoCorrelate(_ buffer: [Float], sampleRate: Double) -> Double? {
        let n = buffer.count
        guard n > 0 else { return nil }

        var rms: Double = 0
        for sample in buffer { rms += Double(sample) * Double(sample) }
        rms = (rms / Double(n)).squareRoot()
        guard rms >= 0.01 else { return nil }

        var start = 0
        var end = n - 1
        let threshold = rms * 0.2
        while start < n, abs(Double(buffer[start])) < threshold { start += 1 }
        while end > start, abs(Double(buffer[end])) < threshold { end -= 1 }

        let size = end - start + 1
        guard size >= 512 else { return nil }
        let trimmed = Array(buffer[start...end])

        let minFreq = 150.0 // below violin's open G (~196Hz), with margin
        let maxFreq = 3500.0 // above violin's practical upper range
        let minLag = Int(sampleRate / maxFreq)
        let maxLag = min(Int(sampleRate / minFreq), size - 1)
        guard maxLag > minLag else { return nil }

        var correlations = [Double](repeating: 0, count: maxLag + 1)
        for lag in minLag...maxLag {
            var sum: Double = 0
            for i in 0..<(size - lag) {
                sum += Double(trimmed[i]) * Double(trimmed[i + lag])
            }
            correlations[lag] = sum
        }

        var bestLag = -1
        var bestValue = -Double.infinity
        for lag in minLag...maxLag where correlations[lag] > bestValue {
            bestValue = correlations[lag]
            bestLag = lag
        }
        guard bestLag > minLag, bestValue > 0 else { return nil }

        // Parabolic interpolation around the peak for sub-sample lag precision.
        let y0 = correlations[bestLag - 1]
        let y1 = correlations[bestLag]
        let y2 = bestLag + 1 <= maxLag ? correlations[bestLag + 1] : y1
        let denom = 2 * (2 * y1 - y0 - y2)
        let shift = denom != 0 ? (y0 - y2) / denom : 0
        let refinedLag = Double(bestLag) + max(-1, min(1, shift))

        let frequency = sampleRate / refinedLag
        guard frequency.isFinite, frequency >= minFreq, frequency <= maxFreq else { return nil }
        return frequency
    }

    public struct NoteMatch: Equatable {
        public let midi: Int
        public let name: String
        public let octave: Int
        /// Deviation from the nearest chromatic note, in cents. Negative = flat, positive = sharp.
        public let cents: Int

        public var label: String { "\(name)\(octave)" }
    }

    public static func frequencyToNote(_ frequency: Double, a4: Double = 440) -> NoteMatch {
        let midiFloat = 69 + 12 * log2(frequency / a4)
        let midi = Int(midiFloat.rounded())
        let cents = Int(((midiFloat - Double(midi)) * 100).rounded())
        let name = noteNames[((midi % 12) + 12) % 12]
        let octave = Int(floor(Double(midi) / 12)) - 1
        return NoteMatch(midi: midi, name: name, octave: octave, cents: cents)
    }

    public static func midiToFrequency(_ midi: Int, a4: Double = 440) -> Double {
        a4 * pow(2, Double(midi - 69) / 12)
    }
}
