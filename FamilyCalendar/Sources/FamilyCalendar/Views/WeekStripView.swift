import SwiftUI

/// The seven days of the shown week, as tappable pills.
///
/// A whole week at once rather than a scrolling month grid: a month is too
/// much information for a glance and too small a touch target for a child,
/// and "this week" is the horizon a school week actually runs on.
struct WeekStripView: View {
    @EnvironmentObject private var store: CalendarStore
    let child: Child
    let now: Date

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(store.weekDays, id: \.self) { day in
                DayPill(
                    day: day,
                    child: child,
                    isSelected: store.calendar.isDate(day, inSameDayAs: store.selectedDay),
                    isToday: store.calendar.isDate(day, inSameDayAs: now),
                    count: store.count(for: child, on: day)
                ) {
                    store.select(day: day)
                }
            }
        }
    }
}

private struct DayPill: View {
    let day: Date
    let child: Child
    let isSelected: Bool
    let isToday: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xs) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(Theme.display(15, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.black.opacity(0.65) : Theme.Palette.tertiaryText)

                Text(day.formatted(.dateTime.day()))
                    .font(Theme.display(30, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.black : Theme.Palette.primaryText)

                // Dots rather than a number: readable at a glance and at a
                // distance. Capped at three, because past "a few things" the
                // exact count doesn't change what you do next.
                HStack(spacing: 3) {
                    ForEach(0..<min(count, 3), id: \.self) { _ in
                        Circle()
                            .fill(isSelected ? Color.black.opacity(0.55) : accent)
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(isSelected ? accent : Theme.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(
                        isToday && !isSelected ? accent.opacity(0.8) : Theme.Palette.hairline,
                        lineWidth: isToday && !isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(EventFormatting.daySubtitle(for: day))
        .accessibilityValue(EventFormatting.summary(count: count))
    }

    private var accent: Color { Theme.Palette.accent(for: child) }
}
