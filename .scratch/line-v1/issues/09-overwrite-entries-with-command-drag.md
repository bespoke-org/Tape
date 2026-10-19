# 09: Overwrite entries with Command-drag

**Spec:** [Line v1 — Command-drag overwrite](../spec.md#command-drag-overwrite)

**What to build:** Hold ⌘ while drawing a new interval to replace time already assigned to other entries. Trim partially covered entries, split entries when the selection covers their middle, and delete entries covered entirely.

**Blocked by:** [03: Draw historical entries or start tracking from the past](03-draw-historical-entries-or-start-tracking-from-the-past.md).

**Status:** ready-for-agent

**Execution:** done

**Scheduling:** follow-up; does not block tickets 04–08.

## Acceptance criteria

- [x] Holding Command when a drag begins enables overwrite for that gesture, including when the origin is inside an existing entry. Capture that intent for the draft through task selection; releasing Command afterward does not silently change the pending operation. Ordinary drawing retains its existing gap constraints.
- [x] Allow the selection to cross multiple entries without stopping at their boundaries. Support either drag direction, existing zoom-dependent snapping, and the existing rules for Now, future selections, and zero-duration cancellation.
- [x] Clearly distinguish the overwrite preview and show which time will be replaced before committing. Previewing and opening the task picker do not change stored records. Escape, Cancel, or closing the popover preserves all entries.
- [x] On task submission, create the new entry and subtract its interval from every overlapping entry. An overlap at one edge trims that edge. Coverage of an entire entry deletes it. Coverage strictly inside an entry leaves two entries for its original task, preserving both uncovered portions. Entries merely touching the selection remain unchanged, and no zero-duration fragments survive.
- [x] Preserve exact timestamps outside the overwritten interval and retain each surviving fragment's task. Do not delete reusable tasks when their entries disappear.
- [x] Handle running entries consistently: a historical overwrite preserves the uncovered running tail; a selection reaching Now starts the selected task and replaces the covered running time, including task-picker time. Keep at most one running entry and preserve appropriate checkpoint/recovery state.
- [x] Revalidate the draft against current records at commit. Save trimming, splitting, deletion, and the new entry as one atomic operation. A validation or storage failure leaves all existing entries and running state intact. If continuation countdowns exist by then, beginning overwrite cancels them like other entry creation.
- [x] Test edge trimming, middle splits, full coverage, multiple entries, adjacency, reverse drags, cancellation, running entries, delayed task selection, failed writes, and reopening storage. Verify Command-drag and the preview in the packaged app.

Example: overwriting 10:20–10:40 inside an existing 10:00–11:00 entry leaves the original task at 10:00–10:20 and 10:40–11:00, with the selected task at 10:20–10:40.

This ticket adds overwrite to interval drawing. It does not change ordinary entry resizing or timestamp editing into overwrite operations.

Implemented on 2026-10-19. See [verification notes](../../../docs/ticket-09-verification.md) for automated checks, review results, and the physical gesture/appearance checks carried to ticket 07.
