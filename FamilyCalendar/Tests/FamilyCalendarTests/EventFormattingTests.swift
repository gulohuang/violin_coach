import Foundation
import XCTest
@testable import FamilyCalendar

final class EventFormattingTests: XCTestCase {
    private let calendar = TestCalendar.mondayFirstUTC
    private let day = TestCalendar.date(2026, 8, 19)

    private func lesson(from: Date, to: Date) -> CalendarEvent {
        TestCalendar.event("Violin lesson", from: from, to: to)
    }

    // MARK: - Status

    func testStatusBeforeDuringAndAfter() {
        let event = lesson(
            from: TestCalendar.date(2026, 8, 19, 15, 45),
            to: TestCalendar.date(2026, 8, 19, 16, 30)
        )
        XCTAssertEqual(EventFormatting.status(of: event, now: TestCalendar.date(2026, 8, 19, 15)), .upcoming)
        XCTAssertEqual(EventFormatting.status(of: event, now: TestCalendar.date(2026, 8, 19, 16)), .happeningNow)
        XCTAssertEqual(EventFormatting.status(of: event, now: TestCalendar.date(2026, 8, 19, 17)), .past)
    }

    /// A zero-length entry would otherwise be "past" the instant it began,
    /// greying itself out the moment it became relevant.
    func testZeroLengthEventIsCurrentForAMinute() {
        let start = TestCalendar.date(2026, 8, 19, 8)
        let reminder = TestCalendar.event("Library books due", from: start, to: start)
        XCTAssertEqual(EventFormatting.status(of: reminder, now: start.addingTimeInterval(30)), .happeningNow)
        XCTAssertEqual(EventFormatting.status(of: reminder, now: start.addingTimeInterval(90)), .past)
    }

    // MARK: - Countdown

    func testCountdownWording() {
        let start = TestCalendar.date(2026, 8, 19, 16)
        let event = lesson(from: start, to: start.addingTimeInterval(3600))
        func countdown(minutesBefore: Double) -> String? {
            EventFormatting.countdown(
                to: event,
                now: start.addingTimeInterval(-minutesBefore * 60),
                calendar: calendar
            )
        }
        XCTAssertEqual(countdown(minutesBefore: 20), "in 20 min")
        XCTAssertEqual(countdown(minutesBefore: 90), "in 1 hr 30 min")
        XCTAssertEqual(countdown(minutesBefore: 120), "in 2 hr")
        XCTAssertEqual(countdown(minutesBefore: 0.5), "in a minute")
    }

    func testCountdownIsNowWhileRunningAndNothingOnceFinished() {
        let start = TestCalendar.date(2026, 8, 19, 16)
        let event = lesson(from: start, to: start.addingTimeInterval(3600))
        XCTAssertEqual(EventFormatting.countdown(to: event, now: start.addingTimeInterval(600), calendar: calendar), "Now")
        XCTAssertNil(EventFormatting.countdown(to: event, now: start.addingTimeInterval(7200), calendar: calendar))
    }

    /// Past twelve hours out the clock time is the useful information and a
    /// countdown is just noise.
    func testNoCountdownBeyondTwelveHours() {
        let start = TestCalendar.date(2026, 8, 20, 9)
        let event = lesson(from: start, to: start.addingTimeInterval(3600))
        XCTAssertNil(EventFormatting.countdown(to: event, now: TestCalendar.date(2026, 8, 19, 9), calendar: calendar))
    }

    // MARK: - Time summary
    //
    // Only the parts that aren't locale-dependent are asserted — the clock
    // times themselves come from Foundation's own formatting.

    func testAllDayEventsReadAsAllDay() {
        let allDay = CalendarEvent(
            id: "x", title: "Non-uniform day", start: day,
            end: EventNormalization.normalizedEnd(start: day, end: day, isAllDay: true, calendar: calendar),
            isAllDay: true
        )
        XCTAssertEqual(EventFormatting.timeSummary(for: allDay, on: day, calendar: calendar), "All day")
    }

    func testEventArrivingFromAnEarlierDayReadsAsAnEndTime() {
        let event = lesson(
            from: TestCalendar.date(2026, 8, 18, 20),
            to: TestCalendar.date(2026, 8, 19, 10)
        )
        XCTAssertTrue(
            EventFormatting.timeSummary(for: event, on: day, calendar: calendar).hasPrefix("Until "),
            "an event that started yesterday should only show when it ends"
        )
    }

    func testEventRunningIntoTheNextDayReadsAsAStartTime() {
        let event = lesson(
            from: TestCalendar.date(2026, 8, 19, 20),
            to: TestCalendar.date(2026, 8, 20, 10)
        )
        XCTAssertTrue(EventFormatting.timeSummary(for: event, on: day, calendar: calendar).hasPrefix("From "))
    }

    func testAWholeDaySpanReadsAsAllDayEvenWhenNotFlagged() {
        let trip = lesson(
            from: TestCalendar.date(2026, 8, 18, 9),
            to: TestCalendar.date(2026, 8, 21, 17)
        )
        XCTAssertEqual(EventFormatting.timeSummary(for: trip, on: day, calendar: calendar), "All day")
    }

    func testOrdinaryEventShowsARange() {
        let event = lesson(
            from: TestCalendar.date(2026, 8, 19, 15, 45),
            to: TestCalendar.date(2026, 8, 19, 16, 30)
        )
        XCTAssertTrue(EventFormatting.timeSummary(for: event, on: day, calendar: calendar).contains("–"))
    }

    // MARK: - Headlines

    func testDayHeadlinesUseRelativeWordsWhereTheyApply() {
        let now = TestCalendar.date(2026, 8, 19, 12)
        XCTAssertEqual(EventFormatting.dayHeadline(for: TestCalendar.date(2026, 8, 19), now: now, calendar: calendar), "Today")
        XCTAssertEqual(EventFormatting.dayHeadline(for: TestCalendar.date(2026, 8, 20), now: now, calendar: calendar), "Tomorrow")
        XCTAssertEqual(EventFormatting.dayHeadline(for: TestCalendar.date(2026, 8, 18), now: now, calendar: calendar), "Yesterday")
        XCTAssertNotEqual(EventFormatting.dayHeadline(for: TestCalendar.date(2026, 8, 22), now: now, calendar: calendar), "Today")
    }

    func testTileSummaryCountsReadAsPlainWords() {
        XCTAssertEqual(EventFormatting.summary(count: 0), "Nothing today")
        XCTAssertEqual(EventFormatting.summary(count: 1), "1 thing today")
        XCTAssertEqual(EventFormatting.summary(count: 4), "4 things today")
    }
}
