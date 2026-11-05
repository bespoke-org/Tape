import Foundation
import Observation

public enum ScheduledAction: String, Sendable { case start, stop }

public struct ScheduleNotice: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let entryID: UUID
    public let taskID: UUID
    public let action: ScheduledAction
    public let deadline: Date
    let plannedStart: Date
    let plannedEnd: Date

    public func remainingSeconds(at now: Date) -> Int { Int(ceil(max(0, deadline.timeIntervalSince(now)))) }
}

/// Clock-driven scheduling, independent of UI, hover, and automatic-resume preferences.
@MainActor
@Observable
public final class TrackingSchedule {
    private let store: TrackingStore
    private let now: () -> Date
    public private(set) var notice: ScheduleNotice?
    public private(set) var calendarConflict: [TimeEntry] = []

    public init(store: TrackingStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    public func suspend() { notice = nil; calendarConflict = [] }

    public func poll(available: Bool) throws {
        let instant = now()
        calendarConflict = []
        if !available {
            notice = nil
            if let active = store.activeScheduledEntry { try store.stop(at: min(instant, active.end!), preservingPlan: true) }
            return
        }
        // Stop at the intended boundary even when the timer was delivered a little late.
        if let active = store.activeScheduledEntry, active.end! <= instant {
            if let next = store.scheduledEntries.first(where: {
                $0.state.awaitsStart && !store.isCalendarCandidate($0) && $0.start == active.end! && $0.taskID == active.taskID && $0.end! > instant
            }) {
                try store.startScheduledEntry(id: next.id, at: next.start)
            } else {
                try store.finishScheduledEntry(id: active.id, at: active.end!)
            }
        }
        for plan in store.scheduledEntries where plan.state.awaitsStart && plan.end! <= instant {
            try store.markEntryMissed(id: plan.id)
        }
        if let current = notice {
            let plan = store.scheduledEntries.first { $0.id == current.entryID }
            let valid = plan.map {
                $0.start == current.plannedStart && $0.end! == current.plannedEnd && $0.taskID == current.taskID &&
                    (current.action == .start ? $0.state.awaitsStart && !store.calendarStartIsBlocked($0, at: instant) : $0.state == .active)
            } ?? false
            let newlyConflicting = current.action == .start && plan.map { event in
                store.isCalendarCandidate(event) && store.scheduledEntries.contains {
                    $0.id != event.id && $0.state.awaitsStart && store.isCalendarCandidate($0) &&
                    !store.calendarStartIsBlocked($0, at: instant) && $0.start < event.end! && $0.end! > max(event.start, instant)
                }
            } == true
            if !valid || newlyConflicting { notice = nil }
            else if current.deadline <= instant {
                if current.action == .start { try store.startScheduledEntry(id: current.entryID, at: current.deadline) }
                else { try store.finishScheduledEntry(id: current.entryID, at: current.deadline) }
                notice = nil
            }
        }
        guard notice == nil else { return }
        let countdown = TimeInterval(store.resumeCountdownSeconds)
        let candidates = store.scheduledEntries.filter {
            $0.state.awaitsStart && $0.end! > instant && !store.calendarStartIsBlocked($0, at: instant)
        }.sorted { $0.start < $1.start }
        let next = candidates.first
        if let next, store.isCalendarCandidate(next), next.start.timeIntervalSince(instant) <= countdown {
            let conflicts = candidates.filter { store.isCalendarCandidate($0) && $0.start < next.end! && $0.end! > max(next.start, instant) }
            if conflicts.count > 1 || store.calendarOccurrence(id: next.id)?.requiresChoice == true {
                try store.requireCalendarChoice(ids: Set(conflicts.map(\.id)))
                calendarConflict = conflicts
                return
            }
        }
        let active = store.activeScheduledEntry
        // Adjacent plans announce the next task; stopping and switching still happen at the shared boundary.
        if let active, active.end!.timeIntervalSince(instant) <= countdown,
           next == nil || next!.start > active.end! {
            notice = makeNotice(active, action: .stop, deadline: active.end!)
            return
        }
        guard let next, next.start.timeIntervalSince(instant) <= countdown else { return }
        if !store.isCalendarCandidate(next) && store.runningTask?.id == next.taskID {
            if next.start <= instant {
                try store.startScheduledEntry(id: next.id)
                if next.end!.timeIntervalSince(instant) <= countdown {
                    notice = makeNotice(next, action: .stop, deadline: next.end!)
                }
            }
            return
        }
        let deadline = next.start >= instant ? next.start : instant.addingTimeInterval(countdown)
        guard deadline < next.end! else {
            try store.markEntryMissed(id: next.id)
            return
        }
        notice = makeNotice(next, action: .start, deadline: deadline)
    }

    private func makeNotice(_ plan: TimeEntry, action: ScheduledAction, deadline: Date) -> ScheduleNotice {
        ScheduleNotice(id: UUID(), entryID: plan.id, taskID: plan.taskID, action: action, deadline: deadline,
                       plannedStart: plan.start, plannedEnd: plan.end!)
    }

    public func chooseCalendar(id: UUID, available: Bool) throws {
        guard available, calendarConflict.contains(where: { $0.id == id }) else { return }
        try store.chooseCalendarOccurrence(id: id, among: Set(calendarConflict.map(\.id)))
        calendarConflict = []
        try poll(available: available)
    }

    public func skipCalendarConflict() throws {
        for entry in calendarConflict { try store.suppressCalendarOccurrence(id: entry.id) }
        calendarConflict = []
    }

    public func accept(available: Bool) throws {
        guard available, let current = notice else { notice = nil; return }
        guard let plan = store.scheduledEntries.first(where: { $0.id == current.entryID }),
              plan.start == current.plannedStart, plan.end! == current.plannedEnd, plan.taskID == current.taskID else {
            notice = nil
            return
        }
        if current.action == .start { try store.startScheduledEntry(id: current.entryID) }
        else { try store.finishScheduledEntry(id: current.entryID) }
        notice = nil
    }

    public func reject() throws {
        guard let current = notice else { return }
        guard let plan = store.scheduledEntries.first(where: { $0.id == current.entryID }),
              plan.start == current.plannedStart, plan.end! == current.plannedEnd, plan.taskID == current.taskID,
              current.action == .start ? plan.state.awaitsStart : plan.state == .active else {
            notice = nil
            return
        }
        // For a stop notice, this cancels only the endpoint and leaves tracking running.
        try store.skipScheduledEntry(id: current.entryID)
        notice = nil
    }
}
