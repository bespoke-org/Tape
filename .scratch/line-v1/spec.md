# Line v1: personal menu bar time tracking

**Status:** ready-for-agent

**Scope:** Native Swift app for one person's Mac. This spec records the approved design interview, including the native macOS design requirement. Ticket decomposition is reviewed separately before publication.

## Problem Statement

I want to record what I am working on without managing a full desktop app. I need to see my time as a continuous strip, add work I forgot to track, and reuse the same task across multiple days. Locking or sleeping my Mac should exclude that absence without making me manually restart a timer every time I return.

## Solution

Line lives in the macOS menu bar with no Dock icon. Its popover shows a horizontal timeline and compact tracking controls. Time moves beneath a centered now marker when following the present. Scrolling browses history and the future; pinching adjusts the scale. Drawing on empty timeline space records time, and drawing up to now starts ongoing tracking.

Tasks are reusable names with colors. Each task can have many time entries, but only one task runs at a time and entries never overlap. Lock or sleep stops tracking. A usable return presents a ten-second countdown anchored to the menu bar; unless rejected, it resumes the previous task and includes those ten seconds. Everything is stored locally.

The app should look and behave like a native macOS 26 utility, using system controls, typography, and Liquid Glass materials. Native behavior and accessibility are part of acceptance, including the custom timeline.

## User Stories

1. As the user, I want to launch Line as a menu bar app without a Dock icon, so that it stays available without occupying my workspace.
2. As the user, I want the menu bar icon to indicate whether tracking is running, so that I can check its state at a glance.
3. As the user, I want clicking the icon to open a popover and clicking outside to dismiss it, so that it behaves like a familiar Mac utility.
4. As the user, I want tracking to continue while the popover is closed, so that I can work in other apps.
5. As the user, I want to type a task name and see matching existing tasks, so that I can create or reuse a task in one place.
6. As the user, I want tasks to have reusable names and colors, so that work on the same activity is recognizable across days and weeks.
7. As the user, I want a new task to receive a random, legible color, so that creating it requires only a name.
8. As the user, I want to rename and recolor a task across all its entries, so that I can keep my records consistent.
9. As the user, I want duplicate task names to be prevented regardless of capitalization or surrounding spaces, so that I do not accidentally split one activity into multiple tasks.
10. As the user, I want to start, stop, and switch tasks, so that I can track what I am doing as it changes.
11. As the user, I want to see the running task and its growing timeline entry, so that I know what Line is recording.
12. As the user, I want to view recorded entries on a continuous horizontal timeline, so that I can understand where my time went.
13. As the user, I want the timeline to follow the present beneath a centered now marker, so that the display stays current.
14. As the user, I want to scroll backward and forward without the view snapping back, so that I can browse time freely.
15. As the user, I want two-finger double-tap and reopening the popover to return to the present, so that I can quickly regain my current context.
16. As the user, I want a four-hour initial view and pinch-to-zoom with a remembered scale, so that I can choose how much time I see without zoom buttons.
17. As the user, I want to draw an interval on empty timeline space and then name or select its task, so that I can record work retrospectively.
18. As the user, I want cancelling task selection to discard the proposed entry, so that an unfinished interaction does not create records.
19. As the user, I want drawing up to or beyond now to start tracking from the selected start time, so that recording recent work can flow directly into ongoing work.
20. As the user, I want overlap attempts explained and rejected without changing existing entries, so that my records remain consistent.
21. As the user, I want to click an entry to change its task or timestamps, so that I can correct mistakes.
22. As the user, I want to resize completed entries by dragging their edges with minute snapping, so that common corrections are quick.
23. As the user, I want live tracking to preserve actual timestamps, so that minute snapping does not distort recorded durations.
24. As the user, I want to edit a running entry's task or start without stopping it, so that corrections need not interrupt tracking.
25. As the user, I want deletion to require confirmation and deletion of a running entry to stop tracking, so that accidental actions do not silently remove my work.
26. As the user, I want screen lock and system sleep to stop tracking immediately, so that my absence is not counted as work.
27. As the user, I want ordinary inactivity and display dimming or display-off alone to leave tracking running, so that reading and thinking still count.
28. As the user, I want returning from lock or sleep to show a ten-second automatic-continuation countdown without stealing focus, so that I can resume work without interacting with Line.
29. As the user, I want Reject to cancel continuation and exclude the countdown interval, so that breaks do not become recorded work.
30. As the user, I want ordinary Mac use and dismissing the popover to leave the countdown active, so that I can continue working normally.
31. As the user, I want an uninterrupted countdown to resume the previous task from the time I returned, so that those ten seconds are included.
32. As the user, I want another lock or sleep during the countdown to cancel it and offer a fresh countdown next time, so that repeated interruptions are handled predictably.
33. As the user, I want explicit tracking or entry-editing actions to cancel pending continuation, so that an old task cannot restart over my action.
34. As the user, I want quitting to stop tracking and relaunching to start idle, so that Line does not count time while it is not running.
35. As the user, I want unexpected-exit recovery to preserve only the last saved tracking point, so that downtime is not silently counted as work.
36. As the user, I want all tasks, entries, and preferences stored on this Mac, so that the app works without an account or network connection.
37. As the user, I want an optional launch-at-login setting that starts off, so that I control whether Line starts with my session.
38. As the user, I want native controls, Liquid Glass, keyboard behavior, and accessible labels, so that Line feels at home on macOS.
39. As the user, I want light/dark appearance and contrast, transparency, and motion preferences respected, so that the interface remains comfortable and legible.
40. As the user, I want a locally runnable app with reproducible build instructions, so that I can use and maintain it on my own Mac.

