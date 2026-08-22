import Foundation
import XCTest
@testable import FamilyCalendar

final class WeekPlannerTests: XCTestCase {
    private let calendar = TestCalendar.mondayFirstUTC

    func testWeekIsSevenConsecutiveDays() {
        let days = WeekPlanner.week(containing: TestCalendar.date(2026, 8, 19), calendar: calendar)
        XCTAssertEqual(days.count, 7)
        for (previous, next) in zip(days, days.dropFirst()) {
            XCTAssertEqual(calendar.date(byAdding: .day, value: 1, to: previous), next)
        }
    }

    /// Wednesday 19 August 2026 sits in the week beginning Monday the 17th —
    /// but only in a calendar whose weeks start on Monday, which is why the
    /// calendar is injected rather than taken from the machine.
    func testWeekStartsOnTheCalendarsFirstWeekday() {
        let days = WeekPlanner.week(containing: TestCalendar.date(2026, 8, 19), calendar: calendar)
        XCTAssertEqual(days.first, TestCalendar.date(2026, 8, 17))
        XCTAssertEqual(days.last, TestCalendar.date(2026, 8, 23))
    }

    /// The Sunday trap: with Monday-first weeks, Sunday closes the week it
    /// belongs to rather than opening the next one.
    func testSundayBelongsToTheWeekThatPrecedesIt() {
        let days = WeekPlanner.week(containing: TestCalendar.date(2026, 8, 23, 22), calendar: calendar)
        XCTAssertEqual(days.first, TestCalendar.date(2026, 8, 17))
    }

    func testSundayFirstCalendarStartsItsWeekOnSunday() {
        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        let days = WeekPlanner.week(containing: TestCalendar.date(2026, 8, 19), calendar: sundayFirst)
        XCTAssertEqual(days.first, TestCalendar.date(2026, 8, 16))
    }

    func testIntervalSpansMidnightToMidnight() {
        let days = WeekPlanner.week(containing: TestCalendar.date(2026, 8, 19), calendar: calendar)
        let interval = WeekPlanner.interval(covering: days, calendar: calendar)
        XCTAssertEqual(interval.start, TestCalendar.date(2026, 8, 17))
        XCTAssertEqual(interval.end, TestCalendar.date(2026, 8, 24))
    }

    func testShiftMovesAWholeWeek() {
        let shifted = WeekPlanner.shift(TestCalendar.date(2026, 8, 19), byWeeks: -1, calendar: calendar)
        XCTAssertEqual(
            WeekPlanner.week(containing: shifted, calendar: calendar).first,
            TestCalendar.date(2026, 8, 10)
        )
    }
}

final class CalendarMatchingTests: XCTestCase {
    private let all = [
        CalendarDescriptor(identifier: "1", title: "Alfred"),
        CalendarDescriptor(identifier: "2", title: "elliot's school"),
        CalendarDescriptor(identifier: "3", title: "Work"),
        CalendarDescriptor(identifier: "4", title: "Holidays"),
    ]

    func testMatchesAnExactlyNamedCalendar() {
        XCTAssertEqual(CalendarMatching.calendars(for: .alfred, in: all).map(\.identifier), ["1"])
    }

    /// "elliot's school" should match Elliot: families name calendars however
    /// they like, and requiring an exact title would fail silently.
    func testMatchesCaseInsensitivelyAndOnSubstrings() {
        XCTAssertEqual(CalendarMatching.calendars(for: .elliot, in: all).map(\.identifier), ["2"])
    }

    func testDoesNotMatchUnrelatedCalendars() {
        let unrelated = [CalendarDescriptor(identifier: "9", title: "Bin collection")]
        XCTAssertTrue(CalendarMatching.calendars(for: .alfred, in: unrelated).isEmpty)
    }

    /// A calendar shared by both children legitimately belongs to both.
    func testACalendarNamingBothChildrenMatchesBoth() {
        let shared = [CalendarDescriptor(identifier: "5", title: "Alfred & Elliot")]
        XCTAssertEqual(CalendarMatching.calendars(for: .alfred, in: shared).count, 1)
        XCTAssertEqual(CalendarMatching.calendars(for: .elliot, in: shared).count, 1)
    }
}
