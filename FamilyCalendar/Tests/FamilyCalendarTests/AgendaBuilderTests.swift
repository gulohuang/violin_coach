import Foundation
import XCTest
@testable import FamilyCalendar

final class AgendaBuilderTests: XCTestCase {
    private let calendar = TestCalendar.mondayFirstUTC

    /// A week away shown only under the Monday it began is the failure this
    /// guards: it has to appear on every day it covers.
    func testMultiDayEventAppearsOnEveryDayItTouches() {
        let trip = TestCalendar.event(
            "Camping",
            from: TestCalendar.date(2026, 8, 19, 9),
            to: TestCalendar.date(2026, 8, 21, 17)
        )
        for day in 19...21 {
            let events = AgendaBuilder.events(
                on: TestCalendar.date(2026, 8, day),
                from: [trip],
                calendar: calendar
            )
            XCTAssertEqual(events.map(\.title), ["Camping"], "missing on the \(day)th")
        }
    }

    func testEventIsAbsentFromDaysOutsideItsSpan() {
        let trip = TestCalendar.event(
            "Camping",
            from: TestCalendar.date(2026, 8, 19, 9),
            to: TestCalendar.date(2026, 8, 21, 17)
        )
        XCTAssertTrue(AgendaBuilder.events(on: TestCalendar.date(2026, 8, 18), from: [trip], calendar: calendar).isEmpty)
        XCTAssertTrue(AgendaBuilder.events(on: TestCalendar.date(2026, 8, 22), from: [trip], calendar: calendar).isEmpty)
    }

    /// Half-open day boundaries: an event finishing at midnight belongs to the
    /// day that just ended, not to the one starting.
    func testEventEndingExactlyAtMidnightDoesNotLeakIntoTheNextDay() {
        let party = TestCalendar.event(
            "Sleepover",
            from: TestCalendar.date(2026, 8, 19, 20),
            to: TestCalendar.date(2026, 8, 20, 0)
        )
        XCTAssertEqual(
            AgendaBuilder.events(on: TestCalendar.date(2026, 8, 19), from: [party], calendar: calendar).count, 1
        )
        XCTAssertTrue(
            AgendaBuilder.events(on: TestCalendar.date(2026, 8, 20), from: [party], calendar: calendar).isEmpty
        )
    }

    func testZeroLengthEventStillCountsOnItsDay() {
        let reminder = TestCalendar.event(
            "Library books due",
            from: TestCalendar.date(2026, 8, 19, 8),
            to: TestCalendar.date(2026, 8, 19, 8)
        )
        XCTAssertEqual(
            AgendaBuilder.events(on: TestCalendar.date(2026, 8, 19), from: [reminder], calendar: calendar).count, 1
        )
    }

    func testAllDayEventsSortBeforeTimedOnes() {
        let day = TestCalendar.date(2026, 8, 19)
        let timed = TestCalendar.event(
            "Swimming",
            from: TestCalendar.date(2026, 8, 19, 8, 30),
            to: TestCalendar.date(2026, 8, 19, 9, 30)
        )
        let allDay = CalendarEvent(
            id: "mufti",
            title: "Non-uniform day",
            start: day,
            end: EventNormalization.normalizedEnd(start: day, end: day, isAllDay: true, calendar: calendar),
            isAllDay: true
        )
        let events = AgendaBuilder.events(on: day, from: [timed, allDay], calendar: calendar)
        XCTAssertEqual(events.map(\.title), ["Non-uniform day", "Swimming"])
    }

    func testTimedEventsSortByStart() {
        let day = TestCalendar.date(2026, 8, 19)
        let late = TestCalendar.event("Judo", from: TestCalendar.date(2026, 8, 19, 16), to: TestCalendar.date(2026, 8, 19, 17))
        let early = TestCalendar.event("Assembly", from: TestCalendar.date(2026, 8, 19, 9), to: TestCalendar.date(2026, 8, 19, 10))
        XCTAssertEqual(
            AgendaBuilder.events(on: day, from: [late, early], calendar: calendar).map(\.title),
            ["Assembly", "Judo"]
        )
    }

    /// A timed event that swallows the whole day should read as "all day" on
    /// that day even though it isn't flagged as one.
    func testTimedEventSpanningAWholeDayCountsAsCoveringIt() {
        let middleDay = TestCalendar.date(2026, 8, 20)
        let trip = TestCalendar.event(
            "Camping",
            from: TestCalendar.date(2026, 8, 19, 9),
            to: TestCalendar.date(2026, 8, 21, 17)
        )
        XCTAssertTrue(AgendaBuilder.coversWholeDay(trip, day: middleDay, calendar: calendar))
        XCTAssertFalse(AgendaBuilder.coversWholeDay(trip, day: TestCalendar.date(2026, 8, 19), calendar: calendar))
    }

    func testAgendaCoversEveryRequestedDayIncludingEmptyOnes() {
        let days = WeekPlanner.week(containing: TestCalendar.date(2026, 8, 19), calendar: calendar)
        let agenda = AgendaBuilder.agenda(for: days, events: [], calendar: calendar)
        XCTAssertEqual(agenda.count, 7)
        XCTAssertTrue(agenda.allSatisfy(\.isEmpty))
    }
}

final class EventNormalizationTests: XCTestCase {
    private let calendar = TestCalendar.mondayFirstUTC

    /// EventKit's usual form for a one-day all-day event: an end at midnight
    /// on the *following* day. Left alone it puts the event on two days.
    func testExclusiveMidnightEndCollapsesToTheLastDayCovered() {
        let start = TestCalendar.date(2026, 8, 19)
        let end = TestCalendar.date(2026, 8, 20)
        let normalized = EventNormalization.normalizedEnd(start: start, end: end, isAllDay: true, calendar: calendar)
        XCTAssertTrue(calendar.isDate(normalized, inSameDayAs: start))
        XCTAssertLessThan(normalized, end)
    }

    func testAllDayEndEqualToStartBecomesEndOfThatDay() {
        let start = TestCalendar.date(2026, 8, 19)
        let normalized = EventNormalization.normalizedEnd(start: start, end: start, isAllDay: true, calendar: calendar)
        XCTAssertTrue(calendar.isDate(normalized, inSameDayAs: start))
        XCTAssertGreaterThan(normalized, start)
    }

    func testMultiDayAllDayEventKeepsItsLastDay() {
        let start = TestCalendar.date(2026, 8, 19)
        let end = TestCalendar.date(2026, 8, 22)
        let normalized = EventNormalization.normalizedEnd(start: start, end: end, isAllDay: true, calendar: calendar)
        XCTAssertTrue(calendar.isDate(normalized, inSameDayAs: TestCalendar.date(2026, 8, 21)))
    }

    func testTimedEventsArePassedThrough() {
        let start = TestCalendar.date(2026, 8, 19, 9)
        let end = TestCalendar.date(2026, 8, 19, 10)
        XCTAssertEqual(
            EventNormalization.normalizedEnd(start: start, end: end, isAllDay: false, calendar: calendar), end
        )
    }

    func testEndBeforeStartIsClampedRatherThanInverted() {
        let start = TestCalendar.date(2026, 8, 19, 9)
        let end = TestCalendar.date(2026, 8, 19, 8)
        XCTAssertEqual(
            EventNormalization.normalizedEnd(start: start, end: end, isAllDay: false, calendar: calendar), start
        )
    }
}
