import Foundation

/// Works out which seven days a week view shows.
///
/// Pure and calendar-injected rather than reaching for `Calendar.current`,
/// because the week's first day is a locale setting (Sunday in the US, Monday
/// in most of Europe) and getting it wrong silently shifts every column.
public enum WeekPlanner {
    /// The seven start-of-day dates of the week containing `date`, in order,
    /// beginning on the calendar's own first weekday.
    public static func week(containing date: Date, calendar: Calendar) -> [Date] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return [calendar.startOfDay(for: date)]
        }
        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }
    }

    /// The half-open span covering all of `days`, for querying the event
    /// store. Empty input yields an empty interval at `date`.
    public static func interval(covering days: [Date], calendar: Calendar) -> DateInterval {
        guard let first = days.min(), let last = days.max(),
              let start = calendar.dateInterval(of: .day, for: first)?.start,
              let end = calendar.dateInterval(of: .day, for: last)?.end
        else {
            return DateInterval(start: .distantPast, duration: 0)
        }
        return DateInterval(start: start, end: end)
    }

    /// The same week shifted by `weeks`, used by the back/forward arrows.
    public static func shift(_ date: Date, byWeeks weeks: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .weekOfYear, value: weeks, to: date) ?? date
    }
}
