import Foundation

/// Pure pitch-detection math, kept free of AVFoundation so it can be unit
/// tested against synthetic signals without touching the microphone.
///
/// The detector here is YIN. The web prototype under `app/` still uses the
/// original autocorrelation version this project started from — treat that as
/// history rather than as the reference implementation, since the two have
/// deliberately diverged.
public enum PitchMath {
    private static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// Signal below this RMS is treated as silence and not analyzed. This is
    /// the knob behind the tuner's sensitivity setting — see
    /// `PitchDetector.Sensitivity`.
    public static let defaultMinimumRMS = 0.01

    /// Root-mean-square amplitude of the analysis window, 0...1 for normalized
    /// float samples. Drives the input level meter, and is what
    /// `yin` gates on before doing the expensive work.
    public static func rms(_ buffer: [Float], maxWindow: Int? = nil) -> Double {
        let n = min(buffer.count, maxWindow ?? buffer.count)
        guard n > 0 else { return 0 }
        // Only the first `n` samples — the analysis window — take part, so the
        // sum and the divisor stay consistent when maxWindow trims the buffer.
        var sum: Double = 0
        for i in 0..<n { sum += Double(buffer[i]) * Double(buffer[i]) }
        return (sum / Double(n)).squareRoot()
    }

    /// Maps an RMS amplitude onto 0...1 for display, on a decibel scale.
    /// Linear RMS makes a useless meter — normal playing sits in the bottom
    /// few percent of it — so this spreads `floorDB`...0 dBFS across the bar,
    /// which is how audio level meters are conventionally read.
    public static func meterLevel(rms: Double, floorDB: Double = -60) -> Double {
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return max(0, min(1, (db - floorDB) / -floorDB))
    }

    /// A YIN estimate: the pitch, plus how confidently periodic the signal was.
    public struct PitchEstimate: Equatable {
        public let frequency: Double
        /// 0...1, the complement of YIN's aperiodicity at the chosen lag.
        /// 1 is a perfectly periodic signal; noise tends toward 0. This is
        /// what "sensitivity" thresholds against — see `PitchDetector.Sensitivity`.
        public let clarity: Double
    }

    /// Lowest and highest fundamentals tracked. The violin's open G is ~196Hz
    /// and its practical top is well under 3.5kHz, so this brackets the
    /// instrument with margin while keeping the lag search small.
    static let minFrequency = 150.0
    static let maxFrequency = 3500.0

    /// YIN pitch detection (de Cheveigné & Kawahara, 2002).
    ///
    /// Chosen over plain autocorrelation because it solves two problems that
    /// matter for a bowed string. Autocorrelation's peak grows at longer lags
    /// for signals whose overtones are stronger than the fundamental — which
    /// a violin's often are — so it drops octaves; YIN's cumulative mean
    /// normalization removes that bias. And YIN yields a *confidence* value
    /// for free, so the detector can tell "no clear pitch" from "a pitch",
    /// rather than only being able to ask whether the signal was loud enough.
    ///
    /// - Parameters:
    ///   - threshold: Proportion of aperiodic power tolerated. Lower is
    ///     stricter: fewer detections, higher confidence in each. The paper's
    ///     usual working range is 0.10–0.20.
    ///   - minimumRMS: Amplitude floor, applied first so silent buffers cost
    ///     almost nothing.
    public static func yin(
        _ buffer: [Float],
        sampleRate: Double,
        maxWindow: Int? = nil,
        threshold: Double = 0.15,
        minimumRMS: Double = defaultMinimumRMS
    ) -> PitchEstimate? {
        let n = min(buffer.count, maxWindow ?? buffer.count)
        guard n > 0, sampleRate > 0 else { return nil }
        guard rms(buffer, maxWindow: maxWindow) >= minimumRMS else { return nil }

        let minTau = max(1, Int(sampleRate / maxFrequency))
        let maxTau = min(Int(sampleRate / minFrequency), n - 1)
        // The difference function compares x[j] against x[j + tau], so the
        // comparison window has to leave room for the longest lag.
        let windowSize = n - maxTau
        guard maxTau > minTau, windowSize >= 256 else { return nil }

        // Step 1: difference function.
        var diff = [Double](repeating: 0, count: maxTau + 1)
        for tau in 1...maxTau {
            var sum = 0.0
            for j in 0..<windowSize {
                let delta = Double(buffer[j]) - Double(buffer[j + tau])
                sum += delta * delta
            }
            diff[tau] = sum
        }

        // Step 2: cumulative mean normalized difference. This is what stops
        // the function drifting toward zero at long lags, which is the octave
        // error plain autocorrelation is prone to.
        var cmnd = [Double](repeating: 1, count: maxTau + 1)
        var runningSum = 0.0
        for tau in 1...maxTau {
            runningSum += diff[tau]
            cmnd[tau] = runningSum > 0 ? diff[tau] * Double(tau) / runningSum : 1
        }

        // Step 3: absolute threshold — take the *first* dip below it, not the
        // global minimum, since the global minimum is often an octave down.
        var chosenTau = -1
        var tau = minTau
        while tau <= maxTau {
            if cmnd[tau] < threshold {
                // Walk to the bottom of this dip.
                while tau + 1 <= maxTau, cmnd[tau + 1] < cmnd[tau] { tau += 1 }
                chosenTau = tau
                break
            }
            tau += 1
        }
        // Nothing periodic enough. Reported as "no pitch" rather than
        // returning the global minimum with low confidence — for a tuner,
        // showing nothing beats showing a fabricated note.
        guard chosenTau > 0 else { return nil }

        // Step 4: parabolic interpolation for sub-sample lag precision.
        var refinedTau = Double(chosenTau)
        if chosenTau > minTau, chosenTau < maxTau {
            let s0 = cmnd[chosenTau - 1]
            let s1 = cmnd[chosenTau]
            let s2 = cmnd[chosenTau + 1]
            let denom = 2 * (2 * s1 - s2 - s0)
            if denom != 0 {
                let shift = (s2 - s0) / denom
                if abs(shift) <= 1 { refinedTau += shift }
            }
        }

        let frequency = sampleRate / refinedTau
        guard frequency.isFinite, frequency >= minFrequency, frequency <= maxFrequency else { return nil }
        let clarity = max(0, min(1, 1 - cmnd[chosenTau]))
        return PitchEstimate(frequency: frequency, clarity: clarity)
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

    /// Interval between two frequencies in cents (1200 per octave).
    /// Negative = `frequency` is below `reference`, i.e. flat.
    ///
    /// Distinct from `frequencyToNote(_:).cents`, which measures against the
    /// *nearest* chromatic note. Use this when there's a specific target —
    /// the note being practised, or the string being tuned — because a badly
    /// flat A should read as a very flat A, not as a nearly in-tune G#.
    public static func cents(from frequency: Double, to reference: Double) -> Double {
        guard frequency > 0, reference > 0 else { return 0 }
        return 1200 * log2(frequency / reference)
    }
}
