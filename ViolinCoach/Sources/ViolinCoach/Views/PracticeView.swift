import SwiftUI

/// Tab 3: note-by-note practice. Shows the score with a cursor on the
/// expected note, listens to the mic, and gives live "too high"/"too low"/
/// "in tune" feedback — advancing to the next note automatically once
/// you've held the right pitch for a moment (see `PracticeViewModel`).
struct PracticeView: View {
    @StateObject private var viewModel = PracticeViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let score = viewModel.score {
                    ScoreCanvasView(score: score, currentPlayableIndex: viewModel.currentIndex)
                        .padding(.top, 16)

                    Spacer()

                    FeedbackBadge(
                        isActive: viewModel.isActive,
                        isComplete: viewModel.isComplete,
                        direction: viewModel.direction,
                        expectedNoteLabel: viewModel.expectedNoteLabel
                    )
                    .padding(.horizontal, 32)

                    Spacer()

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
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.isActive ? .red : .accentColor)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
                } else if let error = viewModel.loadError {
                    Spacer()
                    ContentUnavailableView("Couldn't load score", systemImage: "exclamationmark.triangle", description: Text(error))
                    Spacer()
                } else {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
            .navigationTitle("Practice")
        }
        .onDisappear { viewModel.stop() }
    }
}

private struct FeedbackBadge: View {
    let isActive: Bool
    let isComplete: Bool
    let direction: PitchDirection?
    let expectedNoteLabel: String

    var body: some View {
        VStack(spacing: 12) {
            if isComplete {
                Label("Piece complete!", systemImage: "checkmark.seal.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.green)
            } else if isActive {
                Text("Play \(expectedNoteLabel)")
                    .font(.title.bold())

                Group {
                    switch direction {
                    case .tooHigh:
                        Label("Too high", systemImage: "arrow.up")
                            .foregroundStyle(.orange)
                    case .tooLow:
                        Label("Too low", systemImage: "arrow.down")
                            .foregroundStyle(.orange)
                    case .inTune:
                        Label("In tune", systemImage: "checkmark")
                            .foregroundStyle(.green)
                    case nil:
                        Label("Listening…", systemImage: "waveform")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.title3.bold())
                .animation(.snappy, value: direction)
            } else {
                Text("Tap Start Practice to begin")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

#Preview {
    PracticeView()
}
