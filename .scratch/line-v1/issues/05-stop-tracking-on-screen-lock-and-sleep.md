# 05: Stop tracking on screen lock and sleep

**Spec:** [Line v1](../spec.md)

**What to build:** Detect actual lock/sleep, save the interruption endpoint, distinguish usable return from wake-while-locked, and ignore ordinary inactivity/display-off.

**Blocked by:** [01: Track tasks on a live timeline](01-track-tasks-on-a-live-timeline.md).

**Status:** ready-for-agent

**Execution:** not started

## Acceptance criteria

- [ ] Actual screen lock and system sleep stop and save a running entry once, remembering its task for potential continuation.
- [ ] Duplicate and differently ordered lock/sleep events do not create extra entries; wake while locked is not a usable return.
- [ ] Inactivity, display dimming, and display-off alone leave tracking running. Idle state remains idle.
- [ ] Test state transitions with controlled signals and verify real lock/unlock and sleep/wake on this Mac. This slice stops safely but does not yet resume automatically.

Native macOS appearance, Liquid Glass use, and accessibility follow the spec and apply to every UI change in this ticket.
