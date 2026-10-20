# 06: Resume interrupted work with a cancellable countdown

**Spec:** [Line v1](../spec.md)

**What to build:** Show a non-focus-stealing menu bar countdown, include its interval on completion, support Reject/dismiss/re-lock, and verify cancellation by all implemented creation/editing actions.

**Blocked by:** [04: Correct entries and maintain reusable tasks](04-correct-entries-and-maintain-reusable-tasks.md), [05: Stop tracking on screen lock and sleep](05-stop-tracking-on-screen-lock-and-sleep.md).

**Status:** ready-for-agent

**Execution:** not started

## Acceptance criteria

- [ ] After a usable return, immediately present a ten-second countdown and Reject from the menu bar without stealing keyboard focus.
- [ ] Countdown completion creates exactly one running entry starting at usable return. Reject creates none; outside clicks and ordinary Mac use do not cancel.
- [ ] Another lock/sleep cancels the provisional interval and offers a fresh countdown on the next usable return. Duplicate return signals do not reset or multiply countdowns.
- [ ] Starting a task, beginning entry creation/editing, Stop, or Quit prevents pending continuation from committing. Verify this against the actual creation/editing flows delivered by 04 and its blockers.
- [ ] Test completion/action races and restart during a countdown with controlled time; manually verify focus, anchoring, dismissal, and real system-event behavior.

Native macOS appearance, Liquid Glass use, and accessibility follow the spec and apply to every UI change in this ticket.

## Implementation note from ticket 05

Both blockers are done. Current availability reflects received lock/sleep events rather than an independent OS-state query. Before implementing automatic continuation, account for an initially unknown or missed lock state; do not treat the initial availability value as proof the Mac is unlocked. See [ticket 05 verification](../../../docs/ticket-05-verification.md).
