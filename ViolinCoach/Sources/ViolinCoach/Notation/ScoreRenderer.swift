import Foundation
import VexFoundation

/// Where one playable note ended up on screen after formatting, so a cursor
/// overlay can be drawn at the right spot. `playableIndex` matches the
/// indices used by `Score.playableNotes`, `ScoreAudioPlayer.currentIndex`,
/// and `PracticeViewModel` — the single shared numbering that keeps
/// "what note is expected," "what's playing," and "what's highlighted" all
/// pointing at the same note.
public struct RenderedNotePosition {
    public let playableIndex: Int
    public let x: Double
    public let staveY: Double
    public let staveHeight: Double
}

public struct ScoreLayout {
    public let totalWidth: Double
    public let totalHeight: Double
    public let notePositions: [RenderedNotePosition]
}

/// Renders a `Score` as a single-line, horizontally laid out staff (one
/// `Stave` per measure, left to right) using VexFoundation, and reports each
/// note's on-screen x position for the practice/playback cursor.
///
/// Deliberately does not use VexFoundation's `System`/multi-line layout —
/// `System` is for stacking multiple simultaneous staves (e.g. multiple
/// instrument parts in a score), not for laying out successive measures of
/// one part. A single scrolling line (wrapped in a horizontal ScrollView by
/// the caller) sidesteps needing to implement line-breaking/justification
/// logic, and doubles as the natural "follow along while it scrolls" UX
/// this app's practice mode wants anyway.
///
/// Everything is rebuilt from scratch on every call, matching the pattern
/// already used by the Claveo app's VexFoundation staff view: VexFoundation
/// objects are cheap, view-model-like builders, not a persistent scene
/// graph, so there's no need to diff/update them incrementally.
public enum ScoreRenderer {
    // Circle-of-fifths (MusicXML <key><fifths>) -> VexFoundation major key-signature name.
    // Verified against VexFoundation's own Tables.keySignatures dictionary.
    private static let keyNames: [Int: String] = [
        0: "C", 1: "G", 2: "D", 3: "A", 4: "E", 5: "B", 6: "F#", 7: "C#",
        -1: "F", -2: "Bb", -3: "Eb", -4: "Ab", -5: "Db", -6: "Gb", -7: "Cb",
    ]

    public struct Metrics {
        public var staveSpace: Double
        public var measureWidth: Double
        public var firstMeasureExtraWidth: Double
        public var topMargin: Double
        public var leftMargin: Double

        public init(
            staveSpace: Double = 40,
            measureWidth: Double = 170,
            firstMeasureExtraWidth: Double = 100,
            topMargin: Double = 20,
            leftMargin: Double = 10
        ) {
            self.staveSpace = staveSpace
            self.measureWidth = measureWidth
            self.firstMeasureExtraWidth = firstMeasureExtraWidth
            self.topMargin = topMargin
            self.leftMargin = leftMargin
        }
    }

    /// The pixel size `draw(score:into:metrics:)` will use for this score —
    /// exposed separately so a view can size its `VexCanvas`/`ScrollView`
    /// without needing a live `RenderContext` first.
    public static func canvasSize(for score: Score, metrics: Metrics = Metrics()) -> (width: Double, height: Double) {
        let measureCount = max(1, score.measures.count)
        let width = metrics.leftMargin
            + Double(measureCount) * metrics.measureWidth
            + metrics.firstMeasureExtraWidth
            + metrics.leftMargin
        let height = metrics.topMargin * 2 + metrics.staveSpace * 5
        return (width, height)
    }

