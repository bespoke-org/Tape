# Ticket 03 verification

Implementation: [Draw historical entries or start tracking from the past](../.scratch/line-v1/issues/03-draw-historical-entries-or-start-tracking-from-the-past.md).

## Behavior

Drag horizontally from empty strip space to select time. The viewport pauses following during drawing so the selection keeps its time coordinates. A dashed preview identifies the unsaved interval. On release, the existing task picker opens and focuses its field, with the selected timestamps and a Cancel action. Save records historical time; Start begins tracking from the drawn start. Selecting an existing task uses the same operation as submitting a new name.

Reverse drags normalize before minute snapping. The thin Now marker has a three-point hit tolerance; reaching or crossing it preserves running intent while the picker is open. Completed entries retain minute endpoints; live tracking retains actual timestamps. Escape during dragging or task selection, Cancel, and popover dismissal discard the draft without saving a task or entry.

Selection and commit both validate overlap, duration, and future timestamps. Running selections cannot replace a running task. Historical insertion keeps entries ordered and leaves the running checkpoint unchanged. A failed save preserves existing tasks and entries.

## Automated checks

- `swift test`: 19 tests pass. New tests cover reverse selections, minute snapping, task reuse, sorted historical insertion, reopen persistence, through-Now intent and picker delay, recovery timestamps, overlap revalidation, adjacency, invalid drafts, and failed writes.
- `python3 scripts/smoke-test.py --creation`: packaged native picker and synthetic input checks pass. Covers new/existing tasks, reverse drags, cancellation while drawing/typing, closing and reopening with a draft, invalid intervals, starting on an existing entry, through-Now tracking, and stable popover anchoring. The process has isolated data and a 20-second timeout.
- `python3 scripts/smoke-test.py`: existing tracking, picker, focus, anchoring, and jitter checks pass.
- `python3 scripts/smoke-test.py --timeline`: scrolling, pinch, smart zoom, Now, reopening, saved zoom across fresh launches, and stable anchoring pass.

Standards and spec reviews found no actionable findings or unnecessary complexity.

## Manual checks

Physical mouse/trackpad delivery, drag feel, and light/dark appearance, Reduce Transparency, Reduce Motion, increased contrast, and VoiceOver remain unverified. Synthetic input reaches the production handler but does not establish hardware event delivery or rendered appearance.
