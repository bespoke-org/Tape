# Ticket 06 verification

Implementation: [Resume interrupted work with a cancellable countdown](../.scratch/line-v1/issues/06-resume-interrupted-work-with-a-cancellable-countdown.md).

Implemented on 2026-10-20. Automated checks and review are complete. Hands-on acceptance is pending.

## Behavior

Lock or system sleep still ends the running entry at notification receipt. On an awake, unlocked return, Line offers a ten-second countdown below its menu bar icon. The panel shows the task, remaining seconds, and Reject without becoming the key or main window.

Completion records one running entry starting at the usable return, including the countdown interval. Reject records none. Clicking outside dismisses only the panel; ordinary Mac use and timeline browsing preserve the countdown. Opening Line shows the countdown and Reject in the main popover.

Opening the task picker, starting a task, beginning a valid draw, overwrite or resize, selecting an entry to edit, reassigning, recoloring, deleting, Stop, and Quit cancel continuation. Abandoning the action does not reinstate it. Another lock/sleep discards the provisional interval but retains the task for a fresh offer. Duplicate return notifications do not reset the deadline.

The countdown uses monotonic uptime. Recorded entries use wall-clock dates and existing overlap validation. Pending time is never saved before completion. Relaunch forgets it. Failed completion clears the offer and displays an error instead of silently retrying later. Failed interruption saves retain their original boundary; a successful retry clears the matching error.

## Platform integration

The automatic UI is an AppKit `NSPanel` with native Liquid Glass and controls. It uses `.nonactivatingPanel`, cannot become key or main, and calls [`orderFrontRegardless`](https://developer.apple.com/documentation/appkit/nswindow/orderfrontregardless()), which does not change the key or main window. The ordinary popover still activates only in response to a user click.

Before offering or completing continuation, Line queries [`CGSessionCopyCurrentDictionary`](https://developer.apple.com/documentation/coregraphics/cgsessioncopycurrentdictionary()). It requires an active console and completed login, and checks `CGSSessionScreenIsLocked`. The lock key is undocumented and confined to the system adapter, like the existing lock notifications. Chromium's [GPU test instrumentation](https://chromium.googlesource.com/codesearch/chromium/src/+/d3ec5653e532b8137a3f5e7fb4a798e4691e2a68/content/test/gpu/run_gpu_integration_test.py) also uses that key. Missing session, console, or login state prevents continuation.

A read-only probe on this Mac observed the lock key absent while unlocked and true while locked. The latter also prevented the continuation smoke check from offering a countdown during an actual locked session. These observations do not establish every wake/unlock ordering or future OS compatibility.

The timer runs only while an interrupted task is awaiting a usable return or countdown completion. Main-actor serialization orders system signals, explicit actions, and completion. The panel removes its outside-click monitors when dismissed.

## Automated verification

- `swift test`: 60 tests across seven suites passed. Six continuation tests cover exact return-time recording and persistence, duplicate completion, rejection at expiry, restart during countdown, re-lock and fresh return, unavailable session checks, wall-clock jumps/reversal, overlap/manual-work conflicts, and failed completion without later retry.
- `python3 scripts/smoke-test.py --continuation`: passed with isolated storage and a 40-second process limit. It checks menu-bar anchoring, non-key/non-main presentation, unchanged frontmost application during automatic presentation and native Reject action, enabled first-click support, the accessible Reject title, dismissal without reopening, browsing/main-popover behavior, actual timer completion, and cancellation by the implemented tracking/editing actions.
- `python3 scripts/smoke-test.py --system-activity`: passed after integration, covering private notification delivery, exact stop boundaries, duplicates/orderings, ignored display sleep, and draft dismissal.
- Existing `--editing` and base tracking smoke checks passed after integration, including resizing, deletion, task switching, persistence, and stable popover positioning.
- Release build and strict code-signature verification passed. The prior app quit normally, and the updated `build/Line.app` was launched through the existing installation path.

The native Reject test invokes its button action and checks `acceptsFirstMouse`; it does not inject a physical click into another application's focus context. Outside dismissal is exercised through its production callback. No fake system notifications are broadcast, and no release data is used.

Spec and standards reviews found one stale error-message issue after automatic save retry. It was fixed and reviewed again. No remaining actionable findings were reported.

## Hands-on checks before acceptance

1. Start a task, lock, and unlock. Confirm the popup appears below Line, its countdown decreases, and typing continues in the previously focused app.
2. Let the countdown finish. Confirm the resumed entry begins at return, with the locked interval excluded.
3. Repeat and click Reject once while another app has focus. Confirm it closes immediately and leaves Line stopped.
4. Repeat and click outside or use another app. Confirm tracking resumes after ten seconds. Open Line during the countdown and try its Reject button too.
5. Lock or sleep again during a countdown. Confirm no provisional time is saved and the next return gets a fresh ten seconds.
6. Try sleep/wake, wake while still locked, full-screen apps, Spaces, and the current monitor arrangement. Confirm anchoring and focus behavior.
7. Check long task names, light/dark appearance, Reduce Transparency, Increase Contrast, and VoiceOver.

Physical input delivery, visible rendering, keyboard-focus preservation, and the complete wake/unlock matrix remain unverified until these checks are performed.
