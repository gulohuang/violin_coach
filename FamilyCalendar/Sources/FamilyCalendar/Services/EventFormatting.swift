import Foundation

public enum EventStatus: Sendable, Equatable {
    case past
    case happeningNow
    case upcoming
}

/// All the "what does this event say on screen" logic, kept pure and with
/// `now` passed in rather than read from the clock, so every case below is
/// testable without waiting for real time to pass.
///
/// Formatting goes through `Date.FormatStyle` rather than `DateFormatter`
/// because a cached `DateFormatter` can't be a `static let` under Swift 6's
/// concurrency checking, and building one per row is needlessly slow.
public enum EventFormatting {

    public static func status(of event: CalendarEvent, now: Date) -> EventStatus {
        if now < event.start { return .upcoming }
        // Zero-length events would otherwise be "past" the instant they start;
        // give them a minute of being current so they don't grey out on arrival.
        let end = max(event.end, event.start.addingTimeInterval(60))
        return now < end ? .happeningNow : .past
    }

    /// A short "when" for a row, expressed relative to the day it's shown on:
    /// an event running from yesterday into this afternoon reads "Until 2 PM"
    /// here, not as a date range nobody wants to parse.
    public static func timeSummary(
        for event: CalendarEvent,
        on day: Date,
        calendar: Calendar
    ) -> String {
        guard let dayInterval = calendar.dateInterval(of: .day, for: day) else {
            return clockTime(event.start)
        }
        if AgendaBuilder.coversWholeDay(event, day: day, calendar: calendar) {
            return "All day"
        }
        let startsEarlier = event.start < dayInterval.start
        let endsLater = event.end >= dayInterval.end
        if startsEarlier { return "Until \(clockTime(event.end))" }
        if endsLater { return "From \(clockTime(event.start))" }
        if event.end <= event.start { return clockTime(event.start) }
        return "\(clockTime(event.start)) – \(clockTime(event.end))"
    }

    /// "Now", "in 20 min", "in 3 hr" — or nil when there's nothing useful to
    /// say. Only the next 12 hours get a countdown; beyond that the time of
    /// day is the more informative thing, and the badge is just noise.
    public static func countdown(to event: CalendarEvent, now: Date, calendar: Calendar) -> String? {
        switch status(of: event, now: now) {
        case .past:
            return nil
        case .happeningNow:
            return "Now"
        case .upcoming:
            let seconds = event.start.timeIntervalSince(now)
            guard seconds < 12 * 3600 else { return nil }
            let minutes = Int((seconds / 60).rounded(.up))
            if minutes <= 1 { return "in a minute" }
            if minutes < 60 { return "in \(minutes) min" }
            let hours = minutes / 60
            let remainder = minutes % 60
            if remainder == 0 { return "in \(hours) hr" }
            return "in \(hours) hr \(remainder) min"
        }
    }

    /// "Today", "Tomorrow", "Yesterday", else the weekday name. A wall
    /// display is read at a glance from a distance; "Today" lands faster than
    /// a date does.
    public static func dayHeadline(for day: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(day, inSameDayAs: tomorrow) { return "Tomorrow" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide))
    }

    /// The subtitle under the headline: "Saturday 22 August" (locale-ordered).
    public static func daySubtitle(for day: Date) -> String {
        day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    /// "18 – 24 August" for the week header, collapsing the month when both
    /// ends share one.
    public static func weekSubtitle(for days: [Date], calendar: Calendar) -> String {
        guard let first = days.min(), let last = days.max() else { return "" }
        let sameMonth = calendar.isDate(first, equalTo: last, toGranularity: .month)
        let firstText = sameMonth
            ? first.formatted(.dateTime.day())
            : first.formatted(.dateTime.day().month(.abbreviated))
        let lastText = last.formatted(.dateTime.day().month(.wide))
        return "\(firstText) – \(lastText)"
    }

    /// "Nothing today" / "1 thing today" / "3 things today" for a lock screen
    /// tile. Plain words, because the tile is read by children.
    public static func summary(count: Int) -> String {
        switch count {
        case 0: return "Nothing today"
        case 1: return "1 thing today"
        default: return "\(count) things today"
        }
    }

    private static func clockTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
