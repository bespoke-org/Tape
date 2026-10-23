# 04: Correct entries and maintain reusable tasks

- STATUS: CLOSED
- PRIORITY: 100
- TAGS:
- LEGACY-ID: 04

**Spec:** [Tape v1](../../docs/spec.md)

**What to build:** Edit tasks and timestamps, resize entries, recolor tasks, and confirm deletion; keep running-entry behavior and validation consistent.

**Blocked by:** [03: Draw historical entries or start tracking from the past](../20261020-190554-ticket-03/TASK.md).

## Interface

Clicking an entry opens its settings inline below the timeline, in the same position as the task picker. The 15-point color circle, task search field, and Delete share one row, without a divider. Change start and end times by dragging the entry edges; there are no timestamp fields. Color changes save immediately across the task's entries. Selecting a suggestion or pressing Return reassigns this entry, creating a task for a new name. Typing alone does not save. Omit Save/Cancel buttons and retain native deletion confirmation. Task renaming is not supported. Clicking empty timeline space deselects the entry.

## Acceptance criteria

- [x] Click entries to edit their task and color; change start/end times by resizing completed and running entries with edge drags. Editing a running start/task keeps it running. Dragging its end into the past stops it at that time; leaving the end at or beyond Now keeps tracking. Dragging a completed end to or past Now continues the same entry as running, unless blocked by another entry.
- [x] Recolor tasks across all entries. Reassigning one entry preserves existing task names and other entries.
- [x] Require native deletion confirmation; cancellation preserves records and running state; confirming deletion of a running entry stops tracking. Deleting a task's last entry also removes that task from suggestions.
- [x] Reject invalid or overlapping edits without altering existing data; persist successful corrections and verify storage reopening.
- [x] User accepts the current usability and functionality. Automated editing and accessibility-label checks pass; the remaining physical-input, VoiceOver, and appearance matrix is carried to ticket 07, not claimed as verified.

Native macOS appearance, Liquid Glass use, and accessibility follow the spec and apply to every UI change in this ticket.

Accepted by the user on 2026-10-20 after the final review. The current UI is accepted unchanged, including the subtle search-field border. Immediate color-menu dismissal attempts remain reverted. The unused general-purpose editing method is an optional cleanup, not a blocker.

See [verification notes](../../docs/ticket-04-verification.md) for automated checks, resolved review findings, and remaining manual input/appearance checks.