## Implementation Decisions

### App and UI boundaries

- Build in Swift for macOS 26.0 or later, using SwiftUI and AppKit where needed for menu bar integration, focus behavior, and system lifecycle events. The verified development machine runs macOS 26.6.2 on Apple Silicon, with Xcode 26.5 and Swift 6.3.2.
- Use a native status item/popover integration that supports both deliberate user interaction and automatic, non-focus-stealing continuation presentation. Verify these behaviors with a runnable app early; do not assume an ordinary interactive popover automatically meets the focus requirement.
- Keep the menu bar icon compact; task names belong inside the popover; omit the elapsed-time display for now. Left-click opens the timeline with Start/task selection, Stop and task switching. Return to Now uses two-finger double-tap, without a dedicated button. Secondary click (including trackpad secondary click and Control-click) opens a native actions menu containing only Quit Line for now. The popover has no three-dot menu or Quit action. Add access to preferences when the later settings features are implemented.
- Keep tracking operations separate from view rendering and system-event delivery. Route mutations through a single application-level boundary so overlap validation, persistence, and cancellation rules apply consistently to every interaction.
- The default popover shows the current state and timeline, with task selection hidden behind Start task or Switch task. Show these header actions as plain icons: play for Start task, opposing arrows for Switch task, and a square for Stop. Keep tooltips and accessible labels, with no visible text or button backgrounds. Revealing the inline picker focuses its search field. Successful task selection or Escape collapses the picker; Escape with no picker open dismisses the popover. Reopening starts with the picker hidden. Keep the layout compact without titles or subtitles. When the picker is open, separate it from the timeline with a native divider. Task suggestions show only their color dot and name, without trailing action icons. Always show the date or visible date range above the timeline, including while following now.
- Separate timeline coordinate/gesture calculations from tracking timestamps. Rendering cadence must not determine elapsed time or create persistent writes for every animation frame. Avoid continuous timeline rendering while its popover is closed.

### Records and invariants