    /// Draws `score` into `context` and returns the resulting layout. Call
    /// this from inside a `VexCanvas` draw closure.
    @discardableResult
    public static func draw(score: Score, into context: RenderContext, metrics: Metrics = Metrics()) -> ScoreLayout {
        FontLoader.loadDefaultFonts()

        let measures = score.measures
        let size = canvasSize(for: score, metrics: metrics)
        let totalHeight = size.height

        let factory = Factory(options: FactoryOptions(staveSpace: metrics.staveSpace, width: size.width, height: size.height))
        _ = factory.setContext(context)

        let keyName = keyNames[score.fifths] ?? "C"
        var positions: [RenderedNotePosition] = []
        var playableIndex = 0
        var x = metrics.leftMargin

        for (measureIndex, measure) in measures.enumerated() {
            let isFirst = measureIndex == 0
            let width = metrics.measureWidth + (isFirst ? metrics.firstMeasureExtraWidth : 0)
            let stave = factory.Stave(x: x, y: metrics.topMargin, width: width)

            if isFirst {
                _ = stave.addClef(.treble)
                _ = stave.addKeySignature(keyName)
                _ = stave.addTimeSignature(.meter(score.beatsPerMeasure, score.beatType))
            }

            var staveNotes: [StaveNote] = []
            /// Parallel to `staveNotes`: the playable index for a real note, or nil for a rest.
            var staveNotePlayableIndex: [Int?] = []

            for note in measure.notes {
                let durationSpec = NoteDurationSpec(uncheckedValue: Self.noteValue(forTypeName: note.typeName))

                if note.isRest {
                    let restKey = StaffKeySpec(root: .nonNote(.rest), octave: 4)
                    let staveNote = factory.StaveNote(StaveNoteStruct(
                        keys: NonEmptyArray(restKey),
                        duration: durationSpec,
                        dots: note.dots,
                        type: .rest
                    ))
                    staveNotes.append(staveNote)
                    staveNotePlayableIndex.append(nil)
                    continue
                }

                let pitch = Self.staffKeySpec(forMidi: note.midi)
                let staveNote = factory.StaveNote(StaveNoteStruct(
                    keys: NonEmptyArray(pitch.key),
                    duration: durationSpec,
                    dots: note.dots
                ))
                if let accidental = pitch.accidental {
                    _ = staveNote.addModifier(factory.Accidental(type: accidental), index: 0)
                }
                staveNotes.append(staveNote)
                staveNotePlayableIndex.append(playableIndex)
                playableIndex += 1
            }

            let voice = factory.Voice(timeSignature: .meter(score.beatsPerMeasure, score.beatType))
            _ = voice.setStrict(false) // tolerate the last measure being under-full rather than throwing
            _ = voice.addTickables(staveNotes.map { $0 as Tickable })

            let formatter = factory.Formatter()
            _ = formatter.formatToStave([voice], stave: stave)

            for (i, staveNote) in staveNotes.enumerated() {
                guard let pIndex = staveNotePlayableIndex[i] else { continue }
                positions.append(RenderedNotePosition(
                    playableIndex: pIndex,
                    x: staveNote.getAbsoluteX(),
                    staveY: stave.getY(),
                    staveHeight: stave.getHeight()
                ))
            }

            x += width
        }

        try? factory.draw()

        return ScoreLayout(totalWidth: x + metrics.leftMargin, totalHeight: totalHeight, notePositions: positions)
    }

    // MARK: - MusicXML -> VexFoundation mapping

    private static func noteValue(forTypeName typeName: String) -> NoteValue {
        switch typeName {
        case "whole": return .whole
        case "half": return .half
        case "quarter": return .quarter
        case "eighth": return .eighth
        case "16th": return .sixteenth
        case "32nd": return .thirtySecond
        case "64th": return .sixtyFourth
        case "128th": return .oneTwentyEighth
        default: return .quarter // unsupported/unknown type name — documented fallback
        }
    }

    private static let letters: [Character] = ["c", "d", "e", "f", "g", "a", "b"]
    private static let naturalSemitones: [Character: Int] = ["c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11]

    /// Converts a MIDI number to a VexFoundation staff key + accidental,
    /// always spelling with sharps (e.g. MIDI 66 -> F#4, never Gb4). Good
    /// enough for the sharp-key-signature-heavy beginner violin repertoire
    /// this app targets; flat spelling would need real key-aware
    /// enharmonic spelling, which is out of scope for a first version.
    static func staffKeySpec(forMidi midi: Int) -> (key: StaffKeySpec, accidental: AccidentalType?) {
        let octave = midi / 12 - 1
        let pitchClass = ((midi % 12) + 12) % 12
        let naturalIndex = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6][pitchClass] // nearest-below natural letter index (c..b)
        let letter = letters[naturalIndex]
        let noteLetter = NoteLetter(parsing: String(letter))!
        let naturalSemitone = naturalSemitones[letter]!
        let isSharp = pitchClass != naturalSemitone

        let key = StaffKeySpec(letter: noteLetter, accidental: isSharp ? .sharp : nil, octave: octave)
        return (key, isSharp ? .sharp : nil)
    }
}
