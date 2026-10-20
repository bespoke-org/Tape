# Ticket 03 verification

Implementation: [Draw historical entries or start tracking from the past](../tasks/20261020-190554-ticket-03/TASK.md).

Accepted as done by the user on 2026-10-19 after exercising the app and refining drawing behavior. Remaining systematic hardware and appearance/accessibility checks are deferred to ticket 07.

## Behavior

Drag horizontally from empty strip space to select time. The viewport pauses following during drawing so the selection keeps its time coordinates. A gray striped preview with a solid border identifies the unsaved interval. On release, the existing task picker opens and focuses its field, without a timestamp caption or Cancel button. Save records historical time; Start begins tracking from the drawn start. Selecting an existing task uses the same operation as submitting a new name.

Reverse drags normalize before snapping. Views up to two hours snap by one minute, up to eight hours by five minutes, and wider views by fifteen minutes; preview and release use the same grid. The thin Now marker has a three-point hit tolerance; reaching or crossing it preserves running intent while the picker is open. Completed entries retain snapped endpoints; live tracking retains actual timestamps. Escape during dragging or task selection and popover dismissal discard the draft without saving a task or entry. Returning the dragged edge to its origin or releasing a selection that snaps to zero also cancels silently.

The preview and released selection stay within the empty gap containing the drag origin. Both directions stop at the nearest entry, including a running entry. Neighboring timestamps take precedence over minute snapping to preserve exact adjacency. Commit still revalidates overlap, duration, and future timestamps. Running selections cannot replace a running task. Historical insertion keeps entries ordered and leaves the running checkpoint unchanged. A failed save preserves existing tasks and entries.

## Automated checks

- `swift test`: 22 tests pass. New tests cover reverse selections, adaptive snapping and zoom thresholds, task reuse, sorted historical insertion, reopen persistence, through-Now intent and picker delay, recovery timestamps, neighbor boundaries in both directions, overlap revalidation, adjacency, invalid drafts, and failed writes.
- `python3 scripts/smoke-test.py --creation`: packaged native picker and synthetic input checks pass. Covers new/existing tasks, reverse drags, cancellation while drawing/typing and after collapsing to zero, closing and reopening with a draft, invalid intervals, starting on an existing entry, through-Now tracking, and stable popover anchoring. The process has isolated data and a 20-second timeout.
- `python3 scripts/smoke-test.py`: existing tracking, picker, focus, anchoring, and jitter checks pass.
- `python3 scripts/smoke-test.py --timeline`: scrolling, pinch, smart zoom, Now, reopening, saved zoom across fresh launches, and stable anchoring pass.

The final standards review found no issues or unnecessary complexity. The spec review found that collapsed future selections still showed an error. That case now cancels silently, with regression coverage for both collapsed and positive-duration future selections. Follow-up review confirmed no remaining actionable findings.

## Manual checks

The user accepted the app after exercising drawing and requesting refinements. The complete hardware gesture matrix, light/dark appearance, Reduce Transparency, Reduce Motion, increased contrast, and VoiceOver remain for ticket 07. Synthetic input reaches the production handler but does not establish hardware event delivery or rendered appearance.
