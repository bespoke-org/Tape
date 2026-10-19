# Ticket 02 verification

Implementation: [Browse and zoom the timeline](../.scratch/line-v1/issues/02-browse-and-zoom-the-timeline.md).

Accepted as done on 2026-10-18 after the user’s refinements and final review. Standards and spec reviews of the full ticket diff found no actionable issues or unnecessary complexity. All 14 core tests pass; the latest timeline smoke checks cover both steps of the double-tap gesture. The unverified manual checks below are deferred to ticket 07.

## Behavior

Horizontal scrolling and Shift+wheel freeze the viewed time and browse in either direction. The date or visible date range always appears in the existing space above the strip. Return to Now uses the two-finger double-tap gesture; there is no separate button. The marker always represents actual now and disappears outside the visible range. Reopening follows now at the saved scale.

Pinch scales around the pointer while browsing and around now while following. A two-finger double-tap resets to four hours without changing the viewed center or following/browsing state. At the default scale, another double-tap returns to Now. Scale is saved on gesture completion, reset, or popover closure. Five minutes to ninety days are internal rendering bounds, with no added zoom controls. Calendar-based ticks adapt between minutes, hours, days, and months; local day boundaries account for daylight-saving changes.

The strip has no empty-state text. When no events are visible, small chevrons at its left and right edges indicate tracked time before or after the visible range. With no recorded time in a direction, that arrow is hidden. Both arrows stay hidden whenever any event is visible.

The native input view monitors only scroll/magnify events in its own window and bounds, without intercepting clicks or task-field scrolling. Its monitor is removed when the view leaves the window or is dismantled. The existing natural-height sizing and anchor refresh remain in place.

## Automated checks

- `swift test`: 14 tests pass. Added coverage includes frozen browsing versus following, pointer-anchored zoom, finite scale bounds, adaptive/DST-aware ticks, multi-day labels, interval-query boundaries, and zoom persistence from an older JSON store without changing crash-recovery timestamps.
- `python3 scripts/smoke-test.py`: existing task controls, checkpoint persistence, picker, anchoring, and jitter checks pass.
- `python3 scripts/smoke-test.py --timeline`: synthetic events exercise the production AppKit handler for horizontal/Shift scroll, ignored vertical/outside events, cumulative pinch, zoom anchors, two-finger double-tap reset followed by return to Now, gesture bounds and saved scale, and persistence across launches. Double-tapping at the default scale and reopening restore following. Two fresh app processes verify saved zoom. Each process has a 20-second timeout and isolated data.

Standards and spec reviews found repeated date labels at subdaily intervals in wider views. Labels now show dates at midnight and times between them, with a regression test for a 48-hour view. The follow-up review confirmed the fix; no actionable findings remain.

## Limits and manual checks

- Physical trackpad scrolling, momentum, pinch direction/feel, and event-monitor delivery need verification in the running app. The synthetic-event checks do not claim to reproduce hardware input.
- Light/dark appearance, Reduce Motion, Reduce Transparency, increased contrast, and VoiceOver remain manual acceptance items. An attempted ImageRenderer preview cannot render the native input view/glass controls, so it is not accepted as evidence for the composited UI.
- The existing JSON store still loads its data at launch. Timeline rendering now uses binary search over ordered entries and visits only the overlapping slice, rather than scanning all history on every update. Database-backed loading belongs to the separately deferred SQLite ticket.
