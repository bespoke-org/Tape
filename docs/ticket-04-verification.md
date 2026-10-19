# Ticket 04 verification

Implementation: [Correct entries and maintain reusable tasks](../.scratch/line-v1/issues/04-correct-entries-and-maintain-reusable-tasks.md).

Implemented on 2026-10-19; awaiting user acceptance.

## Behavior

Click a timeline entry to open its settings inline below the divider, replacing the task picker. Timestamp controls and Delete appear above a task search field with a swatch picker on its left. Choose a suggestion or press Return to reassign the entry, creating a task for a new name. Typing alone does not change records. Text fields have no opaque fill. The native date control disables its background and bezel so the popover material remains visible, using AppKit’s [drawsBackground](https://developer.apple.com/documentation/appkit/nsdatepicker/drawsbackground) property. Timestamp changes save automatically while the editor stays open. Escape or closing the popover keeps successful changes and discards rejected timestamp drafts. There are no Save or Cancel buttons. Invalid edits stay open with a readable error and preserve saved records.

The swatch-only color picker saves choices immediately across every entry for that task. Task renaming has been removed. Search reassigns only the selected entry, leaving other entries and task names unchanged.

Completed entries support dragging either edge, with minute snapping and exact neighboring boundaries. Command at mouse-down retains overwrite behavior instead. Previews do not write records, Escape cancels, and crossing the opposite edge cancels a resize. Coincident edges prefer the entry containing the pointer. Click targets match the rendered two-point minimum width; later entries win shared boundaries.

Running entries can change task/start without stopping. Stop tracking with the main status row’s stop icon before assigning a fixed end. The editor has no separate stop button. Native deletion confirmation preserves records and tracking on cancellation; confirmation removes the entry and stops it if running. Removing a task's last entry prunes the task atomically.

Timestamp edits use absolute instants. During a repeated local hour, an additional UTC-offset choice distinguishes the two occurrences. This uses Foundation's [repeated-time matching policy](https://developer.apple.com/documentation/foundation/calendar/nextdate(after:matching:matchingpolicy:repeatedtimepolicy:direction:)).

## Automated checks

- `swift test`: 44 tests passed in five suites. Nine editing tests cover reassignment, identity, recoloring with names preserved, deletion/orphan pruning, minute resizing, exact boundaries, invalid/stale edits, running recovery, write failures, reopening, midnight, and repeated-hour absolute timestamps.
- `python3 scripts/smoke-test.py --editing`: passed. Exercises task search, creation on Return and reassignment from suggestions without stopping tracking, native date autosave, full-color swatch-only native menu choices, left-side picker placement, immediate color selection, rejected-edit preservation, Escape, native deletion confirmation and cancellation, running corrections/deletion, short-entry clicks, shared boundaries, adjacent-entry resizing, and stable popover anchoring.
- Existing base, `--timeline`, `--creation`, and `--overwrite` packaged smoke checks all passed.
- Each smoke process uses isolated temporary data and a bounded limit: 40 seconds for the expanded editing sequence, 20 seconds for other modes. Native controls are driven within the app; pointer and Escape inputs exercise the same handler as the local event monitor.

## Standards

No remaining actionable findings. The initial exclusive-end hit-testing finding was resolved and covered in the packaged smoke check.

## Spec

No remaining blockers. Review identified minimum-width click targets and coincident resize edges; both were fixed and covered in the packaged smoke check.

## Still manual

Physical mouse/trackpad and keyboard delivery, VoiceOver navigation, the complete light/dark and accessibility appearance matrix, and the repeated-hour UTC-offset control need hands-on verification. Synthetic event delivery and native control actions do not establish these. The user should try the inline layout before accepting the ticket.

Color-menu regression: the original SF Symbol images arrived in the native menu as monochrome templates. Non-template swatch images preserve the task colors. The packaged editing check inspects every native menu image and its center pixel; it failed on the original blue swatch and passes with full-color images.
