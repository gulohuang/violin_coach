import Foundation

/// Whether we can read the system calendar. Write access is deliberately not
/// modelled — this display never writes.
public enum CalendarAccess: Sendable, Equatable {
    case notDetermined
    case granted
    /// Denied, restricted, or granted write-only (which can't read events).
    case denied
}

/// A system calendar, reduced to the two fields the matcher needs. Lets the
/// child-to-calendar matching be unit-tested without an EventKit database.
public struct CalendarDescriptor: Hashable, Sendable {
    public let identifier: String
    public let title: String

    public init(identifier: String, title: String) {
        self.identifier = identifier
        self.title = title
    }
}

/// Where a child's events come from. One protocol so the real EventKit-backed
/// provider and the sample one used in previews are interchangeable, and so
/// nothing above this layer imports EventKit.
public protocol EventProviding: Sendable {
    func currentAccess() async -> CalendarAccess
    func requestAccess() async -> CalendarAccess
    /// Every readable calendar, for the "which calendars did we find" empty state.
    func calendars() async -> [CalendarDescriptor]
    func events(for child: Child, in interval: DateInterval) async -> [CalendarEvent]
    /// Fires whenever the underlying store changes, so a wall display picks up
    /// an event a parent just added on their phone instead of showing stale
    /// information until someone touches it.
    func changes() -> AsyncStream<Void>
}

/// Matches system calendars to children by name.
///
/// Matching on the calendar's *title* rather than a stored identifier is a
/// deliberate trade: it means setup is "name the shared calendar Alfred" with
/// no configuration screen on the device — and a configuration screen is
/// exactly what a kiosk shouldn't have. The cost is that renaming a calendar
/// silently unhooks it, which the empty state calls out by name.
public enum CalendarMatching {
    public static func calendars(for child: Child, in all: [CalendarDescriptor]) -> [CalendarDescriptor] {
        all.filter { descriptor in
            descriptor.title.range(
                of: child.name,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }
    }
}
