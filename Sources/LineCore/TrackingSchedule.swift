import Foundation
import Observation

public enum ScheduledAction: String, Sendable { case start, stop }

public struct ScheduleNotice: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let planID: UUID
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

    public init(store: TrackingStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    public func suspend() { notice = nil }

    public func poll(available: Bool) throws {
        let instant = now()
        if !available {
            notice = nil
            if let active = store.activePlan { try store.stop(at: min(instant, active.end), preservingPlan: true) }
            return
        }
        // Stop at the intended boundary even when the timer was delivered a little late.
        if let active = store.activePlan, active.end <= instant {
            if let next = store.plans.first(where: {
                $0.state.awaitsStart && $0.start == active.end && $0.taskID == active.taskID && $0.end > instant
            }) {
                try store.startPlan(id: next.id, at: next.start)
            } else {
                try store.finishPlan(id: active.id, at: active.end)
            }
        }
        for plan in store.plans where plan.state.awaitsStart && plan.end <= instant {
            try store.setPlanState(id: plan.id, state: .missed)
        }
        if let current = notice {
            let plan = store.plans.first { $0.id == current.planID }
            let valid = plan.map {
                $0.start == current.plannedStart && $0.end == current.plannedEnd && $0.taskID == current.taskID &&
                    (current.action == .start ? $0.state.awaitsStart : $0.state == .active)
            } ?? false
            if !valid { notice = nil }
            else if current.deadline <= instant {
                if current.action == .start { try store.startPlan(id: current.planID, at: current.deadline) }
                else { try store.finishPlan(id: current.planID, at: current.deadline) }
                notice = nil
            }
        }
        guard notice == nil else { return }
        let countdown = TimeInterval(store.resumeCountdownSeconds)
        let next = store.plans.filter { $0.state.awaitsStart && $0.end > instant }
            .sorted { $0.start < $1.start }.first
        let active = store.activePlan
        // Adjacent plans announce the next task; stopping and switching still happen at the shared boundary.
        if let active, active.end.timeIntervalSince(instant) <= countdown,
           next == nil || next!.start > active.end {
            notice = makeNotice(active, action: .stop, deadline: active.end)
            return
        }
        guard let next, next.start.timeIntervalSince(instant) <= countdown else { return }
        if store.runningTask?.id == next.taskID {
            if next.start <= instant {
                try store.startPlan(id: next.id)
                if next.end.timeIntervalSince(instant) <= countdown {
                    notice = makeNotice(next, action: .stop, deadline: next.end)
                }
            }
            return
        }
        let deadline = next.start >= instant ? next.start : instant.addingTimeInterval(countdown)
        guard deadline < next.end else {
            try store.setPlanState(id: next.id, state: .missed)
            return
        }
        notice = makeNotice(next, action: .start, deadline: deadline)
    }

    private func makeNotice(_ plan: PlannedEntry, action: ScheduledAction, deadline: Date) -> ScheduleNotice {
        ScheduleNotice(id: UUID(), planID: plan.id, taskID: plan.taskID, action: action, deadline: deadline,
                       plannedStart: plan.start, plannedEnd: plan.end)
    }

    public func accept(available: Bool) throws {
        guard available, let current = notice else { notice = nil; return }
        guard let plan = store.plans.first(where: { $0.id == current.planID }),
              plan.start == current.plannedStart, plan.end == current.plannedEnd, plan.taskID == current.taskID else {
            notice = nil
            return
        }
        if current.action == .start { try store.startPlan(id: current.planID) }
        else { try store.finishPlan(id: current.planID) }
        notice = nil
    }

    public func reject() throws {
        guard let current = notice else { return }
        guard let plan = store.plans.first(where: { $0.id == current.planID }),
              plan.start == current.plannedStart, plan.end == current.plannedEnd, plan.taskID == current.taskID,
              current.action == .start ? plan.state.awaitsStart : plan.state == .active else {
            notice = nil
            return
        }
        // For a stop notice, this cancels only the endpoint and leaves tracking running.
        try store.setPlanState(id: current.planID, state: .skipped)
        notice = nil
    }
}