- A task has a stable identifier, display name, and color. Remove tasks with no remaining entries as part of the same atomic save; tasks with recorded time remain reusable. Trim names, reject empty names, and compare names without case sensitivity when checking uniqueness. Renaming and recoloring retain identity and apply to all linked entries.
- Use a 12-color palette, grouped by shade in the picker: red, orange, brown, yellow, green, mint, teal, cyan, blue, indigo, purple, and pink. Pink uses a rosier custom shade (#F062B3). Randomly choose among colors unused by tasks with entries; when all colors are used, choose from the full palette. Keep existing task colors unchanged and check palette legibility during appearance verification. Allow later color changes while keeping labels readable. Task color is not the only indication of identity.
- A time entry has a stable identifier, task reference, start instant, and either a fixed end instant or running state. Only one entry can be running. The running entry continues accumulating time without a numeric elapsed-time display.
- Use absolute instants for storage and duration calculation, with local dates/times for presentation. Preserve durations across midnight and daylight-saving transitions; ambiguous local timestamp edits must identify the intended instant rather than silently changing duration.
- Completed entries have positive duration, end no later than now, and do not overlap. Touching endpoints are allowed. Treat intervals as start-inclusive and end-exclusive so switching tasks at one instant produces adjacent entries.
- Starting a different task ends the previous entry and starts the new entry at the same instant as one operation. Starting the already-running task is a no-op. These are implementation defaults that preserve the single-running-task rule.
- Apply validation again when committing an edit or completing task selection, because time and tracking state can change while a control is open. Rejected operations preserve existing entries and give a readable explanation.

### Timeline and entry creation

- Show four hours initially, with now centered. Maintain following and browsing states. Scrolling enters browsing; two-finger double-tap at the default scale and reopening the popover return to following. Retain and persist the chosen zoom scale.
- The now marker denotes actual current time only. It can move offscreen while browsing; a central marker must not relabel a historical time as now.
- Support horizontal trackpad scrolling and Shift+mouse-wheel navigation. Click-and-drag on empty space draws an interval; it does not pan. Pinch changes scale without zoom buttons. Keep zoom stable around the interaction location where practical. A two-finger double-tap resets to the default four-hour scale, preserving the viewed center and following/browsing state, and saves that scale. At the default scale, a two-finger double-tap returns to Now.
- There is no user-selected product minimum or maximum zoom range. Use finite internal bounds to keep labels, selection, and rendering usable; do not turn those bounds into extra controls or claim the previously suggested ranges were approved.
- Present date context and time ticks at a density appropriate to scale, and render only the visible range. Browsing is not restricted to a fixed day or week. Future space remains available for navigation but cannot contain recorded future entries.
- After a valid drag, focus a native text field that both accepts a new task name and filters existing tasks. Enter/select commits; Escape cancels. No task or entry is persisted by merely typing a draft.
- A wholly historical selection creates a completed entry. A selection with a past start that reaches or crosses now creates a running entry from the selected start through task selection and onward. Determine this intent at selection time so time spent typing does not turn it into a historical entry.
- A selection entirely in the future creates nothing. A selection with no duration, including one that snaps to zero, silently cancels without an error or task picker. Normalize reverse-direction drags before validation. Drawing snaps to one minute with up to two hours visible, five minutes with up to eight hours visible, and fifteen minutes at wider scales. The special endpoint now and neighboring entry boundaries retain their actual instants. Resize timestamps snap to whole minutes.
- Constrain an ordinary drawn selection to the empty gap containing its drag origin. The preview and released interval stop at neighboring entries in either direction, including a running entry. Exact neighboring timestamps take precedence over minute snapping at those boundaries. Revalidate on commit and reject conflicts introduced after selection. Ordinary drawing never truncates or replaces existing entries. The Command-drag exception is described below.

### Command-drag overwrite

- [Ticket 09](issues/09-overwrite-entries-with-command-drag.md) adds overwrite drawing. Hold Command at the start of a drag to select across existing entries, including starting inside one. Retain overwrite intent through task selection and show a gray striped preview before committing, with explicit Overwrite or Overwrite & Start submission. Keep the picker compact: no extra overwrite label, selected-time caption, or Cancel button. Escape or closing the popover cancels the draft.
- Committing replaces the selected time: trim partially covered edges, delete fully covered entries, and split an entry into two surviving fragments if the new interval covers its middle. Keep uncovered timestamps and task assignments unchanged. Delete a task when its final entry disappears; retain tasks referenced by any surviving or replacement entry. Clean up unused task records from earlier versions on load.
- Merge the overwrite result with directly adjoining entries for the selected task, including fragments on either side and running entries. Continue through the connected same-task entries to form one continuous interval. A real gap or a different task stops merging. Do not merge unrelated history or change ordinary drawing's behavior.
- Preserve ordinary drawing's snapping, cancellation, and historical/through-Now semantics. A historical overwrite leaves any uncovered running tail running; an overwrite through Now starts the selected task instead. Apply the entire replacement atomically after revalidation, preserving the single-running-entry and non-overlap invariants. Cancellation or failure changes no records.

### Corrections and deletion

- Clicking an entry opens an inline editor below the timeline divider, in the same position as the task picker, for its task and timestamps. Valid task, timestamp, and color changes save automatically without collapsing the editor. There are no Save or Cancel buttons. Task names save on Return, focus loss, or editor dismissal. Escape or popover dismissal keeps saved changes and discards rejected timestamp drafts. A separate expandable section edits reusable task name/color across all linked entries. Its compact color picker sits before the name field and shows colored circles without visible color names. Completed entries also support resizing either edge. Changing an entry's task reassigns that entry; renaming a task changes the reusable task everywhere.
- A running entry can change task or start while remaining running. Its live endpoint is not a fixed resize handle; stop it before assigning a fixed end.
- All corrections obey overlap and timestamp invariants. Provide a native confirmation for an explicit entry-deletion action. Cancelling confirmation preserves the entry and running state; confirming deletion of a running entry also stops tracking. Command-drag overwrite commits through its preview and task submission, including any fully covered entries it removes.
- Initiating an explicit start, entry-creation flow, or entry-editing flow cancels pending continuation before a delayed callback can resume the old task. Do not reinstate the countdown if the user later abandons that action. Opening the main popover, scrolling, or clicking elsewhere alone is not an edit and does not reject continuation.

### Lock, sleep, and continuation

- Screen lock or system sleep ends a running entry at the interruption boundary and remembers its task for possible continuation. Ordinary inactivity and display-off alone do not stop tracking.
- Treat locked and sleeping conditions independently. A return is usable only when awake and unlocked. Duplicate notifications, sleep followed by lock, and wake while still locked must not produce duplicate entries or multiple countdowns.
- If a task was interrupted, a usable return starts one ten-second pending continuation and immediately presents a popover anchored to the menu bar without stealing focus. Show the task name, a decreasing countdown, and Reject. An idle app does not invent a task to resume.
- Dismissing that popover or using another app leaves the countdown active. On completion, start one entry at the usable-return instant, including the countdown interval. Use elapsed time, not animation frames, to decide completion.
- Reject clears pending continuation without creating an entry. Another interruption also cancels it and leaves the provisional interval untracked, but retains the interrupted task for a fresh countdown on the next usable return.
- An explicit tracking/editing action cancels pending continuation. Stop or Quit also prevents its later completion. Serialize return events, user actions, and countdown completion so at most one continuation can commit; recheck validity before committing.
- Implement and manually verify actual lock/unlock and sleep/wake detection on the target Mac. Keep this integration isolated from the tracking operations so event-ordering tests can use simulated signals. Display inactivity is not an acceptable substitute for screen-lock detection.

### Local durability and lifecycle

- Store tasks, entries, preferences, and recovery information in the user's local application data location, outside the source checkout and app bundle. Use a versioned local store with atomic mutation behavior. Selecting the storage library is an implementation choice; no sync framework is required.
- Persist accepted mutations immediately and checkpoint a running entry periodically. Use five seconds as the initial checkpoint interval and verify that recovery does not include time after the last successfully saved checkpoint. Successful checkpoints must remain consistent with task/entry mutations.
- On deliberate quit, end and save the running entry, clear pending continuation, then exit. Normal relaunch starts idle. Launch at login also starts idle.
- After an unexpected exit, close any formerly running entry at its last saved tracking point and leave tracking stopped. Do not substitute relaunch time as its end or start a continuation countdown. Drop a recovered zero-duration provisional record if needed to preserve valid intervals.
- A pending continuation is not recorded work until accepted by countdown completion. An unexpected exit during the countdown must not commit it later.
- Surface storage failures without falsely reporting successful saves; preserve the previous valid stored data. Reopening the store must retain task identity, entry links, and the saved zoom preference.
- Provide launch at login using supported macOS facilities, initially off, and report the actual registration state. Keep the app self-contained with no separately installed background service.

### Native appearance and accessibility

- Prefer standard SwiftUI/AppKit controls, system fonts, semantic colors, standard spacing, and SF Symbols. Use public system materials and let standard popovers and controls adopt Liquid Glass.
- Apply custom glass sparingly to controls. Keep timeline content and task blocks legible without stacking glass effects on each entry. Where a custom text-heavy glass treatment is necessary, prefer the regular variant.
- Follow native focus, hover, selection, keyboard dismissal, and destructive-confirmation conventions. The AirPods comparison describes unobtrusive continuation behavior, not a requirement to reproduce private Apple UI.
- Support light/dark appearance, Reduce Transparency, Reduce Motion, and increased contrast. Reduced animation must not change tracking semantics or stop the clock. Give actionable controls and timeline entries accessible labels and provide keyboard editing through standard fields.
- While tracking, the task-colored dot beside the current task name emits two staggered, expanding and fading pulses. Keep the center steady and the header layout unchanged. With Reduce Motion enabled, show only the static dot. Animate only while the popover is open.
- Use the timestamp editor as a precise alternative to dragging entry edges. Do not depend on color alone to identify tasks or the running state.

### Delivery and planning

- Deliver a locally runnable app bundle and source/build instructions for this Mac. No App Store submission, notarized distribution workflow, account system, or hosted component is required.
- Keep the spec and individual implementation tickets in the local Markdown tracker. Approved tickets use ready-for-agent and explicitly declare their dependencies.

## Testing Decisions

- Test observable tracking operations and resulting records/state through the single application-level mutation boundary. Avoid tests of private methods, view structure, or framework implementation details. There is no existing test suite or prior implementation in this initially empty repository.
- Inject controllable time and system-event signals at that boundary to exercise start/stop/switch, duplicate starts, overlap rejection, endpoint adjacency, pending continuation, re-lock, duplicate wake/unlock notifications, and user-action races without ten-second real waits.
- Test manual historical creation, drawing through now with delayed task selection, cancellation, reverse drags, minute snapping, resize/edit conflicts, and running-entry deletion. Verify both successful mutations and preservation of existing data after rejection.
- Verify persistence by saving to temporary real local storage and reopening it. Cover clean quit, checkpoint recovery, unexpected exit during pending continuation, preferences, reusable task identity, and storage failure behavior.
- Include midnight and daylight-saving cases for duration and timestamp editing. Confirm monotonic countdown behavior independently of changes to displayed wall time where the implementation separates those clocks.
- Manually verify native menu bar and Dock behavior, actual trackpad scroll/pinch/drawing, editor focus and keyboard use, real lock/sleep transitions, non-focus-stealing continuation, dismissal during countdown, and login startup on the target Mac. Simulated lifecycle tests alone do not establish that platform integration works.
- Manually verify light/dark appearance, contrast, transparency, and motion preferences, readable task colors, accessible labels, and the behavior of the packaged app outside the development process.
- Include relevant checks in every vertical slice. Final delivery verification exercises the combined flows rather than deferring all testing or native appearance to the end.

## Out of Scope

- Calendar integration, planned future entries, reminders, and future scheduling.
- Accounts, cloud services, peer-to-peer synchronization, and Automerge integration.
- Additional task fields, projects, billing, reports, exports, and task deletion/archiving workflows.
- Automatic inactivity detection, application monitoring, or inferring the task from computer use.
- Overlapping entries, simultaneous timers, automatic trimming/replacement, and a full undo system.
- Zoom buttons, a full desktop workspace, mobile versions, support for older macOS releases, and distribution to other users.

## Further Notes

The user approved the product interview and proposed testing approach, then added native macOS and Liquid Glass as explicit requirements. The source design notes and glossary remain in the repository for context; this spec is the implementation reference.

The main platform integration risks are reliably distinguishing lock from display inactivity and presenting an automatic menu bar popover without stealing focus. Verify both on the actual Mac and report any limitation before claiming those behaviors complete.

Apple references: [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [Human Interface Guidelines: Materials](https://developer.apple.com/design/human-interface-guidelines/materials).
