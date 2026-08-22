import Foundation

/// One day's worth of a child's calendar.
public struct DayAgenda: Identifiable, Hashable, Sendable {
    public var id: Date { date }
    /// Start of day.
    public let date: Date
    public let events: [CalendarEvent]

    public var isEmpty: Bool { events.isEmpty }

    public init(date: Date, events: [CalendarEvent]) {
        self.date = date
        self.events = events
    }
}

/// Turns a flat list of events into per-day agendas.
///
/// A multi-day event appears on *every* day it touches rather than only on the
/// day it starts. A week away shown only under the Monday it began is exactly
/// the kind of thing a child scanning "what's on today" would miss.
public enum AgendaBuilder {
    public static func agenda(
        for days: [Date],
        events: [CalendarEvent],
        calendar: Calendar
    ) -> [DayAgenda] {
        days.map { day in
            DayAgenda(date: calendar.startOfDay(for: day), events: self.events(on: day, from: events, calendar: calendar))
        }
    }

    /// Events touching `day`, ordered the way you'd read them: things that
    /// last all day first (they're context for the rest), then by start time.
    /// Title is the final tiebreak purely so the order is stable across
    /// refreshes — a list that reshuffles itself while you look at it reads as
    /// a glitch.
    public static func events(
        on day: Date,
        from events: [CalendarEvent],
        calendar: Calendar
    ) -> [CalendarEvent] {
        events
            .filter { $0.occurs(on: day, calendar: calendar) }
            .sorted { lhs, rhs in
                let lhsAllDay = coversWholeDay(lhs, day: day, calendar: calendar)
                let rhsAllDay = coversWholeDay(rhs, day: day, calendar: calendar)
                if lhsAllDay != rhsAllDay { return lhsAllDay }
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                if lhs.title != rhs.title { return lhs.title < rhs.title }
                return lhs.id < rhs.id
            }
    }

    /// True when the event blankets the whole of `day` — either flagged
    /// all-day, or a timed event that started before this day and ends after
    /// it, which amounts to the same thing from this day's point of view.
    public static func coversWholeDay(_ event: CalendarEvent, day: Date, calendar: Calendar) -> Bool {
        if event.isAllDay { return true }
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return false }
        return event.start <= interval.start && event.end >= interval.end
    }
}
