import SwiftUI

/// Tab 3: note-by-note practice. Shows the score with a cursor on the
/// expected note, listens to the mic, and gives live "too high"/"too low"/
/// "in tune" feedback — advancing to the next note automatically once
/// you've held the right pitch for a moment (see `PracticeViewModel`).
struct PracticeView: View {
    @StateObject private var viewModel = PracticeViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if let score = viewModel.score {
                    loaded(score: score)
                } else if let error = viewModel.loadError {
                    ScoreUnavailableView(title: "Couldn't load score", message: error)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Palette.background.ignoresSafeArea())
            .navigationTitle("Practice")
        }
        .onDisappear { viewModel.stop() }
    }

    private func loaded(score: Score) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            VStack(spacing: Theme.Spacing.sm) {
                ScoreCanvasView(score: score, currentPlayableIndex: viewModel.currentIndex)
                ScoreProgressBar(
                    current: viewModel.currentIndex,
                    total: score.playableNotes.count
                )
            }

            Spacer(minLength: Theme.Spacing.md)

            FeedbackCard(
                isActive: viewModel.isActive,
                isComplete: viewModel.isComplete,
                direction: viewModel.direction,
                expectedNoteLabel: viewModel.expectedNoteLabel
            )

            Spacer(minLength: Theme.Spacing.md)

            Button {
                if viewModel.isActive {
                    viewModel.stop()
                } else {
                    viewModel.start()
                }
            } label: {
                Label(
                    viewModel.isActive ? "Stop" : (viewModel.isComplete ? "Practice Again" : "Start Practice"),
                    systemImage: viewModel.isActive ? "mic.slash.fill" : "mic.fill"
                )
            }
            .buttonStyle(PrimaryActionButtonStyle(
                tint: viewModel.isActive ? Theme.Palette.stop : Theme.Palette.accent
            ))
            .padding(.bottom, Theme.Spacing.lg)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.md)
    }
}

/// Live pitch feedback. Direction is carried by an arrow, a word, *and*
/// position — never by color alone, so the red/green signal at the heart of
/// this screen still works for colorblind players.
private struct FeedbackCard: View {
    let isActive: Bool
    let isComplete: Bool
    let direction: PitchDirection?
    let expectedNoteLabel: String

    private var accent: Color {
        switch direction {
        case .inTune: return Theme.Palette.inTune
        case .tooHigh, .tooLow: return Theme.Palette.outOfTune
        case nil: return Theme.Palette.idle
        }
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            if isComplete {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.Palette.inTune)
                Text("Piece complete")
                    .font(.title3.weight(.semibold))
            } else if isActive {
                VStack(spacing: Theme.Spacing.xs) {
                    Text("Play")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(expectedNoteLabel)
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .animation(Theme.Motion.gentle, value: expectedNoteLabel)
                }

                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: symbolName)
                        .font(.title3.weight(.bold))
                    Text(statusText)
                        .font(.headline)
                }
                .foregroundStyle(accent)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(
                    Capsule().fill(accent.opacity(0.12))
                )
                .animation(Theme.Motion.gentle, value: direction)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Tap Start Practice to begin")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .card(padding: Theme.Spacing.lg)
        .accessibilityElement(children: .combine)
    }

    private var symbolName: String {
        switch direction {
        case .tooHigh: return "arrow.down"   // play *lower* to correct a sharp note
        case .tooLow: return "arrow.up"
        case .inTune: return "checkmark.circle.fill"
        case nil: return "waveform"
        }
    }

    private var statusText: String {
        switch direction {
        case .tooHigh: return "Too high"
        case .tooLow: return "Too low"
        case .inTune: return "In tune"
        case nil: return "Listening…"
        }
    }
}

struct PracticeView_Previews: PreviewProvider {
    static var previews: some View {
        PracticeView()
    }
}
