# Line

A personal macOS menu bar time tracker, built with Swift, SwiftUI, and AppKit. Requires macOS 26 and Xcode 26 or newer.

## Build and run

```sh
./scripts/build-app.sh
open build/Line.app
```

The script builds a release executable and creates an ad-hoc-signed app bundle. For a debug build, use `./scripts/build-app.sh debug`. Open `Package.swift` in Xcode to work on the Swift package; launch the bundled app to verify its menu bar and no-Dock behavior.

Click Line's menu bar icon to see the current state and timeline. Start task or Switch task reveals and focuses the task picker. Enter a name and press Return or Start, or choose an existing task from the list. Choosing a task or pressing Escape hides the picker. Switching tasks ends the previous entry at the new entry's start. Stop ends tracking; closing the popover leaves it running. The timeline starts with a four-hour view and follows now. Scroll horizontally, or use Shift+mouse-wheel, to browse history and future space. Pinch to zoom; while browsing, zoom stays anchored under the pointer. Double-tap with two fingers to reset to four hours while keeping the viewed time centered. At the default scale, another double-tap returns to Now. Now returns to the present, and reopening follows now at the saved zoom level. Right-click the menu bar icon, including a trackpad secondary click or Control-click, for the native menu containing Quit Line.

Tickets 1 and 2 supply tracking and timeline browsing. Drawing/editing entries, lock/sleep handling, automatic continuation, and launch at login are subsequent tickets and are not implemented yet. Until lock/sleep handling lands, stop tracking before leaving the Mac.

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
```

Tests exercise the public tracking operations using a controlled clock and temporary real files. Native menu bar behavior, focus, dismissal, rendering, and appearance/accessibility settings also need checks in the running app.

The smoke check builds a separate debug bundle under `build/smoke/`, uses temporary data, drives the app's own native text field and accessible Stop button, then exits. It kills the test process if it exceeds 20 seconds. It also checks popover close/reopen, anchoring to the menu bar through content resizing, and continued tracking. It needs a logged-in graphical session; avoid interacting with other apps during the short run. It does not change system accessibility settings or require control of other apps, and it leaves the main release bundle untouched.

The timeline smoke check sends deterministic events through the AppKit input handler and verifies browsing, pinch anchors, two-finger double-tap reset, Now, popover stability, and persisted zoom across two fresh processes. Physical trackpad behavior and the system event-monitor delivery still require a manual check. Zoom is saved in the existing JSON store when a pinch ends, zoom is reset, or the popover closes.

## Plan

- [Domain vocabulary](CONTEXT.md)
- [Spec](.scratch/line-v1/spec.md)
- [Tickets and dependencies](.scratch/line-v1/ticket-plan.md)
