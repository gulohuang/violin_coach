import Foundation

/// A single thing on a child's calendar, flattened out of whatever the system
/// calendar gave us. A plain value type with no EventKit types in it, so
/// everything above the provider layer is testable without a calendar
/// database, and so a different source (a shared JSON file, a school feed)
/// could be dropped in later without touching a view.
public struct CalendarEvent: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    /// Always >= `start`, and for all-day events always the *last instant of
    /// the last day covered* — see `EventNormalization`.
    public let end: Date
    public let isAllDay: Bool
    public let location: String?
    /// Title of the system calendar it came from. Shown nowhere; kept for
    /// diagnosing "why is this on the wrong child's screen".
    public let calendarTitle: String

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        location: String? = nil,
        calendarTitle: String = ""
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.calendarTitle = calendarTitle
    }

    /// True if any part of the event falls inside the given day.
    ///
    /// Half-open on purpose: an event ending exactly at midnight belongs to
    /// the day that just finished, not to the one starting. A zero-length
    /// event (a reminder-style entry) still counts on the day it starts.
    public func occurs(on day: Date, calendar: Calendar) -> Bool {
        guard let dayInterval = calendar.dateInterval(of: .day, for: day) else { return false }
        if start == end { return start >= dayInterval.start && start < dayInterval.end }
        return start < dayInterval.end && end > dayInterval.start
    }
}

/// All-day events arrive from EventKit with inconsistent end dates: sometimes
/// midnight at the *start* of the following day, sometimes the last second of
/// the last day. Left alone, the first form makes a one-day holiday show up on
/// two days. Normalizing once, at the edge, means nothing downstream has to
/// know about the discrepancy.
public enum EventNormalization {
    public static func normalizedEnd(
        start: Date,
        end: Date,
        isAllDay: Bool,
        calendar: Calendar
    ) -> Date {
        guard isAllDay else { return max(end, start) }

        let lastDay: Date
        if end <= start {
            lastDay = start
        } else if let dayStart = calendar.dateInterval(of: .day, for: end)?.start, dayStart == end {
            // Exclusive midnight end: the event's last day is the one before.
            lastDay = calendar.date(byAdding: .day, value: -1, to: end) ?? start
        } else {
            lastDay = end
        }

        guard let interval = calendar.dateInterval(of: .day, for: max(lastDay, start)) else {
            return max(end, start)
        }
        return interval.end.addingTimeInterval(-1)
    }
}
