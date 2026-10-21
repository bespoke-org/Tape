# DayTape usage and development

A personal macOS menu bar time tracker, built with Swift, SwiftUI, and AppKit. Requires macOS 26 and Xcode 26 or newer.

Commands below run from the repository root.

## Build and run

```sh
./scripts/build-app.sh
open build/DayTape.app
```

The script builds a release executable and creates an ad-hoc-signed app bundle. For a debug build, use `./scripts/build-app.sh debug`. Open `Package.swift` in Xcode to work on the Swift package; launch the bundled app to verify its menu bar and main-window behavior.

Click DayTape's menu bar icon to see the current state and timeline. The play icon when idle, or the switch arrows while tracking, reveals and focuses the task picker. The square stop icon ends tracking. These actions use plain icons with tooltips. Enter a name and press Return or Start, or choose an existing task from the list. Choosing a task hides the picker. Escape dismisses tag suggestions first, then hides the picker. Switching tasks ends the previous entry at the new entry's start. Stop ends tracking; closing the popover leaves it running. The timeline opens at your configured default zoom, initially eight hours, and follows Now. Scroll horizontally, or use Shift+mouse-wheel, to browse history and future space. Pinch to zoom; while browsing, zoom stays anchored under the pointer. Double-tap with two fingers to reset to your configured default while keeping the viewed time centered. At the default scale, another double-tap returns to Now. Both transitions ease in and out over 0.3 seconds. Scrolling, pinching, or starting a drag interrupts the animation; Reduce Motion makes the change immediate. Reopening follows Now at the configured default. Pinch zoom is temporary. There is no separate Now button. Right-click the menu bar icon, including a trackpad secondary click or Control-click, for the native menu containing General Settings…, About DayTape, then a separator and Quit DayTape. The section items open their page directly in the existing window, restoring it if minimized or closed.

Click the gear icon at the right of the popover controls to open DayTape's main window. You can also choose General Settings… or About DayTape from the status menu or press Command-comma while DayTape has focus. The sidebar contains General and About. Its Default zoom slider saves automatically at seven stops: 1, 2, 4, 8, 12, 16, and 24 hours, with eight hours initially. Only 1, 8, and 24 hours have visible labels. Previously saved values use the nearest stop, choosing the lower value on a tie. Changes apply on the next timeline opening or reset. Existing last-used pinch zoom is ignored when upgrading.

Add tags in the task input, for example `Building DayLine :dayline :coding :deepwork`. Tags can appear anywhere as separate words beginning with `:`; words ending with `:` stay part of the name, so `:peka:` remains literal text. The saved name excludes tags and extra spaces. Tags are case-insensitive across languages, display in lowercase, and belong to the task across all its entries. Starting or creating another entry adds typed tags to the task; omitting tags preserves them. Adding tags to the running task does not restart it.

Type `:` to see saved tags, then type a prefix to narrow them. Arrow keys select a suggestion; Tab or Return inserts it as plain text with a trailing space. Nothing is selected initially: Return without a selection submits the input as typed. Escape closes suggestions before canceling the draft. Completed tags filter task suggestions by all specified tags, and the remaining text filters names. A tag at the caret remains a completion prefix until you finish it with a space or submit it. Tag-only input searches tasks but cannot create a nameless entry.

The entry editor shows the complete tag list. Edit it and press Return to replace the task's tags, or remove all tags to clear them. These changes affect every entry for the task. Selecting another task loads that task's tags without copying the previous task's tags. Suggestions and timeline tooltips display saved tags. Tags disappear from autocomplete when their last task association is removed.

Time format, beneath Default zoom in General, offers System, 12-hour, and 24-hour. System follows your macOS preference. Changes save automatically and apply immediately to timeline labels, entry tooltips, and accessibility descriptions. Dates, time zones, and recorded time stay the same.

Task order, in General’s Tracking section, controls suggestions when creating or editing entries. Recently used is the default and puts tasks with the latest entry start times first. Alphabetical uses natural name order, such as Task 2 before Task 10. Most used puts tasks with the most entries first. Ties sort alphabetically; tasks without entries sort last for recency and usage. Search keeps the selected order and matches names without case sensitivity. The choice saves automatically. Adding older history does not make a task recent, and editing or deleting entries updates its ranking.

