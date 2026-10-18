# Ticket 01 verification

Implementation: [Track tasks on a live timeline](../.scratch/line-v1/issues/01-track-tasks-on-a-live-timeline.md).

## Automated checks

- `swift test`: eight tests pass at the public tracking boundary with controlled time and real temporary storage.
- `python3 scripts/smoke-test.py`: passes. The runner builds a separate debug app under `build/smoke/`, uses isolated data, and imposes a 20-second timeout on the app process. It submits text through the native field editor, invokes the public accessible Stop action, checks tracking transitions and elapsed accessibility output, and opens/closes/reopens the actual popover. It measures the popover's screen-space distance from the status item on opening, task creation, search-result height changes, and reopening. The debug-only driver is absent from release builds.
- The smoke runner verifies that the process exited and persisted completed entries. No test instance is intentionally left running.
- Release app built with `./scripts/build-app.sh release`; bundle signature and property-list validation run on the produced app.

## Standards review

One finding: the elapsed text's accessibility label replaced its spoken duration without providing a value. Fixed by supplying the formatted duration as the accessibility value. The smoke check verifies that the value is present.

No significant structural smell findings. Tracking operations remain separate from rendering, domain vocabulary is consistent, and system controls/materials are used.

## Spec review

One finding: the same missing elapsed accessibility value. Fixed and checked. No other missing ticket-01 implementation behavior or scope creep was identified by the reviewer. Features in later tickets were explicitly excluded from this review.

## Manual checks remaining

- Inspect the actual composited popover and timeline in light and dark appearance.
- Check Increase Contrast, Reduce Transparency, and Reduce Motion, including task-label legibility and unchanged timekeeping.
- Exercise outside-click dismissal, task selection, and VoiceOver in ordinary desktop use.

The environment could launch the native app and exercise its own controls, but external accessibility automation was disabled and a full window capture failed. View-cache bitmaps did not faithfully composite system materials, so those images are not accepted as visual evidence. The ticket retains the manual acceptance items unchecked.

## Popover placement regression

The user's screenshot exposed a detached popover below the menu bar. The native smoke check reproduced an 86-point vertical gap twice on the initial empty popover. AppKit positioned the initial fixed-height popover before SwiftUI shrank it to fit the content. Measuring the hosting view's fitting size before each presentation removed the offset. The regression check now requires the popover's top edge to remain within 12 points of the status item's bottom edge, including after content changes and reopening. The existing native animation and anchor rectangle remain unchanged.

## Timeline bounds correction

An isolated SwiftUI ImageRenderer render of the actual LiveTimeline reproduced ticks extending 4 points below the 64-point strip, with the Now marker extending 10 points above and only 4 below. After clipping ticks to the rounded strip and deriving the marker height from a shared overhang, the same pixel check found no tick pixels below the strip and equal 10-point overhangs. The check used a fixed timestamp and a 2× dark render without opening an interactive popover. This verifies timeline geometry, not system-material compositing.

## Limits of this slice

This is the first runnable version. Scrolling, pinch zoom, drawing/editing entries, screen-lock/sleep stopping, continuation countdowns, and launch at login belong to later tickets. Stop tracking before leaving the Mac until lock/sleep handling is implemented.
