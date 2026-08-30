import SwiftUI

/// Tab 2: renders the score and plays it back with a cursor that follows
/// along, note by note, driven directly by `ScoreAudioPlayer.currentIndex`.
struct ScorePlayerView: View {
    @StateObject private var viewModel = ScorePlayerViewModel()
    @StateObject private var library = ScoreLibraryViewModel()

    var body: some View {
        // The tab opens on the folder and pushes the player. Using a real
        // `NavigationStack` push rather than swapping the root view is what
        // gives the back button, the swipe-back gesture and the title
        // animation without any of them being hand-built.
        NavigationStack {
            ScoreLibraryView(library: library, prompt: "Choose a score to play")
                .navigationTitle("Scores")
                .background(Theme.Palette.background.ignoresSafeArea())
                .navigationDestination(for: ScoreEntry.self) { entry in
                    player(for: entry)
                }
        }
        .onDisappear { viewModel.stop() }
    }

    private func player(for entry: ScoreEntry) -> some View {
        Group {
            if let score = viewModel.score, viewModel.isLoaded(entry) {
                loaded(score: score)
            } else if let error = viewModel.loadError, viewModel.isLoaded(entry) {
                ScoreUnavailableView(title: "Couldn't load score", message: error)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.background.ignoresSafeArea())
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        // Loading here rather than in the view model's init: the score to open
        // isn't known until one is picked.
        .onAppear { viewModel.load(entry) }
        // Leaving the screen silences playback. Without this a score keeps
        // sounding from the folder listing, which is baffling.
        .onDisappear { viewModel.stop() }
    }

    private func loaded(score: Score) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                // The title lives in the navigation bar now that the score is
                // something you navigated to, so this is just the details.
                Text("\(score.beatsPerMeasure)/\(score.beatType) · \(score.playableNotes.count) notes")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Greedy: the score takes whatever height is left above the
                // transport and scrolls internally, so no Spacer here.
                ScoreCanvasView(
                    score: score,
                    currentPlayableIndex: viewModel.currentPlayableIndex,
                    noteSize: viewModel.noteSize,
                    autoScroll: viewModel.autoScroll,
                    tempoBPM: viewModel.tempoBPM
                )
                .frame(maxHeight: .infinity)

                ScoreControlsBar(
                    tempoBPM: $viewModel.tempoBPM,
                    noteSize: $viewModel.noteSize,
                    autoScroll: $viewModel.autoScroll,
                    defaultTempoBPM: score.tempoBPM
                )

                ScoreProgressBar(
                    current: viewModel.currentPlayableIndex,
                    total: score.playableNotes.count
                )
            }

            Button {
                viewModel.togglePlayback()
            } label: {
                Image(systemName: viewModel.isPlaying ? "stop.fill" : "play.fill")
                    .accessibilityLabel(viewModel.isPlaying ? "Stop" : "Play")
            }
            .buttonStyle(CircularTransportButtonStyle(
                tint: viewModel.isPlaying ? Theme.Palette.stop : Theme.Palette.accent
            ))
            .padding(.bottom, Theme.Spacing.lg)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.md)
    }
}

/// A thin progress track shared by the player and practice tabs, driven by
/// position within `Score.playableNotes`.
struct ScoreProgressBar: View {
    let current: Int
    let total: Int

    private var fraction: Double {
        guard total > 0, current >= 0 else { return 0 }
        return Double(current + 1) / Double(total)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Palette.idle.opacity(0.25))
                    Capsule()
                        .fill(Theme.Palette.accent)
                        .frame(width: geo.size.width * fraction)
                        .animation(Theme.Motion.gentle, value: fraction)
                }
            }
            .frame(height: 5)

            Text(current >= 0 ? "Note \(current + 1) of \(total)" : "\(total) notes")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(current >= 0 ? "Note \(current + 1) of \(total)" : "\(total) notes")
    }
}

struct ScorePlayerView_Previews: PreviewProvider {
    static var previews: some View {
        ScorePlayerView()
    }
}
