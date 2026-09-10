import XCTest
@testable import ViolinCoach

/// Covers the decoding rules that protect an already-saved settings blob —
/// the two ways `TuningStore` could silently hand the detector a value that
/// stops it working.
final class TuningParametersTests: XCTestCase {

    private func decode(_ json: String) throws -> TuningParameters {
        try JSONDecoder().decode(TuningParameters.self, from: Data(json.utf8))
    }

    func testRoundTripsThroughJSON() throws {
        var parameters = TuningParameters.default
        parameters.centsTolerance = 22
        parameters.tapBufferFrames = 2048
        let data = try JSONEncoder().encode(parameters)
        XCTAssertEqual(try JSONDecoder().decode(TuningParameters.self, from: data), parameters)
    }

    /// The synthesized initializer threw on any missing key, which
    /// `TuningStore`'s `try?` turned into "discard every setting" — so adding
    /// one parameter reset all of them.
    func testMissingKeysKeepTheirDefaultsRatherThanFailing() throws {
        let parameters = try decode(#"{"centsTolerance": 12}"#)
        XCTAssertEqual(parameters.centsTolerance, 12)
        XCTAssertEqual(parameters.minimumHold, TuningParameters.default.minimumHold)
        XCTAssertEqual(parameters.tapBufferFrames, TuningParameters.default.tapBufferFrames)
    }

    /// 512 was an offered analysis window until it turned out YIN's own guard
    /// rejects it on every buffer. A blob saved back then must not resurrect a
    /// permanently silent detector.
    func testRetiredAnalysisWindowSnapsToTheNearestOffered() throws {
        let parameters = try decode(#"{"analysisWindow": 512}"#)
        XCTAssertEqual(parameters.analysisWindow, 1024)
        XCTAssertTrue(TuningParameters.analysisWindowChoices.contains(parameters.analysisWindow))
    }

    func testStoredSizesAlwaysLandOnASliderPosition() throws {
        let parameters = try decode(#"{"tapBufferFrames": 3000, "analysisWindow": 5000}"#)
        XCTAssertTrue(TuningParameters.bufferSizeChoices.contains(parameters.tapBufferFrames))
        XCTAssertTrue(TuningParameters.analysisWindowChoices.contains(parameters.analysisWindow))
        XCTAssertEqual(parameters.tapBufferFrames, 2048)
        XCTAssertEqual(parameters.analysisWindow, 4096)
    }

    /// Every offered window must leave YIN room for its longest lag plus the
    /// 256 samples it compares over, at both sample rates iOS hands us.
    func testEveryOfferedWindowIsUsableByYIN() {
        for sampleRate in [44_100.0, 48_000.0] {
            let maxTau = Int(sampleRate / PitchMath.minFrequency)
            for window in TuningParameters.analysisWindowChoices {
                XCTAssertGreaterThanOrEqual(
                    window - maxTau, 256,
                    "a \(window)-sample window leaves YIN nothing to compare at \(sampleRate) Hz"
                )
            }
        }
    }

    /// The default hop is what the user feels as detection latency.
    func testDefaultHopIsShortEnoughToFeelLive() {
        let parameters = TuningParameters.default
        let hopMilliseconds = Double(parameters.tapBufferFrames) / 48_000 * 1000
        XCTAssertLessThan(hopMilliseconds, 25, "the tap hop is the floor on how stale a reading can be")
        XCTAssertTrue(TuningParameters.bufferSizeChoices.contains(parameters.tapBufferFrames))
    }
}
