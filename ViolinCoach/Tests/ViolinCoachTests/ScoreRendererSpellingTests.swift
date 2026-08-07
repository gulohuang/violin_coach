import XCTest
@testable import ViolinCoach

/// Tests the pure MIDI -> staff-key-spelling math in isolation, without
/// touching VexFoundation's actual rendering (which needs a live
/// RenderContext this project can't construct/verify outside Xcode).
final class ScoreRendererSpellingTests: XCTestCase {
    func testNaturalNotesHaveNoAccidental() {
        // C4, D4, E4, F4, G4, A4, B4
        for midi in [60, 62, 64, 65, 67, 69, 71] {
            let spelling = ScoreRenderer.staffKeySpec(forMidi: midi)
            XCTAssertNil(spelling.accidental, "MIDI \(midi) should be natural")
        }
    }

    func testSharpsSpelledFromLowerNaturalLetter() {
        // F#4 (MIDI 66) should be spelled as F#, not Gb.
        let fSharp = ScoreRenderer.staffKeySpec(forMidi: 66)
        XCTAssertEqual(fSharp.accidental, .sharp)
        XCTAssertEqual(fSharp.key.rawValue, "f#/4")
    }

    func testViolinOpenStringOctaves() {
        // G3 (open G string, MIDI 55) and A4 (open A string, MIDI 69).
        XCTAssertEqual(ScoreRenderer.staffKeySpec(forMidi: 55).key.rawValue, "g/3")
        XCTAssertEqual(ScoreRenderer.staffKeySpec(forMidi: 69).key.rawValue, "a/4")
    }

    func testMiddleCIsC4() {
        XCTAssertEqual(ScoreRenderer.staffKeySpec(forMidi: 60).key.rawValue, "c/4")
    }

    func testEFAndBCHaveNoAccidentalGap() {
        // E4->F4 and B4->C5 are natural half-steps with no sharp between them.
        XCTAssertNil(ScoreRenderer.staffKeySpec(forMidi: 64).accidental) // E4
        XCTAssertNil(ScoreRenderer.staffKeySpec(forMidi: 65).accidental) // F4
        XCTAssertNil(ScoreRenderer.staffKeySpec(forMidi: 71).accidental) // B4
        XCTAssertNil(ScoreRenderer.staffKeySpec(forMidi: 72).accidental) // C5
    }
}
