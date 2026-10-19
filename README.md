# Line

A personal macOS menu bar time tracker, built with Swift, SwiftUI, and AppKit. Requires macOS 26 and Xcode 26 or newer.

## Build and run

```sh
./scripts/build-app.sh
open build/Line.app
```

The script builds a release executable and creates an ad-hoc-signed app bundle. For a debug build, use `./scripts/build-app.sh debug`. Open `Package.swift` in Xcode to work on the Swift package; launch the bundled app to verify its menu bar and no-Dock behavior.

Click Line's menu bar icon to see the current state and timeline. The play icon when idle, or the switch arrows while tracking, reveals and focuses the task picker. The square stop icon ends tracking. These actions use plain icons with tooltips. Enter a name and press Return or Start, or choose an existing task from the list. Choosing a task or pressing Escape hides the picker. Switching tasks ends the previous entry at the new entry's start. Stop ends tracking; closing the popover leaves it running. The timeline starts with a four-hour view and follows now. Scroll horizontally, or use Shift+mouse-wheel, to browse history and future space. Pinch to zoom; while browsing, zoom stays anchored under the pointer. Double-tap with two fingers to reset to four hours while keeping the viewed time centered. At the default scale, another double-tap returns to Now. Reopening follows now at the saved zoom level. There is no separate Now button. Right-click the menu bar icon, including a trackpad secondary click or Control-click, for the native menu containing Quit Line.

Drag empty timeline space to select time, then type a task name or choose an existing one. Historical selections use Save; selections reaching Now use Start and include time spent choosing the task. Escape, Cancel, or closing the popover discards the draft. Reverse drags work, snapping adapts to zoom, and the dragged edge stops at neighboring entries. Views up to two hours snap by one minute, up to eight hours by five minutes, and wider views by fifteen minutes. Contact with a neighbor uses its exact timestamp; new conflicts are still rejected when saving.

Hold ⌘ when starting a drag to overwrite existing time, even when starting inside an entry. The gray striped selection shows the time to replace. Release, then choose a task or submit with Overwrite; through-Now selections use Overwrite & Start. Partial overlaps trim existing entries, middle overlaps split them, and fully covered entries disappear. Choosing the same task merges the new interval with connected entries into one continuous block, including running time. Real gaps and different tasks stay separate. Uncovered time remains. A task disappears from suggestions when its last entry is removed; tasks with other entries remain reusable. Unused task names left by earlier builds are cleaned up on launch. Releasing ⌘ after starting the drag does not change its mode. The overwrite picker has no extra caption or Cancel button; Escape or closing the popover discards the draft.

Click an entry to open its settings below the timeline divider. Time settings and Delete sit above the task search field. Select a suggestion or press Return to reassign this entry, creating a task if the name is new. Typing alone does not change records. Timestamp and color changes save automatically while the editor stays open. Escape or closing the popover keeps successful changes and discards rejected timestamp drafts. The swatch beside the search field changes the task color across all entries. There are no Save or Cancel buttons in the editor. Delete requires confirmation. Running entries keep tracking while their task or start is corrected; stop before setting a fixed end. Hover near either edge of an entry for a bracket-style trim cursor. The bracket identifies which entry edge will move. It stays visible during resizing; holding Command suppresses the hint for overwrite mode. Drag either edge to resize it, snapping to minutes and stopping at neighboring entries. Dragging a completed entry’s end to or past Now continues that same entry as running, unless another entry blocks it. For a running entry, moving the start keeps tracking; dragging the end into the past stops it at that time, while leaving it at or beyond Now keeps tracking. Command-drag still overwrites instead of resizing.

Tickets 1–4 and 9 supply tracking, browsing, drawing, corrections, and Command-drag overwrite. Lock/sleep handling, automatic continuation, and launch at login are subsequent tickets and are not implemented yet. Until lock/sleep handling lands, stop tracking before leaving the Mac.

New tasks use a 12-color palette, choosing an unused color when available before repeating colors. Existing tasks keep their assigned colors.

## Local data

Records are stored in `~/Library/Application Support/Line/tracking.json`, independently of the source checkout and app bundle. Accepted changes are saved atomically. A five-second checkpoint timer limits recovery to the last saved point after an unexpected exit; quitting normally saves the exact stop time. Relaunch always starts idle. Very short, zero-duration entries are discarded on recovery or stop.

If a save fails, Line shows an error and keeps the previous valid records; a quit that cannot save is cancelled. Unknown store versions or unreadable data are not overwritten. Back up the data file with Line quit before moving or changing it.

For an isolated development session, launch the executable with a separate data directory:

```sh
LINE_DATA_DIRECTORY="$(mktemp -d)" build/Line.app/Contents/MacOS/Line
```

Use only one Line process per data directory.

## Validation

```sh
swift test
python3 scripts/smoke-test.py
python3 scripts/smoke-test.py --timeline
python3 scripts/smoke-test.py --creation
python3 scripts/smoke-test.py --overwrite
python3 scripts/smoke-test.py --editing
```

Tests exercise the public tracking operations using a controlled clock and temporary real files. Native menu bar behavior, focus, dismissal, rendering, and appearance/accessibility settings also need checks in the running app.

The smoke check builds a separate debug bundle under `build/smoke/`, uses temporary data, drives the app's own native text field and accessible Stop button, then exits. It kills the test process if it exceeds 20 seconds, or 40 seconds for the longer editing check. It also checks popover close/reopen, anchoring to the menu bar through content resizing, and continued tracking. It needs a logged-in graphical session; avoid interacting with other apps during the short run. It does not change system accessibility settings or require control of other apps, and it leaves the main release bundle untouched.

The timeline smoke check sends deterministic events through the AppKit input handler and verifies browsing, pinch anchors, two-finger double-tap reset, Now, popover stability, and persisted zoom across two fresh processes. Physical trackpad behavior and the system event-monitor delivery still require a manual check. Zoom is saved in the existing JSON store when a pinch ends, zoom is reset, or the popover closes.

The creation smoke check exercises the production mouse-event handler and native task picker. It covers historical and running entries, reverse drags, task reuse, cancellation during dragging and typing, dismissal, selection boundaries and rejected future selections, and popover anchoring. Physical pointer delivery and appearance still need manual verification.

The overwrite smoke check covers Command captured at mouse-down and released before dragging, cancellation, split entries, reverse replacement across multiple entries, task reuse, through-Now tracking, and stable popover positioning. It uses the same isolated data and 20-second process limit.

The editing smoke check uses native date controls and confirmation buttons alongside the production pointer handler. It checks click targets, automatic entry corrections and task color changes, rejected edits and Escape, deletion cancellation/confirmation, running corrections/deletion, edge resizing, and popover anchoring. Physical mouse/keyboard delivery and appearance still need manual verification.

## Plan

- [Domain vocabulary](CONTEXT.md)
- [Spec](.scratch/line-v1/spec.md)
- [Tickets and dependencies](.scratch/line-v1/ticket-plan.md)
