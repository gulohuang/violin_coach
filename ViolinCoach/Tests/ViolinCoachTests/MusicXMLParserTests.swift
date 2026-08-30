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

    // MARK: - Header-only title scan (library listing)

    private func writeTemporary(_ xml: String, named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).musicxml")
        try xml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testParseTitleReadsWorkTitleWithoutParsingNotes() throws {
        let url = try writeTemporary(Self.sampleXML, named: "work")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(MusicXMLParser.parseTitle(contentsOf: url), "Test Piece")
    }

    /// Engraving programs often leave `<work-title>` empty and fill in
    /// `<movement-title>` instead, so the listing has to accept either.
    func testParseTitleFallsBackToMovementTitle() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="3.1">
          <movement-title>Gavotte</movement-title>
          <part-list><score-part id="P1"><part-name>Violin</part-name></score-part></part-list>
          <part id="P1"><measure number="1"></measure></part>
        </score-partwise>
        """
        let url = try writeTemporary(xml, named: "movement")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(MusicXMLParser.parseTitle(contentsOf: url), "Gavotte")
    }

    /// A file with no title at all yields nil, so the library can fall back to
    /// the filename rather than printing an empty row.
    func testParseTitleReturnsNilWhenAbsent() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="3.1">
          <part-list><score-part id="P1"><part-name>Violin</part-name></score-part></part-list>
          <part id="P1"><measure number="1"></measure></part>
        </score-partwise>
        """
        let url = try writeTemporary(xml, named: "untitled")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(MusicXMLParser.parseTitle(contentsOf: url))
    }

    func testParseTitleReturnsNilForAMissingFile() {
        let url = URL(fileURLWithPath: "/nonexistent/nope.musicxml")
        XCTAssertNil(MusicXMLParser.parseTitle(contentsOf: url))
    }

    // MARK: - Notation

    static let notationXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="3.1">
      <part-list><score-part id="P1"><part-name>Violin</part-name></score-part></part-list>
      <part id="P1">
        <measure number="1">
          <attributes>
            <divisions>2</divisions>
            <key><fifths>1</fifths></key>
            <time><beats>4</beats><beat-type>4</beat-type></time>
          </attributes>
          <direction><direction-type><dynamics><mf/></dynamics></direction-type></direction>
          <note>
            <pitch><step>F</step><alter>1</alter><octave>4</octave></pitch>
            <duration>1</duration><type>eighth</type>
            <beam number="1">begin</beam>
            <notations>
              <slur number="1" type="start"/>
              <articulations><staccato/><accent/></articulations>
              <technical><up-bow/><fingering>2</fingering></technical>
            </notations>
          </note>
          <note>
            <pitch><step>B</step><alter>-1</alter><octave>4</octave></pitch>
            <duration>1</duration><type>eighth</type>
            <beam number="1">end</beam>
            <notations><slur number="1" type="stop"/></notations>
          </note>
        </measure>
      </part>
    </score-partwise>
    """

    func testParsesArticulationsBowingsAndFingering() throws {
        let score = try MusicXMLParser.parse(data: Self.notationXML.data(using: .utf8)!)
        let first = score.notes[0]
        XCTAssertEqual(Set(first.articulations), [.staccato, .accent, .upBow])
        XCTAssertEqual(first.fingering, "2")
    }

    func testParsesBeamAndSlurRoles() throws {
        let score = try MusicXMLParser.parse(data: Self.notationXML.data(using: .utf8)!)
        XCTAssertEqual(score.notes[0].beam, .begin)
        XCTAssertEqual(score.notes[1].beam, .end)
        XCTAssertEqual(score.notes[0].slur, .start)
        XCTAssertEqual(score.notes[1].slur, .stop)
    }

    /// Dynamics appear in a <direction> before the note they apply to.
    func testDynamicAttachesToTheFollowingNote() throws {
        let score = try MusicXMLParser.parse(data: Self.notationXML.data(using: .utf8)!)
        XCTAssertEqual(score.notes[0].dynamic, "mf")
        XCTAssertNil(score.notes[1].dynamic, "a dynamic applies once, not to every later note")
    }

    /// Written spelling has to survive, because MIDI cannot distinguish
    /// B-flat from A-sharp and the score should print what was written.
    func testKeepsWrittenSpellingNotJustMIDI() throws {
        let score = try MusicXMLParser.parse(data: Self.notationXML.data(using: .utf8)!)
        let bFlat = score.notes[1]
        XCTAssertEqual(bFlat.step, "B")
        XCTAssertEqual(bFlat.alter, -1)
        XCTAssertEqual(bFlat.midi, 70) // same pitch as A#4
    }

    // Loading the actual bundled gavotte.musicxml resource is exercised
    // manually via the app (ScorePlayerViewModel/PracticeViewModel surface a
    // visible error if it fails to load) rather than here — whether a unit
    // test target can see the app target's bundled resources depends on
    // Xcode test-host configuration this project can't verify without Xcode,
    // so this file sticks to fixture-based parsing correctness instead.
}
