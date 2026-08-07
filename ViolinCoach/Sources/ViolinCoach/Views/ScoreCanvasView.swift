import SwiftUI
import VexFoundation

/// Renders a `Score` with VexFoundation and highlights the note at
/// `currentPlayableIndex` (matching `Score.playableNotes` numbering; -1 for
/// no highlight). Shared by the Score Player and Practice tabs so both use
/// the exact same rendering and cursor-highlight code.
///
/// The score scrolls horizontally (user-driven) rather than auto-scrolling
/// to follow the cursor — auto-scroll-to-cursor is a known follow-up, not
/// implemented in this first version (see CLAUDE.md).
/// Stands in for `ContentUnavailableView`, which is iOS 17+ while this app
/// targets iOS 16. Same role: a centered icon/title/message for an empty or
/// failed state.
struct ScoreUnavailableView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
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
        .padding(32)
    }
}

struct ScoreCanvasView: View {
    let score: Score
    let currentPlayableIndex: Int

    private let metrics = ScoreRenderer.Metrics()

    var body: some View {
        let size = ScoreRenderer.canvasSize(for: score, metrics: metrics)
        ScrollView(.horizontal, showsIndicators: true) {
            VexCanvas(width: size.width, height: size.height) { context in
                context.clear()
                let layout = ScoreRenderer.draw(score: score, into: context, metrics: metrics)
                guard currentPlayableIndex >= 0,
                      let position = layout.notePositions.first(where: { $0.playableIndex == currentPlayableIndex })
                else { return }

                let cursorWidth = 26.0
                let cursorPadding = 10.0
                _ = context.setFillStyle("rgba(90, 120, 240, 0.28)")
                _ = context.fillRect(
                    position.x - cursorWidth / 2,
                    position.staveY - cursorPadding,
                    cursorWidth,
                    position.staveHeight + cursorPadding * 2
                )
            }
            .frame(width: size.width, height: size.height)
        }
    }
}
