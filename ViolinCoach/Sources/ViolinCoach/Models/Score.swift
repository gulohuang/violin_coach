import Foundation

/// One playable event parsed out of the MusicXML: a pitch with a duration,
/// or a rest. `beatsInQuarters` is always relative to a quarter note
/// (MusicXML's `<divisions>` is defined the same way), independent of the
/// piece's actual time signature beat unit.
/// Marks printed above or below a notehead. Only the ones the repertoire here
/// actually uses — the parser ignores anything else rather than guessing.
public enum Articulation: String, Equatable, Sendable {
    case staccato, staccatissimo, accent, tenuto, marcato, fermata
    case upBow, downBow

    /// VexFlow's articulation code. Verified against VexFoundation's
    /// `Tables.articulationCodes`.
    public var vexCode: String {
        switch self {
        case .staccato: return "a."
        case .staccatissimo: return "av"
        case .accent: return "a>"
        case .tenuto: return "a-"
        case .marcato: return "a^"
        case .fermata: return "a@a"
        case .upBow: return "a|"
        case .downBow: return "am"
        }
    }
}

/// Where a note sits in a beam group, from MusicXML's `<beam>`.
public enum BeamRole: String, Equatable, Sendable {
    case begin, `continue`, end
}

/// Where a note sits in a slur.
public enum SlurRole: String, Equatable, Sendable {
    case start, stop
    /// A note can end one slur and start the next on the same notehead.
    case stopStart
}

public struct ScoreNote: Identifiable, Equatable, Sendable {
    public let id: Int
    public let isRest: Bool
    /// MIDI note number (concert pitch, A4 = 69 = 440Hz). Meaningless when `isRest` is true.
    /// This is what practice and playback use; the fields below are for engraving.
    public let midi: Int
    /// Note letter as written ("F", "B"...). Kept alongside `midi` because MIDI
    /// alone cannot distinguish B-flat from A-sharp, and the score should print
    /// what the composer wrote.
    public let step: String
    /// Chromatic alteration as written: +1 sharp, -1 flat, 0 natural.
    public let alter: Int
    public let octave: Int
    public let beatsInQuarters: Double
    /// Note type as given in the MusicXML `<type>` tag (e.g. "quarter", "eighth").
    public let typeName: String
    public let dots: Int
    /// 1-based measure number this note belongs to, for rendering measures separately.
    public let measureNumber: Int

    // MARK: - Notation
    //
    // Everything below is engraving detail: it changes how the note is drawn
    // but never what pitch is expected or when. Practice and playback read
    // only `midi` and `beatsInQuarters`, so notation can be added or dropped
    // without touching either.

    public let articulations: [Articulation]
    public let beam: BeamRole?
    public let slur: SlurRole?
    /// Left-hand fingering digit, printed beside the notehead.
    public let fingering: String?
    /// Dynamic marking starting at this note ("p", "mf", "f"...).
    public let dynamic: String?

    public init(
        id: Int,
        isRest: Bool,
        midi: Int,
        step: String = "C",
        alter: Int = 0,
        octave: Int = 4,
        beatsInQuarters: Double,
        typeName: String,
        dots: Int,
        measureNumber: Int,
        articulations: [Articulation] = [],
        beam: BeamRole? = nil,
        slur: SlurRole? = nil,
        fingering: String? = nil,
        dynamic: String? = nil
    ) {
        self.id = id
        self.isRest = isRest
        self.midi = midi
        self.step = step
        self.alter = alter
        self.octave = octave
        self.beatsInQuarters = beatsInQuarters
        self.typeName = typeName
        self.dots = dots
        self.measureNumber = measureNumber
        self.articulations = articulations
        self.beam = beam
        self.slur = slur
        self.fingering = fingering
        self.dynamic = dynamic
    }
}

public struct ScoreMeasure: Identifiable, Sendable {
    public let id: Int
    public let number: Int
    public let notes: [ScoreNote]

    public init(number: Int, notes: [ScoreNote]) {
        self.id = number
        self.number = number
        self.notes = notes
    }
}

/// A single-part, single-voice piece parsed from MusicXML. This app only
/// supports one staff/one voice (a solo violin line), which covers the vast
/// majority of beginner/intermediate violin repertoire and keeps both the
/// renderer and the practice/playback logic tractable to hand-verify.
public struct Score: Sendable {
    public let title: String
    /// Circle-of-fifths key signature count from MusicXML (<key><fifths>). Positive = sharps, negative = flats.
    public let fifths: Int
    public let beatsPerMeasure: Int
    public let beatType: Int
    public let tempoBPM: Double
    public let notes: [ScoreNote]

    public init(
        title: String,
        fifths: Int,
        beatsPerMeasure: Int,
        beatType: Int,
        tempoBPM: Double,
        notes: [ScoreNote]
    ) {
        self.title = title
        self.fifths = fifths
        self.beatsPerMeasure = beatsPerMeasure
        self.beatType = beatType
        self.tempoBPM = tempoBPM
        self.notes = notes
    }

    public var measures: [ScoreMeasure] {
        let grouped = Dictionary(grouping: notes, by: \.measureNumber)
        return grouped.keys.sorted().map { number in
            ScoreMeasure(number: number, notes: grouped[number]!.sorted { $0.id < $1.id })
        }
    }

    /// Playable (non-rest) notes only, in order — what the tuner/practice/player logic walks.
    public var playableNotes: [ScoreNote] {
        notes.filter { !$0.isRest }
    }

    /// Seconds a note of this length should sound at the score's tempo (quarter note = one beat).
    public func seconds(forBeats beats: Double) -> Double {
        beats * (60.0 / tempoBPM)
    }
}
