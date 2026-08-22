import Combine
import Foundation

/// Owns *what is on screen* and *when it goes away again* — nothing about
/// calendars.
///
/// The two-screen shape is the whole point of the app. There is no navigation
/// stack, no settings, and no way out of these two states, because the iPad
/// this runs on is meant to sit on a wall in Guided Access: whatever a child
/// can reach from here is the entire app. See `KIOSK-SETUP.md`.
@MainActor
public final class KioskViewModel: ObservableObject {

    public enum Screen: Equatable {
        /// The app's own lock screen: clock plus one tile per child.
        case lock
        /// A child's calendar. Which child lives in `selectedChildID` so that
        /// swiping between children doesn't churn the screen state.
        case calendar
    }

    @Published public private(set) var screen: Screen = .lock
    /// Bound to the paged view, so a horizontal swipe moves between children.
    @Published public var selectedChildID: String = Child.everyone[0].id
    /// Ticks at minute resolution — see `tick(at:)`.
    @Published public private(set) var now: Date

    /// How long a calendar stays up with nobody touching it before the
    /// display returns to the lock screen. Two minutes is long enough to read
    /// a week without the screen changing under you, short enough that the
    /// iPad is back to its neutral state before the next person walks past.
    public let idleTimeout: TimeInterval

    private var lastInteraction: Date
    private var tickCancellable: AnyCancellable?

    public init(now: Date = Date(), idleTimeout: TimeInterval = 120) {
        self.now = now
        self.lastInteraction = now
        self.idleTimeout = idleTimeout
    }

    public var selectedChild: Child {
        Child.child(id: selectedChildID) ?? Child.everyone[0]
    }

    // MARK: - Navigation

    public func open(_ child: Child, at date: Date = Date()) {
        selectedChildID = child.id
        screen = .calendar
        registerInteraction(at: date)
    }

    public func lock(at date: Date = Date()) {
        screen = .lock
        // Reset to the first child so the next person always starts from the
        // same place rather than wherever the last one left the pager.
        selectedChildID = Child.everyone[0].id
        registerInteraction(at: date)
    }

    /// Called for *any* touch anywhere in the app. Cheap on purpose — it runs
    /// on every drag update.
    public func registerInteraction(at date: Date = Date()) {
        lastInteraction = date
    }

    // MARK: - Clock

    public func startClock() {
        guard tickCancellable == nil else { return }
        // One second is the coarsest interval that still returns to the lock
        // screen promptly; `tick` is what keeps this from causing a redraw
        // every second.
        tickCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in self?.tick(at: date) }
    }

    public func stopClock() {
        tickCancellable = nil
    }

    /// Advances the clock and applies the idle rule. Separated from the timer
    /// so tests can drive time forward without waiting for it.
    ///
    /// `now` is only republished when the displayed minute actually changes:
    /// every published change redraws the clock and every countdown badge on
    /// screen, and doing that 60 times a minute to show the same digits is
    /// pure heat on a display that's on permanently.
    public func tick(at date: Date) {
        if minuteIndex(date) != minuteIndex(now) {
            now = date
        }
        if screen != .lock, date.timeIntervalSince(lastInteraction) >= idleTimeout {
            lock(at: date)
        }
    }

    /// Whole minutes since the reference date — timezone-independent, so a
    /// clock change can't wedge the comparison.
    private func minuteIndex(_ date: Date) -> Int {
        Int((date.timeIntervalSinceReferenceDate / 60).rounded(.down))
    }
}
