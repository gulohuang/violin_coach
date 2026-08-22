import SwiftUI

/// The selected day's events for one child.
struct AgendaListView: View {
    @EnvironmentObject private var store: CalendarStore
    let child: Child
    let now: Date

    private var day: Date { store.selectedDay }
    private var events: [CalendarEvent] { store.events(for: child, on: day) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                header

                // Order matters. Until the first load lands there are no
                // calendars to match against, and without this first branch
                // the screen accuses the family of not having made a calendar
                // that it simply hasn't looked for yet.
                if store.isLoading && store.availableCalendars.isEmpty {
                    ProgressView()
                        .tint(Theme.Palette.accent(for: child))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.xl)
                } else if store.access == .denied {
                    NoAccessView(child: child)
                } else if !store.hasCalendar(for: child) {
                    MissingCalendarView(child: child)
                } else if events.isEmpty {
                    EmptyDayView(child: child)
                } else {
                    ForEach(events) { event in
                        EventRow(event: event, child: child, day: day, now: now)
                    }
                }
            }
            .padding(.bottom, Theme.Spacing.xl)
        }
        // Resetting the scroll position when the day changes stops a long
        // Monday from leaving you halfway down an empty Tuesday.
        .id(day)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Text(EventFormatting.dayHeadline(for: day, now: now, calendar: store.calendar))
                .font(Theme.display(34, weight: .bold))
                .foregroundStyle(Theme.Palette.primaryText)

            Text(EventFormatting.daySubtitle(for: day))
                .font(Theme.display(20, weight: .medium))
                .foregroundStyle(Theme.Palette.tertiaryText)

            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

/// One event. The row is sized for reading at arm's length or further, so
/// there are only ever three things on it: when, what, and where.
private struct EventRow: View {
    @EnvironmentObject private var store: CalendarStore
    let event: CalendarEvent
    let child: Child
    let day: Date
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(accent)
                .frame(width: 6)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 2) {
                Text(EventFormatting.timeSummary(for: event, on: day, calendar: store.calendar))
                    .font(Theme.display(19, weight: .semibold))
                    .foregroundStyle(accent)

                Text(event.title)
                    .font(Theme.display(28, weight: .semibold))
                    .foregroundStyle(Theme.Palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let location = event.location {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(Theme.display(18, weight: .regular))
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
            }

            Spacer(minLength: 0)

            if let countdown = EventFormatting.countdown(to: event, now: now, calendar: store.calendar) {
                Text(countdown)
                    .font(Theme.display(17, weight: .bold))
                    .foregroundStyle(isNow ? Color.black : accent)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(
                        Capsule().fill(isNow ? accent : accent.opacity(0.18))
                    )
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(isNow ? Theme.Palette.surfaceRaised : Theme.Palette.surface)
        )
        // Finished events stay on the list — a child wants to see that they
        // did swimming this morning — but recede so the eye lands on what's
        // still to come.
        .opacity(isPast ? 0.45 : 1)
    }

    private var accent: Color { Theme.Palette.accent(for: child) }
    private var status: EventStatus { EventFormatting.status(of: event, now: now) }
    private var isNow: Bool { status == .happeningNow && !AgendaBuilder.coversWholeDay(event, day: day, calendar: store.calendar) }
    private var isPast: Bool { status == .past }
}

private struct EmptyDayView: View {
    let child: Child

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "sun.max")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(Theme.Palette.accent(for: child).opacity(0.7))
            Text("Nothing planned")
                .font(Theme.display(26, weight: .semibold))
                .foregroundStyle(Theme.Palette.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
        .card()
    }
}

/// Shown when no calendar on the device carries the child's name. This is a
/// setup problem, not an empty week, and the two must not look the same:
/// silently showing "Nothing planned" for a calendar we never found is how a
/// family misses a dentist appointment.
private struct MissingCalendarView: View {
    @EnvironmentObject private var store: CalendarStore
    let child: Child

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("No calendar called “\(child.name)”", systemImage: "calendar.badge.exclamationmark")
                .font(Theme.display(24, weight: .semibold))
                .foregroundStyle(Theme.Palette.primaryText)

            Text("In the Calendar app, make a calendar named “\(child.name)” — or share one with that name to this iPad — and \(child.name)’s events will show up here.")
                .font(Theme.display(19, weight: .regular))
                .foregroundStyle(Theme.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if !store.availableCalendars.isEmpty {
                Text("Calendars found: \(store.availableCalendars.map(\.title).joined(separator: ", "))")
                    .font(Theme.display(16, weight: .regular))
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Spacing.md)
        .card()
    }
}

/// Calendar permission was refused. Distinct from a missing calendar and from
/// an empty day, because the fix is somewhere else entirely — and because a
/// display that shows "Nothing planned" when it simply isn't allowed to look
/// is actively misleading.
private struct NoAccessView: View {
    let child: Child

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("No access to the calendar", systemImage: "lock.slash")
                .font(Theme.display(24, weight: .semibold))
                .foregroundStyle(Theme.Palette.accent(for: child))

            Text("Turn this on in Settings › Privacy & Security › Calendars › FamilyCalendar, then reopen the app.")
                .font(Theme.display(19, weight: .regular))
                .foregroundStyle(Theme.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Spacing.md)
        .card()
    }
}
