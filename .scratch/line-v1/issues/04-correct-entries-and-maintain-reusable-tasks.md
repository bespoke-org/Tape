# 04: Correct entries and maintain reusable tasks

**Spec:** [Line v1](../spec.md)

**What to build:** Edit tasks and timestamps, resize entries, rename/recolor tasks, and confirm deletion; keep running-entry behavior and validation consistent.

**Blocked by:** [03: Draw historical entries or start tracking from the past](03-draw-historical-entries-or-start-tracking-from-the-past.md).

**Status:** ready-for-agent

**Execution:** not started

## Acceptance criteria

- [ ] Click entries to edit task/start/end, and resize completed entries by dragging edges. Editing a running start/task keeps it running; setting a fixed end requires stopping.
- [ ] Rename/recolor tasks across all entries, enforcing name uniqueness. Reassigning one entry does not rename its task globally.
- [ ] Require native deletion confirmation; cancellation preserves records and running state; confirming deletion of a running entry stops tracking.
- [ ] Reject invalid or overlapping edits without altering existing data; persist successful corrections and verify storage reopening.
- [ ] Verify keyboard editing, accessible labels, contrast, and editor behavior with real timeline interactions.

Native macOS appearance, Liquid Glass use, and accessibility follow the spec and apply to every UI change in this ticket.
