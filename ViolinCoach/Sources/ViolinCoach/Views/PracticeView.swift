import SwiftUI

/// Tab 3: note-by-note practice. Shows the score with a cursor on the
/// expected note, listens to the mic, and gives live "too high"/"too low"/
/// "in tune" feedback — advancing to the next note automatically once
/// you've held the right pitch for a moment (see `PracticeViewModel`).
struct PracticeView: View {
    @StateObject private var viewModel = PracticeViewModel()
    @StateObject private var library = ScoreLibraryViewModel()

    var body: some View {
        // Same shape as the player tab: the folder is the root, a score is a
        // push, and the system back button is the way out. The navigation bar
        // deliberately stays visible while practising even though the controls
        // fade — it's the only route back to the folder.
        NavigationStack {
            ScoreLibraryView(library: library, prompt: "Choose a score to practise")
                .navigationTitle("Scores")
                .background(Theme.Palette.background.ignoresSafeArea())
                .navigationDestination(for: ScoreEntry.self) { entry in
                    practice(for: entry)
                }
        }
        .onDisappear { viewModel.stop() }
    }

    private func practice(for entry: ScoreEntry) -> some View {
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
        .onAppear { viewModel.load(entry) }
        // Going back releases the microphone. Leaving it live behind a folder
        // listing would keep the recording indicator on for no reason.
        .onDisappear { viewModel.stop() }
    }

    private func loaded(score: Score) -> some View {
        PracticeSessionView(viewModel: viewModel, score: score)
    }
}

struct PracticeView_Previews: PreviewProvider {
    static var previews: some View {
        PracticeView()
    }
}
