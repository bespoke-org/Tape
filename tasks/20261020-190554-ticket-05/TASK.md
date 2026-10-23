# 05: Stop tracking on screen lock and sleep

- STATUS: CLOSED
- PRIORITY: 100
- TAGS:
- LEGACY-ID: 05

**Spec:** [Tape v1](../../docs/spec.md)

**What to build:** Detect actual lock/sleep, save the interruption endpoint, distinguish usable return from wake-while-locked, and ignore ordinary inactivity/display-off.

**Blocked by:** [01: Track tasks on a live timeline](../20261020-190554-ticket-01/TASK.md).

## Acceptance criteria

- [x] Actual screen lock and system sleep stop and save a running entry once, remembering its task for potential continuation.
- [x] Duplicate and differently ordered lock/sleep events do not create extra entries; wake while locked is not a usable return.
- [x] Inactivity, display dimming, and display-off alone leave tracking running. Idle state remains idle.
- [x] State transitions pass controlled-signal tests; the user reports the implementation working on this Mac and accepts the ticket. This slice stops safely but does not yet resume automatically. The complete physical scenario matrix remains part of ticket 07.

Native macOS appearance, Liquid Glass use, and accessibility follow the spec and apply to every UI change in this ticket.

## Implementation and verification

Closing the lid stops tracking when it causes system sleep. A Mac that remains awake with an external display keeps tracking, as confirmed by the user. Ordinary inactivity and display-off are not interruption signals.

The first lock/sleep ends the entry at notification receipt, saves it, and remembers its task in memory. Duplicate signals preserve that endpoint. Wake and unlock must both complete before the Mac is available again. This ticket leaves tracking stopped; ticket 06 supplies automatic continuation. Save failures retain the original stop boundary for retry.

Accepted by the user on 2026-10-20 after the code review, automated checks, and their hands-on check. See [ticket 05 verification](../../docs/ticket-05-verification.md). The user reported that it works without enumerating every physical scenario; the full matrix remains recorded for ticket 07.
