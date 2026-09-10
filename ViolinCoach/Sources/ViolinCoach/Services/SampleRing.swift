import Foundation

/// A fixed-capacity ring of the newest microphone samples, so the analysis
/// window no longer has to fit inside a single tap buffer.
///
/// Before this existed, one tap callback was one analysis: the window was
/// the newest slice of that one buffer, so a 2048-sample window forced a
/// 4096-frame tap — an 85 ms hop at 48 kHz, with the older half of every
/// buffer thrown away unanalysed. The wait for readings, not the analysis
/// itself, was the pitch-display lag on the Tuner, Practice and Fine Tune
/// tabs. The ring decouples the two: the tap can be small (the hop, which
/// sets both the detection rate and the freshness of every reading) while
/// the window stays as long as YIN wants, spanning as many buffers as it
/// takes.
///
/// Threading: `append` and `latest` are only ever called from the audio
/// tap's callback thread, one after the other, so they need no
/// synchronisation with each other. `reset` runs on the engine's serial
/// queue between `removeTap` and `installTap`, while no tap is delivering.
/// Storage is allocated once at the maximum window and never reallocated,
/// so even a straggling callback racing a reset can at worst read mixed
/// samples for one analysis — never unsafe memory. That discipline is what
/// makes the `@unchecked` conformance honest.
final class SampleRing: @unchecked Sendable {
    private var storage: [Float]
    private var window: Int
    private var writeIndex = 0
    private var filled = 0

    init(maximumWindow: Int) {
        let capacity = max(1, maximumWindow)
        storage = [Float](repeating: 0, count: capacity)
        window = capacity
    }

    /// Empties the ring and sets the window `latest()` returns. Clamped to
    /// the storage allocated at init, because growing it here would
    /// reallocate under a tap callback still in flight.
    func reset(window newWindow: Int) {
        window = max(1, min(newWindow, storage.count))
        writeIndex = 0
        filled = 0
    }

    /// Appends one tap buffer. A buffer longer than the window contributes
    /// only its newest samples — the rest could never appear in `latest()`.
    func append(_ samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        let cap = window
        let start = max(0, count - cap)
        var remaining = count - start
        var source = samples + start
        storage.withUnsafeMutableBufferPointer { dst in
            guard let base = dst.baseAddress else { return }
            while remaining > 0 {
                let chunk = min(remaining, cap - writeIndex)
                (base + writeIndex).update(from: source, count: chunk)
                source += chunk
                remaining -= chunk
                writeIndex = (writeIndex + chunk) % cap
            }
        }
        filled = min(cap, filled + count - start)
    }

    /// Convenience for callers (and tests) holding an array.
    func append(_ samples: [Float]) {
        samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            append(base, count: buffer.count)
        }
    }

    /// The newest `window` samples in chronological order, or nil until the
    /// ring has heard that much audio — which only happens briefly, right
    /// after a start.
    func latest() -> [Float]? {
        let cap = window
        guard filled >= cap else { return nil }
        var out = [Float](repeating: 0, count: cap)
        let tail = cap - writeIndex
        out.withUnsafeMutableBufferPointer { dst in
            storage.withUnsafeBufferPointer { src in
                guard let d = dst.baseAddress, let s = src.baseAddress else { return }
                d.update(from: s + writeIndex, count: tail)
                if writeIndex > 0 {
                    (d + tail).update(from: s, count: writeIndex)
                }
            }
        }
        return out
    }
}
