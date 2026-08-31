import XCTest
@testable import ViolinCoach

/// The generator is pure model code — no audio, no rendering — so all of it is
/// testable here. The cases below are the ones that actually go wrong when
/// scale spelling is done naively from pitch classes.
final class ScaleGeneratorTests: XCTestCase {

    private func spelling(_ root: ScaleRoot, _ type: ScaleType) -> [String] {
        ScaleGenerator.degreeSpellings(root: root, intervals: type.ascendingIntervals)
            .map { degree in
                let accidental = String(repeating: degree.alter > 0 ? "#" : "b", count: abs(degree.alter))
                return degree.step + accidental
            }
    }

    // MARK: - Key signatures

    func testMajorKeySignatures() {
        let expected: [(ScaleRoot, Int)] = [
            (ScaleRoot("C"), 0), (ScaleRoot("G"), 1), (ScaleRoot("D"), 2),
            (ScaleRoot("A"), 3), (ScaleRoot("E"), 4), (ScaleRoot("B"), 5),
            (ScaleRoot("F", 1), 6), (ScaleRoot("F"), -1), (ScaleRoot("B", -1), -2),
            (ScaleRoot("E", -1), -3), (ScaleRoot("A", -1), -4), (ScaleRoot("D", -1), -5),
        ]
        for (root, fifths) in expected {
            XCTAssertEqual(ScaleGenerator.fifths(root: root, type: .major), fifths, "\(root.label) major")
        }
    }

    /// A minor key takes its relative major's signature — three steps
    /// flatward — which is what makes the harmonic minor's raised seventh
    /// print as an accidental instead of being folded into the signature.
    func testMinorKeySignaturesUseTheRelativeMajor() {
        XCTAssertEqual(ScaleGenerator.fifths(root: ScaleRoot("A"), type: .naturalMinor), 0)
        XCTAssertEqual(ScaleGenerator.fifths(root: ScaleRoot("E"), type: .harmonicMinor), 1)
        XCTAssertEqual(ScaleGenerator.fifths(root: ScaleRoot("C"), type: .melodicMinor), -3)
        XCTAssertEqual(ScaleGenerator.fifths(root: ScaleRoot("E", -1), type: .naturalMinor), -6)
    }

    /// A chromatic scale belongs to no key, so it prints its own accidentals.
    func testChromaticHasNoKeySignature() {
        XCTAssertEqual(ScaleGenerator.fifths(root: ScaleRoot("D"), type: .chromatic), 0)
    }

    /// Every offered tonic must land on a signature that can actually be
    /// written — seven sharps or seven flats is the limit.
    func testEveryOfferedRootHasAWritableSignature() {
        for type in ScaleType.allCases {
            for root in ScaleGenerator.roots(for: type) {
                let fifths = ScaleGenerator.fifths(root: root, type: type)
                XCTAssertLessThanOrEqual(abs(fifths), 7, "\(root.label) \(type.label) needs \(fifths) accidentals")
            }
            XCTAssertEqual(ScaleGenerator.roots(for: type).count, 12)
        }
    }

    // MARK: - Spelling

    func testMajorScalesUseEachLetterOnce() {
        XCTAssertEqual(spelling(ScaleRoot("G"), .major), ["G", "A", "B", "C", "D", "E", "F#"])
        XCTAssertEqual(spelling(ScaleRoot("E", -1), .major), ["Eb", "F", "G", "Ab", "Bb", "C", "D"])
        XCTAssertEqual(spelling(ScaleRoot("F", 1), .major), ["F#", "G#", "A#", "B", "C#", "D#", "E#"])
    }

    /// The point of spelling by letter rather than by pitch class: A harmonic
    /// minor's leading tone is G♯, never A♭, and the augmented second between
    /// F and G♯ is what the scale is *for*.
    func testHarmonicMinorRaisesTheSeventhInTheRightLetter() {
        XCTAssertEqual(spelling(ScaleRoot("A"), .harmonicMinor), ["A", "B", "C", "D", "E", "F", "G#"])
        XCTAssertEqual(spelling(ScaleRoot("C"), .harmonicMinor), ["C", "D", "Eb", "F", "G", "Ab", "B"])
    }

    /// G♯ harmonic minor genuinely needs a double sharp on its seventh degree.
    /// `ScoreRenderer.accidentalType(forAlter:)` handles ±2, so this must come
    /// through as F## rather than being folded to a wrong letter.
    func testDoubleSharpIsSpelledNotFlattened() {
        XCTAssertEqual(spelling(ScaleRoot("G", 1), .harmonicMinor).last, "F##")
    }

    func testMelodicMinorDescendsAsNaturalMinor() {
        let score = ScaleGenerator.score(
            root: ScaleRoot("A"), type: .melodicMinor,
            octaves: 1, direction: .ascendingDescending
        )
        let names = score.playableNotes.map { $0.step + (($0.alter == 1) ? "#" : "") }
        // Up: A B C D E F# G# A. Down: G F E D C B A.
        XCTAssertEqual(names.prefix(8).map { $0 }, ["A", "B", "C", "D", "E", "F#", "G#", "A"])
        XCTAssertEqual(names.suffix(7).map { $0 }, ["G", "F", "E", "D", "C", "B", "A"])
    }

