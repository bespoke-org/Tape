import Foundation

public enum TrackingError: LocalizedError {
    case emptyTaskName
    case clockMovedBackwards
    case unsupportedStoreVersion

    public var errorDescription: String? {
        switch self {
        case .emptyTaskName: "Enter a task name."
        case .clockMovedBackwards: "The Mac's clock moved backward. Tracking was not changed. Check Date & Time settings and try again."
        case .unsupportedStoreVersion: "This data was saved by a different version of Line. It has not been changed."
        }
    }
}
