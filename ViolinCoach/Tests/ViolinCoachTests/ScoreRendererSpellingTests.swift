import CoreGraphics
import XCTest
@testable import ViolinCoach

/// Tests ScoreRenderer's pure math — pitch spelling and tap hit-testing — in
/// isolation, without touching VexFoundation's actual rendering (which needs a
/// live RenderContext this project can't construct/verify outside Xcode).
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

    // MARK: - Tap-to-move hit testing

    /// 11 measures of four quarter notes, shaped like the bundled sample.
    private func makeScore(measures: Int = 11) -> Score {
        var notes: [ScoreNote] = []
        var id = 0
        for measure in 1...measures {
            for _ in 0..<4 {
                notes.append(ScoreNote(
                    id: id, isRest: false, midi: 62 + (id % 5),
                    beatsInQuarters: 1, typeName: "quarter", dots: 0,
                    measureNumber: measure
                ))
                id += 1
            }
        }
        return Score(title: "T", fifths: 2, beatsPerMeasure: 4, beatType: 4, tempoBPM: 120, notes: notes)
    }

    /// Tapping the centre of each measure must land on a note in that measure.
    /// This is the round-trip between `draw`'s placement and `playableIndex`'s
    /// inverse of it — the two derive from shared arithmetic, and an off-by-one
    /// in either would show up here.
    func testTapOnEachMeasureResolvesToThatMeasure() {
        let score = makeScore()
        let metrics = ScoreRenderer.Metrics()
        let playable = score.playableNotes

        for width in [345.0, 430.0] {
            let plan = ScoreRenderer.rowPlan(
                measureCount: score.measures.count,
                availableWidth: width,
                metrics: metrics
            )
            for (i, measure) in score.measures.enumerated() {
                let row = i / plan.measuresPerRow
                let column = i % plan.measuresPerRow
                let rowPrefix = metrics.rowPrefixWidth + (row == 0 ? metrics.firstRowExtraWidth : 0)
                let measureWidth = (plan.contentWidth - rowPrefix) / Double(plan.measuresPerRow)
                let x = metrics.horizontalMargin + rowPrefix + Double(column) * measureWidth + measureWidth / 2
                let y = metrics.topMargin + Double(row) * (metrics.rowHeight + metrics.rowGap) + metrics.rowHeight / 2

                guard let index = ScoreRenderer.playableIndex(
                    at: CGPoint(x: x, y: y),
                    score: score,
                    availableWidth: width,
                    metrics: metrics
                ) else {
                    XCTFail("no note found for measure \(measure.number) at width \(width)")
                    continue
                }
                XCTAssertEqual(
                    playable[index].measureNumber, measure.number,
                    "tap on measure \(measure.number) resolved into measure \(playable[index].measureNumber) at width \(width)"
                )
            }
        }
    }

    func testTapAboveTheStaffResolvesToNothing() {
        let score = makeScore()
        XCTAssertNil(ScoreRenderer.playableIndex(
            at: CGPoint(x: 200, y: -80),
            score: score,
            availableWidth: 345
        ))
    }

    func testTapBeyondTheLastRowClampsToTheScore() {
        let score = makeScore()
        let index = ScoreRenderer.playableIndex(
            at: CGPoint(x: 200, y: 100_000),
            score: score,
            availableWidth: 345
        )
        XCTAssertNotNil(index)
        // Clamped into range rather than running off the end.
        XCTAssertLessThan(index ?? .max, score.playableNotes.count)
    }

    func testTapInTheClefAreaBelongsToTheFirstMeasureOfTheRow() {
        let score = makeScore()
        let metrics = ScoreRenderer.Metrics()
        // x inside the leading clef/key-signature block, before any notes.
        let index = ScoreRenderer.playableIndex(
            at: CGPoint(x: metrics.horizontalMargin + 4, y: metrics.topMargin + metrics.rowHeight / 2),
            score: score,
            availableWidth: 345,
            metrics: metrics
        )
        XCTAssertEqual(score.playableNotes[index ?? 0].measureNumber, 1)
    }

    func testEFAndBCHaveNoAccidentalGap() {
        // E4->F4 and B4->C5 are natural half-steps with no sharp between them.
        XCTAssertNil(ScoreRenderer.staffKeySpec(forMidi: 64).accidental) // E4
        XCTAssertNil(ScoreRenderer.staffKeySpec(forMidi: 65).accidental) // F4
        XCTAssertNil(ScoreRenderer.staffKeySpec(forMidi: 71).accidental) // B4
        XCTAssertNil(ScoreRenderer.staffKeySpec(forMidi: 72).accidental) // C5
    }
}
