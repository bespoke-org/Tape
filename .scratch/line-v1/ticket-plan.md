# Line v1 ticket breakdown

**Status:** approved with the basic live timeline merged into ticket 01 and browsing/zooming retained as ticket 02. Individual tickets are published in [issues](issues/).

**Spec:** [Line v1](spec.md)

Each ticket delivers usable behavior through UI, tracking operations, local storage where applicable, and validation. Native appearance and accessibility apply to every UI slice. There is no existing implementation to prefactor.

| Ticket | Title | Blocked by | What it delivers |
| --- | --- | --- | --- |
| 01 | Track tasks on a live timeline | None | A runnable native menu bar app; create/search tasks, start/stop/switch, and watch entries grow on a four-hour timeline following now; preserve data and stop safely on quit or recovery. |
| 02 | Browse and zoom the timeline | 01 | Scroll into history/future, return to now, pinch to zoom, adapt date/time ticks to scale, and retain scale across reopen/relaunch. |
| 03 | Draw historical entries or start tracking from the past | 02 | Drag empty space, type/select a task, save historical time or keep running when drawing through now; support cancellation and reject overlaps without modifying existing entries. |
| 04 | Correct entries and maintain reusable tasks | 03 | Edit tasks and timestamps, resize entries, rename/recolor tasks, and confirm deletion; keep running-entry behavior and validation consistent. |
| 05 | Stop tracking on screen lock and sleep | 01 | Detect actual lock/sleep, save the interruption endpoint, distinguish usable return from wake-while-locked, and ignore ordinary inactivity/display-off. |
| 06 | Resume interrupted work with a cancellable countdown | 04, 05 | Show a non-focus-stealing menu bar countdown, include its interval on completion, support Reject/dismiss/re-lock, and verify cancellation by all implemented creation/editing actions. |
| 07 | Finish personal installation and verify complete workflows | 06 | Optional launch at login, reproducible local build/install instructions, and verification of the packaged app, native appearance/accessibility, persistence, and combined tracking workflows. |

## Acceptance outline

### 01: Track tasks on a live timeline

- Build and run a native Swift app bundle on this Mac without a Dock icon; show a compact status item and a dismissible popover with system controls and materials.
- Type to create or search reusable tasks; enforce trimmed, nonempty, case-insensitively unique names and persist a random legible color.
- Start, stop, and switch tasks with a single-running-entry invariant, adjacent switch timestamps, and a running indicator. Closing the popover does not stop tracking.
- Show saved and growing entries with readable task labels/colors on a basic four-hour timeline centered on now. Follow time automatically beneath the now marker, with enough date/time context to read the strip.
- Verify that starting a task grows its entry on the timeline, stopping fixes its endpoint, and switching produces adjacent entries. Keep the basic timeline legible in light/dark appearance and with accessibility preferences; closed popovers do not need continuous rendering.
- Save mutations atomically; persist five-second running checkpoints; reopen the store; clean quit ends tracking and relaunch starts idle. Unexpected-exit recovery stops at the saved point rather than counting downtime.
- Verify through observable tracking operations and real storage reopening, plus a manual smoke test of the app bundle. Provide initial build/run instructions with the slice.

### 02: Browse and zoom the timeline

- Extend the existing live timeline with continuous navigation into history and the future. Scrolling pauses following and allows the now marker to leave the view.
- Adapt date context and tick density to the chosen scale and visible range. Render only the visible range so browsing does not require loading or drawing an unbounded history.
- Now and popover reopening restore following. Horizontal scroll/Shift+wheel browse; pinch changes scale; no zoom buttons. Retain the scale across launches.
- Verify time-to-position behavior across dates and zoom levels; manually test actual trackpad scrolling/pinch, appearance settings, and Reduce Motion.

### 03: Draw historical entries or start tracking from the past

- Drag empty space to select minute-snapped historical time and open the combined task-name/search field. Support reverse drags and Escape cancellation without creating records.
- Drawing through now preserves running intent through delayed task selection and starts from the selected past instant, including picker time.
- Reject overlaps with completed or running entries and revalidate on commit. Reject empty and wholly future selections; allow adjacent endpoints.
- Preserve accurate live timestamps and provide readable validation feedback. Persist accepted entries and verify them after reopen.
- Test creation through application operations and verify gesture behavior manually.

### 04: Correct entries and maintain reusable tasks

- Click entries to edit task/start/end, and resize completed entries by dragging edges. Editing a running start/task keeps it running; setting a fixed end requires stopping.
- Rename/recolor tasks across all entries, enforcing name uniqueness. Reassigning one entry does not rename its task globally.
- Require native deletion confirmation; cancellation preserves records and running state; confirming deletion of a running entry stops tracking.
- Reject invalid or overlapping edits without altering existing data; persist successful corrections and verify storage reopening.
- Verify keyboard editing, accessible labels, contrast, and editor behavior with real timeline interactions.

### 05: Stop tracking on screen lock and sleep

- Actual screen lock and system sleep stop and save a running entry once, remembering its task for potential continuation.
- Duplicate and differently ordered lock/sleep events do not create extra entries; wake while locked is not a usable return.
- Inactivity, display dimming, and display-off alone leave tracking running. Idle state remains idle.
- Test state transitions with controlled signals and verify real lock/unlock and sleep/wake on this Mac. This slice stops safely but does not yet resume automatically.

### 06: Resume interrupted work with a cancellable countdown

- After a usable return, immediately present a ten-second countdown and Reject from the menu bar without stealing keyboard focus.
- Countdown completion creates exactly one running entry starting at usable return. Reject creates none; outside clicks and ordinary Mac use do not cancel.
- Another lock/sleep cancels the provisional interval and offers a fresh countdown on the next usable return. Duplicate return signals do not reset or multiply countdowns.
- Starting a task, beginning entry creation/editing, Stop, or Quit prevents pending continuation from committing. Verify this against the actual creation/editing flows delivered by 04 and its blockers.
- Test completion/action races and restart during a countdown with controlled time; manually verify focus, anchoring, dismissal, and real system-event behavior.

### 07: Finish personal installation and verify complete workflows

- Offer launch at login, initially off, through supported macOS facilities; reflect the actual registration state. Login launches idle.
- Provide reproducible build, launch, and local installation instructions and a runnable app bundle that retains data independently of the checkout.
- Run applicable automated checks, then verify packaged-app workflows combining tracking, historical corrections, lock/sleep continuation, rejection, quit/relaunch, and recovery.
- Check native controls/materials, light/dark appearance, contrast/transparency/motion settings, readable task colors, keyboard editing, accessible labels, and no Dock icon. Fix discovered issues within the agreed scope.
- Record what was verified and any remaining platform limitations; do not claim manual checks that were not performed.

## Dependency rationale

- 02 extends the working live timeline from 01 with navigation and zoom.
- 03 uses the navigable timeline from 02.
- 04 builds the correction flows over the selectable, validated entry interactions from 03.
- 05 needs the running entry and persistence from 01, but no timeline or editing work; it can proceed independently of 02–04.
- 06 combines interruption handling from 05 with the completed entry-action flows from 04 to verify countdown cancellation end to end.
- 07 verifies the whole app. Its dependency on 06 includes all earlier tickets transitively; no redundant blockers are listed.

## Approval

The user approved moving the basic live timeline into the first usable tracking slice while keeping navigation and zoom as a separate follow-up. The resulting seven tickets are published individually with ready-for-agent status and explicit blockers. Ticket 01 is implemented, with manual appearance/accessibility checks still recorded in its acceptance criteria; the remaining tickets have not started.
