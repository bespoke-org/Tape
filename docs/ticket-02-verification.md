# Ticket 02 verification

Implementation: [Browse and zoom the timeline](../.scratch/line-v1/issues/02-browse-and-zoom-the-timeline.md).

## Behavior

Horizontal scrolling and Shift+wheel freeze the viewed time and browse in either direction. A compact date range and Now button occupy the existing space above the strip while browsing. The marker always represents actual now and disappears outside the visible range. Reopening follows now at the saved scale.

Pinch scales around the pointer while browsing and around now while following. Scale is saved on gesture completion or popover closure. Five minutes to ninety days are internal rendering bounds, with no added zoom controls. Calendar-based ticks adapt between minutes, hours, days, and months; local day boundaries account for daylight-saving changes.

The native input view monitors only scroll/magnify events in its own window and bounds, without intercepting clicks or task-field scrolling. Its monitor is removed when the view leaves the window or is dismantled. The existing natural-height sizing and anchor refresh remain in place.

## Automated checks

- `swift test`: 13 tests pass. Added coverage includes frozen browsing versus following, pointer-anchored zoom, finite scale bounds, adaptive/DST-aware ticks, interval-query boundaries, and zoom persistence from an older JSON store without changing crash-recovery timestamps.
- `python3 scripts/smoke-test.py`: existing task controls, checkpoint persistence, picker, anchoring, and jitter checks pass.
- `python3 scripts/smoke-test.py --timeline`: synthetic events exercise the production AppKit handler for horizontal/Shift scroll, ignored vertical/outside events, cumulative pinch, zoom anchors, and persistence. The native Now button and reopening restore following. Two fresh app processes verify saved zoom. Each process has a 20-second timeout and isolated data.

## Limits and manual checks

- Physical trackpad scrolling, momentum, pinch direction/feel, and event-monitor delivery need verification in the running app. The synthetic-event checks do not claim to reproduce hardware input.
- Light/dark appearance, Reduce Motion, Reduce Transparency, increased contrast, and VoiceOver remain manual acceptance items. An attempted ImageRenderer preview cannot render the native input view/glass controls, so it is not accepted as evidence for the composited UI.
- The existing JSON store still loads its data at launch. Timeline rendering now uses binary search over ordered entries and visits only the overlapping slice, rather than scanning all history on every update. Database-backed loading belongs to the separately deferred SQLite ticket.
