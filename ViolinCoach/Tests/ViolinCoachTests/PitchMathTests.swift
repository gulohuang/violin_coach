import Foundation
import XCTest
@testable import ViolinCoach

/// Direct port of the test cases already validated against the web
/// prototype's TypeScript pitch-detection module (app/src/lib/pitchDetection.test.ts,
/// 12 passing tests) — same synthetic-sine-wave methodology, same tolerances.
final class PitchMathTests: XCTestCase {
    let sampleRate = 44100.0

    func generateSineWave(frequency: Double, seconds: Double) -> [Float] {
        let n = Int(sampleRate * seconds)
        return (0..<n).map { i in
            Float(0.8 * sin(2 * Double.pi * frequency * Double(i) / sampleRate))
        }
    }

    func testReturnsNilForSilence() {
        let buffer = [Float](repeating: 0, count: 4096)
        XCTAssertNil(PitchMath.yin(buffer, sampleRate: sampleRate))
    }

    func testReturnsNilForQuietNoise() {
        let buffer = (0..<4096).map { _ in Float.random(in: -0.0025...0.0025) }
        XCTAssertNil(PitchMath.yin(buffer, sampleRate: sampleRate))
    }

    /// Loud but aperiodic. An amplitude gate alone would let this through and
    /// report a fabricated note; YIN's periodicity test is what rejects it.
    func testRejectsLoudWhiteNoise() {
        var generator = SystemRandomNumberGenerator()
        let buffer = (0..<4096).map { _ in Float.random(in: -0.8...0.8, using: &generator) }
        XCTAssertNil(PitchMath.yin(buffer, sampleRate: sampleRate))
    }

    func testDetectsOpenG3() { assertDetects(196.0, tolerance: 0.01) }
    func testDetectsOpenD4() { assertDetects(293.66, tolerance: 0.01) }
    func testDetectsOpenA4() { assertDetects(440.0, tolerance: 0.01) }
    func testDetectsOpenE5() { assertDetects(659.25, tolerance: 0.01) }
    func testDetectsG4FirstFingerOnDString() { assertDetects(392.0, tolerance: 0.01) }

    private func assertDetects(_ frequency: Double, tolerance: Double, file: StaticString = #filePath, line: UInt = #line) {
        let buffer = generateSineWave(frequency: frequency, seconds: 0.1)
        guard let estimate = PitchMath.yin(buffer, sampleRate: sampleRate) else {
            XCTFail("expected to detect \(frequency)Hz but got nil", file: file, line: line)
            return
        }
        let detected = estimate.frequency
        XCTAssertGreaterThan(estimate.clarity, 0.9, "a pure tone should be near-perfectly periodic", file: file, line: line)
        let relativeError = abs(detected - frequency) / frequency
        XCTAssertLessThan(relativeError, tolerance, "detected \(detected)Hz, expected close to \(frequency)Hz", file: file, line: line)
    }

    func testA4IsExactlyInTune() {
        let match = PitchMath.frequencyToNote(440)
        XCTAssertEqual(match.name, "A")
        XCTAssertEqual(match.octave, 4)
        XCTAssertEqual(match.cents, 0)
    }

    func testTwentyCentsSharp() {
        let sharp = 440 * pow(2, 20.0 / 1200)
        let match = PitchMath.frequencyToNote(sharp)
        XCTAssertEqual(match.name, "A")
        XCTAssertEqual(match.cents, 20)
    }

    func testTwentyCentsFlat() {
        let flat = 440 * pow(2, -20.0 / 1200)
        let match = PitchMath.frequencyToNote(flat)
        XCTAssertEqual(match.name, "A")
        XCTAssertEqual(match.cents, -20)
    }

    func testRoundTripsThroughMidiToFrequency() {
        let match = PitchMath.frequencyToNote(PitchMath.midiToFrequency(69))
        XCTAssertEqual(match.label, "A4")
    }

    // MARK: - rms / meterLevel / sensitivity

    func testRMSOfSilenceIsZero() {
        XCTAssertEqual(PitchMath.rms([Float](repeating: 0, count: 1024)), 0, accuracy: 0.0001)
    }

    func testRMSOfFullScaleSineIsAboutRootHalf() {
        // A unit-amplitude sine has RMS 1/sqrt(2).
        let buffer = (0..<4410).map { Float(sin(2 * Double.pi * 440 * Double($0) / sampleRate)) }
        XCTAssertEqual(PitchMath.rms(buffer), 1 / 2.0.squareRoot(), accuracy: 0.01)
    }

