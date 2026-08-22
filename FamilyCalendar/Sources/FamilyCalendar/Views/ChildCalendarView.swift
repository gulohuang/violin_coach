import SwiftUI

/// One child's week. Header, the week strip, then the selected day's agenda.
struct ChildCalendarView: View {
    @EnvironmentObject private var kiosk: KioskViewModel
    @EnvironmentObject private var store: CalendarStore
    let child: Child

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            header
            WeekStripView(child: child, now: kiosk.now)
            AgendaListView(child: child, now: kiosk.now)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.md)
        .background(
            // A faint wash of the child's colour behind the whole screen, so
            // which calendar you're on is obvious peripherally — before you've
            // read the name at the top.
            RadialGradient(
                colors: [Theme.Palette.accent(for: child).opacity(0.16), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 700
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: child.symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 54, height: 54)
                .background(Circle().fill(accent.opacity(0.18)))

            VStack(alignment: .leading, spacing: 0) {
                Text(child.name)
                    .font(Theme.display(38, weight: .bold))
                    .foregroundStyle(Theme.Palette.primaryText)
                Text(EventFormatting.weekSubtitle(for: store.weekDays, calendar: store.calendar))
                    .font(Theme.display(18, weight: .medium))
                    .foregroundStyle(Theme.Palette.tertiaryText)
            }

            Spacer(minLength: 0)

            weekControls

            Button {
                withAnimation(Theme.Motion.screen) { kiosk.lock() }
            } label: {
                Label("Done", systemImage: "lock.fill")
                    .font(Theme.display(19, weight: .semibold))
                    .foregroundStyle(Theme.Palette.primaryText)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Capsule().fill(Theme.Palette.surfaceRaised))
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Back to the lock screen")
        }
    }

    private var weekControls: some View {
        HStack(spacing: Theme.Spacing.xs) {
            weekButton(systemImage: "chevron.left", offset: -1)
                .accessibilityLabel("Previous week")

            Button {
                store.showToday(now: kiosk.now)
                Task { await store.refresh() }
            } label: {
                Text("Today")
                    .font(Theme.display(18, weight: .semibold))
                    .foregroundStyle(Theme.Palette.primaryText)
                    .padding(.horizontal, Theme.Spacing.md)
                    .frame(height: 46)
                    .background(Capsule().fill(Theme.Palette.surface))
            }
            .buttonStyle(PressableButtonStyle())
            // Hidden rather than disabled: on a display with no cursor, a
            // greyed-out control reads as broken rather than as unnecessary.
            .opacity(store.isShowingCurrentWeek ? 0 : 1)
            .allowsHitTesting(!store.isShowingCurrentWeek)

            weekButton(systemImage: "chevron.right", offset: 1)
                .accessibilityLabel("Next week")
        }
    }

    private func weekButton(systemImage: String, offset: Int) -> some View {
        Button {
            Task { await store.showWeek(offsetBy: offset, now: kiosk.now) }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.Palette.primaryText)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Theme.Palette.surface))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var accent: Color { Theme.Palette.accent(for: child) }
}
