import XCTest
@testable import ViolinCoach

/// The same cases the ring's index math was validated against numerically
/// before being written in Swift: every hop shape the tap can produce, since
/// `installTap`'s bufferSize is only a hint and iOS may deliver another size.
final class SampleRingTests: XCTestCase {
    /// Feeds a counting sequence through the ring in the given hop sizes and
    /// checks that `latest()` is always exactly the newest `window` samples.
    private func run(window: Int, hops: [Int], file: StaticString = #filePath, line: UInt = #line) {
        let ring = SampleRing(maximumWindow: 4096)
        ring.reset(window: window)
        var stream: [Float] = []
        var next: Float = 0
        for hop in hops {
            let chunk = (0..<hop).map { _ -> Float in
                defer { next += 1 }
                return next
            }
            stream += chunk
            ring.append(chunk)
            if stream.count < window {
                XCTAssertNil(ring.latest(), "must not report a window before hearing one", file: file, line: line)
            } else {
                XCTAssertEqual(ring.latest(), Array(stream.suffix(window)), "after \(stream.count) samples", file: file, line: line)
            }
        }
    }

    func testHopSmallerThanWindow() {
        // The shipped defaults: 1024-frame hop feeding a 2048-sample window.
        run(window: 2048, hops: Array(repeating: 1024, count: 20))
    }

    func testHopEqualToWindow() {
        run(window: 2048, hops: Array(repeating: 2048, count: 10))
    }

    func testHopLargerThanWindow() {
        // iOS granted a bigger buffer than asked for.
        run(window: 2048, hops: Array(repeating: 4096, count: 8))
    }

    func testRaggedHops() {
        run(window: 2048, hops: [700, 1300, 941, 2048, 133, 4096, 512, 2048, 77, 3000])
    }

    func testWindowNotADivisorOfHop() {
        run(window: 1536, hops: Array(repeating: 1024, count: 15))
    }

    func testResetForgetsOldAudio() {
        let ring = SampleRing(maximumWindow: 4096)
        ring.reset(window: 1024)
        ring.append([Float](repeating: 1, count: 2048))
        XCTAssertNotNil(ring.latest())
        ring.reset(window: 1024)
        XCTAssertNil(ring.latest(), "a reset ring must refill before reporting")
    }

    func testWindowClampsToAllocatedStorage() {
        let ring = SampleRing(maximumWindow: 1024)
        ring.reset(window: 8192)
        ring.append([Float](repeating: 1, count: 1024))
        XCTAssertEqual(ring.latest()?.count, 1024)
    }
}
