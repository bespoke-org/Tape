# Tape design interview

Working record of agreed behavior and unresolved decisions. This is not the implementation spec.

## Agreed behavior

- Tape is a Swift macOS menu bar app with no Dock icon.
- Clicking the menu bar icon opens a popover; clicking outside dismisses it. Tracking continues while it is closed, and the icon indicates whether tracking is running.
- Secondary click on the menu bar icon opens a native actions menu containing only Quit Tape for now. Trackpad secondary click and Control-click use this menu. The popover has no three-dot menu or Quit action.
- The main view is a continuous horizontal timeline with extensive scrolling in either direction.
- While following the present, time moves beneath a centered now marker. Browsing pauses following; a Now action returns to the present and resumes following. The now marker need not remain visible when browsing.
- Click-and-drag on empty timeline space creates a time entry. Horizontal scrolling browses time; Shift+mouse-wheel provides a mouse alternative.
- The default visible timeline span is eight hours. Users adjust the scale with pinch-to-zoom; no zoom buttons. Product zoom limits have not been selected.
- After drawing, a text field accepts a new task name while searching existing tasks. Selecting an existing task or creating a new one saves the entry; Escape cancels. Live tracking uses the same task picker.
- Clicking an entry allows changing its task, editing start/end times, or deleting it. Dragging an edge resizes it. Mouse edits snap to whole minutes; live tracking retains actual timestamps.
- Creating or editing an entry cannot overlap another entry. Reject the overlap with an explanation and preserve existing entries.
- Reopening the popover returns to now and retains the chosen zoom level.
- Tasks are reusable across entries, days, and weeks. Starting another task ends the current entry. Only one task can run, and entries cannot overlap.
- Tasks have a name and color only for the first version. Creating a task assigns it a random color. Users can recolor tasks, updating all their entries. Task renaming is not supported. Names are unique ignoring capitalization and surrounding spaces.
- The popover shows the running task, Stop, and task switching. The elapsed-time display is omitted for now. The menu bar shows a compact Tape icon with a running indicator.
- By default, the popover shows only the current state and timeline. Start task or Switch task reveals and focuses the inline task picker. Selecting a task or pressing Escape collapses it; reopening the popover starts with the picker hidden. Omit titles, subtitles, and dividers. Show the date or visible date range above the timeline.
- The first version records actual time only. Recorded entries cannot extend into the future. Calendar events are a possible later feature.
- Screen lock stops tracking. Locked time is excluded by default. On return, if a task was running, Tape immediately shows a non-focus-stealing popover from its menu bar icon, similar to the AirPods reconnect popup, with a 10-second countdown and a Reject action. If the countdown completes without rejection, Tape resumes the previous task with an entry starting at unlock/usable wake, including the countdown interval. Rejecting leaves that interval untracked. This replaces the earlier explicit-resume proposal.
- Clicking outside dismisses the continuation popover without cancelling the countdown. Ordinary use of the Mac does not reject continuation.
- Locking or sleeping again during the countdown cancels the pending continuation and leaves that interval untracked. The next usable return starts a fresh countdown for the same task. Waking while still locked does not start a countdown.
- Ordinary keyboard and mouse inactivity does not stop tracking.
- System sleep also stops tracking, even without screen lock, and uses the same automatic-continuation flow on return. Display dimming or display-off alone does not stop tracking.
- A manual entry drawn up to or beyond now becomes a running entry when created, starting at the selected start time and including time spent choosing the task. Cancelling the task picker creates nothing. Existing overlap rules still apply, including overlap with another running entry.
- Quitting Tape stops tracking; relaunch starts idle. After an unexpected exit, recover a formerly running entry only through its last saved tracking point and leave it stopped. The user can correct the endpoint and start tracking again.
- Explicitly starting a task, creating an entry, or editing an existing entry cancels any pending automatic continuation. The pending task cannot restart over the user's action.
- A running entry can have its task or start time edited without stopping, subject to overlap checks. Setting a fixed end time requires stopping it first. Deleting it also stops tracking.
- Deleting any entry requires confirmation. A full undo system is outside the first version.
- Launch at login is optional and initially off.
- Data stays on this Mac and survives app restarts. No accounts or sync in the first version. Automerge and peer-to-peer sync are possible future directions, not selected architecture.
- Delivery is a locally runnable .app, with source and build instructions in this repo, targeting the user's installed macOS. No App Store publication or other distribution is planned.
- The spec and tickets live in this repo as Markdown. Each ticket has its own file with status, acceptance criteria, and dependencies.

## Planning status

The product interview and proposed testing approach were accepted. The implementation reference is now [the Tape v1 spec](spec.md). The [approved ticket breakdown](ticket-plan.md) merges the basic live timeline into the first tracking slice, with browsing and zoom as the next slice. Individual tasks are maintained with tatr under [tasks](../tasks/README.md). Planning records follow [the task tracking workflow](issue-tracker.md).

## Native macOS design requirements

Native appearance and behavior are acceptance criteria for the first version, including Apple's macOS 26 Liquid Glass design language.

- Prefer standard SwiftUI and AppKit controls, system typography, semantic colors, standard spacing, and SF Symbols for familiar actions. Use public system APIs for menu bar presentation and materials.
- Let system popovers and controls adopt Liquid Glass. Apply custom glass sparingly to controls; keep timeline content and task blocks readable without layering glass on every entry. Use Apple's regular glass variant when a custom glass treatment contains substantial text.
- Follow macOS keyboard, focus, hover, selection, dismissal, and confirmation conventions. Keep the automatic-continuation presentation anchored to the menu bar and non-focus-stealing. Its resemblance to the AirPods reconnect popup describes its behavior, not a requirement to reproduce private system UI.
- Support light and dark appearance, Reduce Transparency, Reduce Motion, and increased contrast. Keep timekeeping correct when reducing animation. Give controls and timeline entries accessible labels, and do not rely on task color alone to identify entries.
- Assign random task colors from a palette checked for legibility in supported appearances. Keep labels and selection indicators readable after user color changes.
- Include appearance and accessibility settings in manual verification, alongside keyboard interaction and focus behavior. Carry these requirements into the spec and relevant ticket acceptance criteria.

Sources: [Apple: Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [Apple HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials).

## Proposed testing approach

Test through the app's tracking operations, observing resulting entries and tracking state rather than private implementation details. Use controllable time and lock/sleep signals to exercise start, stop, switch, overlap rejection, drawing through now, countdown completion/rejection/cancellation, and unexpected-exit recovery without real-time waits. Verify saved data by reopening local storage. Manually verify the actual menu bar popover, drawing/resizing, trackpad scrolling and pinch, focus behavior on return, real lock/sleep transitions, and launch at login on this Mac.

## Verified build environment

- Apple Silicon Mac running macOS 26.6.2.
- Xcode 26.5, Swift 6.3.2, and macOS SDK 26.5 are installed.
- A macOS 26.0 deployment target supports this Mac with the installed SDK.
- No app build has been attempted yet.

## Next steps

Implement the approved tickets in dependency order, starting with tracking tasks on a live timeline.
