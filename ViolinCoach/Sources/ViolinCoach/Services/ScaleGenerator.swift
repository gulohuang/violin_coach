import Foundation

/// A scale tonic, spelled rather than reduced to a pitch class.
///
/// The spelling matters: `ScoreNote` carries `step`/`alter` alongside `midi`
/// because MIDI alone can't tell B♭ from A♯, and the renderer prints an
/// accidental only where a note departs from the key signature. A scale built
/// from pitch classes alone would come out as "A♯ major" with eleven wrong
/// accidentals on every line.
public struct ScaleRoot: Hashable, Identifiable, Sendable {
    /// Letter name, "C" through "B".
    public let step: String
    /// -1 flat, 0 natural, +1 sharp.
    public let alter: Int

    public var id: String { "\(step)\(alter)" }

    public var label: String {
        switch alter {
        case 1: return "\(step)♯"
        case -1: return "\(step)♭"
        default: return step
        }
    }

    public var pitchClass: Int {
        ((ScaleGenerator.naturalSemitone(step) + alter) % 12 + 12) % 12
    }

    public init(_ step: String, _ alter: Int = 0) {
        self.step = step
        self.alter = alter
    }
}

public enum ScaleType: String, CaseIterable, Identifiable, Sendable {
    case major
    case naturalMinor
    case harmonicMinor
    case melodicMinor
    case chromatic

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .major: return "Major"
        case .naturalMinor: return "Natural Minor"
        case .harmonicMinor: return "Harmonic Minor"
        case .melodicMinor: return "Melodic Minor"
        case .chromatic: return "Chromatic"
        }
    }

    /// Semitones above the tonic, one octave's worth.
    var ascendingIntervals: [Int] {
        switch self {
        case .major: return [0, 2, 4, 5, 7, 9, 11]
        case .naturalMinor: return [0, 2, 3, 5, 7, 8, 10]
        case .harmonicMinor: return [0, 2, 3, 5, 7, 8, 11]
        case .melodicMinor: return [0, 2, 3, 5, 7, 9, 11]
        case .chromatic: return Array(0..<12)
        }
    }

    /// Melodic minor is the one scale that differs coming down — it reverts to
    /// natural minor, which is how it's taught and how it's printed. Every
    /// other scale descends the way it ascended.
    var descendingIntervals: [Int] {
        switch self {
        case .melodicMinor: return [0, 2, 3, 5, 7, 8, 10]
        default: return ascendingIntervals
        }
    }

    /// Minor keys take the relative major's signature, so the harmonic and
    /// melodic forms print their raised degrees as accidentals — which is
    /// exactly right.
    var isMinor: Bool {
        switch self {
        case .naturalMinor, .harmonicMinor, .melodicMinor: return true
        case .major, .chromatic: return false
        }
    }
}

public enum ScaleDirection: String, CaseIterable, Identifiable, Sendable {
    case ascending
    case ascendingDescending

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .ascending: return "Up"
        case .ascendingDescending: return "Up & Down"
        }
    }
}

/// Builds a scale as a `Score`, so the Scale tab gets notation, playback and
/// the following cursor from the machinery that already exists rather than
/// from a second, parallel implementation.
public enum ScaleGenerator {

    /// The open G string — the lowest note a violin has, so every scale starts
    /// at or above it.
    public static let lowestMIDI = 55
    /// E7. Standard three-octave scale books top out around here; past it the
    /// notation is more ledger lines than music.
    public static let highestMIDI = 100

