# Ticket 04 verification

Implementation: [Correct entries and maintain reusable tasks](../.scratch/line-v1/issues/04-correct-entries-and-maintain-reusable-tasks.md).

Implemented on 2026-10-19; awaiting user acceptance.

## Behavior

Click a timeline entry to open its settings inline below the divider, replacing the task picker. Native task and timestamp controls edit this entry. Task and timestamp changes save automatically while the editor stays open. Escape or closing the popover keeps successful changes and discards rejected timestamp drafts. There are no Save or Cancel buttons. Invalid edits stay open with a readable error and preserve saved records.

The expandable task section places a swatch-only color picker before the name field. It saves color choices immediately and names on Return, focus loss, or editor dismissal. Renaming/recoloring applies to every entry for that task; changing the entry's task does not rename the original task. Closing the editor retains saved global task changes.

Completed entries support dragging either edge, with minute snapping and exact neighboring boundaries. Command at mouse-down retains overwrite behavior instead. Previews do not write records, Escape cancels, and crossing the opposite edge cancels a resize. Coincident edges prefer the entry containing the pointer. Click targets match the rendered two-point minimum width; later entries win shared boundaries.

Running entries can change task/start without stopping. Their editor offers Stop tracking before a fixed end can be assigned. Native deletion confirmation preserves records and tracking on cancellation; confirmation removes the entry and stops it if running. Removing a task's last entry prunes the task atomically.

Timestamp edits use absolute instants. During a repeated local hour, an additional UTC-offset choice distinguishes the two occurrences. This uses Foundation's [repeated-time matching policy](https://developer.apple.com/documentation/foundation/calendar/nextdate(after:matching:matchingpolicy:repeatedtimepolicy:direction:)).

## Automated checks

- `swift test`: 43 tests passed in five suites. Eight editing tests cover reassignment, identity, rename/recolor uniqueness, deletion/orphan pruning, minute resizing, exact boundaries, invalid/stale edits, running recovery, write failures, reopening, midnight, and repeated-hour absolute timestamps.
- `python3 scripts/smoke-test.py --editing`: passed. Exercises native date autosave, rename-on-blur without a Save button, full-color swatch-only native menu choices, left-side picker placement, immediate color selection, rejected-edit preservation, Escape, native deletion confirmation and cancellation, running corrections/deletion, short-entry clicks, shared boundaries, adjacent-entry resizing, and stable popover anchoring.
- Existing base, `--timeline`, `--creation`, and `--overwrite` packaged smoke checks all passed.
- Each smoke process uses isolated temporary data and a 20-second limit. Native controls are driven within the app; pointer and Escape inputs exercise the same handler as the local event monitor.

## Standards

No remaining actionable findings. The initial exclusive-end hit-testing finding was resolved and covered in the packaged smoke check.

## Spec

No remaining blockers. Review identified minimum-width click targets and coincident resize edges; both were fixed and covered in the packaged smoke check.

## Still manual

Physical mouse/trackpad and keyboard delivery, VoiceOver navigation, the complete light/dark and accessibility appearance matrix, and the repeated-hour UTC-offset control need hands-on verification. Synthetic event delivery and native control actions do not establish these. The user should try the inline layout before accepting the ticket.

Color-menu regression: the original SF Symbol images arrived in the native menu as monochrome templates. Non-template swatch images preserve the task colors. The packaged editing check inspects every native menu image and its center pixel; it failed on the original blue swatch and passes with full-color images.
