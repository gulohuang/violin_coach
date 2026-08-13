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

    /// Engine and node live off the main actor for the same reason as in
    /// `PitchDetector`: `setActive`, `prepare()` and `start()` are blocking
    /// CoreAudio calls, and running them on the main thread stalled the Play
    /// button for as long as they took. Touched only on `audioQueue`.
    private final class PlaybackBox: @unchecked Sendable {
        var engine: AVAudioEngine?
        var node: AVAudioPlayerNode?
    }

    private nonisolated let box = PlaybackBox()
    private nonisolated let audioQueue = DispatchQueue(label: "com.violincoach.score-playback")
    private var playTask: Task<Void, Never>?

    public init() {}

    public func play(score: Score, a4: Double = 440) {
        stop()
        let notes = score.playableNotes
        guard !notes.isEmpty else { return }

        // Flip published state immediately so the button responds on tap; the
        // engine spins up behind it.
        isPlaying = true
        currentIndex = -1

        audioQueue.async { [box] in
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

            box.engine = eng
            box.node = node
            node.play()
        }

        playTask = Task { [weak self] in
            for (i, note) in notes.enumerated() {
                if Task.isCancelled { break }
                guard let self else { return }
                self.currentIndex = i
                let seconds = score.seconds(forBeats: note.beatsInQuarters)
                if !note.isRest {
                    // Rendering the tone buffer is real DSP work — keep it and
                    // the node access on the audio queue, off the main actor.
                    let midi = note.midi
                    let toneSeconds = min(1.8, seconds * 0.95)
                    self.audioQueue.async { [box] in
                        guard let node = box.node else { return }
                        let renderFormat = node.outputFormat(forBus: 0)
                        guard let buffer = ToneSynthesizer.renderBuffer(
                            midi: midi,
                            seconds: toneSeconds,
                            sampleRate: renderFormat.sampleRate,
                            a4: a4
                        ) else { return }
                        // The explicit completionHandler selects the
                        // fire-and-forget overload. In an async context the
                        // bare `scheduleBuffer(_:at:)` resolves to the `async`
                        // one, which suspends until the buffer finishes
                        // playing — that would make each note wait for the
                        // previous one instead of being queued ahead of time,
                        // and the loop here already handles note timing.
                        node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
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
        // Published state first, so the button flips on tap rather than after
        // CoreAudio finishes tearing the engine down.
        isPlaying = false
        currentIndex = -1

        audioQueue.async { [box] in
            box.node?.stop()
            box.engine?.stop()
            box.node = nil
            box.engine = nil
        }
    }
}
