import SwiftUI

/// The whole app: a lock screen and a pager of children's calendars, with
/// nothing else reachable from either.
struct RootView: View {
    @EnvironmentObject private var kiosk: KioskViewModel
    @EnvironmentObject private var store: CalendarStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            switch kiosk.screen {
            case .lock:
                LockScreenView()
                    .transition(.opacity)
            case .calendar:
                CalendarPagerView()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            }
        }
        // Any touch anywhere counts as "someone is here", which is what keeps
        // the idle timeout from firing while a child is reading the screen.
        // A simultaneous zero-distance drag sees every touch without
        // swallowing it, so buttons and the pager still work normally.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in kiosk.registerInteraction() }
                .onEnded { _ in kiosk.registerInteraction() }
        )
        .onAppear { kiosk.startClock() }
        .onChange(of: kiosk.now) { now in
            Task { await store.handleClockTick(now: now) }
        }
        .onChange(of: kiosk.screen) { screen in
            // Locking resets the view for whoever comes next: back to this
            // week, back to today, and freshly loaded.
            guard screen == .lock else { return }
            store.showToday(now: kiosk.now)
            Task { await store.refresh() }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            // Anything that put the app in the background — a Guided Access
            // exit, a restart — should bring the display back to its resting
            // state rather than to whatever was last on screen.
            if kiosk.screen != .lock {
                withAnimation(Theme.Motion.screen) { kiosk.lock() }
            }
            Task { await store.refresh() }
        }
    }
}

/// The two calendars side by side, swipeable.
///
/// Paging rather than a tab bar: a swipe is the gesture a child already knows
/// from photos, and there is no small permanent control to mis-tap. The pips
/// at the bottom are the only hint that a second calendar exists, so they
/// carry names rather than dots.
private struct CalendarPagerView: View {
    @EnvironmentObject private var kiosk: KioskViewModel

    var body: some View {
        TabView(selection: $kiosk.selectedChildID) {
            ForEach(Child.everyone) { child in
                ChildCalendarView(child: child)
                    .tag(child.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .overlay(alignment: .bottom) { pips }
    }

    private var pips: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(Child.everyone) { child in
                let isCurrent = child.id == kiosk.selectedChildID
                Button {
                    withAnimation(Theme.Motion.screen) { kiosk.selectedChildID = child.id }
                } label: {
                    Text(child.name)
                        .font(Theme.display(17, weight: .semibold))
                        .foregroundStyle(isCurrent ? Color.black : Theme.Palette.secondaryText)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(
                            Capsule().fill(
                                isCurrent
                                    ? Theme.Palette.accent(for: child)
                                    : Theme.Palette.surface
                            )
                        )
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .padding(Theme.Spacing.xs)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .padding(.bottom, Theme.Spacing.sm)
    }
}