    // MARK: - Range and shape

    func testScalesStartAtOrAboveTheOpenG() {
        for type in ScaleType.allCases {
            for root in ScaleGenerator.roots(for: type) {
                let start = ScaleGenerator.startingMIDI(root: root)
                XCTAssertGreaterThanOrEqual(start, ScaleGenerator.lowestMIDI, "\(root.label)")
                // The first occurrence, not some higher one.
                XCTAssertLessThan(start, ScaleGenerator.lowestMIDI + 12, "\(root.label)")
                XCTAssertEqual(start % 12, root.pitchClass, "\(root.label)")
            }
        }
    }

    func testOctaveCountNeverExceedsTheInstrument() {
        for root in ScaleGenerator.roots(for: .major) {
            let octaves = ScaleGenerator.maximumOctaves(root: root)
            XCTAssertGreaterThanOrEqual(octaves, 1)
            XCTAssertLessThanOrEqual(octaves, 3)
            let top = ScaleGenerator.startingMIDI(root: root) + 12 * octaves
            XCTAssertLessThanOrEqual(top, ScaleGenerator.highestMIDI, "\(root.label) tops out at \(top)")
        }
    }

    /// Three octaves of G fits on a violin; three of F♯ would need a note past
    /// the top of the fingerboard, so the picker has to offer fewer.
    func testHighTonicsGetFewerOctaves() {
        XCTAssertEqual(ScaleGenerator.maximumOctaves(root: ScaleRoot("G")), 3)
        XCTAssertEqual(ScaleGenerator.maximumOctaves(root: ScaleRoot("F", 1)), 2)
    }

    func testNoteCounts() {
        let up = ScaleGenerator.score(root: ScaleRoot("G"), type: .major, octaves: 2, direction: .ascending)
        XCTAssertEqual(up.playableNotes.count, 15) // 7 per octave + the top tonic

        let both = ScaleGenerator.score(root: ScaleRoot("G"), type: .major, octaves: 2, direction: .ascendingDescending)
        XCTAssertEqual(both.playableNotes.count, 29) // the top note sounds once, not twice

        let chromatic = ScaleGenerator.score(root: ScaleRoot("G"), type: .chromatic, octaves: 1, direction: .ascending)
        XCTAssertEqual(chromatic.playableNotes.count, 13)
    }

    func testAscendingScaleIsStrictlyRising() {
        let score = ScaleGenerator.score(root: ScaleRoot("B", -1), type: .major, octaves: 2, direction: .ascending)
        let midis = score.playableNotes.map(\.midi)
        XCTAssertEqual(midis, midis.sorted())
        XCTAssertEqual(Set(midis).count, midis.count, "a scale shouldn't repeat a pitch on the way up")
    }

    /// The written octave comes from the letter, not the MIDI number: B♯4 and
    /// C5 are the same key, but B♯ belongs to octave 4 and putting it in 5
    /// would draw it a line and a space away from where it goes.
    func testOctaveFollowsTheWrittenLetter() {
        XCTAssertEqual(ScaleGenerator.octave(forMIDI: 72, step: "B", alter: 1), 4)
        XCTAssertEqual(ScaleGenerator.octave(forMIDI: 72, step: "C", alter: 0), 5)
        XCTAssertEqual(ScaleGenerator.octave(forMIDI: 71, step: "C", alter: -1), 5)
    }

    /// Every note's spelling has to agree with its MIDI number, or the score
    /// will play one pitch and print another.
    func testSpellingAlwaysAgreesWithMIDI() {
        for type in ScaleType.allCases {
            for root in ScaleGenerator.roots(for: type) {
                let score = ScaleGenerator.score(
                    root: root, type: type,
                    octaves: ScaleGenerator.maximumOctaves(root: root),
                    direction: .ascendingDescending
                )
                for note in score.playableNotes {
                    let fromSpelling = (note.octave + 1) * 12
                        + ScaleGenerator.naturalSemitone(note.step) + note.alter
                    XCTAssertEqual(fromSpelling, note.midi,
                                   "\(root.label) \(type.label): \(note.step)\(note.alter) octave \(note.octave)")
                    XCTAssertLessThanOrEqual(abs(note.alter), 2, "unwritable accidental")
                }
            }
        }
    }

    func testBarsHoldFourQuarterNotes() {
        let score = ScaleGenerator.score(root: ScaleRoot("D"), type: .major, octaves: 1, direction: .ascending)
        XCTAssertEqual(score.beatsPerMeasure, 4)
        XCTAssertEqual(score.beatType, 4)
        XCTAssertTrue(score.playableNotes.allSatisfy { $0.beatsInQuarters == 1 })
        // 8 notes -> two full bars.
        XCTAssertEqual(score.measures.count, 2)
        XCTAssertEqual(score.measures.first?.notes.count, 4)
    }
}