    static let letters = ["C", "D", "E", "F", "G", "A", "B"]
    private static let naturalSemitones = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]

    static func naturalSemitone(_ step: String) -> Int {
        naturalSemitones[step.uppercased()] ?? 0
    }

    /// Circle-of-fifths position of each natural letter *as a major tonic*.
    private static let letterFifths = ["F": -1, "C": 0, "G": 1, "D": 2, "A": 3, "E": 4, "B": 5]

    /// The twelve tonics offered for a mode, spelled so the key signature is
    /// the one a player would actually see in print — D♭ major rather than
    /// C♯ major, E♭ minor rather than D♯ minor.
    public static func roots(for type: ScaleType) -> [ScaleRoot] {
        if type.isMinor {
            return [
                ScaleRoot("C"), ScaleRoot("C", 1), ScaleRoot("D"), ScaleRoot("E", -1),
                ScaleRoot("E"), ScaleRoot("F"), ScaleRoot("F", 1), ScaleRoot("G"),
                ScaleRoot("G", 1), ScaleRoot("A"), ScaleRoot("B", -1), ScaleRoot("B"),
            ]
        }
        return [
            ScaleRoot("C"), ScaleRoot("D", -1), ScaleRoot("D"), ScaleRoot("E", -1),
            ScaleRoot("E"), ScaleRoot("F"), ScaleRoot("F", 1), ScaleRoot("G"),
            ScaleRoot("A", -1), ScaleRoot("A"), ScaleRoot("B", -1), ScaleRoot("B"),
        ]
    }

    /// `<key><fifths>` for this tonic and mode. A minor key carries its
    /// relative major's signature, three steps flatward.
    public static func fifths(root: ScaleRoot, type: ScaleType) -> Int {
        // A chromatic scale belongs to no key; an empty signature makes every
        // altered note print its own accidental, which is how one is written.
        guard type != .chromatic else { return 0 }
        let base = (letterFifths[root.step.uppercased()] ?? 0) + 7 * root.alter
        return type.isMinor ? base - 3 : base
    }

    /// Lowest playable starting note for this tonic: the first occurrence of
    /// its pitch class at or above the open G.
    public static func startingMIDI(root: ScaleRoot) -> Int {
        var midi = lowestMIDI
        while midi % 12 != root.pitchClass { midi += 1 }
        return midi
    }

    /// How many octaves fit under `highestMIDI` from this tonic, 1...3.
    ///
    /// It's a computed ceiling rather than a fixed three because the top of
    /// the violin is a fixed pitch, not a fixed interval above wherever the
    /// scale starts: three octaves of G reaches G6, but three octaves of F♯
    /// would need a note above the fingerboard.
    public static func maximumOctaves(root: ScaleRoot) -> Int {
        let start = startingMIDI(root: root)
        for octaves in stride(from: 3, through: 1, by: -1) where start + 12 * octaves <= highestMIDI {
            return octaves
        }
        return 1
    }

    public static func title(root: ScaleRoot, type: ScaleType, octaves: Int) -> String {
        let octaveText = octaves == 1 ? "1 octave" : "\(octaves) octaves"
        return type == .chromatic
            ? "Chromatic from \(root.label) · \(octaveText)"
            : "\(root.label) \(type.label) · \(octaveText)"
    }

    /// Builds the scale.
    ///
    /// Written in plain quarter notes in 4/4. Scales are a rhythm exercise
    /// only incidentally — what matters is the pitch sequence and being able
    /// to slow it down, which the tempo control already does. Even notes also
    /// mean no beaming to get wrong.
    public static func score(
        root: ScaleRoot,
        type: ScaleType,
        octaves: Int,
        direction: ScaleDirection,
        tempoBPM: Double = 80
    ) -> Score {
        let span = max(1, min(maximumOctaves(root: root), octaves))
        let start = startingMIDI(root: root)

        var spelled = pitches(root: root, intervals: type.ascendingIntervals, start: start, octaves: span)

        if direction == .ascendingDescending {
            // Coming down is its own spelling pass, because melodic minor
            // changes on the way down. Drop the first element so the top note
            // sounds once rather than twice.
            let down = pitches(root: root, intervals: type.descendingIntervals, start: start, octaves: span)
                .reversed()
                .dropFirst()
            spelled.append(contentsOf: down)
        }

        let notes = spelled.enumerated().map { index, note in
            ScoreNote(
                id: index,
                isRest: false,
                midi: note.midi,
                step: note.step,
                alter: note.alter,
                octave: note.octave,
                beatsInQuarters: 1,
                typeName: "quarter",
                dots: 0,
                measureNumber: index / 4 + 1
            )
        }

        return Score(
            title: title(root: root, type: type, octaves: span),
            fifths: fifths(root: root, type: type),
            beatsPerMeasure: 4,
            beatType: 4,
            tempoBPM: tempoBPM,
            notes: notes
        )
    }

    // MARK: - Spelling

    struct SpelledNote: Equatable {
        let midi: Int
        let step: String
        let alter: Int
        let octave: Int
    }

    /// One ascending run: `intervals.count × octaves` notes plus the closing
    /// tonic on top.
    static func pitches(root: ScaleRoot, intervals: [Int], start: Int, octaves: Int) -> [SpelledNote] {
        guard !intervals.isEmpty else { return [] }
        let degrees = degreeSpellings(root: root, intervals: intervals)
        var result: [SpelledNote] = []
        for i in 0...(intervals.count * octaves) {
            let octaveOffset = i / intervals.count
            let degree = i % intervals.count
            let midi = start + 12 * octaveOffset + intervals[degree]
            let (step, alter) = degrees[degree]
            result.append(SpelledNote(midi: midi, step: step, alter: alter, octave: octave(forMIDI: midi, step: step, alter: alter)))
        }
        return result
    }

    /// How each degree of the scale is written.
    ///
    /// A diatonic scale uses each letter exactly once and in order, which is
    /// what makes the accidentals come out right: the alteration is whatever
    /// it takes to bend that letter to the pitch the interval asks for. That
    /// one rule gives F♯ in G major, G♯ (not A♭) as the leading tone of A
    /// harmonic minor, and the F𝄪 that G♯ harmonic minor genuinely needs.
    static func degreeSpellings(root: ScaleRoot, intervals: [Int]) -> [(step: String, alter: Int)] {
        // A chromatic scale can't use consecutive letters — twelve degrees,
        // seven letters — so it takes the conventional spelling instead:
        // sharps, or flats when the tonic itself is flat. The tonic keeps its
        // own spelling either way, so "Chromatic from E♭" doesn't open on a
        // D♯.
        guard intervals.count == 7, let letterIndex = letters.firstIndex(of: root.step.uppercased()) else {
            var degrees = intervals.map {
                chromaticSpelling(pitchClass: (root.pitchClass + $0) % 12, preferFlats: root.alter < 0)
            }
            if !degrees.isEmpty { degrees[0] = (root.step.uppercased(), root.alter) }
            return degrees
        }

        let rootPitchClass = root.pitchClass
        return intervals.enumerated().map { degree, semitones in
            let letter = letters[(letterIndex + degree) % letters.count]
            let target = (rootPitchClass + semitones) % 12
            var alter = (target - naturalSemitone(letter)) % 12
            // Fold into -6...5 so a letter is sharpened or flattened by the
            // smaller amount rather than, say, raised eleven semitones.
            if alter > 6 { alter -= 12 }
            if alter < -6 { alter += 12 }
            return (letter, alter)
        }
    }

    /// Conventional chromatic spelling — sharps going up, flats in a flat key.
    private static func chromaticSpelling(pitchClass: Int, preferFlats: Bool) -> (step: String, alter: Int) {
        switch ((pitchClass % 12) + 12) % 12 {
        case 0: return ("C", 0)
        case 1: return preferFlats ? ("D", -1) : ("C", 1)
        case 2: return ("D", 0)
        case 3: return preferFlats ? ("E", -1) : ("D", 1)
        case 4: return ("E", 0)
        case 5: return ("F", 0)
        case 6: return preferFlats ? ("G", -1) : ("F", 1)
        case 7: return ("G", 0)
        case 8: return preferFlats ? ("A", -1) : ("G", 1)
        case 9: return ("A", 0)
        case 10: return preferFlats ? ("B", -1) : ("A", 1)
        default: return ("B", 0)
        }
    }

    /// Which printed octave a spelled note sits in.
    ///
    /// Derived from the *letter*, not from the MIDI number, because they can
    /// disagree at the octave boundary: B♯4 and C5 are the same key but B♯
    /// belongs to octave 4, and getting that wrong puts the note a line and a
    /// space away from where it should be.
    static func octave(forMIDI midi: Int, step: String, alter: Int) -> Int {
        (midi - alter - naturalSemitone(step)) / 12 - 1
    }
}
