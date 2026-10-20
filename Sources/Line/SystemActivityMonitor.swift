import AppKit
import CoreGraphics
import LineCore

/// Only actual lock and system sleep affect tracking. Screen/display sleep is ignored.
@MainActor
final class SystemActivityMonitor: NSObject {
    static let locked = Notification.Name("com.apple.screenIsLocked")
    static let unlocked = Notification.Name("com.apple.screenIsUnlocked")

    static func sessionIsUsable() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              session[kCGSessionOnConsoleKey as String] as? Bool == true,
              session[kCGSessionLoginDoneKey as String] as? Bool == true else { return false }
        // macOS omits this key while unlocked. Like the lock notifications, the key
        // is undocumented; keep the compatibility check confined to this adapter.
        if let value = session["CGSSessionScreenIsLocked"] {
            return value as? Bool == false
        }
        return true
    }

    private let workspace: NotificationCenter
    private let lockNotifications: NotificationCenter
    private let receive: (SystemActivityEvent) -> Void

    init(workspace: NotificationCenter = NSWorkspace.shared.notificationCenter,
         lockNotifications: NotificationCenter = DistributedNotificationCenter.default(),
         receive: @escaping (SystemActivityEvent) -> Void) {
        self.workspace = workspace
        self.lockNotifications = lockNotifications
        self.receive = receive
        super.init()
        workspace.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        for name in [Self.locked, Self.unlocked] {
            // These lock notifications are emitted by macOS but are not documented AppKit API.
            // Keep them isolated here and verify delivery on the target Mac.
            if let distributed = lockNotifications as? DistributedNotificationCenter {
                distributed.addObserver(self, selector: #selector(lockChanged), name: name,
                                        object: nil, suspensionBehavior: .deliverImmediately)
            } else {
                lockNotifications.addObserver(self, selector: #selector(lockChanged), name: name, object: nil)
            }
        }
    }

    deinit {
        workspace.removeObserver(self)
        lockNotifications.removeObserver(self)
    }

    // Save synchronously before returning from willSleep; do not defer it in a Task.
    @objc private func willSleep(_ notification: Notification) { receive(.willSleep) }
    @objc private func didWake(_ notification: Notification) { receive(.didWake) }
    @objc private func lockChanged(_ notification: Notification) {
        receive(notification.name == Self.locked ? .locked : .unlocked)
    }
}
