import SwiftUI
import UIKit

@main
struct FamilyCalendarApp: App {
    @StateObject private var kiosk = KioskViewModel()
    @StateObject private var store = CalendarStore(provider: AppEnvironment.makeProvider())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(kiosk)
                .environmentObject(store)
                // Fixed dark, regardless of the system setting — see Theme.
                .preferredColorScheme(.dark)
                .statusBarHidden()
                // Hides the home indicator so the resting screen is just the
                // clock and two names.
                .persistentSystemOverlays(.hidden)
                .task { await store.start() }
                .onAppear {
                    // The display is meant to stay lit: this is a wall clock
                    // that happens to show a calendar, and a black rectangle
                    // that needs waking defeats the point. Pair it with
                    // Settings › Display & Brightness › Auto-Lock › Never,
                    // which is what actually stops the device locking — this
                    // flag only covers the app while it's in front.
                    UIApplication.shared.isIdleTimerDisabled = true
                }
        }
    }
}

/// Chooses where events come from.
///
/// The sample provider is opt-in via a launch argument and never a fallback:
/// on a real wall display, invented events that look real are worse than an
/// empty screen, because nobody would know to check.
enum AppEnvironment {
    static func makeProvider() -> any EventProviding {
        if ProcessInfo.processInfo.arguments.contains("--sample-events") {
            return SampleEventProvider()
        }
        return EventKitEventProvider()
    }
}
