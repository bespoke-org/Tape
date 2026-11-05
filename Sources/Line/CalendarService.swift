import AppKit
import EventKit
import LineCore
import Observation

actor EventKitCalendarReader {
    private let events = EKEventStore()

    func requestAccess() async throws -> Bool { try await events.requestFullAccessToEvents() }

    func calendars() -> [CalendarDescriptor] {
        events.calendars(for: .event).map {
            CalendarDescriptor(id: $0.calendarIdentifier, title: $0.title, account: $0.source.title)
        }.sorted { ($0.account, $0.title) < ($1.account, $1.title) }
    }

    func fetch(in range: DateInterval, calendars ids: Set<String>) -> [CalendarEvent] {
        let calendars = events.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let predicate = events.predicateForEvents(withStart: range.start, end: range.end, calendars: calendars)
        return events.events(matching: predicate).map { event in
            let external = event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier
            // Occurrence date remains the original date when a recurring instance is moved.
            let series = [event.calendar.source.sourceIdentifier, external]
                .map { "\($0.utf8.count):\($0)" }.joined()
            let recurring = event.hasRecurrenceRules || event.isDetached
            let occurrence = recurring ? String((event.occurrenceDate ?? event.startDate).timeIntervalSinceReferenceDate) : "single"
            let participant = event.attendees?.first { $0.isCurrentUser }
            let status = participant?.participantStatus
            let selfOrganized = event.organizer?.isCurrentUser == true
            let ownAppointment = (event.attendees?.isEmpty ?? true) && event.organizer == nil
            let tentative = event.status == .tentative || status == .tentative || status == .pending
            let eligible = !tentative && (status == .accepted || selfOrganized || ownAppointment)
            return CalendarEvent(key: series + ":" + occurrence, seriesKey: recurring ? series : nil,
                                 calendarID: event.calendar.calendarIdentifier, calendarTitle: event.calendar.title,
                                 title: event.title ?? "Untitled event", start: event.startDate, end: event.endDate,
                                 eligibleForAutomaticTracking: eligible,
                                 excluded: event.isAllDay || event.status == .canceled || event.availability == .free || status == .declined)
        }
    }
}

@MainActor
@Observable
final class CalendarService {
    private let store: TrackingStore
    private let reader = EventKitCalendarReader()
    private var refreshTask: Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?
    private var requestedRange: DateInterval?
    private var generation = 0
    private var lastRefresh = Date.distantPast
    private(set) var calendars: [CalendarDescriptor] = []
    private(set) var errorMessage: String?
    private(set) var isRefreshing = false
    var onChange: (() -> Void)?

    #if DEBUG
    private var fixture: ([CalendarDescriptor], [CalendarEvent])?
    func installFixture(calendars: [CalendarDescriptor], events: [CalendarEvent]) {
        fixture = (calendars, events)
        refresh()
    }
    #endif

    var accessGranted: Bool {
        #if DEBUG
        if fixture != nil { return true }
        #endif
        return EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    init(store: TrackingStore) {
        self.store = store
        notificationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        Task {
            do {
                if enabled && !accessGranted {
                    guard try await reader.requestAccess() else {
                        errorMessage = "Calendar access is off. Allow Tape in System Settings → Privacy & Security → Calendars."
                        store.calendarAccessAvailable = false
                        return
                    }
                }
                try store.setCalendarsEnabled(enabled)
                refresh()
            } catch { errorMessage = error.localizedDescription }
            onChange?()
        }
    }

    func setSelected(_ id: String, selected: Bool) {
        do { try store.setCalendarSelected(id, selected: selected); refresh() }
        catch { errorMessage = error.localizedDescription }
        onChange?()
    }

    func setAutomatic(_ enabled: Bool) {
        do { try store.setAutomaticCalendarTracking(enabled); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
        onChange?()
    }

    func tick() {
        if store.calendarsEnabled && Date.now.timeIntervalSince(lastRefresh) >= 60 { refresh() }
    }

    func show(range: DateInterval) {
        guard requestedRange.map({ abs($0.start.timeIntervalSince(range.start)) < 60 && abs($0.duration - range.duration) < 60 }) != true else { return }
        requestedRange = range
        refresh()
    }

    func refresh() {
        generation += 1
        let current = generation
        refreshTask?.cancel()
        #if DEBUG
        if let fixture {
            store.calendarAccessAvailable = true
            calendars = fixture.0
            do { try store.reconcileCalendars(fixture.1, in: DateInterval(start: .now.addingTimeInterval(-86_400), end: .now.addingTimeInterval(30 * 86_400)), calendarIDs: store.selectedCalendarIDs) }
            catch { errorMessage = error.localizedDescription }
            onChange?()
            return
        }
        #endif
        store.calendarAccessAvailable = accessGranted
        lastRefresh = .now
        guard accessGranted, store.calendarsEnabled else {
            isRefreshing = false
            onChange?()
            return
        }
        let selected = store.selectedCalendarIDs
        let instant = Date.now
        let upcoming = DateInterval(start: instant.addingTimeInterval(-86_400), end: instant.addingTimeInterval(30 * 86_400))
        let visible = requestedRange
        isRefreshing = true
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let available = await reader.calendars()
            let upcomingEvents = await reader.fetch(in: upcoming, calendars: selected)
            let extraRange = visible.flatMap { $0.end > upcoming.end ? $0 : nil }
            let extra = if let extraRange { await reader.fetch(in: extraRange, calendars: selected) } else { [CalendarEvent]() }
            guard !Task.isCancelled, current == generation else { return }
            store.calendarAccessAvailable = accessGranted
            guard accessGranted else { isRefreshing = false; onChange?(); return }
            calendars = available
            do {
                // Include both result sets during reconciliation so moving between windows is not a deletion.
                let all = Array(Dictionary((upcomingEvents + extra).map { ($0.key, $0) }, uniquingKeysWith: { _, b in b }).values)
                try store.reconcileCalendars(all, in: upcoming, calendarIDs: selected)
                if let extraRange { try store.reconcileCalendars(all, in: extraRange, calendarIDs: selected) }
                errorMessage = nil
            } catch { errorMessage = error.localizedDescription }
            isRefreshing = false
            onChange?()
        }
    }
}
