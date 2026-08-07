import Foundation

/// One playable event parsed out of the MusicXML: a pitch with a duration,
/// or a rest. `beatsInQuarters` is always relative to a quarter note
/// (MusicXML's `<divisions>` is defined the same way), independent of the
/// piece's actual time signature beat unit.
public struct ScoreNote: Identifiable, Equatable, Sendable {
    public let id: Int
    public let isRest: Bool
    /// MIDI note number (concert pitch, A4 = 69 = 440Hz). Meaningless when `isRest` is true.
    public let midi: Int
    public let beatsInQuarters: Double
    /// Note type as given in the MusicXML `<type>` tag (e.g. "quarter", "eighth").
    public let typeName: String
    public let dots: Int
    /// 1-based measure number this note belongs to, for rendering measures separately.
    public let measureNumber: Int

    public init(
        id: Int,
        isRest: Bool,
        midi: Int,
        beatsInQuarters: Double,
        typeName: String,
        dots: Int,
        measureNumber: Int
    ) {
        self.id = id
        self.isRest = isRest
        self.midi = midi
        self.beatsInQuarters = beatsInQuarters
        self.typeName = typeName
        self.dots = dots
        self.measureNumber = measureNumber
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
