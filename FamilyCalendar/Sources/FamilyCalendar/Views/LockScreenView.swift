import SwiftUI

/// The app's own lock screen, and the thing anyone walking past sees: a clock,
/// today's date, and one tile per child.
///
/// It stands in for the iPad's real lock screen, which no third-party app can
/// draw on. The iPad itself is set never to sleep and never to lock (see
/// KIOSK-SETUP.md), so this is the screen it rests on — and because Guided
/// Access pins the app, tapping a name is the only thing anyone can do with
/// the device.
struct LockScreenView: View {
    @EnvironmentObject private var kiosk: KioskViewModel
    @EnvironmentObject private var store: CalendarStore

    var body: some View {
        GeometryReader { geometry in
            let isWide = geometry.size.width > geometry.size.height
            let minEdge = min(geometry.size.width, geometry.size.height)

            VStack(spacing: Theme.Spacing.xl) {
                clock(size: minEdge)

                tiles(isWide: isWide, available: geometry.size)

                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Theme.Spacing.lg)
        }
    }

    // MARK: - Clock

    private func clock(size: CGFloat) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(kiosk.now.formatted(date: .omitted, time: .shortened))
                // Scaled off the screen's short edge so the clock is the same
                // proportion of the display on any iPad, in either orientation.
                .font(Theme.display(min(max(size * 0.2, 56), 190), weight: .medium))
                // Without this, the whole line shifts as the digits change —
                // very obvious on a clock you can see from across a room.
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.primaryText)

            Text(EventFormatting.daySubtitle(for: kiosk.now))
                .font(Theme.display(min(max(size * 0.035, 17), 34), weight: .regular))
                .foregroundStyle(Theme.Palette.secondaryText)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Tiles

    @ViewBuilder
    private func tiles(isWide: Bool, available: CGSize) -> some View {
        let tileViews = ForEach(Child.everyone) { child in
            ChildTile(child: child, today: kiosk.now) {
                withAnimation(Theme.Motion.screen) {
                    kiosk.open(child)
                }
            }
        }

        if isWide {
            HStack(spacing: Theme.Spacing.md) { tileViews }
                .frame(maxHeight: available.height * 0.44)
        } else {
            VStack(spacing: Theme.Spacing.md) { tileViews }
                .frame(maxHeight: available.height * 0.56)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if store.access == .denied {
                Label(
                    "Calendar access is off. Turn it on in Settings › Privacy & Security › Calendars.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(Theme.display(15, weight: .medium))
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
            }

            Text("Tap a name")
                .font(Theme.display(17, weight: .medium))
                .foregroundStyle(Theme.Palette.tertiaryText)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

/// One child's tile: the only control on the lock screen.
private struct ChildTile: View {
    @EnvironmentObject private var store: CalendarStore
    let child: Child
    let today: Date
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: child.symbol)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 68, height: 68)
                        .background(Circle().fill(Color.black.opacity(0.25)))

                    Text(child.name)
                        .font(Theme.display(52, weight: .bold))
                        .foregroundStyle(Theme.Palette.primaryText)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }

                Text(EventFormatting.summary(count: events.count))
                    .font(Theme.display(22, weight: .medium))
                    .foregroundStyle(Theme.Palette.secondaryText)

                // The single most useful line on the whole display: what's
                // next, without touching anything.
                if let next = nextEvent {
                    HStack(spacing: Theme.Spacing.xs) {
                        Circle().fill(accent).frame(width: 8, height: 8)
                        Text(next.title)
                            .lineLimit(1)
                        Text(EventFormatting.countdown(to: next, now: today, calendar: store.calendar)
                            ?? EventFormatting.timeSummary(for: next, on: today, calendar: store.calendar))
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                    .font(Theme.display(19, weight: .medium))
                    .foregroundStyle(Theme.Palette.primaryText)
                }

                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .fill(Theme.Palette.wash(for: child))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .strokeBorder(accent.opacity(0.45), lineWidth: 2)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("\(child.name). \(EventFormatting.summary(count: events.count))")
    }

    private var accent: Color { Theme.Palette.accent(for: child) }

    private var events: [CalendarEvent] {
        store.events(for: child, on: today)
    }

    /// The next thing that hasn't finished yet — so at 4pm the tile shows
    /// this evening's swimming, not this morning's assembly.
    private var nextEvent: CalendarEvent? {
        events.first { EventFormatting.status(of: $0, now: today) != .past }
    }
}
