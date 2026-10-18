# Ticket 01 verification

Implementation: [Track tasks on a live timeline](../.scratch/line-v1/issues/01-track-tasks-on-a-live-timeline.md).

## Automated checks

- `swift test`: eight tests pass at the public tracking boundary with controlled time and real temporary storage.
- `python3 scripts/smoke-test.py`: passes. The runner builds a debug app, uses isolated data, and imposes a 20-second timeout on the app process. It submits text through the native field editor, invokes the public accessible Stop action, checks tracking transitions and elapsed accessibility output, and opens/closes/reopens the actual popover. The debug-only driver is absent from release builds.
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

## Limits of this slice

This is the first runnable version. Scrolling, pinch zoom, drawing/editing entries, screen-lock/sleep stopping, continuation countdowns, and launch at login belong to later tickets. Stop tracking before leaving the Mac until lock/sleep handling is implemented.
