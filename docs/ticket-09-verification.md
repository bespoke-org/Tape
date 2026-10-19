# Ticket 09 verification

Implementation: [Overwrite entries with Command-drag](../.scratch/line-v1/issues/09-overwrite-entries-with-command-drag.md).

## Behavior

Hold Command at mouse-down, then drag across timeline entries. The gesture retains overwrite intent after Command is released and while the task picker is open. Ordinary drawing keeps its existing empty-gap constraints. A gray striped preview, solid outline, and Overwrite indicator identify replacement mode. Task submission uses Overwrite or Overwrite & Start; choosing an existing task commits the same operation.

Committing subtracts the new interval from existing entries. Partial edge overlaps trim entries, middle overlaps split them into two fragments, and full coverage removes them. Touching neighbors and uncovered timestamps remain unchanged. Tasks remain available while referenced by any entry, including the replacement. When a task loses its last entry, the same atomic save removes its task record, so it disappears from suggestions. Loading also removes unused task records left by earlier builds.

A historical overwrite preserves an uncovered running tail. When modifying a running entry, the atomic save also advances its checkpoint so recovery cannot end a surviving tail before it starts. A selection through Now starts the chosen task from the selected time, including picker time. The operation uses current records at commit, so intervening tracking changes cannot produce overlaps.

No records change during preview or task selection. Escape, Cancel, popover dismissal, and zero-duration selections discard the draft. Validation and write failures preserve existing tasks, entries, and running state.

## Automated checks

- `swift test`: 29 tests pass, including overwrite tests through public tracking operations and real temporary storage. Coverage includes trimming, splitting completed and running entries, deletion, reverse snapping, adjacency, exact surviving timestamps, task reuse, removal of unused tasks, cleanup on load, delayed selection and intervening task starts, recovery, invalid drafts, failed writes, and reopening.
- `python3 scripts/smoke-test.py --overwrite`: passes using a separate packaged app, temporary data, and a 20-second process limit. Exercises Command captured at mouse-down and released before dragging, ordinary occupied-origin rejection, preview without writes, Escape/Cancel/dismissal/zero-duration cancellation, native picker submission, splitting, reverse replacement across multiple entries, through-Now tracking, and stable anchoring.
- Existing tracking, timeline, and creation smoke checks pass. The creation check initially failed at its final through-Now assertion. Added selection/error diagnostics and reran it twice successfully; the initial failure was not reproduced or attributed to a specific cause.

Standards review: no findings. Spec review: no findings. Both reviewed the implementation against commit `f964cd0`.

The follow-up change to remove tasks with no entries was reviewed against `fe730d1`, with no findings on either axis. Its overwrite smoke check also verifies that the removed task is absent from native picker suggestions; the normal tracking smoke check passes.

## Manual verification limits

The smoke checks send synthetic events through the production AppKit handler and use the native task picker. They do not prove physical Command-drag delivery through the system event monitor or rendered stripe appearance. Physical gestures, light/dark appearance, increased contrast, Reduce Transparency, and VoiceOver remain part of ticket 07's manual verification.
