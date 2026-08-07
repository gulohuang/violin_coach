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

    public init(player: ScoreAudioPlayer = ScoreAudioPlayer()) {
        self.player = player
        load()
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
