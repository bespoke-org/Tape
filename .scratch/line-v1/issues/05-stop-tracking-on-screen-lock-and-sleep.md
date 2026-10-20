# 05: Stop tracking on screen lock and sleep

**Spec:** [Line v1](../spec.md)

**What to build:** Detect actual lock/sleep, save the interruption endpoint, distinguish usable return from wake-while-locked, and ignore ordinary inactivity/display-off.

**Blocked by:** [01: Track tasks on a live timeline](01-track-tasks-on-a-live-timeline.md).

**Status:** ready-for-human

**Execution:** implemented; awaiting physical lock/sleep verification and user acceptance

## Acceptance criteria

- [x] Actual screen lock and system sleep stop and save a running entry once, remembering its task for potential continuation.
- [x] Duplicate and differently ordered lock/sleep events do not create extra entries; wake while locked is not a usable return.
- [x] Inactivity, display dimming, and display-off alone leave tracking running. Idle state remains idle.
- [ ] Test state transitions with controlled signals and verify real lock/unlock and sleep/wake on this Mac. This slice stops safely but does not yet resume automatically.

Native macOS appearance, Liquid Glass use, and accessibility follow the spec and apply to every UI change in this ticket.

## Implementation and verification

Closing the lid stops tracking when it causes system sleep. A Mac that remains awake with an external display keeps tracking, as confirmed by the user. Ordinary inactivity and display-off are not interruption signals.

The first lock/sleep ends the entry at notification receipt, saves it, and remembers its task in memory. Duplicate signals preserve that endpoint. Wake and unlock must both complete before the Mac is available again. This ticket leaves tracking stopped; ticket 06 supplies automatic continuation. Save failures retain the original stop boundary for retry.

See [ticket 05 verification](../../../docs/ticket-05-verification.md). Physical lock/unlock and sleep/wake delivery still need verification on this Mac; automated notification checks do not establish it.
