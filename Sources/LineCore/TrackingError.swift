import Foundation

public enum TrackingError: LocalizedError {
    case emptyTaskName
    case clockMovedBackwards
    case unsupportedStoreVersion
    case emptyInterval
    case futureInterval
    case overlappingEntry
    case missingEntry
    case missingTask
    case trackingStateChanged
    case duplicateTaskName

    public var errorDescription: String? {
        switch self {
        case .emptyTaskName: "Enter a task name."
        case .clockMovedBackwards: "The Mac's clock moved backward. Tracking was not changed. Check Date & Time settings and try again."
        case .unsupportedStoreVersion: "This data was saved by a different version of Line. It has not been changed."
        case .emptyInterval: "The end must be after the start."
        case .futureInterval: "Time entries must start in the past."
        case .overlappingEntry: "This interval overlaps tracked time. Choose an empty interval."
        case .missingEntry: "This entry no longer exists."
        case .missingTask: "This task no longer exists."
        case .trackingStateChanged: "Stop tracking before setting an end time. Completed entries must keep an end time."
        case .duplicateTaskName: "A task with this name already exists. Choose another name."
        }
    }
}
