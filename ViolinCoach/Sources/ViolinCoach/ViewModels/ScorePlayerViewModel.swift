import Combine
import Foundation

/// Tab 2: loads the score and drives playback. The cursor position is just
/// `player.currentIndex` — the audio player is the single source of truth
/// for "where we are," so the view's cursor can never drift out of sync
/// with what's actually sounding.
@MainActor
public final class ScorePlayerViewModel: ObservableObject {
    @Published public private(set) var score: Score?
    @Published public private(set) var loadError: String?

    public let player: ScoreAudioPlayer
    public var a4Reference: Double = 440

    private var cancellables = Set<AnyCancellable>()

    public init(player: ScoreAudioPlayer = ScoreAudioPlayer()) {
        self.player = player
        // See TunerViewModel: a nested ObservableObject's changes don't reach
        // the object holding it, so without this relay the cursor would never
        // advance and the play button would never flip to stop.
        player.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        load()
    }

    public var isPlaying: Bool {
        player.isPlaying
    }

    public func stop() {
        player.stop()
    }

    public func load() {
        switch ScoreLibrary.loadBundledSample() {
        case .success(let score):
            self.score = score
            self.loadError = nil
        case .failure(let error):
            self.loadError = error.localizedDescription
        }
    }

    public func togglePlayback() {
        guard let score else { return }
        if player.isPlaying {
            player.stop()
        } else {
            player.play(score: score, a4: a4Reference)
        }
    }

    public var currentPlayableIndex: Int {
        player.currentIndex
    }
}
