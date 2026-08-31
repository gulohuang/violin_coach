import SwiftUI

/// Tab 2: scales. Choose a key, mode, range and direction; the scale is
/// engraved and can be played back with the cursor following, on the same
/// violin tone the score player uses.
///
/// Everything below the picker row is the score player's machinery reused
/// verbatim — the scale is just a `Score` that happens to be generated rather
/// than parsed, which is the whole reason `ScaleGenerator` produces one.
struct ScaleView: View {
    @StateObject private var viewModel = ScaleViewModel()

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Palette.background.ignoresSafeArea())
                .navigationTitle("Scales")
        }
        .onDisappear { viewModel.stop() }
    }

    private var content: some View {
        VStack(spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                pickers

                if let score = viewModel.score {
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
                        defaultTempoBPM: ScaleViewModel.defaultTempoBPM
                    )

                    ScoreProgressBar(
                        current: viewModel.currentPlayableIndex,
                        total: score.playableNotes.count
                    )
                } else {
                    Spacer()
                }
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

    /// Four menus on one wrapping row. Menus rather than segmented controls
    /// because twelve keys and five modes don't fit across a phone, and these
    /// are chosen once at the start of a practice session rather than adjusted
    /// while playing.
    private var pickers: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Menu {
                    ForEach(viewModel.availableRoots) { root in
                        Button(root.label) { viewModel.select(root: root) }
                    }
                } label: {
                    chip(viewModel.root.label, icon: "key")
                }

                Menu {
                    ForEach(ScaleType.allCases) { type in
                        Button(type.label) { viewModel.select(type: type) }
                    }
                } label: {
                    chip(viewModel.type.label, icon: "music.quarternote.3")
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: Theme.Spacing.sm) {
                Menu {
                    // The ceiling moves with the key: three octaves of G fits
                    // on the instrument, three of F♯ doesn't.
                    ForEach(1...viewModel.maximumOctaves, id: \.self) { count in
                        Button(count == 1 ? "1 octave" : "\(count) octaves") {
                            viewModel.select(octaves: count)
                        }
                    }
                } label: {
                    chip(viewModel.octaves == 1 ? "1 octave" : "\(viewModel.octaves) octaves",
                         icon: "arrow.up.and.down")
                }

                Menu {
                    ForEach(ScaleDirection.allCases) { direction in
                        Button(direction.label) { viewModel.select(direction: direction) }
                    }
                } label: {
                    chip(viewModel.direction.label, icon: "arrow.turn.up.right")
                }

                Spacer(minLength: 0)
            }

            if let summary = viewModel.rangeSummary {
                Text(summary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chip(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Capsule().fill(Theme.Palette.cardSurface))
            .foregroundStyle(Color.primary)
    }
}

struct ScaleView_Previews: PreviewProvider {
    static var previews: some View {
        ScaleView()
    }
}
