# FamilyCalendar

A wall-mounted iPad display: a clock, and one calendar for each child, reached
without unlocking anything. Tap **Alfred** or **Elliot** to see their week;
swipe to move between them; it returns to the clock by itself.

Read **[KIOSK-SETUP.md](KIOSK-SETUP.md)** first — the app is only half of
this. The other half is three iPad settings, and the first of them explains
what "without unlocking" can and cannot mean on iOS.

> **Not yet compiled.** Like `ViolinCoach/` in this repository, this app was
> written in a Linux container with no macOS, Xcode, or Swift toolchain.
> The pure logic (day bucketing, week starts, all-day normalization, the
> formatting rules, the idle timer) has unit tests covering the cases that
> matter; none of it has been through a compiler. Budget a fix-up pass on the
> first `xcodebuild`.

## Build

```bash
brew install xcodegen        # one-time
cd FamilyCalendar && xcodegen generate
xcodebuild -scheme FamilyCalendar -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)' build
xcodebuild test -scheme FamilyCalendar -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)'
```

A simulator has an empty Calendar database, so the scheme passes
`--sample-events` on Run: both children get a plausible week from
`SampleEventProvider`. That flag is the *only* way to get sample data — it is
never a fallback on a real device, because a display quietly showing invented
events is worse than one showing nothing.

## Architecture

SwiftUI + MVVM, iOS 16, Swift 6, no third-party dependencies. Layered
`Views → ViewModels → Services → Models`, the same one-directional rule as
`ViolinCoach/`.

| | |
|---|---|
| **Models** | `Child` (Alfred and Elliot, compiled in), `CalendarEvent`, and `EventNormalization` for EventKit's inconsistent all-day end dates. Foundation only. |
| **Services** | `EventProviding` and its two implementations — `EventKitEventProvider` (an `actor`, so its blocking database fetches never reach the main thread) and `SampleEventProvider`. Plus the pure logic: `WeekPlanner`, `AgendaBuilder`, `EventFormatting`, `CalendarMatching`. |
| **ViewModels** | `KioskViewModel` (which screen, and the idle return) and `CalendarStore` (the data both screens read). |
| **Views** | `RootView` → `LockScreenView` or the two-page `ChildCalendarView`. |

### Decisions worth knowing

- **Two screens, no navigation.** No stack, no settings, no way out. Whatever
  a child can reach from the lock screen is the entire app, which is what
  makes it safe to hand over an unlocked iPad.
- **Children are compiled in, not configured on the device.** An editing UI
  is one more surface a child could wander into. Adding a third child is one
  line in `Child.everyone`.
- **Calendars are matched by name, not by stored identifier.** Setup is
  "name the shared calendar Alfred" with no configuration screen — and a
  configuration screen is exactly what a kiosk shouldn't have. The cost is
  that renaming a calendar unhooks it, so the empty state names the calendar
  it was looking for and lists the ones it found.
- **Both children load together.** One fetch fills the lock screen's "3 things
  today" *and* the calendar behind it, so the two can never disagree, and a
  swipe between children shows data rather than a spinner.
- **The clock republishes once a minute, not once a second.** Every published
  change redraws the clock and every countdown badge; doing that 60 times a
  minute to render the same digits is pure heat on a display that never turns
  off.
- **Fixed dark palette, in both appearances.** A white rectangle glowing in a
  dark hallway at night is the wrong object, and the system appearance of a
  device nobody unlocks says nothing about the room it is in.
- **Multi-day events appear on every day they touch.** A week away listed only
  under the Monday it began is exactly what a child scanning "what's on today"
  would miss.
- **It reads, never writes,** and makes no network connections of its own.

## Known limitations

- **No month view.** A week is the horizon a school week runs on, and a month
  grid is both too much to take in at a glance and too small to tap.
- **Events are read-only** — nothing can be added or edited from the display.
  That is deliberate for a device children can reach.
- **No per-event colour.** The child's colour owns the screen; a second colour
  system on top of it would say less, not more.
- **Reminders aren't shown**, only calendar events.
- **The lock screen shows today only.** Tomorrow's first event would be useful
  late in the evening; it isn't there yet.
