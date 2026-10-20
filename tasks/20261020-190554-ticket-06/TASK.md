# 06: Resume interrupted work with a cancellable countdown

- STATUS: CLOSED
- PRIORITY: 100
- TAGS:
- LEGACY-ID: 06

**Spec:** [DayTape v1](../../docs/spec.md)

**What to build:** Show a non-focus-stealing menu bar countdown, include its interval on completion, support Reject/dismiss/re-lock, and verify cancellation by all implemented creation/editing actions.

**Blocked by:** [04: Correct entries and maintain reusable tasks](../20261020-190554-ticket-04/TASK.md), [05: Stop tracking on screen lock and sleep](../20261020-190554-ticket-05/TASK.md).

## Acceptance criteria

- [x] After a usable return, immediately present a nine-second countdown with OK and Reject from the menu bar without stealing keyboard focus. Highlight the menu bar icon while the notice is visible and clear the highlight when it closes.
- [x] Continuation reopens the interrupted entry for a break under five minutes; otherwise it creates one running entry starting at usable return. Reject creates none. Clicks elsewhere keep the notice visible and countdown running. OK or opening DayTape accepts immediately; the main window never shows a continuation dialog. Hovering over the notice freezes its remaining countdown; moving away resumes it. OK and Reject still work immediately while paused. Other activity leaves the countdown active.
- [x] Another lock/sleep cancels the provisional interval and offers a fresh countdown on the next usable return. Duplicate return signals do not reset or multiply countdowns.
- [x] Starting a task, beginning entry creation/editing, Stop, or Quit prevents pending continuation from committing. Verify this against the actual creation/editing flows delivered by 04 and its blockers.
- [x] Completion/action races and restart pass controlled-time tests; packaged-app checks cover focus, anchoring, and dismissal. The user accepts the implementation. The full physical system-event and appearance matrix remains part of ticket 07.

Native macOS appearance, Liquid Glass use, and accessibility follow the spec and apply to every UI change in this ticket.

## Implementation note from ticket 05

Both blockers are done. Current availability reflects received lock/sleep events rather than an independent OS-state query. Before implementing automatic continuation, account for an initially unknown or missed lock state; do not treat the initial availability value as proof the Mac is unlocked. See [ticket 05 verification](../../docs/ticket-05-verification.md).


## Implementation and verification

Implemented on 2026-10-20. A non-activating AppKit panel uses native Liquid Glass, labels, and OK/Reject buttons. Clicks elsewhere keep the notice visible. OK or opening DayTape accepts immediately; the main popover never shows the countdown. Return and completion both check console, login, and lock state; countdown expiry uses monotonic uptime. Provisional time stays in memory until acceptance or countdown completion, and failed completion does not retry silently.

Core tests and isolated packaged-app checks cover countdown completion, cancellation, re-lock, restart, conflicts, storage failures, and the implemented editing flows. Review found one stale save-error issue, which was fixed. See [ticket 06 verification](../../docs/ticket-06-verification.md) for evidence and remaining physical checks carried to ticket 07. Accepted as done by the user on 2026-10-20 after the UI refinements, hover pause, and menu bar highlight. This acceptance does not imply every physical scenario was individually tested.
