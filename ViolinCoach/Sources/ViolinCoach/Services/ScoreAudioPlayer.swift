import AVFoundation
import Combine

/// Plays a whole `Score` back note-by-note, publishing `currentIndex` (into
/// `score.playableNotes`) as each note starts so a view can drive the
/// notation cursor in lockstep — this is Tab 2's "score player" engine.
@MainActor
public final class ScoreAudioPlayer: ObservableObject {
    @Published public private(set) var isPlaying = false
    /// Index into the score's playable (non-rest) notes, or -1 when idle.
    @Published public private(set) var currentIndex = -1

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var playTask: Task<Void, Never>?

    public init() {}

    public func play(score: Score, a4: Double = 440) {
        stop()
        let notes = score.playableNotes
        guard !notes.isEmpty else { return }

        let eng = AVAudioEngine()
        let node = AVAudioPlayerNode()
        eng.attach(node)
        let format = eng.mainMixerNode.outputFormat(forBus: 0)
        eng.connect(node, to: eng.mainMixerNode, format: format)

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            eng.prepare()
            try eng.start()
        } catch {
            #if DEBUG
            print("ScoreAudioPlayer: failed to start engine: \(error)")
            #endif
            return
        }

        engine = eng
        playerNode = node
        node.play()
        isPlaying = true

        playTask = Task { [weak self] in
            for (i, note) in notes.enumerated() {
                if Task.isCancelled { break }
                guard let self else { return }
                self.currentIndex = i
                let seconds = score.seconds(forBeats: note.beatsInQuarters)
                if !note.isRest, let playerNode = self.playerNode {
                    let renderFormat = playerNode.outputFormat(forBus: 0)
                    if let buffer = ToneSynthesizer.renderBuffer(
                        midi: note.midi,
                        seconds: min(1.8, seconds * 0.95),
                        sampleRate: renderFormat.sampleRate,
                        a4: a4
                    ) {
                        playerNode.scheduleBuffer(buffer, at: nil)
                    }
                }
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            }
            guard let self, !Task.isCancelled else { return }
            self.isPlaying = false
        }
    }

    public func stop() {
        playTask?.cancel()
        playTask = nil
        playerNode?.stop()
        engine?.stop()
        engine = nil
        playerNode = nil
        isPlaying = false
        currentIndex = -1
    }
}
