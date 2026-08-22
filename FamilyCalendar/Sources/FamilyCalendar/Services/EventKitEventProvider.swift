import EventKit
import Foundation

/// The real event source: the iPad's own Calendar database.
///
/// An `actor` rather than a class because `EKEventStore`'s fetches hit a
/// database synchronously and can take long enough to drop frames — actor
/// isolation keeps every one of those calls off the main thread, and keeps
/// the non-Sendable `EKEventStore` legally shared under Swift 6 concurrency
/// checking without an unchecked escape hatch.
public actor EventKitEventProvider: EventProviding {
    private let store = EKEventStore()
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func currentAccess() async -> CalendarAccess {
        let status = EKEventStore.authorizationStatus(for: .event)
        // iOS 17 split "authorized" into full and write-only access, and a
        // write-only grant cannot read a single event — it has to count as
        // denied here or the screen sits empty with no explanation.
        if #available(iOS 17.0, *) {
            if status == .fullAccess { return .granted }
            if status == .writeOnly { return .denied }
        }
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .granted
        default: return .denied
        }
    }

    public func requestAccess() async -> CalendarAccess {
        if #available(iOS 17.0, *) {
            do {
                return try await store.requestFullAccessToEvents() ? .granted : .denied
            } catch {
                return .denied
            }
        } else {
            return await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted ? .granted : .denied)
                }
            }
        }
    }

    public func calendars() async -> [CalendarDescriptor] {
        store.calendars(for: .event)
            .map { CalendarDescriptor(identifier: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    public func events(for child: Child, in interval: DateInterval) async -> [CalendarEvent] {
        let all = store.calendars(for: .event)
        let descriptors = all.map {
            CalendarDescriptor(identifier: $0.calendarIdentifier, title: $0.title)
        }
        let wantedIDs = Set(CalendarMatching.calendars(for: child, in: descriptors).map(\.identifier))
        let wanted = all.filter { wantedIDs.contains($0.calendarIdentifier) }
        // An empty calendar array in the predicate means *all* calendars, so
        // bailing out here is load-bearing: without it, a child with no
        // matching calendar would be shown the entire family's diary.
        guard !wanted.isEmpty else { return [] }

        let predicate = store.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: wanted
        )
        return store.events(matching: predicate).map { event in
            CalendarEvent(
                // Every occurrence of a repeating event shares one
                // eventIdentifier, so the start date has to be part of the
                // key — otherwise a weekly lesson gives a SwiftUI list seven
                // rows with the same identity and it renders one of them.
                id: "\(event.eventIdentifier ?? UUID().uuidString)@\(event.startDate.timeIntervalSinceReferenceDate)",
                title: event.title ?? "Untitled",
                start: event.startDate,
                end: EventNormalization.normalizedEnd(
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    calendar: calendar
                ),
                isAllDay: event.isAllDay,
                location: event.location?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                calendarTitle: event.calendar?.title ?? ""
            )
        }
    }

    /// Bridges EventKit's change notification into an `AsyncStream`. The
    /// notification is coalesced by the system and carries no payload — it
    /// only ever means "re-fetch".
    nonisolated public func changes() -> AsyncStream<Void> {
        let notifications = NotificationCenter.default.notifications(named: .EKEventStoreChanged)
        return AsyncStream { continuation in
            let task = Task {
                for await _ in notifications {
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension String {
    /// A location of "" is common in EventKit and should render as no location
    /// at all rather than as an empty second line.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
