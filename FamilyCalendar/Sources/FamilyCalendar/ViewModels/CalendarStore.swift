import Foundation

/// The calendar data every screen reads from: one shared load for both
/// children, so the lock screen's "3 things today" and the calendar you open
/// by tapping it can never disagree.
///
/// Both children's weeks are fetched together rather than lazily per child.
/// It's two queries against a local database, and it means a swipe from one
/// child to the other shows data immediately instead of flashing a spinner.
@MainActor
public final class CalendarStore: ObservableObject {
    @Published public private(set) var access: CalendarAccess = .notDetermined
    @Published public private(set) var isLoading = false
    /// Every readable calendar on the device — used by the empty state to say
    /// what it *did* find when a child's calendar is missing.
    @Published public private(set) var availableCalendars: [CalendarDescriptor] = []
    @Published public private(set) var eventsByChild: [String: [CalendarEvent]] = [:]
    /// Any date inside the week being shown.
    @Published public private(set) var anchorDate: Date
    /// The day whose agenda is listed.
    @Published public private(set) var selectedDay: Date

    public let calendar: Calendar
    private let provider: any EventProviding
    private var watchTask: Task<Void, Never>?
    /// The day we last loaded for, so a display left running overnight rolls
    /// over to the new day by itself.
    private var loadedDay: Date

    public init(provider: any EventProviding, calendar: Calendar = .current, now: Date = Date()) {
        self.provider = provider
        self.calendar = calendar
        self.anchorDate = now
        self.selectedDay = calendar.startOfDay(for: now)
        self.loadedDay = calendar.startOfDay(for: now)
    }

    /// Stops watching the system calendar. Nothing in this app calls it —
    /// the store lives as long as the process does — but a `deinit` can't
    /// touch main-actor state, so cancellation has to be explicit for anyone
    /// who later embeds this store somewhere that goes away.
    public func stop() {
        watchTask?.cancel()
        watchTask = nil
    }

    // MARK: - Loading

    public func start() async {
        access = await provider.currentAccess()
        if access == .notDetermined {
            access = await provider.requestAccess()
        }
        await refresh()
        watchForChanges()
    }

    public func refresh() async {
        guard access == .granted else { return }
        isLoading = true
        let interval = WeekPlanner.interval(covering: weekDays, calendar: calendar)
        var loaded: [String: [CalendarEvent]] = [:]
        for child in Child.everyone {
            loaded[child.id] = await provider.events(for: child, in: interval)
        }
        eventsByChild = loaded
        availableCalendars = await provider.calendars()
        isLoading = false
    }

    private func watchForChanges() {
        guard watchTask == nil else { return }
        let changes = provider.changes()
        watchTask = Task { [weak self] in
            for await _ in changes {
                await self?.refresh()
            }
        }
    }

    /// Driven by the kiosk clock. Its only job is the midnight roll-over:
    /// a display that's been on since Tuesday should say Wednesday on
    /// Wednesday without anyone touching it.
    public func handleClockTick(now: Date) async {
        let today = calendar.startOfDay(for: now)
        guard today != loadedDay else { return }
        loadedDay = today
        showToday(now: now)
        await refresh()
    }

    // MARK: - Week and day selection

    public var weekDays: [Date] {
        WeekPlanner.week(containing: anchorDate, calendar: calendar)
    }

    public func showWeek(offsetBy weeks: Int, now: Date = Date()) async {
        anchorDate = WeekPlanner.shift(anchorDate, byWeeks: weeks, calendar: calendar)
        // Keep the selection inside the week on screen. Landing on today when
        // you page back to this week is friendlier than landing on Monday.
        let days = weekDays
        selectedDay = days.first { calendar.isDate($0, inSameDayAs: now) } ?? days.first ?? selectedDay
        await refresh()
    }

    public func showToday(now: Date = Date()) {
        anchorDate = now
        selectedDay = calendar.startOfDay(for: now)
    }

    public func select(day: Date) {
        selectedDay = calendar.startOfDay(for: day)
    }

    public var isShowingCurrentWeek: Bool {
        weekDays.contains { calendar.isDate($0, inSameDayAs: Date()) }
    }

    // MARK: - Reading

    public func events(for child: Child, on day: Date) -> [CalendarEvent] {
        AgendaBuilder.events(
            on: day,
            from: eventsByChild[child.id] ?? [],
            calendar: calendar
        )
    }

    public func count(for child: Child, on day: Date) -> Int {
        events(for: child, on: day).count
    }

    public func agenda(for child: Child) -> [DayAgenda] {
        AgendaBuilder.agenda(
            for: weekDays,
            events: eventsByChild[child.id] ?? [],
            calendar: calendar
        )
    }

    /// Whether a calendar named after this child exists at all. False is the
    /// setup problem — no calendar to read — as opposed to a genuinely empty
    /// week, and the two need different words on screen.
    public func hasCalendar(for child: Child) -> Bool {
        !CalendarMatching.calendars(for: child, in: availableCalendars).isEmpty
    }
}
