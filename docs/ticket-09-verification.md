# Ticket 09 verification

Implementation: [Overwrite entries with Command-drag](../.scratch/line-v1/issues/09-overwrite-entries-with-command-drag.md).

Accepted as done by the user on 2026-10-19, including cleanup of task names after their last entry is removed.

## Behavior

Hold Command at mouse-down, then drag across timeline entries. The gesture retains overwrite intent after Command is released and while the task picker is open. Ordinary drawing keeps its existing empty-gap constraints. A gray striped preview and solid outline identify replacement mode. The picker omits the extra overwrite label, selected-time caption, and Cancel button. Task submission uses Overwrite or Overwrite & Start; choosing an existing task commits the same operation.

Committing subtracts the new interval from existing entries. Partial edge overlaps trim entries, middle overlaps split them into two fragments, and full coverage removes them. Uncovered timestamps remain unchanged. When the selected task matches adjoining entries, the overwrite and its connected same-task neighbors merge into one interval. This includes inside selections, extensions, bridges, and running entries. Real gaps, different tasks, and unrelated history remain separate. Ordinary drawing does not merge entries. Tasks remain available while referenced by any entry, including the replacement. When a task loses its last entry, the same atomic save removes its task record, so it disappears from suggestions. Loading also removes unused task records left by earlier builds.

A historical overwrite preserves an uncovered running tail. When modifying a running entry, the atomic save also advances its checkpoint so recovery cannot end a surviving tail before it starts. A selection through Now starts the chosen task from the selected time, including picker time. The operation uses current records at commit, so intervening tracking changes cannot produce overlaps.

No records change during preview or task selection. Escape, popover dismissal, and zero-duration selections discard the draft. Validation and write failures preserve existing tasks, entries, and running state.

## Automated checks

- `swift test`: 33 tests pass, including overwrite tests through public tracking operations and real temporary storage. Coverage includes same-task merging, connected chains, preserved gaps and other tasks, running merges and recovery, trimming, splitting completed and running entries, deletion, reverse snapping, adjacency, exact surviving timestamps, task reuse, removal of unused tasks, cleanup on load, delayed selection and intervening task starts, recovery, invalid drafts, failed writes, and reopening.
- `python3 scripts/smoke-test.py --overwrite`: passes using a separate packaged app, temporary data, and a 20-second process limit. Exercises Command captured at mouse-down and released before dragging, ordinary occupied-origin rejection, preview without writes, Escape during drawing and task selection, dismissal, zero-duration cancellation, native picker submission, same-task merging, splitting, reverse replacement across multiple entries, through-Now tracking, and stable anchoring.
- Existing tracking, timeline, and creation smoke checks pass. The creation check initially failed at its final through-Now assertion. Added selection/error diagnostics and reran it twice successfully; the initial failure was not reproduced or attributed to a specific cause.

Standards review: no findings. Spec review: no findings. Both reviewed the implementation against commit `f964cd0`.

The follow-up change to remove tasks with no entries was reviewed against `fe730d1`, with no findings on either axis. Its overwrite smoke check also verifies that the removed task is absent from native picker suggestions; the normal tracking smoke check passes.

Same-task overwrite merging was reviewed against `96c7395`, with no findings on either axis. All 33 core tests and the packaged overwrite check pass, including selecting the original task inside its existing entry and retaining one continuous block.

## Manual verification limits

The smoke checks send synthetic events through the production AppKit handler and use the native task picker. They do not prove physical Command-drag delivery through the system event monitor or rendered stripe appearance. Physical gestures, light/dark appearance, increased contrast, Reduce Transparency, and VoiceOver remain part of ticket 07's manual verification.
