import AVFoundation
import Foundation

/// Renders a bowed-violin tone for a given MIDI pitch. Used everywhere a note
/// needs to be heard: score playback, and the reference note in the tuner.
///
/// There is no sampled violin in the bundle — a usable multi-sampled library
/// is tens of megabytes and several licences, against a brief that asks for a
/// lightweight app. So this synthesises one, and the shape of the synthesis is
/// what makes it read as a violin rather than as an organ:
///
/// - **A sawtooth spectrum, not a handful of harmonics.** A bowed string moves
///   in Helmholtz motion, whose spectrum is very close to a sawtooth: every
///   harmonic present, falling off as 1/n. The previous four-harmonic stack
///   was the main reason it sounded synthetic.
/// - **Fixed body resonances, not a fixed harmonic shape.** The violin's tone
///   comes from a wooden box whose resonances sit at the *same frequencies*
///   whatever note you play — the A0 air mode near 280 Hz, the main wood modes
///   around 460 and 700 Hz, and the broad "bridge hill" near 2.8 kHz that
///   gives the instrument its carrying brilliance. Weighting each harmonic by
///   where it happens to land in that fixed response is what makes a low G and
///   a high E sound like one instrument. It also reproduces something real:
///   on the G string the second harmonic comes out *stronger than the
///   fundamental*, because 392 Hz sits on the main wood resonance. That is
///   exactly the timbre `PitchMath` uses YIN to handle.
/// - **A slow attack.** ~55 ms, against the 15 ms it had. A bow takes time to
///   set a string going, and a fast attack is what makes a synth sound plucked.
/// - **Vibrato that fades in.** ±16 cents at 5.5 Hz, arriving after the note
///   has spoken, as a player's does.
/// - **A breath of bow noise** in the attack only — the scrape before the
///   string catches.
///
/// Rendering is a wavetable read rather than a per-sample sum of sines: one
/// cycle is built once per pitch (and cached), then read back with a moving
/// rate, which is both far cheaper and exactly how vibrato should behave —
/// every harmonic shifts together.
public enum ToneSynthesizer {

    // MARK: - Timbre

    /// Violin body resonances as (centre frequency, Q, gain). Approximate but
    /// in the right places; the point is that they're fixed in absolute
    /// frequency, which is what a resonating box does.
    private static let bodyResonances: [(frequency: Double, q: Double, gain: Double)] = [
        (280, 6.0, 1.00),   // A0 — the air (Helmholtz) resonance
        (460, 7.0, 0.90),   // B1- — main wood resonance
        (700, 5.0, 0.70),
        (1300, 3.0, 0.55),
        (2800, 1.3, 1.10),  // the "bridge hill" — broad, and where the carrying power lives
    ]

    /// Response between the peaks never reaches zero on a real instrument, so
    /// neither does this.
    private static let responseFloor = 0.22
    /// Gentle top-end rolloff. Without it the highest harmonics of a low note
    /// are harsh rather than bright.
    private static let rolloffHz = 6500.0

    private static let maxHarmonics = 40
    private static let tableLength = 2048

    private static let vibratoRateHz = 5.5
    private static let vibratoCents = 16.0
    /// Vibrato starts after the note has spoken, not from the first sample.
    private static let vibratoOnset = 0.18
    private static let vibratoRamp = 0.25

    private static let attackSeconds = 0.055
    private static let releaseSeconds = 0.09
    private static let bowNoiseGain = 0.030
    /// Headroom. Verified against the modelled render: peak lands at ~0.62.
    private static let outputPeak = 0.60

    /// Body response at a given frequency: a floor plus a Lorentzian peak per
    /// resonance, rolled off at the top.
    static func bodyResponse(at frequency: Double) -> Double {
        var gain = responseFloor
        for resonance in bodyResonances {
            let halfWidth = resonance.frequency / resonance.q
            let x = (frequency - resonance.frequency) / halfWidth
            gain += resonance.gain / (1 + x * x)
        }
        return gain / (1 + pow(frequency / rolloffHz, 2))
    }

    // MARK: - Wavetable

    /// Cached one-cycle tables, keyed by pitch. The same handful of notes
    /// recur constantly in a piece, and building a table is ~80k `sin` calls —
    /// worth doing once. Guarded by a lock because playback renders on its own
    /// queue while the tuner may render on another.
    private final class TableCache: @unchecked Sendable {
        private let lock = NSLock()
        private var tables: [Key: [Double]] = [:]

        struct Key: Hashable {
            let midi: Int
            let a4Millicents: Int
            let sampleRate: Int
        }

        func table(for key: Key, build: () -> [Double]) -> [Double] {
            lock.lock()
            if let cached = tables[key] {
                lock.unlock()
                return cached
            }
            lock.unlock()

            // Built outside the lock: it's pure computation, and two threads
            // racing to build the same table is cheaper than either waiting.
            let table = build()

            lock.lock()
            // A piece has a few dozen distinct pitches; the bound is only here
            // so a long session can't grow this without limit.
            if tables.count > 256 { tables.removeAll() }
            tables[key] = table
            lock.unlock()
            return table
        }
    }

