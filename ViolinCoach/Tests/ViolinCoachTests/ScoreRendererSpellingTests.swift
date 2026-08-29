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

    // MARK: - Key-signature-aware accidentals

    /// The bug this prevents: deriving accidentals from alteration alone put a
    /// sharp on all 40 F naturals in the Gavotte, which is in G major.
    func testAccidentalOmittedWhenTheKeySignatureAlreadyCoversIt() {
        // G major: one sharp, on F.
        XCTAssertEqual(ScoreRenderer.keySignatureAlter(forStep: "F", fifths: 1), 1)
        XCTAssertEqual(ScoreRenderer.keySignatureAlter(forStep: "C", fifths: 1), 0)
        // F major: one flat, on B.
        XCTAssertEqual(ScoreRenderer.keySignatureAlter(forStep: "B", fifths: -1), -1)
        XCTAssertEqual(ScoreRenderer.keySignatureAlter(forStep: "E", fifths: -1), 0)
        // C major alters nothing.
        XCTAssertEqual(ScoreRenderer.keySignatureAlter(forStep: "F", fifths: 0), 0)
    }

    func testNaturalCancellingTheKeySignatureStillPrints() {
        // An F natural in G major departs from the key and must show a natural.
        let fifths = 1
        XCTAssertNotEqual(0, ScoreRenderer.keySignatureAlter(forStep: "F", fifths: fifths))
        XCTAssertEqual(ScoreRenderer.accidentalType(forAlter: 0), .natural)
    }

    func testWrittenSpellingIsPreserved() {
        // B-flat must stay on the B line with a flat, not become A-sharp.
        let bFlat = ScoreRenderer.staffKeySpec(step: "B", alter: -1, octave: 4)
        XCTAssertEqual(bFlat.rawValue, "bb/4")
        let fSharp = ScoreRenderer.staffKeySpec(step: "F", alter: 1, octave: 4)
        XCTAssertEqual(fSharp.rawValue, "f#/4")
        let natural = ScoreRenderer.staffKeySpec(step: "G", alter: 0, octave: 3)
        XCTAssertEqual(natural.rawValue, "g/3")
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
    /// This is the round-trip between the row plan's placement and
    /// `playableIndex`'s inverse of it — both read the same `plan`, and an
    /// off-by-one in either would show up here.
    func testTapOnEachMeasureResolvesToThatMeasure() {
        let score = makeScore()
        let metrics = ScoreRenderer.Metrics()
        let playable = score.playableNotes
        let measures = score.measures

        for width in [345.0, 430.0] {
            let layout = ScoreRenderer.plan(
                measures: measures,
                availableWidth: width,
                metrics: metrics
            )
            for (rowIndex, row) in layout.rows.enumerated() {
                for (column, measureIndex) in row.measureIndices.enumerated() {
                    let measureWidth = row.widths[column]
                    let preceding = row.widths.prefix(column).reduce(0, +)
                    let x = metrics.horizontalMargin + row.prefixWidth + preceding + measureWidth / 2
                    let y = metrics.topMargin
                        + Double(rowIndex) * (metrics.rowHeight + metrics.rowGap)
                        + metrics.rowHeight / 2

                    guard let index = ScoreRenderer.playableIndex(
                        at: CGPoint(x: x, y: y),
                        score: score,
                        availableWidth: width,
                        metrics: metrics
                    ) else {
                        XCTFail("no note found for measure \(measures[measureIndex].number) at width \(width)")
                        continue
                    }
                    XCTAssertEqual(
                        playable[index].measureNumber, measures[measureIndex].number,
                        "tap on measure \(measures[measureIndex].number) resolved into \(playable[index].measureNumber) at width \(width)"
                    )
                }
            }
        }
    }

    /// A row must end exactly at the right margin, or the justification is
    /// leaving a ragged edge.
    func testRowsAreJustifiedFlush() {
        let score = makeScore()
        let metrics = ScoreRenderer.Metrics()
        for width in [345.0, 430.0] {
            let layout = ScoreRenderer.plan(measures: score.measures, availableWidth: width, metrics: metrics)
            for row in layout.rows {
                XCTAssertEqual(row.totalWidth, layout.contentWidth, accuracy: 0.01)
            }
        }
    }

    /// A bar with more notes must be given more room than a sparse one, which
    /// is the point of packing by content rather than by count.
    func testDenserMeasuresGetMoreWidth() {
        let metrics = ScoreRenderer.Metrics()
        let widths = ScoreRenderer.measureWidthsForTesting(noteCounts: [2, 6], available: 400, metrics: metrics)
        XCTAssertGreaterThan(widths[1], widths[0])
    }

    /// Every measure has to land on exactly one row.
    func testEveryMeasureIsPlacedExactlyOnce() {
        let score = makeScore()
        let layout = ScoreRenderer.plan(
            measures: score.measures,
            availableWidth: 345,
            metrics: ScoreRenderer.Metrics()
        )
        let placed = layout.rows.flatMap(\.measureIndices)
        XCTAssertEqual(placed.sorted(), Array(0..<score.measures.count))
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
