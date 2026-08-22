import Foundation
import XCTest
@testable import FamilyCalendar

@MainActor
final class KioskViewModelTests: XCTestCase {
    /// A minute boundary, so "did the displayed minute change" tests aren't
    /// sensitive to where in the minute the clock happened to start.
    private let start = Date(timeIntervalSinceReferenceDate: 60 * 1_000_000)

    private func makeViewModel(idleTimeout: TimeInterval = 120) -> KioskViewModel {
        KioskViewModel(now: start, idleTimeout: idleTimeout)
    }

    func testStartsOnTheLockScreen() {
        XCTAssertEqual(makeViewModel().screen, .lock)
    }

    func testOpeningAChildShowsThatChildsCalendar() {
        let viewModel = makeViewModel()
        viewModel.open(.elliot, at: start)
        XCTAssertEqual(viewModel.screen, .calendar)
        XCTAssertEqual(viewModel.selectedChild, .elliot)
    }

    func testStaysOpenWhileWithinTheIdleTimeout() {
        let viewModel = makeViewModel(idleTimeout: 120)
        viewModel.open(.alfred, at: start)
        viewModel.tick(at: start.addingTimeInterval(119))
        XCTAssertEqual(viewModel.screen, .calendar)
    }

    func testReturnsToTheLockScreenOnceIdle() {
        let viewModel = makeViewModel(idleTimeout: 120)
        viewModel.open(.alfred, at: start)
        viewModel.tick(at: start.addingTimeInterval(120))
        XCTAssertEqual(viewModel.screen, .lock)
    }

    /// Touching the screen has to push the deadline out, or the display locks
    /// itself under the hand of someone who is still reading it.
    func testInteractionPostponesTheLock() {
        let viewModel = makeViewModel(idleTimeout: 120)
        viewModel.open(.alfred, at: start)
        viewModel.registerInteraction(at: start.addingTimeInterval(100))
        viewModel.tick(at: start.addingTimeInterval(200))
        XCTAssertEqual(viewModel.screen, .calendar)
        viewModel.tick(at: start.addingTimeInterval(221))
        XCTAssertEqual(viewModel.screen, .lock)
    }

    func testLockingResetsToTheFirstChild() {
        let viewModel = makeViewModel()
        viewModel.open(.elliot, at: start)
        viewModel.lock(at: start)
        XCTAssertEqual(viewModel.selectedChild, Child.everyone[0])
    }

    /// The clock is republished only when the minute it displays changes —
    /// otherwise every countdown badge on screen redraws once a second, all
    /// day, to show the same digits.
    func testClockOnlyRepublishesWhenTheMinuteChanges() {
        let viewModel = makeViewModel()
        viewModel.tick(at: start.addingTimeInterval(30))
        XCTAssertEqual(viewModel.now, start)
        let nextMinute = start.addingTimeInterval(61)
        viewModel.tick(at: nextMinute)
        XCTAssertEqual(viewModel.now, nextMinute)
    }

    /// Ticking while already locked must not thrash the pager selection.
    func testTickingOnTheLockScreenChangesNothing() {
        let viewModel = makeViewModel(idleTimeout: 1)
        viewModel.selectedChildID = Child.elliot.id
        viewModel.tick(at: start.addingTimeInterval(600))
        XCTAssertEqual(viewModel.screen, .lock)
        XCTAssertEqual(viewModel.selectedChild, .elliot)
    }
}
