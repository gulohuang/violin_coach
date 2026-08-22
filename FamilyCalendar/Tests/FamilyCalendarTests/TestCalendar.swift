import Foundation
@testable import FamilyCalendar

/// A fixed calendar for every test: Gregorian, UTC, weeks starting Monday.
///
/// Nothing here uses `Calendar.current` — the code under test is all about
/// day boundaries and week starts, so a suite that inherits the machine's
/// locale would pass or fail depending on where it ran.
enum TestCalendar {
    static var mondayFirstUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    static func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0,
        calendar: Calendar = TestCalendar.mondayFirstUTC
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    static func event(
        _ title: String,
        from start: Date,
        to end: Date,
        allDay: Bool = false
    ) -> CalendarEvent {
        CalendarEvent(
            id: "\(title)-\(start.timeIntervalSinceReferenceDate)",
            title: title,
            start: start,
            end: end,
            isAllDay: allDay
        )
    }
}
