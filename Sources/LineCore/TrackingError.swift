import Foundation

public enum TrackingError: LocalizedError {
    case emptyTaskName
    case clockMovedBackwards
    case unsupportedStoreVersion
    case emptyInterval
    case futureInterval
    case overlappingEntry

    public var errorDescription: String? {
        switch self {
        case .emptyTaskName: "Enter a task name."
        case .clockMovedBackwards: "The Mac's clock moved backward. Tracking was not changed. Check Date & Time settings and try again."
        case .unsupportedStoreVersion: "This data was saved by a different version of Line. It has not been changed."
        case .emptyInterval: "Select a longer interval, or zoom in for finer snapping."
        case .futureInterval: "Time entries must start in the past."
        case .overlappingEntry: "This interval overlaps tracked time. Choose an empty interval."
        }
    }
}
