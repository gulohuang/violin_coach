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
    /// Y of the top staff line on the row this note landed on.
    public let staffTopY: Double
    /// Y of the bottom staff line on that row.
    public let staffBottomY: Double
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

    /// A stave occupies `spaceAboveStaffLn` (4) + `numLines` (5) +
    /// `spaceBelowStaffLn` (4) line-spacings vertically, so its full extent
    /// from its own y origin is 13 spacings — this matches VexFoundation's
    /// `Stave.getBottomY()`. Sizing a canvas by the 5 staff lines alone
    /// silently crops the clef, the ledger lines and every stem, which is
    /// exactly what happened before this constant existed.
    static let staveExtentInSpaces: Double = 13

    /// Colour of the brackets marking a chosen practice section. A CSS string
    /// because VexFoundation's `RenderContext` takes CSS colors; drawn over
    /// the always-light score paper, so it only needs a light-mode value.
    static let sectionBracketCSS = "rgba(52, 92, 217, 0.95)"

    public struct Metrics {
        /// Distance between staff lines. VexFlow's default is
        /// `Tables.STAVE_LINE_DISTANCE` (10); a little more reads better on a
        /// phone. Everything else scales off this, so raising it far above the
        /// default makes the engraving enormous rather than merely larger.
        public var staveSpace: Double
        /// Measures are never drawn narrower than this; it decides how many
        /// fit on a row before wrapping.
        public var minMeasureWidth: Double
        /// Room reserved at the start of every row for the clef and key
        /// signature, which repeat on each line the way printed music does.
        public var rowPrefixWidth: Double
        /// Extra room on the first row only, for the time signature.
        public var firstRowExtraWidth: Double
        public var topMargin: Double
        public var horizontalMargin: Double
        /// Blank space between wrapped rows.
        public var rowGap: Double

        public init(
            staveSpace: Double = 12,
            // Chosen as the largest width that still fits two measures per row
            // on a ~390pt phone (about 108pt each — comfortable for four
            // quarter notes at this stave size). Larger drops it to one
            // measure per line, which barely improves on not wrapping at all.
            minMeasureWidth: Double = 100,
            rowPrefixWidth: Double = 70,
            firstRowExtraWidth: Double = 34,
            topMargin: Double = 12,
            horizontalMargin: Double = 12,
            rowGap: Double = 16
        ) {
            self.staveSpace = staveSpace
            self.minMeasureWidth = minMeasureWidth
            self.rowPrefixWidth = rowPrefixWidth
            self.firstRowExtraWidth = firstRowExtraWidth
            self.topMargin = topMargin
            self.horizontalMargin = horizontalMargin
            self.rowGap = rowGap
        }

        /// Full vertical extent of one engraved row, excluding the gap.
        var rowHeight: Double { ScoreRenderer.staveExtentInSpaces * staveSpace }
    }

    /// How measures pack onto rows for a given canvas width. Computed the same
    /// way by `canvasSize` and `draw` so the height reserved and the height
    /// actually drawn can't disagree.
    struct RowPlan {
        let measuresPerRow: Int
        let rowCount: Int
        let contentWidth: Double
    }

    static func rowPlan(measureCount: Int, availableWidth: Double, metrics: Metrics) -> RowPlan {
        let contentWidth = max(metrics.minMeasureWidth, availableWidth - metrics.horizontalMargin * 2)
        // The first row is the tightest, since it also carries the time
        // signature. Packing to that width keeps every row the same shape.
        let usable = contentWidth - metrics.rowPrefixWidth - metrics.firstRowExtraWidth
        let perRow = max(1, Int(usable / metrics.minMeasureWidth))
        let count = max(1, Int(ceil(Double(max(1, measureCount)) / Double(perRow))))
        return RowPlan(measuresPerRow: perRow, rowCount: count, contentWidth: contentWidth)
    }

    /// The pixel size `draw` will use for this score at a given width —
    /// exposed separately so a view can size its `VexCanvas` and scroll
    /// content without needing a live `RenderContext` first.
    public static func canvasSize(
        for score: Score,
        availableWidth: Double,
        metrics: Metrics = Metrics()
    ) -> (width: Double, height: Double) {
        let plan = rowPlan(
            measureCount: score.measures.count,
            availableWidth: availableWidth,
            metrics: metrics
        )
        let height = metrics.topMargin * 2
            + Double(plan.rowCount) * metrics.rowHeight
            + Double(max(0, plan.rowCount - 1)) * metrics.rowGap
        return (max(availableWidth, plan.contentWidth), height)
    }

    /// Which playable note a tap at `point` lands on, or nil if the tap is
    /// outside the engraved area.
    ///
    /// Derived from the same row arithmetic `draw` uses rather than from the
    /// formatted note positions, so it needs no `RenderContext` — which means
    /// it is a pure function a view can call on a tap, and one that can be
    /// unit tested. Within a measure the note is picked by *beat* position
    /// rather than by evenly dividing the width, so a measure of mixed
    /// durations still maps a tap to the note actually drawn there.
    public static func playableIndex(
        at point: CGPoint,
        score: Score,
        availableWidth: Double,
        metrics: Metrics = Metrics()
    ) -> Int? {
        let measures = score.measures
        guard !measures.isEmpty else { return nil }
        let plan = rowPlan(measureCount: measures.count, availableWidth: availableWidth, metrics: metrics)

        let rowStride = metrics.rowHeight + metrics.rowGap
        let rowFloat = (Double(point.y) - metrics.topMargin) / rowStride
        guard rowFloat >= -0.35 else { return nil } // above the first stave
        let row = max(0, min(plan.rowCount - 1, Int(rowFloat)))

        let isFirstRow = row == 0
        let rowPrefix = metrics.rowPrefixWidth + (isFirstRow ? metrics.firstRowExtraWidth : 0)
        let measureWidth = (plan.contentWidth - rowPrefix) / Double(plan.measuresPerRow)
        guard measureWidth > 0 else { return nil }

        // Taps in the clef/key-signature area belong to the row's first measure.
        let xInRow = Double(point.x) - metrics.horizontalMargin - rowPrefix
        let column = max(0, min(plan.measuresPerRow - 1, Int(floor(xInRow / measureWidth))))

        let measureIndex = row * plan.measuresPerRow + column
        guard measureIndex >= 0, measureIndex < measures.count else { return nil }
        let measure = measures[measureIndex]

        // Where in the measure the tap fell, 0...1.
        let measureStartX = metrics.horizontalMargin + rowPrefix + Double(column) * measureWidth
        let fraction = max(0, min(1, (Double(point.x) - measureStartX) / measureWidth))

        // Walk the measure's notes by beat and take the one spanning the tap.
        let totalBeats = measure.notes.reduce(0) { $0 + $1.beatsInQuarters }
        guard totalBeats > 0 else { return nil }
        var elapsed = 0.0
        var chosen: ScoreNote?
        for note in measure.notes {
            let end = (elapsed + note.beatsInQuarters) / totalBeats
            if fraction <= end || note.id == measure.notes.last?.id {
                chosen = note
                break
            }
            elapsed += note.beatsInQuarters
        }

        // Rests aren't playable positions; fall forward to the next real note.
        let playable = score.playableNotes
        guard let chosen else { return nil }
        if let exact = playable.firstIndex(where: { $0.id == chosen.id }) { return exact }
        if let next = playable.firstIndex(where: { $0.id > chosen.id }) { return next }
        return playable.isEmpty ? nil : playable.count - 1
    }

    /// Draws `score` into `context` and returns the resulting layout. Call
    /// this from inside a `VexCanvas` draw closure.
    @discardableResult
    /// - Parameter sectionMeasures: bars chosen for repeat practice, marked
    ///   with a bracket at each end of the range.
    public static func draw(
        score: Score,
        into context: RenderContext,
        availableWidth: Double,
        sectionMeasures: ClosedRange<Int>? = nil,
        metrics: Metrics = Metrics()
    ) -> ScoreLayout {
        FontLoader.loadDefaultFonts()

        let measures = score.measures
        let plan = rowPlan(measureCount: measures.count, availableWidth: availableWidth, metrics: metrics)
        let size = canvasSize(for: score, availableWidth: availableWidth, metrics: metrics)

        let factory = Factory(options: FactoryOptions(staveSpace: metrics.staveSpace, width: size.width, height: size.height))
        _ = factory.setContext(context)

        let keyName = keyNames[score.fifths] ?? "C"
        var positions: [RenderedNotePosition] = []
        var playableIndex = 0
        var sectionOpen: (x: Double, top: Double, bottom: Double)?
        var sectionClose: (x: Double, top: Double, bottom: Double)?

        for (measureIndex, measure) in measures.enumerated() {
            let row = measureIndex / plan.measuresPerRow
            let column = measureIndex % plan.measuresPerRow
            let isRowStart = column == 0
            let isFirstRow = row == 0

            // Every row repeats the clef and key signature, as printed music
            // does — a wrapped line has to be readable on its own. Only the
            // first row carries the time signature, so only it needs the
            // extra room.
            let rowPrefix = metrics.rowPrefixWidth + (isFirstRow ? metrics.firstRowExtraWidth : 0)
            // Measures share what's left of the row evenly, so a full row
            // finishes flush at the right margin instead of ending ragged.
            let measureWidth = (plan.contentWidth - rowPrefix) / Double(plan.measuresPerRow)

            // The row's first stave is widened by the prefix and starts at the
            // margin; the rest begin after it.
            let x = metrics.horizontalMargin
                + (isRowStart ? 0 : rowPrefix)
                + Double(column) * measureWidth
            let y = metrics.topMargin + Double(row) * (metrics.rowHeight + metrics.rowGap)

            let staveWidth = measureWidth + (isRowStart ? rowPrefix : 0)
            let stave = factory.Stave(x: x, y: y, width: staveWidth)

            if isRowStart {
                _ = stave.addClef(.treble)
                _ = stave.addKeySignature(keyName)
                if isFirstRow {
                    _ = stave.addTimeSignature(.meter(score.beatsPerMeasure, score.beatType))
                }
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

            // Bracket the cursor to the staff lines themselves rather than the
            // stave's full box, which includes four line-spacings of headroom
            // above the top line and would draw a cursor floating well clear
            // of the notes.
            let staffTop = stave.getYForLine(0)
            let staffBottom = stave.getYForLine(4)

            // Note where the section's brackets go. Drawing has to wait until
            // after factory.draw(), because any fill or stroke style set here
            // would still be current when VexFoundation renders the notation
            // and would tint the noteheads with it.
            if let sectionMeasures {
                if measure.number == sectionMeasures.lowerBound {
                    sectionOpen = (x, staffTop, staffBottom)
                }
                if measure.number == sectionMeasures.upperBound {
                    sectionClose = (x + staveWidth, staffTop, staffBottom)
                }
            }

            for (i, staveNote) in staveNotes.enumerated() {
                guard let pIndex = staveNotePlayableIndex[i] else { continue }
                positions.append(RenderedNotePosition(
                    playableIndex: pIndex,
                    x: staveNote.getAbsoluteX(),
                    staffTopY: staffTop,
                    staffBottomY: staffBottom
                ))
            }
        }

        try? factory.draw()

        // After the notation, so the bracket's stroke style can't bleed into it.
        if let sectionOpen {
            drawSectionBracket(context, x: sectionOpen.x, top: sectionOpen.top, bottom: sectionOpen.bottom, opening: true, metrics: metrics)
        }
        if let sectionClose {
            drawSectionBracket(context, x: sectionClose.x, top: sectionClose.top, bottom: sectionClose.bottom, opening: false, metrics: metrics)
        }

        return ScoreLayout(totalWidth: size.width, totalHeight: size.height, notePositions: positions)
    }

    /// A square bracket marking one end of the practice section — the shape
    /// printed music uses for a repeated span, rather than a wash of colour
    /// that would fight with the notation.
    private static func drawSectionBracket(
        _ context: RenderContext,
        x: Double,
        top: Double,
        bottom: Double,
        opening: Bool,
        metrics: Metrics
    ) {
        let overhang = metrics.staveSpace * 1.2   // reach past the staff lines
        let arm = metrics.staveSpace * 1.1        // length of the horizontal feet
        let y0 = top - overhang
        let y1 = bottom + overhang
        let armEnd = opening ? x + arm : x - arm

        _ = context.save()
        _ = context.setStrokeStyle(sectionBracketCSS)
        _ = context.setLineWidth(2.5)
        _ = context.beginPath()
        _ = context.moveTo(armEnd, y0)
        _ = context.lineTo(x, y0)
        _ = context.lineTo(x, y1)
        _ = context.lineTo(armEnd, y1)
        _ = context.stroke()
        _ = context.restore()
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
