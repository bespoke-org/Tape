# 02: Browse and zoom the timeline

**Spec:** [Line v1](../spec.md)

**What to build:** Scroll into history/future, return to now, pinch to zoom, adapt date/time ticks to scale, and retain scale across reopen/relaunch.

**Blocked by:** [01: Track tasks on a live timeline](01-track-tasks-on-a-live-timeline.md).

**Status:** ready-for-agent

**Execution:** implemented; physical gesture and appearance/accessibility verification pending

## Acceptance criteria

- [x] Extend the existing live timeline with continuous navigation into history and the future. Scrolling pauses following and allows the now marker to leave the view.
- [x] Adapt date context and tick density to the chosen scale and visible range. Render only the visible range so browsing does not require loading or drawing an unbounded history.
- [x] Now and popover reopening restore following. Horizontal scroll/Shift+wheel browse; pinch changes scale; no zoom buttons. Retain the scale across launches.
- [ ] Verify time-to-position behavior across dates and zoom levels; manually test actual trackpad scrolling/pinch, appearance settings, and Reduce Motion.

Native macOS appearance, Liquid Glass use, and accessibility follow the spec and apply to every UI change in this ticket.

## Verification

- Thirteen core tests pass, including following/browsing, anchored zoom, adaptive ticks across daylight-saving changes, range-query endpoints, and backward-compatible zoom persistence.
- Both bounded packaged-app smoke modes pass. Timeline mode tests synthetic AppKit input, Now, reopening, zoom persistence across fresh launches, and stable anchoring. Existing tracking and jitter regressions also pass.
- Real trackpad scrolling/pinch and the complete appearance/accessibility matrix remain manual checks; synthetic inputs do not establish physical gesture behavior.
- See [the verification record](../../../docs/ticket-02-verification.md).
