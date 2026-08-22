import Foundation

public enum MusicXMLParseError: LocalizedError {
    case invalidXML(underlying: Error?)
    case noPlayableNotes

    public var errorDescription: String? {
        switch self {
        case .invalidXML(let underlying):
            return "Could not parse the MusicXML file" + (underlying.map { ": \($0.localizedDescription)" } ?? ".")
        case .noPlayableNotes:
            return "The MusicXML file has no playable notes in its first part."
        }
    }
}

/// A minimal, from-scratch MusicXML reader (Foundation's `XMLParser`,
/// SAX-style) covering exactly what a single-staff, single-voice violin part
/// needs: pitched notes, rests, tempo, key and time signature.
///
/// Deliberately hand-rolled rather than pulling in a third-party MusicXML
/// library: MusicXML is just XML, `XMLParser` is a stable Foundation API,
/// and this keeps the app's only external dependency to VexFoundation
/// (needed for staff engraving, which is a much harder problem to hand-roll
/// than reading a handful of well-documented XML elements).
///
/// Known, deliberate simplifications (documented rather than silently
/// handled) for a first version:
/// - Only the first `<part>` in the file is read (single instrument line).
/// - Chords collapse to their first note — this app is for a solo,
///   monophonic violin line, so simultaneous notes aren't meaningful here.
/// - Ties are not merged: a note tied across a barline becomes two separate
///   `ScoreNote`s and will be treated as two separate attacks by the
///   practice/playback logic. Correct visually, slightly wrong for
///   note-by-note practice timing on tied pieces.
/// - Grace notes (no `<duration>`) are skipped.
public final class MusicXMLParser: NSObject, XMLParserDelegate {
    public static func parse(data: Data) throws -> Score {
        let delegate = MusicXMLParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = delegate
        guard xmlParser.parse() else {
            throw MusicXMLParseError.invalidXML(underlying: delegate.parseError ?? xmlParser.parserError)
        }
        guard !delegate.notes.isEmpty else {
            throw MusicXMLParseError.noPlayableNotes
        }
        return Score(
            title: delegate.workTitle ?? "Untitled",
            fifths: delegate.fifths,
            beatsPerMeasure: delegate.beatsPerMeasure,
            beatType: delegate.beatType,
            tempoBPM: delegate.tempoBPM,
            notes: delegate.notes
        )
    }

    public static func parse(contentsOf url: URL) throws -> Score {
        try parse(data: try Data(contentsOf: url))
    }

    // MARK: - Parse state

    private var parseError: Error?
    private var currentText = ""
    private var elementStack: [String] = []
    /// The element enclosing whichever element is currently ending, i.e. one level up from the top of `elementStack`.
    private var parentOfCurrent: String? { elementStack.dropLast().last }

    private var workTitle: String?
    private var divisions: Double = 1
    private var fifths = 0
    private var beatsPerMeasure = 4
    private var beatType = 4
    private var tempoBPM: Double = 120

    private var currentPartId: String?
    private var firstPartId: String?
    private var currentMeasureNumber = 0

    private var notes: [ScoreNote] = []
    private var nextNoteId = 0

    // Per-<note> scratch state.
    private var inNote = false
    private var noteIsRest = false
    private var noteIsChord = false
    private var noteStep: String?
    private var noteAlter = 0
    private var noteOctave: Int?
    private var noteDuration: Double?
    private var noteType = "quarter"
    private var noteDots = 0
    private var noteArticulations: [Articulation] = []
    private var noteBeam: BeamRole?
    private var noteSlur: SlurRole?
    private var noteFingering: String?
    /// Dynamics arrive in a <direction> *before* the note they apply to, so
    /// they're held here until the next note claims them.
    private var pendingDynamic: String?

    // MARK: - XMLParserDelegate

    public func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        elementStack.append(elementName)
        currentText = ""