    private static let cache = TableCache()

    /// One cycle of the bowed-string spectrum for this fundamental, peak
    /// normalised. Harmonics stop below Nyquist, so reading the table back at
    /// its own rate cannot alias.
    static func waveTable(fundamental: Double, sampleRate: Double) -> [Double] {
        var amplitudes: [(harmonic: Int, gain: Double)] = []
        var n = 1
        while n <= maxHarmonics && Double(n) * fundamental < 0.45 * sampleRate {
            // 1/n is the sawtooth (Helmholtz) falloff; the body response then
            // shapes it.
            amplitudes.append((n, bodyResponse(at: Double(n) * fundamental) / Double(n)))
            n += 1
        }
        guard !amplitudes.isEmpty else { return [Double](repeating: 0, count: tableLength) }

        var table = [Double](repeating: 0, count: tableLength)
        for i in 0..<tableLength {
            var sample = 0.0
            for entry in amplitudes {
                sample += entry.gain * sin(2 * Double.pi * Double(entry.harmonic) * Double(i) / Double(tableLength))
            }
            table[i] = sample
        }

        // Peak normalisation, not sum-of-gains: it keeps loudness even across
        // the range, since how the harmonics happen to line up in phase varies
        // with which resonances a pitch lands on.
        let peak = table.reduce(0.0) { max($0, abs($1)) }
        guard peak > 0 else { return table }
        return table.map { $0 / peak }
    }

    // MARK: - Rendering

    public static func renderBuffer(midi: Int, seconds: Double, sampleRate: Double, a4: Double = 440) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return nil }
        let frameCount = max(1, Int(sampleRate * seconds))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let channels = buffer.floatChannelData else { return nil }

        let frequency = PitchMath.midiToFrequency(midi, a4: a4)
        let key = TableCache.Key(
            midi: midi,
            a4Millicents: Int((a4 * 100).rounded()),
            sampleRate: Int(sampleRate.rounded())
        )
        let table = cache.table(for: key) { waveTable(fundamental: frequency, sampleRate: sampleRate) }
        guard table.count == tableLength else { return nil }

        // A sixteenth at a brisk tempo is shorter than the attack and release
        // want to be, so both are clamped to a share of the note rather than
        // being allowed to overlap and swallow the sustain.
        let attackFrames = max(1, min(Int(sampleRate * attackSeconds), frameCount / 3))
        let releaseFrames = max(1, min(Int(sampleRate * releaseSeconds), frameCount - attackFrames))
        let releaseStart = frameCount - releaseFrames

        var phase = 0.0
        var previousNoise = 0.0
        var noiseState = UInt64(0x2545_F491_4F6C_DD1D)
        let tableCount = Double(tableLength)

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate

            // Vibrato: ramped in, and applied as a *rate* change so every
            // harmonic moves with the fundamental, as it does on a string.
            let onset = max(0, min(1, (t - vibratoOnset) / vibratoRamp))
            let depth = (vibratoCents / 1200.0) * onset
            let rateRatio = pow(2, depth * sin(2 * Double.pi * vibratoRateHz * t))
            let increment = frequency * rateRatio * tableCount / sampleRate

            let index = Int(phase)
            let fraction = phase - Double(index)
            let a = table[index % tableLength]
            let b = table[(index + 1) % tableLength]
            var sample = a * (1 - fraction) + b * fraction

            phase += increment
            // A loop, not an `if`: one subtraction is enough at any sane
            // sample rate, but the index below reads `table[Int(phase)]` and a
            // single wrap that didn't finish would be an out-of-bounds crash.
            while phase >= tableCount { phase -= tableCount }

            var envelope: Double
            if i < attackFrames {
                // Smoothstep rather than linear — a bow's swell has no corner
                // at either end of it.
                let p = Double(i + 1) / Double(attackFrames)
                envelope = p * p * (3 - 2 * p)
            } else if i >= releaseStart {
                let p = Double(i - releaseStart) / Double(releaseFrames)
                envelope = (1 - p) * (1 - p)
            } else {
                envelope = 1
            }
            // The bow arm is never perfectly steady, and the small amplitude
            // wobble that rides with vibrato is part of why it sounds played.
            envelope *= 1 + 0.03 * sin(2 * Double.pi * vibratoRateHz * t + 1.2)

            // Bow noise: the scrape before the string catches. Deterministic
            // (xorshift) so a note renders identically every time, and
            // differenced to push it up out of the fundamental's way.
            noiseState ^= noiseState << 13
            noiseState ^= noiseState >> 7
            noiseState ^= noiseState << 17
            let white = Double(noiseState % 20001) / 10000.0 - 1.0
            let highPassed = white - previousNoise
            previousNoise = white
            let scratch = highPassed * bowNoiseGain * max(0, 1 - t / (attackSeconds * 2.5))

            sample = (sample * envelope + scratch) * outputPeak
            let value = Float(sample)
            channels[0][i] = value
            channels[1][i] = value
        }

        return buffer
    }
}
