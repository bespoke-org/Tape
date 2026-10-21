import AppKit
import LineCore
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var store: TrackingStore?
    private(set) var interruptions: TrackingInterruption?
    private(set) var errorMessage: String?
    private var interruptionError: String?
    private(set) var settingsError: String?
    var defaultZoomHours: Int { store?.defaultZoomHours ?? 8 }
    var timeFormat: TimeFormat { store?.timeFormat ?? .system }
    var resumeCountdownSeconds: Int { store?.resumeCountdownSeconds ?? TrackingStore.defaultResumeCountdownSeconds }
    var automaticResumeEnabled: Bool { store?.automaticResumeEnabled ?? true }
    var shortBreakSeconds: Int { store?.shortBreakSeconds ?? 300 }
    let loginItem = LoginItemSettings()
    var defaultTimelineSpan: TimeInterval { Double(defaultZoomHours) * 3_600 }
    var timeline = TimelineViewport()
    private var timelineAnimation: Task<Void, Never>?
    private var timelineAnimationTarget: TimelineViewport?
    private(set) var entrySelection: EntrySelection?
    private(set) var drawnRange: DateInterval?
    private(set) var entryError: String?
    private(set) var isOverwriting = false
    private(set) var editingEntryID: UUID?
    private(set) var resizingEntryID: UUID?
    private var resizingEdge: EntryEdge?
    private var drawingStart: Date?
    var isDrawing: Bool { drawingStart != nil }
    private let storeURL: URL
    var onChange: (() -> Void)?

    init(storeURL: URL) {
        self.storeURL = storeURL
        load()
    }

    func load() {
        perform {
            store = try TrackingStore(url: storeURL)
            if let store { interruptions = TrackingInterruption(store: store) }
        }
    }

    func start(_ name: String) -> Bool {
        rejectContinuation()
        return perform { try store?.startTask(named: name) }
    }

    func stop() -> Bool {
        rejectContinuation()
        return perform { try store?.stop() }
    }

    func checkpoint() {
        guard store?.runningEntry != nil else { return }
        perform { try store?.checkpoint() }
    }

    func handleSystemEvent(_ event: SystemActivityEvent) {
        guard let interruptions else { return }
        // Update physical state even if a previous stop still needs its save retried.
        do {
            try interruptions.handle(event)
            try interruptions.pollContinuation(sessionIsUsable: SystemActivityMonitor.sessionIsUsable())
            errorMessage = nil
            interruptionError = nil
        } catch {
            errorMessage = error.localizedDescription
            interruptionError = errorMessage
        }
        onChange?()
    }

    func pollContinuation() {
        guard let interruptions, interruptions.needsContinuationPolling else { return }
        let previous = interruptions.pendingContinuation?.id
        let previousError = errorMessage
        do {
            try interruptions.pollContinuation(sessionIsUsable: SystemActivityMonitor.sessionIsUsable())
            if let interruptionError, errorMessage == interruptionError { errorMessage = nil }
            interruptionError = nil
        } catch {
            errorMessage = error.localizedDescription
            interruptionError = errorMessage
        }
        if previous != interruptions.pendingContinuation?.id || previousError != errorMessage { onChange?() }
    }

    func rejectContinuation() {
        interruptions?.cancelContinuation()
        onChange?()
    }

    func setContinuationHovered(_ hovered: Bool, id: UUID) {
        guard interruptions?.pendingContinuation?.id == id else { return }
        interruptions?.setContinuationHovered(hovered)
    }

    func acceptContinuation() {
        guard let interruptions, interruptions.pendingContinuation != nil else { return }
        perform {
            try interruptions.acceptContinuation(sessionIsUsable: SystemActivityMonitor.sessionIsUsable())
        }
    }

    func preparePopover() {
        stopTimelineAnimation()
        cancelEntry()
        timeline = TimelineViewport(span: defaultTimelineSpan)
    }

    func editEntry(id: UUID) {
        guard store?.entries.contains(where: { $0.id == id }) == true else { return }
        rejectContinuation()
        cancelEntry()
        editingEntryID = id
    }

    func selectEntry(at fraction: Double, minimumWidth: Double) {
        guard let store else { return }
        let instant = Date.now
        // Match the visible blocks, including the two-point minimum for short entries.
        // Later entries draw on top and win at shared boundaries.
        let visible = store.entries(overlapping: timeline.range(at: instant), now: instant)
        if let entry = visible.reversed().first(where: {
            let left = max(0, timeline.fraction(for: $0.start, now: instant))
            let right = min(1, timeline.fraction(for: $0.end ?? instant, now: instant))
            return fraction >= left && fraction < max(left + minimumWidth, right)
        }) {
            editEntry(id: entry.id)
        } else if editingEntryID != nil {
            cancelEntry()
        }
    }

    func reassignEntry(id: UUID, taskName: String) -> Bool {
        guard let store else { return false }
        return performEntryEdit { try store.reassignEntry(id: id, taskName: taskName) }
    }

    func saveTaskColor(id: UUID, color: TaskColor) -> Bool {
        guard let store else { return false }
        return performEntryEdit { try store.setTaskColor(id: id, color: color) }
    }

    func deleteEntry(id: UUID) -> Bool {
        guard let store else { return false }
        let deleted = performEntryEdit { try store.deleteEntry(id: id) }
        if deleted { cancelEntry() }
        return deleted
    }

    func resizeEdge(at fraction: Double, tolerance: Double) -> EntryEdge? {
        resizeTarget(at: fraction, tolerance: tolerance, now: .now)?.1
    }

    private func resizeTarget(at fraction: Double, tolerance: Double, now instant: Date) -> (UUID, EntryEdge, Double)? {
        guard let store else { return nil }
        let visible = store.entries(overlapping: timeline.range(at: instant), now: instant)
        let pointedEntryID = visible.reversed().first {
            timeline.fraction(for: $0.start, now: instant) <= fraction &&
                fraction < timeline.fraction(for: $0.end ?? instant, now: instant)
        }?.id ?? editingEntryID
        let edges = visible.flatMap { entry -> [(UUID, EntryEdge, Double)] in
            let end = entry.end ?? instant
            return [(entry.id, .start, timeline.fraction(for: entry.start, now: instant)),
                    (entry.id, .end, timeline.fraction(for: end, now: instant))]
        }.filter { $0.2 >= 0 && $0.2 <= 1 && abs($0.2 - fraction) <= tolerance }
        return edges.min(by: {
            let firstDistance = abs($0.2 - fraction)
            let secondDistance = abs($1.2 - fraction)
            if firstDistance == secondDistance {
                return $0.0 == pointedEntryID && $1.0 != pointedEntryID
            }
            return firstDistance < secondDistance
        })
    }

    func beginResizing(at fraction: Double, tolerance: Double) -> EntryEdge? {
        let instant = Date.now
        guard let nearest = resizeTarget(at: fraction, tolerance: tolerance, now: instant) else { return nil }
        rejectContinuation()
        cancelEntry()
        timeline.pauseFollowing(at: instant)
        resizingEntryID = nearest.0
        resizingEdge = nearest.1
        return nearest.1
    }

    func updateResizing(to fraction: Double, overwriting: Bool) {
        guard let id = resizingEntryID, let edge = resizingEdge, let store else { return }
        let date = timeline.date(at: min(max(fraction, 0), 1), now: .now)
        isOverwriting = overwriting
        if let selection = try? store.prepareResize(id: id, edge: edge, to: date, overwriting: overwriting) {
            drawnRange = DateInterval(start: selection.start, end: selection.end ?? .now)
        } else {
            drawnRange = nil
        }
    }

    func finishResizing(at fraction: Double, tolerance: Double, overwriting: Bool) {
        guard let id = resizingEntryID, let edge = resizingEdge, let store else { cancelEntry(); return }
        let instant = Date.now
        let date = timeline.date(at: min(max(fraction, 0), 1), now: instant)
        let reachesNow = abs(date.timeIntervalSince(instant)) <= timeline.span * tolerance
        cancelEntry()
        do {
            try interruptions?.retryStop()
            try store.resizeEntry(id: id, edge: edge, to: date, reachesNow: reachesNow, overwriting: overwriting)
            errorMessage = nil
            onChange?()
        } catch TrackingError.emptyInterval {
            // Dragging an edge through the other edge abandons the resize.
        } catch {
            entryError = error.localizedDescription
        }
    }

    func beginDrawing(at fraction: Double, overwriting: Bool) -> Bool {
        guard let store else { return false }
        let instant = Date.now
        let start = timeline.date(at: fraction, now: instant)
        guard overwriting || !store.entries.contains(where: { $0.start <= start && ($0.end ?? instant) > start }) else { return false }
        rejectContinuation()
        cancelEntry()
        isOverwriting = overwriting
        timeline.pauseFollowing(at: instant)
        drawingStart = start
        return true
    }

    func updateDrawing(to fraction: Double) {
        guard let start = drawingStart, let store else { return }
        let instant = Date.now
        let end = timeline.date(at: min(max(fraction, 0), 1), now: instant)
        if let selection = try? store.prepareEntry(from: start, to: end, snap: timeline.entrySnap, overwriting: isOverwriting) {
            drawnRange = DateInterval(start: selection.start, end: selection.end ?? instant)
        } else {
            drawnRange = nil
        }
    }

    func finishDrawing(at fraction: Double, tolerance: Double) {
        guard let start = drawingStart, let store else { return }
        let instant = Date.now
        let end = timeline.date(at: min(max(fraction, 0), 1), now: instant)
        // Make the thin Now marker hittable without changing snapping elsewhere.
        let reachesNow = abs(max(start, end).timeIntervalSince(instant)) <= timeline.span * tolerance
        drawingStart = nil
        drawnRange = nil
        do {
            entrySelection = try store.prepareEntry(from: start, to: end, reachesNow: reachesNow,
                                                   snap: timeline.entrySnap, overwriting: isOverwriting)
        } catch TrackingError.emptyInterval {
            cancelEntry()
        } catch {
            isOverwriting = false
            entryError = error.localizedDescription
        }
    }

    func createSelectedEntry(named name: String) -> Bool {
        guard let selection = entrySelection, let store else { return false }
        rejectContinuation()
        do {
            try interruptions?.retryStop()
            try store.createEntry(named: name, selection: selection)
            cancelEntry()
            errorMessage = nil
            onChange?()
            return true
        } catch {
            entryError = error.localizedDescription
            return false
        }
    }

    func cancelEntry() {
        editingEntryID = nil
        resizingEntryID = nil
        resizingEdge = nil
        isOverwriting = false
        drawingStart = nil
        drawnRange = nil
        entrySelection = nil
        entryError = nil
    }

    func resetTimeline(animated: Bool) {
        var target = timelineAnimationTarget ?? timeline
        stopTimelineAnimation()
        if abs(target.span - defaultTimelineSpan) < 0.001 {
            target.followNow()
        } else {
            target.zoom(factor: target.span / defaultTimelineSpan, anchorFraction: 0.5, now: .now)
        }
        let instant = Date.now
        guard animated, timeline.range(at: instant) != target.range(at: instant) else {
            timeline = target
            return
        }
        let origin = timeline
        let started = ProcessInfo.processInfo.systemUptime
        timelineAnimationTarget = target
        timelineAnimation = Task { @MainActor in
            while !Task.isCancelled {
                let progress = min((ProcessInfo.processInfo.systemUptime - started) / 0.3, 1)
                // Smoothstep eases both ends while keeping every tick and entry on the same time scale.
                let eased = progress * progress * (3 - 2 * progress)
                timeline = origin.interpolated(to: target, progress: eased, now: .now)
                if progress >= 1 {
                    timelineAnimation = nil
                    timelineAnimationTarget = nil
                    return
                }
                do { try await Task.sleep(for: .milliseconds(16)) }
                catch { return }
            }
        }
    }

    func stopTimelineAnimation(finish: Bool = false) {
        timelineAnimation?.cancel()
        timelineAnimation = nil
        if finish, let target = timelineAnimationTarget { timeline = target }
        timelineAnimationTarget = nil
    }

    func setDefaultZoomHours(_ hours: Int) {
        guard let store else { return }
        do {
            try store.setDefaultZoomHours(hours)
            settingsError = nil
        } catch {
            settingsError = error.localizedDescription
        }
    }

    func setTimeFormat(_ format: TimeFormat) {
        guard let store else { return }
        do {
            try store.setTimeFormat(format)
            settingsError = nil
        } catch {
            settingsError = error.localizedDescription
        }
    }

    func setResumeCountdownSeconds(_ seconds: Int) {
        guard let store else { return }
        do {
            try store.setResumeCountdownSeconds(seconds)
            settingsError = nil
        } catch {
            settingsError = error.localizedDescription
        }
    }

    func setAutomaticResumeEnabled(_ enabled: Bool) {
        guard let interruptions else { return }
        do {
            try interruptions.setAutomaticResumeEnabled(enabled)
            settingsError = nil
            onChange?()
        } catch {
            settingsError = error.localizedDescription
        }
    }

    func setShortBreakSeconds(_ seconds: Int) {
        guard let store else { return }
        do {
            try store.setShortBreakSeconds(seconds)
            settingsError = nil
        } catch {
            settingsError = error.localizedDescription
        }
    }

    private func performEntryEdit(_ operation: () throws -> Void) -> Bool {
        rejectContinuation()
        do {
            try interruptions?.retryStop()
            try operation()
            entryError = nil
            errorMessage = nil
            onChange?()
            return true
        } catch {
            entryError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    private func perform(_ operation: () throws -> Void) -> Bool {
        do {
            try interruptions?.retryStop()
            try operation()
            errorMessage = nil
            onChange?()
            return true
        } catch {
            errorMessage = error.localizedDescription
            onChange?()
            return false
        }
    }
}
