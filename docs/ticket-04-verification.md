# Ticket 04 verification

Implementation: [Correct entries and maintain reusable tasks](../.scratch/line-v1/issues/04-correct-entries-and-maintain-reusable-tasks.md).

Implemented on 2026-10-19; accepted as done by the user on 2026-10-20 for usability and functionality.

## Behavior

Click a timeline entry to open its settings inline below the timeline, replacing the task picker. The color picker, task search field, and Delete share one row. Start and end controls have been removed; adjust times by dragging the entry edges. Choose a suggestion or press Return to reassign the entry, creating a task for a new name. Typing alone does not change records. Text fields have no opaque fill. Escape or closing the popover keeps saved changes. There are no Save or Cancel buttons. Failed edits preserve saved records and show a readable error.

The swatch-only color picker saves choices immediately across every entry for that task. Task renaming has been removed. Search reassigns only the selected entry, leaving other entries and task names unchanged.

Completed and running entries support dragging either edge, with minute snapping and exact neighboring boundaries. Releasing the end at or past Now starts tracking on the same entry, preserving its task, start, and identity. The Now marker has the same three-point release tolerance as drawing. A neighboring entry still blocks extension, and write failures preserve the completed record. Mirrored bracket-style trim cursors appear within five points of a resizable edge. The bracket marks the selected start or end, with its hotspot on that edge and the bracket opening toward the entry. The chosen shape stays fixed during dragging. Hover and drag share the same edge detection; Command overwrite does not show a resize hint. Native [tracking areas](https://developer.apple.com/documentation/appkit/nstrackingarea) update hover and cursor state. Command at mouse-down retains overwrite behavior instead. Previews do not write records, Escape cancels, and crossing the opposite edge cancels a resize. Coincident edges prefer the entry containing the pointer. Click targets match the rendered two-point minimum width; later entries win shared boundaries.

Running entries can change task/start without stopping. Dragging a running end into the past stops at the selected time; keeping it at or beyond Now preserves tracking. Moving a running start keeps its end open and updates the recovery checkpoint. The main status row’s stop icon also stops tracking. The editor has no separate stop button. Native deletion confirmation preserves records and tracking on cancellation; confirmation removes the entry and stops it if running. Removing a task's last entry prunes the task atomically.

## Automated checks

- `swift test`: 50 tests passed in five suites on 2026-10-20, including compatibility loading for removed palette colors. Fourteen editing tests cover reassignment, identity, recoloring with names preserved, resizing to Now with recovery checkpoints and neighbor/write-failure protection, deletion/orphan pruning, minute resizing, exact boundaries, invalid/stale edits, running recovery, write failures, reopening, midnight, and repeated-hour absolute timestamps.
- `python3 scripts/smoke-test.py --editing`: passed. Exercises distinct start/end cursors at completed edges and both sides of a shared boundary, preservation of the selected edge during dragging, interior/strip exit, Command overwrite, running entries, hover without mutation, task search, creation on Return and reassignment from suggestions without stopping tracking, drag-to-Now continuation, running start/end resizing and normal stop, full-color swatch-only native menu choices, left-side picker placement, immediate color selection, Escape, native deletion confirmation and cancellation, running corrections/deletion, short-entry clicks, shared boundaries, adjacent-entry resizing, and stable popover anchoring.
- Final review on 2026-10-20: `--editing`, `--dismissal`, `--creation`, and `--overwrite` packaged smoke checks passed. Base and `--timeline` checks passed earlier.
- Each smoke process uses isolated temporary data and a bounded limit: 40 seconds for the expanded editing sequence, 20 seconds for other modes. Native controls are driven within the app; pointer and Escape inputs exercise the same handler as the local event monitor.

## Standards

No blocking findings. The initial exclusive-end hit-testing finding was resolved and covered in the packaged smoke check. `TrackingStore.updateEntry` has only test callers now; removing it is optional cleanup.

## Spec

No remaining blockers. Review identified minimum-width click targets and coincident resize edges; both were fixed and covered in the packaged smoke check. The user accepted the current UI, including its subtle search-field border. Ticket/spec descriptions now match the approved single-row editor, edge-only time editing, omitted dividers, and nine-color palette.

## Still manual

The user exercised and accepted the current UI. The complete physical-input, keyboard/VoiceOver, light/dark, and accessibility-preference matrix remains carried to ticket 07. Synthetic event delivery and native control actions do not establish these checks. Acceptance does not claim that full matrix passed. Immediate color-menu dismissal attempts were reverted at the user's request and are not part of the accepted behavior.

Color-menu regression: the original SF Symbol images arrived in the native menu as monochrome templates. Non-template swatch images preserve the task colors. The packaged editing check inspects every native menu image and its center pixel; it failed on the original blue swatch and passes with full-color images.

Resize transition regression: switching between stopped and running changed the menu-bar image dimensions and shifted the popover vertically by one point, despite an unchanged content size. Rendering both status symbols within the same 18-point canvas keeps the native anchor stable. The editing smoke check compares window position and height across both stop-by-resize and resume-by-resize transitions.

Outside-click regression: native transient dismissal could remain inactive after opening and closing the color menu, including after Line had lost activation. Line now installs an [AppKit global mouse-down monitor](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html) only while its popover is open and removes it on close. This observes clicks in other applications without consuming them. `python3 scripts/smoke-test.py --dismissal` exercises the registered callback path before menu use, after cancellation, and after choosing a color. It checks that dismissing the menu alone keeps the popover open. Physical event delivery remains a manual check.
