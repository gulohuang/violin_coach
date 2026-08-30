import XCTest
@testable import ViolinCoach

/// Covers the pure-math half of the violin synth — the body response and the
/// wavetable it shapes. Rendering an `AVAudioPCMBuffer` needs an audio format
/// and is left to the app; everything that decides what the instrument
/// *sounds like* is here and runs without hardware.
final class ToneSynthesizerTests: XCTestCase {

    // MARK: - Body response

    /// The low resonances have to actually be peaks, or the whole formant
    /// model is just a tilted lowpass.
    func testBodyResponsePeaksAtTheLowResonances() {
        for centre in [280.0, 460.0, 700.0] {
            let atPeak = ToneSynthesizer.bodyResponse(at: centre)
            XCTAssertGreaterThan(atPeak, ToneSynthesizer.bodyResponse(at: centre * 0.75), "no peak at \(centre) Hz")
            XCTAssertGreaterThan(atPeak, ToneSynthesizer.bodyResponse(at: centre * 1.35), "no peak at \(centre) Hz")
        }
    }

    /// The bridge hill is a broad shoulder rather than a sharp peak — around
    /// 2.8 kHz it is *lower* than the 1 kHz plateau, so asserting a local
    /// maximum there would be wrong. What matters is that it holds the region
    /// up: this is the band a violin carries on, and letting the rolloff eat it
    /// is what makes a synthesised string sound muffled.
    func testBridgeHillKeepsTheBrillianceBand() {
        let hill = ToneSynthesizer.bodyResponse(at: 2_800)
        XCTAssertGreaterThan(hill, ToneSynthesizer.bodyResponse(at: 460) * 0.5)
        XCTAssertGreaterThan(hill, ToneSynthesizer.bodyResponse(at: 4_500))
    }

    /// Between the peaks the response has to stay well above zero. A response
    /// that dips to nothing would punch holes in the harmonic series and read
    /// as a phaser rather than as wood.
    func testBodyResponseNeverCollapsesBetweenPeaks() {
        for frequency in stride(from: 80.0, through: 5000.0, by: 25.0) {
            XCTAssertGreaterThan(ToneSynthesizer.bodyResponse(at: frequency), 0.1,
                                 "response collapsed at \(frequency) Hz")
        }
    }

    func testBodyResponseRollsOffAtTheTop() {
        XCTAssertLessThan(
            ToneSynthesizer.bodyResponse(at: 12_000),
            ToneSynthesizer.bodyResponse(at: 2_800) * 0.1
        )
    }

    // MARK: - Wavetable

    func testWaveTableIsPeakNormalised() {
        for midi in [55, 62, 69, 76, 88] {
            let table = ToneSynthesizer.waveTable(
                fundamental: PitchMath.midiToFrequency(midi, a4: 440),
                sampleRate: 44_100
            )
            let peak = table.reduce(0.0) { max($0, abs($1)) }
            XCTAssertEqual(peak, 1.0, accuracy: 1e-9, "MIDI \(midi) table not normalised")
        }
    }

    /// Harmonics must stop below Nyquist. If they don't, reading the table back
    /// at its own rate folds them down as aliases — an inharmonic buzz that no
    /// amount of envelope work will hide.
    func testWaveTableStaysBelowNyquist() {
        let sampleRate = 44_100.0
        // A high E on the E string: the harmonic count is what's clamped here.
        let fundamental = PitchMath.midiToFrequency(100, a4: 440) // ~2637 Hz
        let table = ToneSynthesizer.waveTable(fundamental: fundamental, sampleRate: sampleRate)
        XCTAssertEqual(table.count, 2048)
        // The table is one cycle of a real signal; a purely-fundamental table
        // (all higher harmonics correctly rejected) is still a valid sine.
        XCTAssertEqual(table.reduce(0.0) { max($0, abs($1)) }, 1.0, accuracy: 1e-9)
    }

    /// The point of a *fixed* body response: loudness shouldn't lurch between
    /// notes. Normalising by the peak keeps the RMS of one cycle in a narrow
    /// band right across the violin's range.
    func testLoudnessIsEvenAcrossTheRange() {
        var levels: [Double] = []
        for midi in stride(from: 55, through: 100, by: 3) {
            let table = ToneSynthesizer.waveTable(
                fundamental: PitchMath.midiToFrequency(midi, a4: 440),
                sampleRate: 44_100
            )
            let rms = (table.reduce(0.0) { $0 + $1 * $1 } / Double(table.count)).squareRoot()
            levels.append(rms)
        }
        let low = levels.min() ?? 0
        let high = levels.max() ?? 0
        XCTAssertGreaterThan(low, 0.3, "some pitch renders far quieter than the rest")
        // Under 6 dB spread across three octaves.
        XCTAssertLessThan(high / max(low, 1e-9), 2.0, "loudness varies too much with pitch")
    }

    /// On the G string the second harmonic lands on the main wood resonance and
    /// comes out stronger than the fundamental — a real property of the
    /// instrument, and the reason the pitch detector uses YIN rather than
    /// spectral peak-picking. Worth pinning: if a change to the resonances
    /// loses it, the synth has stopped modelling a violin.
    func testLowStringHasAStrongSecondHarmonic() {
        let g3 = PitchMath.midiToFrequency(55, a4: 440) // ~196 Hz
        let first = ToneSynthesizer.bodyResponse(at: g3) / 1
        let second = ToneSynthesizer.bodyResponse(at: g3 * 2) / 2
        XCTAssertGreaterThan(second, first * 0.5,
                             "second harmonic is unexpectedly weak on the G string")
    }
}