Automatic resume in General → Tracking is on by default. Turn it off to keep tracking stopped after unlocking or waking. Turning it off cancels a pending offer; turning it back on waits for the next interruption. It does not stop a task that is currently running. The countdown and threshold controls are disabled while automatic resume is off, but keep their saved values.

Short-break threshold sets how short a break must be to count as part of the same entry. The menu offers Never, 30 seconds, and 1, 2, 5, 10, 15, 30, or 60 minutes, initially 5 minutes. Custom opens a dialog for an exact duration from 0 to 3600 seconds; Save applies it and Cancel keeps the previous value. Existing saved minute values keep their duration. At exactly the threshold or above, resuming starts a new entry at return. Zero appears as Never and always starts a new entry. Changes apply to the next offer.

Launch at login in General → Startup uses the [macOS app service](https://developer.apple.com/documentation/servicemanagement/smappservice). It is off until enabled and reflects the actual system registration, including external changes when you return to DayTape. If approval is needed, use Open System Settings. Login launches remain idle in the menu bar without opening a window.

Resume countdown in General → Tracking sets how long DayTape waits before resuming after an unlock or wake. Type a whole number in the field followed by seconds; the default is 9. Only digits are accepted. Press Return or leave the field to save. Values are bounded to 1–60 seconds, and an empty field restores the previous value. Changes apply to the next countdown. Hovering still pauses the countdown, and OK or Reject acts immediately.

About shows the app icon, description, version and build from the installed bundle, minimum macOS version, license, and source links. Show Data in Finder reveals the local tracking file; it is disabled until the file exists. No page navigation changes your recorded time.

The main window follows System Settings: window controls sit inside the sidebar, the app title is hidden, and native back and forward buttons sit beside the current page heading above the grouped controls. The sidebar lists General and About. Back and Forward follow your page history and disable when there is nowhere to go. The green button zooms rather than entering full screen, so AeroSpace floats the window automatically through its [dialog heuristic](https://nikitabobko.github.io/AeroSpace/guide#dialog-heuristics). The window remembers its size and position. Opening it closes the popover and discards unfinished drafts while keeping saved edits and tracking. DayTape appears in the Dock and app switcher while the window is open or minimized. Opening it again restores the same window; closing it with the red button or Command-W returns to menu-bar-only operation. App launch always leaves this window closed.

Drag empty timeline space to select time, then type a task name or choose an existing one. Historical selections use Save; selections reaching Now use Start and include time spent choosing the task. Escape or closing the popover discards the draft. Reverse drags work, snapping adapts to zoom, and the dragged edge stops at neighboring entries. Views up to two hours snap by one minute, up to eight hours by five minutes, and wider views by fifteen minutes. Contact with a neighbor uses its exact timestamp; new conflicts are still rejected when saving.

Hold ⌘ when starting a drag to overwrite existing time, even when starting inside an entry. Dragging an entry edge resizes it instead. The gray striped selection shows the time to replace. Release, then choose a task or submit with Overwrite; through-Now selections use Overwrite & Start. Partial overlaps trim existing entries, middle overlaps split them, and fully covered entries disappear. Choosing the same task merges the new interval with connected entries into one continuous block, including running time. Real gaps and different tasks stay separate. Uncovered time remains. A task disappears from suggestions when its last entry is removed; tasks with other entries remain reusable. Unused task names left by earlier builds are cleaned up on launch. Releasing ⌘ after starting the drag does not change its mode. The overwrite picker has no extra caption or Cancel button; Escape or closing the popover discards the draft.

Click an entry to open its settings below the timeline. Click empty timeline space to deselect it. The color picker, task search field, and Delete share one row. Adjust start and end times by dragging the entry edges. Select a suggestion to load its name and tags for review, then press Return to reassign this entry. Return with a new name creates a task. Typing alone does not change records. Color changes save immediately. Escape or closing the popover keeps saved changes. The swatch beside the search field changes the task color across all entries. There are no Save or Cancel buttons in the editor. Delete requires confirmation. Running entries keep tracking while their task or start is corrected. Hover near either edge of an entry for a bracket-style trim cursor. The bracket identifies which entry edge will move. It stays visible during resizing; holding Command keeps the same edge cursor. Drag either edge to resize it, snapping to minutes and stopping at neighboring entries. Dragging a completed entry’s end to or past Now continues that same entry as running, unless another entry blocks it. For a running entry, moving the start keeps tracking; dragging the end into the past stops it at that time, while leaving it at or beyond Now keeps tracking. Hold Command before or during resizing to cross neighboring entries. The preview keeps the resized task’s color. Pressing or releasing Command updates the preview immediately, even without moving the pointer; releasing it restores the neighboring boundary. Mouse-up commits the current mode. Overwrite resizing trims or removes covered entries and merges connected time for the same task, preserving the resized entry’s identity. Extending through Now can replace a different running task. Escape cancels without changing records.

Tickets 1–6 and 9 supply tracking, browsing, drawing, corrections, lock/sleep handling, continuation, and Command-drag overwrite. Lock or system sleep stops and saves the running entry. Lid closure counts when it causes system sleep, while an awake Mac with an external display keeps tracking. Ordinary inactivity, dimming, and display-off alone keep tracking.

After an awake, unlocked return, a small Liquid Glass panel below the menu bar offers a countdown with OK and Reject without taking keyboard focus. With automatic resume enabled, if the break from interruption to return is shorter than the configured threshold, acceptance reopens the same entry and counts the short break as tracked time. A break at or above that threshold starts a new entry at return. The countdown time is included in either case. Reject discards that interval. Clicking elsewhere or using other apps keeps the notice visible and the countdown running. Clicking OK or opening DayTape accepts continuation immediately. The main popover never shows the countdown. Other activity leaves the countdown running. Hovering over the notice freezes its remaining countdown; moving away resumes it. OK and Reject still work immediately while paused. Explicit tracking/editing actions, Stop, and Quit cancel any still-pending continuation; opening DayTape has already accepted it. Another lock/sleep discards the countdown and offers a fresh one on return. Relaunch always starts idle. See [ticket 06 verification](ticket-06-verification.md) for automated checks and pending physical checks.

New tasks use a nine-color palette, choosing an unused color when available before repeating colors. Saved mint/cyan shades load as teal and indigo as blue; other assigned colors stay unchanged.

## Local data

DayTape was originally named Line. It retains the original `app.line.timetracker` bundle identifier and data directory so existing history and preferences continue to work. Internal Swift target names and `LINE_` development overrides remain compatible.

Records are stored in `~/Library/Application Support/Line/tracking.json`, independently of the source checkout and app bundle. Accepted changes are saved atomically. A five-second checkpoint timer limits recovery to the last saved point after an unexpected exit; quitting normally saves the exact stop time. Relaunch always starts idle. Very short, zero-duration entries are discarded on recovery or stop.

If a save fails, DayTape shows an error and keeps the previous valid records; a quit that cannot save is cancelled. Unknown store versions or unreadable data are not overwritten. Back up the data file with DayTape quit before moving or changing it.

For an isolated development session, launch the executable with a separate data directory:

```sh
LINE_DATA_DIRECTORY="$(mktemp -d)" build/DayTape.app/Contents/MacOS/DayTape
```

Use only one DayTape process per data directory.

## App icon

The paper icon source is `Resources/DayTapeIcon.png`. Run `./scripts/build-icon.sh` after editing it to regenerate `Resources/DayTape.icns`; the app build includes that icon automatically. Design explorations are kept locally in the ignored `design/` directory and are not required for the build.

## Validation

```sh
swift test
python3 scripts/smoke-test.py
python3 scripts/smoke-test.py --main-window
python3 scripts/smoke-test.py --timeline
python3 scripts/smoke-test.py --creation
python3 scripts/smoke-test.py --overwrite
python3 scripts/smoke-test.py --editing
python3 scripts/smoke-test.py --resize-overwrite
python3 scripts/smoke-test.py --system-activity
python3 scripts/smoke-test.py --continuation
```

Tests exercise the public tracking operations using a controlled clock and temporary real files. Native menu bar behavior, focus, dismissal, rendering, and appearance/accessibility settings also need checks in the running app.

The smoke check builds a separate debug bundle under `build/smoke/`, uses temporary data, drives the app's own native text field and accessible Stop button, then exits. It kills the test process if it exceeds 20 seconds, 40 seconds for editing or main-window checks, or 50 seconds for continuation. It also checks popover close/reopen, anchoring to the menu bar through content resizing, and continued tracking. It needs a logged-in graphical session; avoid interacting with other apps during the short run. It does not change system accessibility settings or require control of other apps, and it leaves the main release bundle untouched.

The main-window smoke check runs two fresh processes with isolated records and window-frame preferences. It exercises the native slider, time-format popup and keyboard selection, popover button, menu actions, Command-comma, Command-W, draft dismissal, minimize/restore, single-window reuse, frame restoration, activation policy, and continued tracking. It saves a content preview under `build/main-window-smoke-results/settings.png`. For a composited image including native glass, run `LINE_SMOKE_CAPTURE=1 python3 scripts/smoke-test.py --main-window`; this captures only the test window into `settings-window.png` when screen capture is available. It also captures `settings-first-open.png` before any slider interaction and checks that the native thumb is light in dark appearance. Physical Dock/app-switcher behavior, Spaces, and the full appearance/accessibility matrix still need manual verification.

The timeline smoke check sends deterministic events through the AppKit input handler and verifies browsing, pinch anchors, two-finger double-tap reset, Now, popover stability, and the configured default across two fresh processes. Physical trackpad behavior and the system event-monitor delivery still require a manual check. The default is saved in the existing JSON store when the Settings slider changes. Pinching, resetting, and closing the popover do not save temporary zoom.

The creation smoke check exercises the production mouse-event handler and native task picker. It covers historical and running entries, reverse drags, task reuse, cancellation during dragging and typing, dismissal, selection boundaries and rejected future selections, and popover anchoring. Physical pointer delivery and appearance still need manual verification.

The resize-overwrite smoke check covers Command held before dragging, toggling Command without pointer movement, release-time mode selection, cancellation, trimming, deletion, and stable popover positioning.

The overwrite smoke check covers Command captured at mouse-down and released before dragging, cancellation, split entries, reverse replacement across multiple entries, task reuse, through-Now tracking, and stable popover positioning. It uses the same isolated data and 20-second process limit.

The editing smoke check uses native color controls and confirmation buttons alongside the production pointer handler. It checks click targets, task reassignment, immediate color changes and Escape, deletion cancellation/confirmation, running corrections/deletion, edge resizing, and popover anchoring. Physical mouse/keyboard delivery and appearance still need manual verification.

## Plan

- [Domain vocabulary](../CONTEXT.md)
- [Spec](spec.md)
- [Tasks](../tasks/README.md)
- [Task tracking workflow](issue-tracker.md)

The `python3 scripts/smoke-test.py --dismissal` check exercises the outside-click callback before using the color menu, after dismissing it, and after choosing a color. Physical outside-click delivery still needs a manual check.

The system-activity smoke check injects private notification centers into the macOS adapter. It verifies lock/sleep stopping, duplicate and reordered signals, ignored display sleep, draft dismissal, and stopped state after return. It never broadcasts fake system notifications or changes the release app's data. The user reports the real implementation working; the full physical scenario matrix remains part of final verification.

The continuation smoke check verifies panel anchoring and non-key/non-main presentation, native OK/Reject actions and first-click support, notice persistence after outside clicks, main-window acceptance, real timer completion, and cancellation by implemented tracking/editing actions. It uses isolated data and synthetic interruption signals. Physical wake/unlock, click delivery, keyboard focus, Spaces, and appearance still need a hands-on check.
