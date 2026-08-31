import SwiftUI
import VexFoundation

/// Stands in for `ContentUnavailableView`, which is iOS 17+ while this app
/// targets iOS 16. Same role: a centered icon/title/message for an empty or
/// failed state.
struct ScoreUnavailableView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.xl)
    }
}

/// The score, wrapped onto rows that scroll vertically.
///
/// Each row is its own `Canvas` inside a `LazyVStack`, so only the rows on
/// screen are engraved. Drawing the whole score into one tall canvas meant
/// every scroll frame rebuilt every stave, note, beam and slur in the piece,
/// which is what made scrolling stutter — and a cursor move redrew all of it
/// too. Now a cursor move repaints one row.
///
/// The canvas sits on a deliberately light "paper" surface in *both*
/// appearances. `VexCanvas` is a transparent SwiftUI `Canvas` and
/// VexFoundation engraves in black, so on a dark background the score would
/// render invisible. Treating the staff as paper — which is what sheet music
/// is — fixes that without restyling every stave and note for a second ink
/// palette.
struct ScoreCanvasView: View {
    let score: Score
    let currentPlayableIndex: Int
    /// Called with the playable-note index when the score is tapped. Nil makes
    /// the score non-interactive, which is what the player tab wants.
    var onSelectNote: ((Int) -> Void)?
    /// Live intonation on the cursor note: a bar above it when sharp, below
    /// when flat. Nil when in tune or when nothing is being graded.
    var cursorDeviation: ScoreRenderer.CursorDeviation?
    /// Bars chosen for repeat practice, marked with a bracket at each end.
    var sectionMeasures: ClosedRange<Int>?
    var noteSize: ScoreRenderer.NoteSize = .medium
    /// Keep the row holding the cursor centred as playback moves.
    var autoScroll: Bool = false
    /// Printed as a tempo marking above the first system.
    var tempoBPM: Double?

    private var metrics: ScoreRenderer.Metrics { .init(noteSize: noteSize) }

    /// Row the follow last moved to. Auto-scroll fires only when this changes,
    /// so the score holds completely still while you play through a system —
    /// notation shifting under your eyes mid-phrase is worse than a page turn.
    @State private var scrolledRow: Int?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let rowCount = ScoreRenderer.rowCount(for: score, availableWidth: width, metrics: metrics)

            ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: metrics.rowGap) {
                    ForEach(0..<max(1, rowCount), id: \.self) { rowIndex in
                        ScoreRowCanvas(
                            score: score,
                            rowIndex: rowIndex,
                            width: width,
                            currentPlayableIndex: currentPlayableIndex,
                            cursorDeviation: cursorDeviation,
                            sectionMeasures: sectionMeasures,
                            tempoBPM: tempoBPM,
                            metrics: metrics
                        )
                        .equatable()
                        // Hit-testing runs off the same row arithmetic the
                        // renderer uses, so no formatted layout has to escape
                        // the draw closure. The tap's y is row-local, so it's
                        // offset back into score space first.
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let onSelectNote else { return }
                            let scoreY = metrics.topMargin
                                + Double(rowIndex) * (metrics.rowHeight + metrics.rowGap)
                                + location.y
                            guard let index = ScoreRenderer.playableIndex(
                                at: CGPoint(x: location.x, y: scoreY),
                                score: score,
                                availableWidth: width,
                                metrics: metrics
                            ) else { return }
                            onSelectNote(index)
                        }
                        .id(rowIndex)
                    }
                }
                .padding(.vertical, metrics.topMargin)
            }
            // Follow only across a line break, never within a row. Once the
            // system you're playing is on screen it stays put: creeping it
            // upward note by note moves the notation you're currently reading,
            // which is far more distracting than the one move at the break.
            //
            // Anchored centre so the new row lands mid-screen with context
            // above and below, rather than at the very top where you can't see
            // what's coming.
            .onChange(of: currentPlayableIndex) { index in
                guard autoScroll, index >= 0 else { return }
                guard let row = ScoreRenderer.rowIndex(
                    forPlayableIndex: index,
                    score: score,
                    availableWidth: width,
                    metrics: metrics
                ) else { return }
                guard row != scrolledRow else { return }
                scrolledRow = row
                withAnimation(Theme.Motion.follow) {
                    proxy.scrollTo(row, anchor: .center)
                }
            }
            }
        }
        // Edge to edge, no card. Sheet music is a page, not a widget: framing
        // it in a rounded, shadowed card wasted width the notation needed and
        // made the score look like a component rather than something to read.
        .background(Theme.Palette.paper)
    }
}

/// One engraved row, wrapped so SwiftUI can skip the work when nothing about
/// the drawing has changed.
///
/// `Canvas`'s render closure is opaque to SwiftUI, so a `Canvas` is redrawn
/// whenever its parent's body re-runs. That matters here because
/// `PracticeViewModel` ticks at 20 Hz to keep the hold meter smooth: without
/// this gate, every one of those ticks re-engraves every visible system —
/// staves, notes, beams and slurs — to produce an identical image. Comparing
/// the inputs first turns twenty redraws a second into one per actual change.
private struct ScoreRowCanvas: View, Equatable {
    let score: Score
    let rowIndex: Int
    let width: Double
    let currentPlayableIndex: Int
    let cursorDeviation: ScoreRenderer.CursorDeviation?
    let sectionMeasures: ClosedRange<Int>?
    let tempoBPM: Double?
    let metrics: ScoreRenderer.Metrics

    var body: some View {
        VexCanvas(width: width, height: metrics.rowHeight) { context in
            context.clear()
            // Positions are only needed by the hit-test path, which
            // recomputes them from the same plan rather than smuggling them
            // out of a draw closure.
            _ = ScoreRenderer.drawRow(
                score: score,
                rowIndex: rowIndex,
                into: context,
                availableWidth: width,
                cursorPlayableIndex: currentPlayableIndex >= 0 ? currentPlayableIndex : nil,
                cursorDeviation: cursorDeviation,
                sectionMeasures: sectionMeasures,
                tempoBPM: tempoBPM,
                metrics: metrics
            )
        }
        .frame(width: width, height: metrics.rowHeight)
    }
}
