# Line

A personal macOS menu bar time tracker, built with Swift, SwiftUI, and AppKit. Requires macOS 26 and Xcode 26 or newer.

## Build and run

```sh
./scripts/build-app.sh
open build/Line.app
```

The script builds a release executable and creates an ad-hoc-signed app bundle. For a debug build, use `./scripts/build-app.sh debug`. Open `Package.swift` in Xcode to work on the Swift package; launch the bundled app to verify its menu bar and no-Dock behavior.

Click Line's menu bar icon, enter a task name, and press Return or Start. Type a name to find existing tasks or pick one from the list. Switching tasks ends the previous entry at the new entry's start. Stop ends tracking; closing the popover leaves it running. The four-hour timeline follows now and shows saved and growing entries. Quit is in the popover's menu.

Ticket 1 supplies this basic tracking experience. Timeline scrolling/zooming, drawing/editing entries, lock/sleep handling, automatic continuation, and launch at login are subsequent tickets and are not implemented yet. Until lock/sleep handling lands, stop tracking before leaving the Mac.

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
```

Tests exercise the public tracking operations using a controlled clock and temporary real files. Native menu bar behavior, focus, dismissal, rendering, and appearance/accessibility settings also need checks in the running app.

The smoke check builds a debug bundle, uses temporary data, drives the app's own native text field and accessible Stop button, then exits. It kills the test process if it exceeds 20 seconds. It also checks popover close/reopen and the elapsed timer's accessibility value. It needs a logged-in graphical session; avoid interacting with other apps during the short run. It does not change system accessibility settings or require control of other apps. Build again with `./scripts/build-app.sh` afterward for a release bundle without the smoke-check code.

## Plan

- [Domain vocabulary](CONTEXT.md)
- [Spec](.scratch/line-v1/spec.md)
- [Tickets and dependencies](.scratch/line-v1/ticket-plan.md)