    func testRMSHonoursMaxWindow() {
        // Loud first half, silent second: windowing to the first half must
        // report the loud level, not the average of both.
        var buffer = [Float](repeating: 0.5, count: 1024)
        buffer.append(contentsOf: [Float](repeating: 0, count: 1024))
        XCTAssertEqual(PitchMath.rms(buffer, maxWindow: 1024), 0.5, accuracy: 0.0001)
        XCTAssertEqual(PitchMath.rms(buffer), 0.5 / 2.0.squareRoot(), accuracy: 0.01)
    }

    func testMeterLevelSpansTheDecibelFloor() {
        XCTAssertEqual(PitchMath.meterLevel(rms: 0), 0, accuracy: 0.0001)          // silence
        XCTAssertEqual(PitchMath.meterLevel(rms: 1), 1, accuracy: 0.0001)          // 0 dBFS
        XCTAssertEqual(PitchMath.meterLevel(rms: 0.001), 0, accuracy: 0.0001)      // -60 dBFS, at the floor
        XCTAssertEqual(PitchMath.meterLevel(rms: 0.0001), 0, accuracy: 0.0001)     // below the floor, clamped
        // Halfway up the bar is -30 dBFS, not half the amplitude — the point
        // of using a decibel scale.
        XCTAssertEqual(PitchMath.meterLevel(rms: pow(10, -30.0 / 20)), 0.5, accuracy: 0.0001)
    }

    // @MainActor because Sensitivity is nested inside the @MainActor
    // PitchDetector, and nested types inherit that isolation.
    @MainActor
    func testSensitivityThresholdsAreOrderedAsLabelled() {
        // "High" must mean a *lower* amplitude gate, or the control is backwards.
        XCTAssertGreaterThan(
            PitchDetector.Sensitivity.low.minimumRMS,
            PitchDetector.Sensitivity.medium.minimumRMS
        )
        XCTAssertGreaterThan(
            PitchDetector.Sensitivity.medium.minimumRMS,
            PitchDetector.Sensitivity.high.minimumRMS
        )
        // Medium preserves the behavior the detector had before the setting existed.
        XCTAssertEqual(PitchDetector.Sensitivity.medium.minimumRMS, PitchMath.defaultMinimumRMS)

        // All five levels, on both knobs, must move monotonically with the
        // label: more sensitive means both a lower clarity requirement and a
        // lower loudness floor.
        let ordered = PitchDetector.Sensitivity.allCases
        XCTAssertEqual(ordered.count, 5)
        for (a, b) in zip(ordered, ordered.dropFirst()) {
            XCTAssertGreaterThan(a.minimumClarity, b.minimumClarity, "\(a.label) -> \(b.label)")
            XCTAssertGreaterThan(a.minimumRMS, b.minimumRMS, "\(a.label) -> \(b.label)")
        }
    }

    func testMinimumRMSGatesDetection() {
        // A quiet tone: detected when the gate is permissive, rejected when not.
        let quiet = (0..<4410).map { Float(0.02 * sin(2 * Double.pi * 440 * Double($0) / sampleRate)) }
        XCTAssertNotNil(PitchMath.yin(quiet, sampleRate: sampleRate, minimumRMS: 0.003))
        XCTAssertNil(PitchMath.yin(quiet, sampleRate: sampleRate, minimumRMS: 0.030))
    }

    /// The reason for moving to YIN. A bowed string's fundamental is often
    /// weaker than its overtones; plain autocorrelation reports the stronger
    /// partial and lands an octave (or a twelfth) high.
    func testTracksFundamentalWhenOvertonesDominate() {
        for fundamental in [196.0, 293.66, 440.0] {
            let n = 4410
            var buffer = (0..<n).map { i -> Float in
                let t = Double(i) / sampleRate
                return Float(
                    0.25 * sin(2 * Double.pi * fundamental * t)       // weak fundamental
                    + 1.00 * sin(2 * Double.pi * 2 * fundamental * t)
                    + 0.80 * sin(2 * Double.pi * 3 * fundamental * t)
                    + 0.50 * sin(2 * Double.pi * 4 * fundamental * t)
                )
            }
            let peak = buffer.map { abs($0) }.max() ?? 1
            buffer = buffer.map { $0 / peak * 0.8 }

            guard let estimate = PitchMath.yin(buffer, sampleRate: sampleRate) else {
                XCTFail("no pitch detected for \(fundamental)Hz timbre")
                continue
            }
            let ratio = estimate.frequency / fundamental
            XCTAssertEqual(ratio, 1.0, accuracy: 0.01, "expected the fundamental, got ratio \(ratio)")
        }
    }

