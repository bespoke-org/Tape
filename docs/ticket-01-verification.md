# Ticket 01 verification

Implementation: [Track tasks on a live timeline](../tasks/20261020-190554-ticket-01/TASK.md).

Accepted as done by the user on 2026-10-18 after confirming the popover jitter fix. The manual checks recorded below remain unverified and are deferred to ticket 07; they do not block ticket 01's closure.

## Automated checks

- `swift test`: eight tests pass at the public tracking boundary with controlled time and real temporary storage.
- `python3 scripts/smoke-test.py`: passes. The runner builds a separate debug app under `build/smoke/`, uses isolated data, and imposes a 20-second timeout on the app process. It submits text through the native field editor, invokes the public accessible Stop action, checks tracking transitions and growing entry duration, and opens/closes/reopens the actual popover. It measures the popover's screen-space distance from the status item on opening, task creation, search-result height changes, and reopening. The debug-only driver is absent from release builds.
- The smoke runner verifies that the process exited and persisted completed entries. No test instance is intentionally left running.
- Release app built with `./scripts/build-app.sh release`; bundle signature and property-list validation run on the produced app.

## Standards review

One finding: the elapsed text's accessibility label replaced its spoken duration without providing a value. Fixed by supplying the formatted duration as the accessibility value. The elapsed-time display was subsequently removed at the user's request; the smoke check still verifies that the running entry accumulates time.

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

After the task picker became collapsible, resizing reproduced an 8.5-point downward shift that the original 12-point tolerance missed. SwiftUI now reports content-size changes, and the app refreshes the native popover size and status-item anchor after layout without replacing the hosting controller. The smoke check seeds a full-height task list, exercises new and existing task selection, and measures the content's top edge relative to its initial position with a 2-point tolerance. The corrected run stayed within 0.5 points through expansion, selection, search filtering, Escape, and reopening. The isolated smoke popover uses application-defined dismissal to prevent unrelated desktop clicks from interrupting measurements; production still uses transient dismissal, and the test explicitly exercises closing through the status item.

## Popover resize stability

The anchor refresh exposed a layout feedback loop: SwiftUI measured the height offered by the hosting window, then that measurement resized the same window. A reopened popover repeatedly alternated between 182 and 183 points tall. Measuring the root view at its natural vertical size breaks that dependency while retaining dynamic picker resizing and native anchoring. The smoke check now samples content position and height 50 times over one second after opening, selecting an existing task, reopening, and stopping. It failed on the one-point oscillation before the fix and passes afterward, alongside the anchor checks.

## Timeline bounds correction

An isolated SwiftUI ImageRenderer render of the actual LiveTimeline reproduced ticks extending 4 points below the 64-point strip, with the Now marker extending 10 points above and only 4 below. After clipping ticks to the rounded strip and deriving the marker height from a shared overhang, the same pixel check found no tick pixels below the strip and equal 10-point overhangs. The check used a fixed timestamp and a 2× dark render without opening an interactive popover. This verifies timeline geometry, not system-material compositing.

## Limits of this slice

This is the first runnable version. Scrolling, pinch zoom, drawing/editing entries, screen-lock/sleep stopping, continuation countdowns, and launch at login belong to later tickets. Stop tracking before leaving the Mac until lock/sleep handling is implemented.
