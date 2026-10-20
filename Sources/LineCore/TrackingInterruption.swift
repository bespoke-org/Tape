import Foundation
import Observation

public enum SystemActivityEvent: Sendable {
    case locked, unlocked, willSleep, didWake
}

public struct PendingContinuation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let task: TrackedTask
    public let returnedAt: Date
    let deadline: TimeInterval
}

/// Lock and sleep are independent. Waking alone does not make a locked Mac available.
@MainActor
@Observable
public final class TrackingInterruption {
    private let store: TrackingStore
    private let now: () -> Date
    private let uptime: () -> TimeInterval
    private var locked = false
    private var sleeping = false
    private var pendingStop: (entryID: UUID, end: Date)?
    public private(set) var interruptedTask: TrackedTask?
    public private(set) var pendingContinuation: PendingContinuation?
    public var isAvailable: Bool { !locked && !sleeping && pendingStop == nil }
    public var needsContinuationPolling: Bool { !locked && !sleeping && interruptedTask != nil }
    public var remainingSeconds: Int {
        guard let pendingContinuation else { return 0 }
        return Int(ceil(max(0, pendingContinuation.deadline - uptime())))
    }

    public init(store: TrackingStore, now: @escaping () -> Date = Date.init,
                uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.store = store
        self.now = now
        self.uptime = uptime
    }

    public func handle(_ event: SystemActivityEvent) throws {
        let wasAway = locked || sleeping
        switch event {
        case .locked:
            locked = true
            pendingContinuation = nil
        case .unlocked: locked = false
        case .willSleep:
            sleeping = true
            pendingContinuation = nil
        case .didWake: sleeping = false
        }
        if !wasAway && (locked || sleeping) && pendingStop == nil {
            if let entry = store.runningEntry {
                interruptedTask = store.runningTask
                pendingStop = (entry.id, now())
            }
        }
        try retryStop()
    }

    /// Retry the same endpoint after a storage failure, never the later retry time.
    public func retryStop() throws {
        guard let pendingStop else { return }
        if store.runningEntry?.id == pendingStop.entryID {
            try store.stop(at: pendingStop.end)
        }
        self.pendingStop = nil
    }

    public func cancelContinuation() {
        pendingContinuation = nil
        interruptedTask = nil
    }

    /// The caller rechecks the current OS session before each poll, including completion.
    public func pollContinuation(sessionIsUsable: Bool) throws {
        try retryStop()
        guard isAvailable, sessionIsUsable else {
            pendingContinuation = nil
            return
        }
        guard let task = interruptedTask else { return }
        guard store.runningEntry == nil else { cancelContinuation(); return }
        if pendingContinuation == nil {
            pendingContinuation = PendingContinuation(id: UUID(), task: task, returnedAt: now(), deadline: uptime() + 10)
            return
        }
        guard let pending = pendingContinuation, uptime() >= pending.deadline else { return }
        // Clear before committing so failure or another callback cannot silently try again.
        cancelContinuation()
        try store.createEntry(named: task.name,
                              selection: EntrySelection(start: pending.returnedAt, end: nil, overwritesExisting: false))
    }
}
