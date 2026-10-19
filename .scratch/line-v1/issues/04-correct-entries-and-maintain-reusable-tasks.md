# 04: Correct entries and maintain reusable tasks

**Spec:** [Line v1](../spec.md)

**What to build:** Edit tasks and timestamps, resize entries, recolor tasks, and confirm deletion; keep running-entry behavior and validation consistent.

**Blocked by:** [03: Draw historical entries or start tracking from the past](03-draw-historical-entries-or-start-tracking-from-the-past.md).

**Status:** ready-for-human

**Execution:** implemented; awaiting user acceptance

## Interface

Clicking an entry opens its settings inline below the timeline divider, in the same position as the task picker. Use native task and timestamp controls that save valid changes automatically, keeping the editor open. Omit Save/Cancel buttons and retain confirmed Delete. Color changes save immediately. Place timestamps and Delete above a task search field, with a swatch-only color picker on its left. Selecting a suggestion or pressing Return reassigns this entry, creating a task for a new name. Color changes apply globally. Task renaming is not supported.

## Acceptance criteria

- [x] Click entries to edit task/start/end, and resize completed entries by dragging edges. Editing a running start/task keeps it running; setting a fixed end requires stopping.
- [x] Recolor tasks across all entries. Reassigning one entry preserves existing task names and other entries.
- [x] Require native deletion confirmation; cancellation preserves records and running state; confirming deletion of a running entry stops tracking. Deleting a task's last entry also removes that task from suggestions.
- [x] Reject invalid or overlapping edits without altering existing data; persist successful corrections and verify storage reopening.
- [ ] Verify keyboard editing, accessible labels, contrast, and editor behavior with real timeline interactions.

Native macOS appearance, Liquid Glass use, and accessibility follow the spec and apply to every UI change in this ticket.

See [verification notes](../../../docs/ticket-04-verification.md) for automated checks, resolved review findings, and remaining manual input/appearance checks.
