#if DEBUG
import SwiftUI

/// Previews run against `SampleEventProvider`, so both screens have a
/// plausible week in them without a calendar database or a permission prompt.
enum PreviewSupport {
    @MainActor
    static func store() -> CalendarStore {
        CalendarStore(provider: SampleEventProvider())
    }
}

private struct PreviewHost<Content: View>: View {
    @StateObject private var kiosk = KioskViewModel()
    @StateObject private var store = PreviewSupport.store()
    let content: () -> Content

    var body: some View {
        content()
            .environmentObject(kiosk)
            .environmentObject(store)
            .preferredColorScheme(.dark)
            .background(Theme.Palette.background.ignoresSafeArea())
            .task { await store.start() }
    }
}

struct LockScreenView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewHost { LockScreenView() }
    }
}

struct ChildCalendarView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewHost { ChildCalendarView(child: .alfred) }
    }
}
#endif
