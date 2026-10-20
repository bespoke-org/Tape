import Foundation

public enum SystemActivityEvent: Sendable {
    case locked, unlocked, willSleep, didWake
}

/// Lock and sleep are independent. Waking alone does not make a locked Mac available.
@MainActor
public final class TrackingInterruption {
    private let store: TrackingStore
    private let now: () -> Date
    private var locked = false
    private var sleeping = false
    private var pendingStop: (entryID: UUID, end: Date)?
    public private(set) var interruptedTask: TrackedTask?
    public var isAvailable: Bool { !locked && !sleeping && pendingStop == nil }

    public init(store: TrackingStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    public func handle(_ event: SystemActivityEvent) throws {
        let wasAway = locked || sleeping
        switch event {
        case .locked: locked = true
        case .unlocked: locked = false
        case .willSleep: sleeping = true
        case .didWake: sleeping = false
        }
        if !wasAway && (locked || sleeping) && pendingStop == nil {
            interruptedTask = store.runningTask
            if let entry = store.runningEntry {
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
}
