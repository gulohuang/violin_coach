# Setting up the iPad

## What "doesn't require unlocking" actually means

No third-party iOS app can draw on the real lock screen, run above it, or be
opened from it. That is a platform rule, not a limitation of this app, and
nothing installable from the App Store gets around it.

What *is* achievable — and what this app is built for — is a dedicated iPad
that is never locked and never asleep, pinned to this one app. Then there is
nothing to unlock: the screen anyone walks up to is this app's own lock
screen, and the only thing they can do with the device is tap **Alfred** or
**Elliot**. Guided Access is what makes that a real restriction rather than a
polite suggestion — without it, a home-button press exits to the home screen.

Three settings, once:

## 1. Stop the iPad sleeping

**Settings › Display & Brightness › Auto-Lock › Never**

The app also sets `isIdleTimerDisabled`, but that only applies while it is
frontmost — Auto-Lock is what actually keeps the device awake, and it has to
be set by hand.

While you are there: turn the brightness down. This screen is on permanently,
and it is far brighter than it needs to be in a hallway.

## 2. Pin the app

**Settings › Accessibility › Guided Access › On**, then set a passcode
(**Passcode Settings › Set Guided Access Passcode**). Choose one the children
don't know.

Open FamilyCalendar, triple-click the top button (or the home button on older
iPads), and tap **Start**. The iPad is now stuck in this app until someone
triple-clicks and enters the passcode.

For a permanent installation, Apple Configurator can supervise the iPad and
put it into Single App Mode, which survives a restart and needs no
triple-click. Guided Access is the version that takes two minutes.

## 3. Give it the calendars

The app looks for calendars **named after each child** — any calendar whose
name contains "Alfred" shows on Alfred's screen, likewise "Elliot". So
"Alfred", "alfred school", and "Alfred & Elliot" all work; "Kids" doesn't.

On the parent's iPhone, in the Calendar app: **Calendars › Add Calendar**, one
named `Alfred` and one named `Elliot`, then share each to the Apple ID the
iPad is signed in to. Add events from any device afterwards — the iPad picks
them up within seconds, without anyone touching it.

Grant calendar access when the app asks on first launch. If you tap the wrong
thing: **Settings › Privacy & Security › Calendars › FamilyCalendar**.

If a child's calendar is missing, the app says so by name on that child's
screen and lists what it *did* find. It never quietly shows an empty week for
a calendar it couldn't find.

## What it does with the data

Reads events. That is all. It never writes to a calendar, and it makes no
network connections of its own — the events come from the iPad's own Calendar
database, which iCloud syncs.

## Day-to-day

- After two minutes with nobody touching it, a calendar returns to the lock
  screen by itself. **Done** (top right) goes back immediately.
- Swipe left and right to move between the two children.
- Left and right arrows move by week; **Today** appears when you have wandered
  off this week.
- Leave it plugged in. A fixed wall charger, not a nightly ritual.