    /// The bug this replaced: without YIN's global-minimum fallback, a signal
    /// whose CMNDF never dips below the paper's 0.15 threshold was reported as
    /// "no pitch" — which is most real playing through a real microphone. The
    /// fallback must find the pitch, and clarity must then decide.
    func testNoisyToneStillDetectedViaGlobalMinimumFallback() {
        var generator = SystemRandomNumberGenerator()
        let target = 440.0
        let buffer = (0..<4410).map { i -> Float in
            let t = Double(i) / sampleRate
            let tone = 0.8 * sin(2 * Double.pi * target * t)
            return Float(tone + Double.random(in: -0.22...0.22, using: &generator))
        }
        guard let estimate = PitchMath.yin(buffer, sampleRate: sampleRate, minimumClarity: 0.3) else {
            XCTFail("noisy tone should still be detected through the fallback")
            return
        }
        XCTAssertEqual(estimate.frequency / target, 1.0, accuracy: 0.02)
        // Degraded, but nowhere near the noise floor.
        XCTAssertGreaterThan(estimate.clarity, 0.3)
    }

    func testClarityGateControlsStrictness() {
        // Ordering is the invariant: a stricter gate must never accept
        // something a looser one rejected.
        let tone = generateSineWave(frequency: 440, seconds: 0.1)
        XCTAssertNotNil(PitchMath.yin(tone, sampleRate: sampleRate, minimumClarity: 0.9))
        XCTAssertNotNil(PitchMath.yin(tone, sampleRate: sampleRate, minimumClarity: 0.3))
        // A clarity gate of 1.0 is unreachable in practice; nothing should pass.
        XCTAssertNil(PitchMath.yin(tone, sampleRate: sampleRate, minimumClarity: 1.01))
    }

    // MARK: - cents(from:to:)

    func testCentsIsZeroAtTheReference() {
        XCTAssertEqual(PitchMath.cents(from: 440, to: 440), 0, accuracy: 0.0001)
    }

    func testOneOctaveIs1200Cents() {
        XCTAssertEqual(PitchMath.cents(from: 880, to: 440), 1200, accuracy: 0.0001)
        XCTAssertEqual(PitchMath.cents(from: 220, to: 440), -1200, accuracy: 0.0001)
    }

    func testCentsSignsFollowDirection() {
        XCTAssertGreaterThan(PitchMath.cents(from: 445, to: 440), 0) // sharp
        XCTAssertLessThan(PitchMath.cents(from: 435, to: 440), 0)    // flat
    }

    /// The distinction that motivates this helper: measured against a specific
    /// target, a very flat A stays a very flat A instead of collapsing to a
    /// nearly in-tune G# the way nearest-note matching would report it.
    func testFlatNoteMeasuresFarFromItsTargetNotNearItsNeighbour() {
        let a4 = PitchMath.midiToFrequency(69)
        let veryFlatA = a4 * pow(2, -80.0 / 1200) // 80 cents flat
        XCTAssertEqual(PitchMath.cents(from: veryFlatA, to: a4), -80, accuracy: 0.01)
        // Nearest-note matching would call the same pitch a near-in-tune G#.
        XCTAssertEqual(PitchMath.frequencyToNote(veryFlatA).name, "G#")
    }

    func testCentsHandlesNonPositiveInputSafely() {
        XCTAssertEqual(PitchMath.cents(from: 0, to: 440), 0)
        XCTAssertEqual(PitchMath.cents(from: 440, to: 0), 0)
    }

    func testLabelsViolinOpenStringsCorrectly() {
        XCTAssertEqual(PitchMath.frequencyToNote(196.0).label, "G3")
        XCTAssertEqual(PitchMath.frequencyToNote(293.66).label, "D4")
        XCTAssertEqual(PitchMath.frequencyToNote(440.0).label, "A4")
        XCTAssertEqual(PitchMath.frequencyToNote(659.25).label, "E5")
    }
}
