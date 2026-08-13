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

/// Renders a `Score` with VexFoundation and highlights the note at
/// `currentPlayableIndex` (matching `Score.playableNotes` numbering; -1 for
/// no highlight). Shared by the Score Player and Practice tabs so both use
/// the exact same rendering and cursor-highlight code.
///
/// The canvas sits on a deliberately light "paper" surface in *both*
/// appearances. `VexCanvas` is a transparent SwiftUI `Canvas` and
/// VexFoundation engraves in black, so on a dark background the score would
/// render invisible. Treating the staff as paper — which is what sheet music
/// is — fixes that without having to restyle every stave and note for a
/// second ink palette.
///
/// The score scrolls horizontally by hand; auto-scrolling to keep the cursor
/// on screen is a known follow-up (see CLAUDE.md).
struct ScoreCanvasView: View {
    let score: Score
    let currentPlayableIndex: Int

    private let metrics = ScoreRenderer.Metrics()

    var body: some View {
        let size = ScoreRenderer.canvasSize(for: score, metrics: metrics)
        ScrollView(.horizontal, showsIndicators: false) {
            VexCanvas(width: size.width, height: size.height) { context in
                context.clear()
                let layout = ScoreRenderer.draw(score: score, into: context, metrics: metrics)
                guard currentPlayableIndex >= 0,
                      let position = layout.notePositions.first(where: { $0.playableIndex == currentPlayableIndex })
                else { return }

                let cursorWidth = 26.0
                let cursorPadding = 10.0
                _ = context.setFillStyle(Theme.Palette.scoreCursorCSS)
                _ = context.fillRect(
                    position.x - cursorWidth / 2,
                    position.staveY - cursorPadding,
                    cursorWidth,
                    position.staveHeight + cursorPadding * 2
                )
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(height: size.height)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Palette.paper)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 4)
    }
}
