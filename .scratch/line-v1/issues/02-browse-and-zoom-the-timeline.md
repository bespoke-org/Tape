# 02: Browse and zoom the timeline

**Spec:** [Line v1](../spec.md)

**What to build:** Scroll into history/future, return to now, pinch to zoom, adapt date/time ticks to scale, and retain scale across reopen/relaunch.

**Blocked by:** [01: Track tasks on a live timeline](01-track-tasks-on-a-live-timeline.md).

**Status:** ready-for-agent

**Execution:** not started

## Acceptance criteria

- [ ] Extend the existing live timeline with continuous navigation into history and the future. Scrolling pauses following and allows the now marker to leave the view.
- [ ] Adapt date context and tick density to the chosen scale and visible range. Render only the visible range so browsing does not require loading or drawing an unbounded history.
- [ ] Now and popover reopening restore following. Horizontal scroll/Shift+wheel browse; pinch changes scale; no zoom buttons. Retain the scale across launches.
- [ ] Verify time-to-position behavior across dates and zoom levels; manually test actual trackpad scrolling/pinch, appearance settings, and Reduce Motion.

Native macOS appearance, Liquid Glass use, and accessibility follow the spec and apply to every UI change in this ticket.
