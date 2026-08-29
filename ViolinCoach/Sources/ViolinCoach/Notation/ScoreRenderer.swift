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

    /// Measure numbers and the tempo marking, in the muted grey printed music
    /// uses for editorial marks rather than the black of the notation itself.
    static let marginInkCSS = "rgba(60, 60, 67, 0.62)"
    static let measureNumberBoxCSS = "rgba(60, 60, 67, 0.08)"

    /// Cursor wash over the current note. Drawn on the always-light score
    /// paper, so it needs only a light-mode value.
    static let cursorCSS = "rgba(52, 92, 217, 0.20)"

    /// Dynamics are conventionally set in bold italic serif.
    static let dynamicsFont = FontInfo(family: "Times New Roman", size: 12, weight: "bold", style: "italic")

    /// How large the notation is drawn. Everything else in `Metrics` scales
    /// off `staveSpace`, so this one value sets the whole engraving size —
    /// and, because rows pack by staff-spaces per note, a larger size also
    /// spreads the music out rather than just magnifying a cramped layout.
    public enum NoteSize: String, CaseIterable, Identifiable, Sendable {
        case small, mediumSmall, medium, mediumLarge, large

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .small: return "Small"
            case .mediumSmall: return "Med. Small"
            case .medium: return "Medium"
            case .mediumLarge: return "Med. Large"
            case .large: return "Large"
            }
        }

        /// VexFlow's default staff-line distance is 10; these bracket it.
        public var staveSpace: Double {
            switch self {
            case .small: return 8
            case .mediumSmall: return 9.5
            case .medium: return 11
            case .mediumLarge: return 13
            case .large: return 15.5
            }
        }
    }

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
        /// Horizontal room each note wants, in staff-spaces. Drives how many
        /// measures fit on a row, so raising it spreads the music out and
        /// lengthens the score rather than squeezing more onto each line.
        public var noteSpacingInSpaces: Double

        public init(
            staveSpace: Double = 11,
            // Chosen as the largest width that still fits two measures per row
            // on a ~390pt phone. Larger drops it to one measure per line,
            // which barely improves on not wrapping at all.
            minMeasureWidth: Double = 100,
            rowPrefixWidth: Double = 70,
            firstRowExtraWidth: Double = 34,
            topMargin: Double = 12,
            horizontalMargin: Double = 12,
            // Generous, because notation now reaches well outside the staff:
            // slurs arc above, fingerings sit over noteheads, dynamics hang
            // below. VexFoundation's own 4 line-spacings of reserved margin
            // don't cover a stacked slur plus fingering, and rows collided.
            rowGap: Double = 36,
            // 2.2 spaces/note keeps the busiest bars of the Gavotte legible
            // (they were at 1.75) without stretching the piece from 45 rows to
            // the 86 that 2.6 would cost.
            noteSpacingInSpaces: Double = 2.2
        ) {
            self.staveSpace = staveSpace
            self.minMeasureWidth = minMeasureWidth
            self.rowPrefixWidth = rowPrefixWidth
            self.firstRowExtraWidth = firstRowExtraWidth
            self.topMargin = topMargin
            self.horizontalMargin = horizontalMargin
            self.rowGap = rowGap
            self.noteSpacingInSpaces = noteSpacingInSpaces
        }

        /// Builds metrics for a chosen note size. The prefix widths and gap
        /// scale with it too, or a large staff would keep a clef block sized
        /// for a small one.
        public init(noteSize: NoteSize) {
            let space = noteSize.staveSpace
            self.init(
                staveSpace: space,
                minMeasureWidth: space * 9,
                rowPrefixWidth: space * 6.4,
                firstRowExtraWidth: space * 3.1,
                topMargin: 12,
                horizontalMargin: 12,
                rowGap: space * 2.4
            )
        }

        /// Full vertical extent of one engraved row, excluding the gap.
        var rowHeight: Double { ScoreRenderer.staveExtentInSpaces * staveSpace }
    }

    /// One engraved row: which measures it holds, how wide each is drawn, and
    /// the clef/key-signature block at its head.
    struct RowLayout {
        let measureIndices: [Int]
        let widths: [Double]
        let prefixWidth: Double

        var totalWidth: Double { prefixWidth + widths.reduce(0, +) }
    }

    /// The whole page: rows of measures, sized to a given canvas width.
    /// Computed once and shared by `canvasSize`, `draw` and `playableIndex`, so
    /// the height reserved, the notation drawn, and where a tap lands can't
    /// disagree with each other.
    struct ScorePlan {
        let rows: [RowLayout]
        let contentWidth: Double
    }

    /// Space a measure wants, before justification: enough for its notes to
    /// breathe, never below `minMeasureWidth`.
    ///
    /// `noteSpacing` is expressed in staff-spaces per note, which is how
    /// engravers think about density — it stays right if the staff size
    /// changes. Packing rows to this rather than to a fixed measures-per-row
    /// is what lets a dense bar take a line to itself while sparse bars share
    /// one, the way printed music does.
    static func idealWidth(noteCount: Int, metrics: Metrics) -> Double {
        max(metrics.minMeasureWidth, Double(max(1, noteCount)) * metrics.staveSpace * metrics.noteSpacingInSpaces)
    }

    /// Justified widths for a hypothetical row, for tests to check that a
    /// denser bar is given more room.
    static func measureWidthsForTesting(noteCounts: [Int], available: Double, metrics: Metrics) -> [Double] {
        let wanted = noteCounts.map { idealWidth(noteCount: $0, metrics: metrics) }
        let total = wanted.reduce(0, +)
        guard total > 0 else { return [] }
        return wanted.map { available * $0 / total }
    }

    static func plan(measures: [ScoreMeasure], availableWidth: Double, metrics: Metrics) -> ScorePlan {
        let contentWidth = max(metrics.minMeasureWidth, availableWidth - metrics.horizontalMargin * 2)
        guard !measures.isEmpty else {
            return ScorePlan(rows: [], contentWidth: contentWidth)
        }

        let ideals = measures.map { idealWidth(noteCount: $0.notes.count, metrics: metrics) }

        // Greedy line breaking: fill a row until the next measure won't fit.
        var rows: [[Int]] = []
        var current: [Int] = []
        var used = 0.0
        var index = 0
        while index < measures.count {
            let prefix = metrics.rowPrefixWidth + (rows.isEmpty ? metrics.firstRowExtraWidth : 0)
            let available = contentWidth - prefix
            if !current.isEmpty, used + ideals[index] > available {
                rows.append(current)
                current = []
                used = 0
                continue
            }
            current.append(index)
            used += ideals[index]
            index += 1
        }
        if !current.isEmpty { rows.append(current) }

        // Justify each row to end flush, keeping the relative proportions.
        let layouts = rows.enumerated().map { rowIndex, indices -> RowLayout in
            let prefix = metrics.rowPrefixWidth + (rowIndex == 0 ? metrics.firstRowExtraWidth : 0)
            let available = contentWidth - prefix
            let wanted = indices.map { ideals[$0] }
            let total = wanted.reduce(0, +)
            let widths = total > 0
                ? wanted.map { available * $0 / total }
                : Array(repeating: available / Double(indices.count), count: indices.count)
            return RowLayout(measureIndices: indices, widths: widths, prefixWidth: prefix)
        }

        return ScorePlan(rows: layouts, contentWidth: contentWidth)
    }

    /// The pixel size `draw` will use for this score at a given width —
    /// exposed separately so a view can size its `VexCanvas` and scroll
    /// content without needing a live `RenderContext` first.
    public static func canvasSize(
        for score: Score,
        availableWidth: Double,
        metrics: Metrics = Metrics()
    ) -> (width: Double, height: Double) {
        let layout = plan(measures: score.measures, availableWidth: availableWidth, metrics: metrics)
        let rowCount = max(1, layout.rows.count)
        let height = metrics.topMargin * 2
            + Double(rowCount) * metrics.rowHeight
            + Double(rowCount - 1) * metrics.rowGap
        return (max(availableWidth, layout.contentWidth), height)
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
        let layout = plan(measures: measures, availableWidth: availableWidth, metrics: metrics)
        guard !layout.rows.isEmpty else { return nil }

        let rowStride = metrics.rowHeight + metrics.rowGap
        let rowFloat = (Double(point.y) - metrics.topMargin) / rowStride
        guard rowFloat >= -0.35 else { return nil } // above the first stave
        let rowIndex = max(0, min(layout.rows.count - 1, Int(rowFloat)))
        let row = layout.rows[rowIndex]
        guard !row.widths.isEmpty else { return nil }

        // Walk the row's widths to find the bar under the tap. Taps in the
        // clef/key-signature block fall before the first width and belong to
        // the row's first measure.
        let xInRow = Double(point.x) - metrics.horizontalMargin - row.prefixWidth
        var column = row.widths.count - 1
        var runningX = 0.0
        var startX = 0.0
        for (i, width) in row.widths.enumerated() {
            if xInRow < runningX + width {
                column = i
                startX = runningX
                break
            }
            runningX += width
            startX = runningX
        }
        column = max(0, min(row.widths.count - 1, column))
        if column == row.widths.count - 1 { startX = row.widths.dropLast().reduce(0, +) }

        let measureIndex = row.measureIndices[column]
        guard measureIndex >= 0, measureIndex < measures.count else { return nil }
        let measure = measures[measureIndex]
        let measureWidth = row.widths[column]
        guard measureWidth > 0 else { return nil }

        // Where in the measure the tap fell, 0...1.
        let measureStartX = metrics.horizontalMargin + row.prefixWidth + startX
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

    /// Draws **one row** of the score into a row-sized context, and returns
    /// where each of its playable notes landed.
    ///
    /// Rows are drawn separately, each into its own canvas, so the view can
    /// put them in a `LazyVStack` and only render what's on screen. Drawing
    /// the whole score into a single canvas meant every scroll frame rebuilt
    /// all 89 staves, 437 notes, 96 beams and 99 slurs — which is what made
    /// scrolling stutter.
    ///
    /// The cost of splitting: a slur spanning a line break can't be drawn as
    /// one curve. Printed music breaks such a slur across the two lines
    /// anyway, so only the joining arc is lost.
    ///
    /// - Parameter cursorPlayableIndex: note to mark, or nil. Passing it here
    ///   rather than drawing the cursor separately keeps a cursor move to a
    ///   single row's redraw.
    @discardableResult
    public static func drawRow(
        score: Score,
        rowIndex: Int,
        into context: RenderContext,
        availableWidth: Double,
        cursorPlayableIndex: Int? = nil,
        sectionMeasures: ClosedRange<Int>? = nil,
        /// Printed as a tempo marking above the first row, as on a printed part.
        tempoBPM: Double? = nil,
        metrics: Metrics = Metrics()
    ) -> [RenderedNotePosition] {
        FontLoader.loadDefaultFonts()

        let measures = score.measures
        let layout = plan(measures: measures, availableWidth: availableWidth, metrics: metrics)
        guard rowIndex >= 0, rowIndex < layout.rows.count else { return [] }
        let row = layout.rows[rowIndex]

        let factory = Factory(options: FactoryOptions(
            staveSpace: metrics.staveSpace,
            width: layout.contentWidth + metrics.horizontalMargin * 2,
            height: metrics.rowHeight
        ))
        _ = factory.setContext(context)

        let keyName = keyNames[score.fifths] ?? "C"
        // Playable index of the first note on this row, so positions carry the
        // same numbering everything else uses.
        var playableIndex = playableIndexOfFirstNote(inRow: row, measures: measures, score: score)

        var positions: [RenderedNotePosition] = []
        var openSlurNotes: [StaveNote] = []
        var slurPairs: [(from: StaveNote, to: StaveNote)] = []
        var sectionOpen: (x: Double, top: Double, bottom: Double)?
        var sectionClose: (x: Double, top: Double, bottom: Double)?
        var rowStaffTop: Double?

        for (column, measureIndex) in row.measureIndices.enumerated() {
            let measure = measures[measureIndex]
            let isRowStart = column == 0
            let measureWidth = row.widths[column]
            let precedingWidth = row.widths.prefix(column).reduce(0, +)
            let x = metrics.horizontalMargin + (isRowStart ? 0 : row.prefixWidth) + precedingWidth
            // Row-local coordinates: each row canvas starts at its own origin.
            let y = 0.0
            let staveWidth = measureWidth + (isRowStart ? row.prefixWidth : 0)
            let stave = factory.Stave(x: x, y: y, width: staveWidth)

            if isRowStart {
                _ = stave.addClef(.treble)
                _ = stave.addKeySignature(keyName)
                if rowIndex == 0 {
                    _ = stave.addTimeSignature(.meter(score.beatsPerMeasure, score.beatType))
                }
            }

            var staveNotes: [StaveNote] = []
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

                // Spelled from what the composer wrote, not derived from MIDI:
                // MIDI cannot tell B-flat from A-sharp.
                let key = Self.staffKeySpec(step: note.step, alter: note.alter, octave: note.octave)
                let staveNote = factory.StaveNote(StaveNoteStruct(
                    keys: NonEmptyArray(key),
                    duration: durationSpec,
                    dots: note.dots
                ))
                // Print an accidental only where the note departs from the key
                // signature. Printing one for every altered note would put a
                // sharp on every F in G major.
                if note.alter != Self.keySignatureAlter(forStep: note.step, fifths: score.fifths),
                   let accidental = Self.accidentalType(forAlter: note.alter) {
                    _ = staveNote.addModifier(factory.Accidental(type: accidental), index: 0)
                }
                for articulation in note.articulations {
                    _ = staveNote.addModifier(factory.Articulation(type: articulation.vexCode), index: 0)
                }
                if let fingering = note.fingering {
                    _ = staveNote.addModifier(factory.Fingering(number: fingering, position: .above), index: 0)
                }
                if let dynamic = note.dynamic {
                    _ = staveNote.addModifier(
                        factory.Annotation(text: dynamic, vJustify: .bottom, font: dynamicsFont),
                        index: 0
                    )
                }

                switch note.slur {
                case .start:
                    openSlurNotes.append(staveNote)
                case .stop:
                    if let from = openSlurNotes.popLast() { slurPairs.append((from, staveNote)) }
                case .stopStart:
                    if let from = openSlurNotes.popLast() { slurPairs.append((from, staveNote)) }
                    openSlurNotes.append(staveNote)
                case nil:
                    break
                }

                staveNotes.append(staveNote)
                staveNotePlayableIndex.append(playableIndex)
                playableIndex += 1
            }

            // Beam runs never cross a barline, so they close out per measure.
            var beamGroup: [StaveNote] = []
            for (i, note) in measure.notes.enumerated() where i < staveNotes.count {
                switch note.beam {
                case .begin:
                    beamGroup = [staveNotes[i]]
                case .continue:
                    if !beamGroup.isEmpty { beamGroup.append(staveNotes[i]) }
                case .end:
                    if !beamGroup.isEmpty {
                        beamGroup.append(staveNotes[i])
                        if beamGroup.count >= 2 { _ = factory.Beam(notes: beamGroup) }
                    }
                    beamGroup = []
                case nil:
                    beamGroup = []
                }
            }

            let voice = factory.Voice(timeSignature: .meter(score.beatsPerMeasure, score.beatType))
            _ = voice.setStrict(false) // tolerate a pickup or short final bar
            _ = voice.addTickables(staveNotes.map { $0 as Tickable })

            let formatter = factory.Formatter()
            _ = formatter.formatToStave([voice], stave: stave)

            let staffTop = stave.getYForLine(0)
            let staffBottom = stave.getYForLine(4)
            if rowStaffTop == nil { rowStaffTop = staffTop }

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

        for pair in slurPairs {
            _ = factory.Curve(from: pair.from, to: pair.to)
        }

        try? factory.draw()

        // Overlays go after the notation: the render context is stateful, and
        // a fill or stroke style set earlier would tint the noteheads.
        if let cursorPlayableIndex,
           let position = positions.first(where: { $0.playableIndex == cursorPlayableIndex }) {
            let cursorWidth = metrics.staveSpace * 2.0
            let padding = metrics.staveSpace * 0.7
            _ = context.save()
            _ = context.setFillStyle(cursorCSS)
            _ = context.fillRect(
                position.x - cursorWidth / 2,
                position.staffTopY - padding,
                cursorWidth,
                position.staffBottomY - position.staffTopY + padding * 2
            )
            _ = context.restore()
        }
        if let sectionOpen {
            drawSectionBracket(context, x: sectionOpen.x, top: sectionOpen.top, bottom: sectionOpen.bottom, opening: true, metrics: metrics)
        }
        if let sectionClose {
            drawSectionBracket(context, x: sectionClose.x, top: sectionClose.top, bottom: sectionClose.bottom, opening: false, metrics: metrics)
        }

        // Bar number at the head of the row, the way printed parts number the
        // start of each system — it's what lets a player find "bar 26".
        // Taken from the stave rather than from a note, so a row opening on a
        // bar of rests is still numbered.
        if let firstMeasure = row.measureIndices.first.map({ measures[$0] }), let rowStaffTop {
            drawMeasureNumber(
                context,
                number: firstMeasure.number,
                x: metrics.horizontalMargin,
                staffTop: rowStaffTop,
                metrics: metrics
            )
        }

        if rowIndex == 0, let tempoBPM {
            drawTempoMarking(context, bpm: tempoBPM, x: metrics.horizontalMargin, metrics: metrics)
        }

        return positions
    }

    /// Which row a playable note is engraved on — what auto-scroll needs to
    /// know which row to bring into view.
    public static func rowIndex(
        forPlayableIndex index: Int,
        score: Score,
        availableWidth: Double,
        metrics: Metrics = Metrics()
    ) -> Int? {
        guard index >= 0 else { return nil }
        let measures = score.measures
        let layout = plan(measures: measures, availableWidth: availableWidth, metrics: metrics)
        var seen = 0
        for (rowIndex, row) in layout.rows.enumerated() {
            let rowNotes = row.measureIndices.reduce(0) { count, mi in
                count + measures[mi].notes.filter { !$0.isRest }.count
            }
            if index < seen + rowNotes { return rowIndex }
            seen += rowNotes
        }
        return layout.rows.isEmpty ? nil : layout.rows.count - 1
    }

    /// How many rows the score wraps to at a given width — what the view
    /// needs to build its lazy stack.
    public static func rowCount(for score: Score, availableWidth: Double, metrics: Metrics = Metrics()) -> Int {
        plan(measures: score.measures, availableWidth: availableWidth, metrics: metrics).rows.count
    }

    /// Playable index the given row starts at, counting non-rest notes in all
    /// preceding measures.
    static func playableIndexOfFirstNote(inRow row: RowLayout, measures: [ScoreMeasure], score: Score) -> Int {
        guard let firstMeasureIndex = row.measureIndices.first else { return 0 }
        return measures.prefix(firstMeasureIndex).reduce(0) { count, measure in
            count + measure.notes.filter { !$0.isRest }.count
        }
    }

    /// The bar number printed at the start of a system, in a soft box.
    private static func drawMeasureNumber(
        _ context: RenderContext,
        number: Int,
        x: Double,
        staffTop: Double,
        metrics: Metrics
    ) {
        let size = metrics.staveSpace * 1.15
        let text = "\(number)"
        let boxWidth = size * (text.count > 1 ? 1.9 : 1.35)
        let boxHeight = size * 1.5
        let y = staffTop - metrics.staveSpace * 3.1

        _ = context.save()
        _ = context.setFillStyle(measureNumberBoxCSS)
        _ = context.fillRect(x, y, boxWidth, boxHeight)
        _ = context.setFillStyle(marginInkCSS)
        _ = context.setFont(FontInfo(family: "Helvetica", size: size, weight: "bold"))
        _ = context.fillText(text, x + boxWidth * 0.28, y + boxHeight * 0.75)
        _ = context.restore()
    }

    /// Tempo marking above the first system, as "= 88" beside a note glyph's
    /// place. Rendered as plain text rather than an engraved metronome mark,
    /// which VexFoundation has no direct API for.
    private static func drawTempoMarking(
        _ context: RenderContext,
        bpm: Double,
        x: Double,
        metrics: Metrics
    ) {
        _ = context.save()
        _ = context.setFillStyle(marginInkCSS)
        _ = context.setFont(FontInfo(family: "Times New Roman", size: metrics.staveSpace * 1.3, weight: "bold", style: "italic"))
        _ = context.fillText("♩ = \(Int(bpm))", x, metrics.staveSpace * 1.6)
        _ = context.restore()
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

    /// Alteration the key signature already applies to a given letter, so the
    /// renderer knows when an accidental is redundant.
    static func keySignatureAlter(forStep step: String, fifths: Int) -> Int {
        let sharpOrder = ["F", "C", "G", "D", "A", "E", "B"]
        let flatOrder = ["B", "E", "A", "D", "G", "C", "F"]
        let letter = step.uppercased()
        if fifths > 0 { return sharpOrder.prefix(min(fifths, 7)).contains(letter) ? 1 : 0 }
        if fifths < 0 { return flatOrder.prefix(min(-fifths, 7)).contains(letter) ? -1 : 0 }
        return 0
    }

    static func accidentalType(forAlter alter: Int) -> AccidentalType? {
        switch alter {
        case 2: return .doubleSharp
        case 1: return .sharp
        case 0: return .natural
        case -1: return .flat
        case -2: return .doubleFlat
        default: return nil
        }
    }

    /// Builds a staff key from the written spelling.
    static func staffKeySpec(step: String, alter: Int, octave: Int) -> StaffKeySpec {
        let letter = NoteLetter(parsing: step) ?? .c
        let accidental: StaffAccidental?
        switch alter {
        case 2: accidental = .doubleSharp
        case 1: accidental = .sharp
        case -1: accidental = .flat
        case -2: accidental = .doubleFlat
        default: accidental = nil
        }
        return StaffKeySpec(letter: letter, accidental: accidental, octave: octave)
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
