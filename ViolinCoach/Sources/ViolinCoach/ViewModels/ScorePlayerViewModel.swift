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

    /// Playback tempo. Starts from the score's own marking and is then the
    /// user's to change; the score is never mutated.
    @Published public var tempoBPM: Double = 120
    @Published public var noteSize: ScoreRenderer.NoteSize = .mediumSmall
    /// Keep the row being played centred on screen.
    @Published public var autoScroll = true

    private var cancellables = Set<AnyCancellable>()
    /// Which score is currently loaded, so returning to the same one from the
    /// folder doesn't re-parse it — and switching to a different one does.
    private var loadedEntryID: String?

    public init(player: ScoreAudioPlayer = ScoreAudioPlayer()) {
        self.player = player
        // See TunerViewModel: a nested ObservableObject's changes don't reach
        // the object holding it, so without this relay the cursor would never
        // advance and the play button would never flip to stop.
        player.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    public var isPlaying: Bool {
        player.isPlaying
    }

    public func stop() {
        player.stop()
    }

    /// Whether `score` is this entry's. The view checks it before rendering,
    /// so pushing a second score never shows a frame of the previous one under
    /// the new title while `onAppear` catches up.
    public func isLoaded(_ entry: ScoreEntry) -> Bool { loadedEntryID == entry.id }

    public func load(_ entry: ScoreEntry) {
        guard loadedEntryID != entry.id else { return }
        player.stop()
        loadedEntryID = entry.id
        switch ScoreLibrary.load(entry) {
        case .success(let score):
            self.score = score
            // Each score brings its own marking; the tempo the user set for
            // the last piece has nothing to do with this one.
            self.tempoBPM = score.tempoBPM
            self.loadError = nil
        case .failure(let error):
            self.score = nil
            self.loadError = error.localizedDescription
        }
    }

    public func togglePlayback() {
        guard let score else { return }
        if player.isPlaying {
            player.stop()
        } else {
            player.play(score: score, a4: a4Reference, tempoBPM: tempoBPM)
        }
    }

    public var currentPlayableIndex: Int {
        player.currentIndex
    }
}
