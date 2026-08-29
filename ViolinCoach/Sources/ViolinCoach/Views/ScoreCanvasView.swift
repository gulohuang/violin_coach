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
    /// Bars chosen for repeat practice, marked with a bracket at each end.
    var sectionMeasures: ClosedRange<Int>?

    private let metrics = ScoreRenderer.Metrics()

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let rowCount = ScoreRenderer.rowCount(for: score, availableWidth: width, metrics: metrics)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: metrics.rowGap) {
                    ForEach(0..<max(1, rowCount), id: \.self) { rowIndex in
                        VexCanvas(width: width, height: metrics.rowHeight) { context in
                            context.clear()
                            ScoreRenderer.drawRow(
                                score: score,
                                rowIndex: rowIndex,
                                into: context,
                                availableWidth: width,
                                cursorPlayableIndex: currentPlayableIndex >= 0 ? currentPlayableIndex : nil,
                                sectionMeasures: sectionMeasures,
                                metrics: metrics
                            )
                        }
                        .frame(width: width, height: metrics.rowHeight)
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
                    }
                }
                .padding(.vertical, metrics.topMargin)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Palette.paper)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            // A hairline edge instead of a drop shadow: on the page-coloured
            // card a shadow reads as a smudge, while a thin rule reads as the
            // edge of a sheet of paper.
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5)
        )
    }
}
