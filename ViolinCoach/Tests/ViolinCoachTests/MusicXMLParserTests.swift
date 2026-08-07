import XCTest
@testable import ViolinCoach

final class MusicXMLParserTests: XCTestCase {
    /// A small, self-contained MusicXML fixture (independent of the bundled
    /// resource file) so this test doesn't depend on how the test target's
    /// resource bundling is configured.
    static let sampleXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="3.1">
      <work><work-title>Test Piece</work-title></work>
      <part-list>
        <score-part id="P1"><part-name>Violin</part-name></score-part>
      </part-list>
      <part id="P1">
        <measure number="1">
          <attributes>
            <divisions>2</divisions>
            <key><fifths>2</fifths></key>
            <time><beats>4</beats><beat-type>4</beat-type></time>
            <clef><sign>G</sign><line>2</line></clef>
          </attributes>
          <direction><sound tempo="100"/></direction>
          <note>
            <pitch><step>D</step><octave>4</octave></pitch>
            <duration>2</duration>
            <voice>1</voice>
            <type>quarter</type>
          </note>
          <note>
            <pitch><step>F</step><alter>1</alter><octave>4</octave></pitch>
            <duration>4</duration>
            <voice>1</voice>
            <type>half</type>
          </note>
          <note>
            <rest/>
            <duration>2</duration>
            <voice>1</voice>
            <type>quarter</type>
          </note>
        </measure>
        <measure number="2">
          <note>
            <pitch><step>A</step><octave>4</octave></pitch>
            <duration>8</duration>
            <voice>1</voice>
            <type>whole</type>
          </note>
        </measure>
      </part>
    </score-partwise>
    """

    func testParsesTitleKeyTimeAndTempo() throws {
        let score = try MusicXMLParser.parse(data: Self.sampleXML.data(using: .utf8)!)
        XCTAssertEqual(score.title, "Test Piece")
        XCTAssertEqual(score.fifths, 2)
        XCTAssertEqual(score.beatsPerMeasure, 4)
        XCTAssertEqual(score.beatType, 4)
        XCTAssertEqual(score.tempoBPM, 100)
    }

    func testParsesNotesInOrderWithCorrectPitchesAndBeats() throws {
        let score = try MusicXMLParser.parse(data: Self.sampleXML.data(using: .utf8)!)
        XCTAssertEqual(score.notes.count, 4)

        let d4 = score.notes[0]
        XCTAssertFalse(d4.isRest)
        XCTAssertEqual(d4.midi, 62) // D4
        XCTAssertEqual(d4.beatsInQuarters, 1, accuracy: 0.0001) // duration 2 / divisions 2

        let fSharp4 = score.notes[1]
        XCTAssertEqual(fSharp4.midi, 66) // F#4 (alter +1)
        XCTAssertEqual(fSharp4.beatsInQuarters, 2, accuracy: 0.0001) // duration 4 / divisions 2

        let rest = score.notes[2]
        XCTAssertTrue(rest.isRest)
        XCTAssertEqual(rest.beatsInQuarters, 1, accuracy: 0.0001)

        let a4 = score.notes[3]
        XCTAssertEqual(a4.midi, 69) // A4
        XCTAssertEqual(a4.measureNumber, 2)
    }

    func testPlayableNotesExcludesRests() throws {
        let score = try MusicXMLParser.parse(data: Self.sampleXML.data(using: .utf8)!)
        XCTAssertEqual(score.playableNotes.count, 3)
        XCTAssertTrue(score.playableNotes.allSatisfy { !$0.isRest })
    }

    func testMeasuresGroupNotesByMeasureNumber() throws {
        let score = try MusicXMLParser.parse(data: Self.sampleXML.data(using: .utf8)!)
        let measures = score.measures
        XCTAssertEqual(measures.count, 2)
        XCTAssertEqual(measures[0].notes.count, 3)
        XCTAssertEqual(measures[1].notes.count, 1)
    }

    func testThrowsOnEmptyPart() {
        let emptyXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="3.1">
          <part-list><score-part id="P1"><part-name>Violin</part-name></score-part></part-list>
          <part id="P1"></part>
        </score-partwise>
        """
        XCTAssertThrowsError(try MusicXMLParser.parse(data: emptyXML.data(using: .utf8)!))
    }

    // Loading the actual bundled twinkle-twinkle.musicxml resource is exercised
    // manually via the app (ScorePlayerViewModel/PracticeViewModel surface a
    // visible error if it fails to load) rather than here — whether a unit
    // test target can see the app target's bundled resources depends on
    // Xcode test-host configuration this project can't verify without Xcode,
    // so this file sticks to fixture-based parsing correctness instead.
}
