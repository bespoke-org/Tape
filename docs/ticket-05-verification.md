# Ticket 05 verification

Implementation: [Stop tracking on screen lock and sleep](../.scratch/line-v1/issues/05-stop-tracking-on-screen-lock-and-sleep.md).

Implemented and accepted as done on 2026-10-20. After trying the rebuilt app, the user reported that it seems to be working. This records user-reported hands-on acceptance, not an independently observed pass of every physical scenario.

## Behavior

Screen lock or system sleep saves the running entry at the time Line receives the notification. The task is remembered in memory for later continuation work. Lock and sleep are independent conditions: waking while locked or unlocking while still asleep is not a usable return. Duplicate signals do not extend the entry or create another one. Returning leaves tracking stopped. Relaunch starts idle and forgets the interrupted task.

The user confirmed that a closed lid with an awake Mac and external display should keep tracking. Lid closure needs no separate sensor: it stops tracking when it causes system sleep. Ordinary inactivity, display dimming, display-off, and unrelated session notifications do not stop tracking.

Lock/sleep closes the popover and discards unfinished timeline/editor drafts. It does not show new UI or take focus on return.

Save failures retain the prior stored state and show the existing error indicator. Line retains the original interruption endpoint in memory and retries on subsequent system events, periodic checkpoints, and before user mutations or quitting. A successful retry excludes the absence. If the app exits unexpectedly before any stop save succeeds, existing checkpoint recovery still limits work to the last saved point.

## Platform integration

`SystemActivityMonitor` observes [NSWorkspace system sleep](https://developer.apple.com/documentation/appkit/nsworkspace/willsleepnotification) and wake notifications. The stop save runs synchronously in the sleep handler. It does not subscribe to [screen sleep](https://developer.apple.com/documentation/appkit/nsworkspace/screensdidsleepnotification), which is a distinct signal.

Screen lock uses `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` through `DistributedNotificationCenter`. These names are not documented AppKit API; their use is also visible in [Hammerspoon's own implementation](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/caffeinate/libcaffeinate_watcher.m). They are isolated in the adapter. The user reports the implementation working on this Mac; delivery remains a regression check for final verification and OS updates. Apple's [distributed-notification documentation](https://developer.apple.com/documentation/Foundation/DistributedNotificationCenter?language=objc) notes that delivery can be delayed or dropped, so the recorded boundary is receipt time, not a guaranteed system timestamp. No accessibility permission, input monitoring, or idle-time polling is required.

## Automated verification

- `swift test`: 54 tests across six suites passed. New tests cover exact stop time and persistence, idle behavior, duplicate notifications, both lock/sleep and return orderings, failed-save retries at the original boundary, and no automatic continuation or continuation state after relaunch.
- `python3 scripts/smoke-test.py --system-activity`: passed with isolated data and a 20-second process limit. Private notification centers drive the production adapter, app delegate, and application model. It checks ignored display sleep, immediate stop/save, task retention, draft/popover dismissal, ordered return state, duplicate handling, and stopped state after return.
- The smoke check never posts fake system notifications to other applications.
- Existing packaged `--editing` and base tracking smoke checks passed after integration.

Review found no functional blockers. For ticket 06, availability currently reflects received events, not an independent query of the OS lock state. Automatic continuation must account for an initially unknown or missed lock state before using availability to start work.

## Physical scenarios for final verification

1. Start a task, lock with Control-Command-Q, then unlock. Confirm the entry ended at lock and Line remains stopped.
2. Start another task, sleep the Mac or close its lid so it sleeps, then wake/unlock. Confirm the absence is untracked and no task starts automatically.
3. Repeat with the popover/editor open and through a lock followed by sleep.
4. Where the Mac remains unlocked and awake, verify display-off and normal inactivity keep tracking. A closed lid with an external display should also keep tracking if the Mac stays awake.

The user confirmed the implementation works but did not enumerate these scenarios individually. Repeat the complete matrix in ticket 07. Ticket 06 will add the ten-second continuation popup after a usable return.