        switch elementName {
        case "part":
            if let id = attributeDict["id"] {
                currentPartId = id
                if firstPartId == nil { firstPartId = id }
            }
        case "measure":
            if let numberStr = attributeDict["number"], let number = Int(numberStr) {
                currentMeasureNumber = number
            } else {
                currentMeasureNumber += 1
            }
        case "note":
            inNote = true
            noteIsRest = false
            noteIsChord = false
            noteStep = nil
            noteAlter = 0
            noteOctave = nil
            noteDuration = nil
            noteType = "quarter"
            noteDots = 0
            noteArticulations = []
            noteBeam = nil
            noteSlur = nil
            noteFingering = nil
        case "rest":
            if inNote { noteIsRest = true }
        case "chord":
            if inNote { noteIsChord = true }
        case "dot":
            if inNote && parentOfCurrent == "note" { noteDots += 1 }
        case "sound":
            if let tempoStr = attributeDict["tempo"], let tempo = Double(tempoStr), tempo > 0 {
                tempoBPM = tempo
            }

        // Articulations and bowings are empty elements inside <notations>,
        // so they're caught on open rather than close.
        case "staccato": if inNote { noteArticulations.append(.staccato) }
        case "staccatissimo": if inNote { noteArticulations.append(.staccatissimo) }
        case "accent": if inNote { noteArticulations.append(.accent) }
        case "tenuto": if inNote { noteArticulations.append(.tenuto) }
        case "strong-accent": if inNote { noteArticulations.append(.marcato) }
        case "fermata": if inNote { noteArticulations.append(.fermata) }
        case "up-bow": if inNote { noteArticulations.append(.upBow) }
        case "down-bow": if inNote { noteArticulations.append(.downBow) }

        case "slur":
            if inNote, let type = attributeDict["type"] {
                switch (type, noteSlur) {
                // A note can close one slur and open the next.
                case ("start", .stop), ("stop", .start): noteSlur = .stopStart
                case ("start", _): noteSlur = .start
                case ("stop", _): noteSlur = .stop
                default: break
                }
            }

        // Dynamics are empty elements named for the marking itself:
        // <dynamics><mf/></dynamics>.
        case "p", "pp", "ppp", "mp", "mf", "f", "ff", "fff", "sf", "sfz", "fp":
            if parentOfCurrent == "dynamics" { pendingDynamic = elementName }
        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    public func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        defer {
            if !elementStack.isEmpty { elementStack.removeLast() }
            currentText = ""
        }

        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        // This app renders one line; a multi-part score just plays its first part.
        let isFirstPart = currentPartId == nil || currentPartId == firstPartId

        switch elementName {
        case "work-title":
            if workTitle == nil { workTitle = text }
        case "divisions":
            if isFirstPart, let value = Double(text), value > 0 { divisions = value }
        case "fifths":
            if isFirstPart, let value = Int(text) { fifths = value }
        case "beats":
            if isFirstPart, parentOfCurrent == "time", let value = Int(text) { beatsPerMeasure = value }
        case "beat-type":
            if isFirstPart, parentOfCurrent == "time", let value = Int(text) { beatType = value }
        case "step":
            if inNote { noteStep = text }
        case "alter":
            if inNote, let value = Int(text) { noteAlter = value }
        case "octave":
            if inNote, let value = Int(text) { noteOctave = value }
        case "duration":
            if inNote, let value = Double(text) { noteDuration = value }
        case "type":
            if inNote, parentOfCurrent == "note" { noteType = text }
        case "beam":
            // MusicXML numbers beams by level; level 1 is the primary beam and
            // is all this renderer groups on.
            if inNote, noteBeam == nil { noteBeam = BeamRole(rawValue: text) }
        case "fingering":
            if inNote, !text.isEmpty { noteFingering = text }
        case "note":
            if isFirstPart { finishNote() }
            inNote = false
        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, parseErrorOccurred error: Error) {
        parseError = error
    }

    // MARK: - Note assembly

    private func finishNote() {
        guard !noteIsChord else { return } // collapse chords to their first note
        guard let duration = noteDuration, divisions > 0 else { return } // skip grace notes / malformed notes
        let beats = duration / divisions

        if noteIsRest {
            notes.append(ScoreNote(
                id: nextNoteId, isRest: true, midi: 0,
                beatsInQuarters: beats, typeName: noteType, dots: noteDots,
                measureNumber: currentMeasureNumber,
                articulations: noteArticulations
            ))
            nextNoteId += 1
            return
        }

        guard let step = noteStep, let octave = noteOctave,
              let midi = Self.midiNumber(step: step, alter: noteAlter, octave: octave) else { return }
        notes.append(ScoreNote(
            id: nextNoteId, isRest: false, midi: midi,
            step: step.uppercased(), alter: noteAlter, octave: octave,
            beatsInQuarters: beats, typeName: noteType, dots: noteDots,
            measureNumber: currentMeasureNumber,
            articulations: noteArticulations,
            beam: noteBeam,
            slur: noteSlur,
            fingering: noteFingering,
            dynamic: pendingDynamic
        ))
        pendingDynamic = nil
        nextNoteId += 1
    }

    private static let stepSemitones: [String: Int] = [
        "C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11,
    ]

    /// MusicXML octave numbering is scientific pitch notation, same as MIDI's (middle C = C4 = MIDI 60).
    static func midiNumber(step: String, alter: Int, octave: Int) -> Int? {
        guard let base = stepSemitones[step.uppercased()] else { return nil }
        return (octave + 1) * 12 + base + alter
    }
}
