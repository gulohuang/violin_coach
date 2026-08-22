import Foundation

/// A stand-in event source with a plausible week for each child.
///
/// Used by SwiftUI previews and by the simulator (which has an empty Calendar
/// database), never as a silent fallback on a real device: a wall display
/// quietly showing invented events would look like it was working when it
/// wasn't. When the real provider finds nothing, the app says so instead.
///
/// Events are generated relative to "now" rather than read from a fixture
/// file, so the sample week is always the current one however long after
/// writing it you look.
public struct SampleEventProvider: EventProviding {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func currentAccess() async -> CalendarAccess { .granted }
    public func requestAccess() async -> CalendarAccess { .granted }

    public func calendars() async -> [CalendarDescriptor] {
        Child.everyone.map { CalendarDescriptor(identifier: $0.id, title: $0.name) }
    }

    public func events(for child: Child, in interval: DateInterval) async -> [CalendarEvent] {
        let week = WeekPlanner.week(containing: interval.start, calendar: calendar)
        let plans = child == .elliot ? Self.elliotPlans : Self.alfredPlans
        return plans.compactMap { plan -> CalendarEvent? in
            guard plan.dayOffset < week.count else { return nil }
            let day = week[plan.dayOffset]
            guard let start = calendar.date(
                bySettingHour: plan.hour, minute: plan.minute, second: 0, of: day
            ) else { return nil }
            let end = plan.allDay
                ? EventNormalization.normalizedEnd(start: day, end: day, isAllDay: true, calendar: calendar)
                : start.addingTimeInterval(plan.minutesLong * 60)
            return CalendarEvent(
                id: "\(child.id)-\(plan.dayOffset)-\(plan.title)",
                title: plan.title,
                start: plan.allDay ? calendar.startOfDay(for: day) : start,
                end: end,
                isAllDay: plan.allDay,
                location: plan.location,
                calendarTitle: child.name
            )
        }
        .filter { $0.start < interval.end && $0.end > interval.start }
    }

    public func changes() -> AsyncStream<Void> {
        // Nothing ever changes underneath a fixture.
        AsyncStream { $0.finish() }
    }

    private struct Plan {
        let dayOffset: Int
        let hour: Int
        var minute: Int = 0
        var minutesLong: Double = 60
        let title: String
        var location: String? = nil
        var allDay: Bool = false
    }

    private static let alfredPlans: [Plan] = [
        Plan(dayOffset: 0, hour: 15, minute: 45, minutesLong: 45, title: "Violin lesson", location: "Music room"),
        Plan(dayOffset: 1, hour: 8, minute: 30, minutesLong: 30, title: "Swimming", location: "Leisure centre"),
        Plan(dayOffset: 2, hour: 16, title: "Football training", location: "Park pitch"),
        Plan(dayOffset: 3, hour: 9, minutesLong: 480, title: "School trip", location: "Natural History Museum"),
        Plan(dayOffset: 5, hour: 11, minutesLong: 120, title: "Theo's party", location: "Bowling alley"),
    ]

    private static let elliotPlans: [Plan] = [
        Plan(dayOffset: 0, hour: 17, minutesLong: 45, title: "Piano practice"),
        Plan(dayOffset: 1, hour: 16, minute: 30, minutesLong: 60, title: "Judo", location: "Sports hall"),
        Plan(dayOffset: 2, hour: 8, title: "Show and tell", location: "Classroom 2B"),
        Plan(dayOffset: 4, hour: 0, title: "Non-uniform day", allDay: true),
        Plan(dayOffset: 6, hour: 14, minutesLong: 90, title: "Cinema with Grandma"),
    ]
}
