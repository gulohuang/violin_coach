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
        XCTAssertNil(PitchMath.autoCorrelate(buffer, sampleRate: sampleRate))
    }

    func testReturnsNilForQuietNoise() {
        let buffer = (0..<4096).map { _ in Float.random(in: -0.0025...0.0025) }
        XCTAssertNil(PitchMath.autoCorrelate(buffer, sampleRate: sampleRate))
    }

    func testDetectsOpenG3() { assertDetects(196.0, tolerance: 0.01) }
    func testDetectsOpenD4() { assertDetects(293.66, tolerance: 0.01) }
    func testDetectsOpenA4() { assertDetects(440.0, tolerance: 0.01) }
    func testDetectsOpenE5() { assertDetects(659.25, tolerance: 0.01) }
    func testDetectsG4FirstFingerOnDString() { assertDetects(392.0, tolerance: 0.01) }

    private func assertDetects(_ frequency: Double, tolerance: Double, file: StaticString = #filePath, line: UInt = #line) {
        let buffer = generateSineWave(frequency: frequency, seconds: 0.1)
        guard let detected = PitchMath.autoCorrelate(buffer, sampleRate: sampleRate) else {
            XCTFail("expected to detect \(frequency)Hz but got nil", file: file, line: line)
            return
        }
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
