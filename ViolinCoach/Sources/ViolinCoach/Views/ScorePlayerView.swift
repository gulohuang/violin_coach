import SwiftUI

/// Tab 2: renders the score and plays it back with a cursor that follows
/// along, note by note, driven directly by `ScoreAudioPlayer.currentIndex`.
struct ScorePlayerView: View {
    @StateObject private var viewModel = ScorePlayerViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let score = viewModel.score {
                    ScoreCanvasView(score: score, currentPlayableIndex: viewModel.currentPlayableIndex)
                        .padding(.top, 16)

                    Text(score.title)
                        .font(.headline)
                        .padding(.top, 8)

                    Spacer()

                    Button {
                        viewModel.togglePlayback()
                    } label: {
                        Label(
                            viewModel.player.isPlaying ? "Stop" : "Play",
                            systemImage: viewModel.player.isPlaying ? "stop.fill" : "play.fill"
                        )
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.player.isPlaying ? .red : .accentColor)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
                } else if let error = viewModel.loadError {
                    Spacer()
                    ScoreUnavailableView(title: "Couldn't load score", message: error)
                    Spacer()
                } else {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
            .navigationTitle("Score Player")
        }
        .onDisappear { viewModel.player.stop() }
    }
}

struct ScorePlayerView_Previews: PreviewProvider {
    static var previews: some View {
        ScorePlayerView()
    }
}
