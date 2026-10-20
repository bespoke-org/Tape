# Ticket 06 verification

Implementation: [Resume interrupted work with a cancellable countdown](../tasks/20261020-190554-ticket-06/TASK.md).

Implemented and accepted as done by the user on 2026-10-20. Automated checks and review are complete. The user accepted the final behavior and UI; the full physical scenario matrix below carries forward to ticket 07.

## Behavior

Lock or system sleep still ends the running entry at notification receipt. On an awake, unlocked return, Line offers a nine-second countdown below its menu bar icon. The panel shows the task, remaining seconds, OK, and Reject without becoming the key or main window. Its menu bar icon uses the native pressed highlight while the notice is visible and clears it on dismissal.

For breaks under five minutes, acceptance reopens the same interrupted entry, counting the short break as tracked time. Break length runs from the saved interruption end to usable return, excluding the countdown. At five minutes or more, continuation creates a new entry from return. Both paths include countdown time. Reopening requires the original entry to remain the latest entry with the same task; intervening records are never overwritten. Reject records none. Clicking outside the panel or using other apps keeps the notice visible and the countdown running. Clicking OK or opening Line accepts continuation immediately using the same short-break rule. The main popover never contains a continuation dialog. Other activity leaves the countdown active.

While continuation is still pending, opening the task picker, starting a task, beginning a valid draw, overwrite or resize, selecting an entry to edit, reassigning, recoloring, deleting, Stop, and Quit cancel continuation. Abandoning the action does not reinstate it. Another lock/sleep discards the provisional interval but retains the task for a fresh offer. Duplicate return notifications do not reset the deadline.

Hovering over the notice freezes the exact remaining countdown; leaving resumes it. OK and Reject still act immediately. Accepted time includes the hover interval. A new lock/sleep clears the paused offer. The countdown uses monotonic uptime. Recorded entries use wall-clock dates and existing overlap validation. Pending time is never saved before completion. Relaunch forgets it. Failed completion clears the offer and displays an error instead of silently retrying later. Failed interruption saves retain their original boundary; a successful retry clears the matching error.

## Platform integration

The automatic UI is an AppKit `NSPanel` with native Liquid Glass and controls. It uses `.nonactivatingPanel`, cannot become key or main, and calls [`orderFrontRegardless`](https://developer.apple.com/documentation/appkit/nswindow/orderfrontregardless()), which does not change the key or main window. The ordinary popover still activates only in response to a user click.

Before offering or completing continuation, Line queries [`CGSessionCopyCurrentDictionary`](https://developer.apple.com/documentation/coregraphics/cgsessioncopycurrentdictionary()). It requires an active console and completed login, and checks `CGSSessionScreenIsLocked`. The lock key is undocumented and confined to the system adapter, like the existing lock notifications. Chromium's [GPU test instrumentation](https://chromium.googlesource.com/codesearch/chromium/src/+/d3ec5653e532b8137a3f5e7fb4a798e4691e2a68/content/test/gpu/run_gpu_integration_test.py) also uses that key. Missing session, console, or login state prevents continuation.

A read-only probe on this Mac observed the lock key absent while unlocked and true while locked. The latter also prevented the continuation smoke check from offering a countdown during an actual locked session. These observations do not establish every wake/unlock ordering or future OS compatibility.

The timer runs only while an interrupted task is awaiting a usable return or countdown completion. Main-actor serialization orders system signals, explicit actions, and completion. The panel has no outside-click dismissal monitors. Programmatic dismissal for lock/sleep, Reject, or completion does not accept.

## Automated verification

- `swift test`: 63 tests across seven suites passed. Nine continuation tests cover exact hover pause/resume, repeated hover signals, acceptance and cancellation while paused, the 4:59, 5:00, and 5:01 boundaries with early acceptance and countdown completion, same-entry persistence/recovery, short-break rejection and failed saves, early acceptance from the return instant, exact return-time recording and persistence, duplicate completion, rejection at expiry, restart during countdown, re-lock and fresh return, unavailable session checks, wall-clock jumps/reversal, overlap/manual-work conflicts, and failed completion without later retry.
- `python3 scripts/smoke-test.py --continuation`: passed with isolated storage and a 50-second process limit. It checks the menu bar highlight during presentation and outside clicks, clearing it on Reject, OK, and timer completion, menu-bar anchoring, non-key/non-main presentation, unchanged frontmost application during automatic presentation and native OK/Reject actions, enabled first-click support, accessible button titles, an always-active tracking area and simulated hover enter/exit callbacks that pause/resume the countdown, continued notice visibility and pending countdown after clicks in another window, opening Line with immediate acceptance and no countdown dialog, actual timer completion, and cancellation by the implemented tracking/editing actions.
- `python3 scripts/smoke-test.py --system-activity`: passed after integration, covering private notification delivery, exact stop boundaries, duplicates/orderings, ignored display sleep, and draft dismissal.
- Existing `--editing` and base tracking smoke checks passed after integration, including resizing, deletion, task switching, persistence, and stable popover positioning.
- Release build and strict code-signature verification passed. The prior app quit normally, and the updated `build/Line.app` was launched through the existing installation path.

The native OK and Reject checks invoke their button actions and checks `acceptsFirstMouse`; it does not inject a physical click into another application's focus context. Outside clicks are sent through AppKit to another window owned by the isolated test app; physical clicks in other applications remain a manual check. No fake system notifications are broadcast, and no release data is used.

Spec and standards reviews found one stale error-message issue after automatic save retry. It was fixed and reviewed again. No remaining actionable findings were reported.

## Physical checks carried to ticket 07

1. Start a task, lock, and unlock. Confirm the popup appears below Line, its countdown decreases, and typing continues in the previously focused app. Move the pointer over the notice, including its buttons, and confirm the countdown freezes until you move away. Physical pointer delivery still needs this check; automation exercises the tracking-area configuration and responder callbacks.
2. Let the countdown finish. For a break under five minutes, confirm the original entry continues and includes the break. Repeat with a break of at least five minutes and confirm a new entry begins at return, excluding the locked interval.
3. Repeat and click Reject once while another app has focus. Confirm it closes immediately and leaves Line stopped.
4. Repeat and click outside or use another app. Confirm the notice stays visible with its countdown running, then continues the task when the countdown finishes. Repeat and click OK; confirm tracking starts immediately without moving keyboard focus. Repeat and open Line; confirm it immediately shows the running task with no countdown dialog. If left alone, the popup must still complete after nine seconds.
5. Lock or sleep again during a countdown. Confirm no provisional time is saved and the next return gets a fresh nine seconds.
6. Try sleep/wake, wake while still locked, full-screen apps, Spaces, and the current monitor arrangement. Confirm anchoring and focus behavior.
7. Check long task names, light/dark appearance, Reduce Transparency, Increase Contrast, and VoiceOver.

The user accepted the implementation without enumerating every scenario above. Do not treat that acceptance as verification of the complete physical input, focus, wake/unlock, and appearance matrix; complete and record those checks in ticket 07.
