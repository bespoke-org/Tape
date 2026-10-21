# Add task tags through inline colon syntax

- STATUS: CLOSED
- PRIORITY: 100
- TAGS:

Add tags to reusable tasks through the existing task input, before implementing statistics. The user agreed to this scope through a design interview. Implementation is complete and accepted, including the compact editor and dimmed inline tags.

Example input:

```text
Building DayLine :dayline :coding :deepwork
```

Saves task name `Building DayLine` with tags `dayline`, `coding`, and `deepwork`.

## Agreed behavior

### Ownership and identity

- Tags belong to tasks. Every past and future entry for a task uses that task's current tags. There are no per-entry overrides.
- A task can have multiple tags. Tags do not become part of its name or create a separate task identity.
- Match tags case-insensitively across languages using Unicode-aware comparison, not ASCII-only conversion. Display tags in lowercase and remove duplicates. For example, `:Coding` and `:coding` are one tag; `:универ` and `:Универ` are one tag.
- Tags can contain non-English letters, numbers, hyphens, and underscores. Do not introduce an ASCII-only restriction. The token rule below determines what counts as a tag.
- Delete a tag when no tasks use it. It then disappears from autocomplete; typing it again can recreate it.

### Parsing and text input

- A whitespace-separated word anywhere in the input is a tag if it begins with `:` and does not end with `:`. Remove the leading colon to obtain its tag name.
- Keep colon-delimited emoji-like words such as `:peka:` in the task name. Ordinary embedded or trailing colons, such as `https://example.com` and `Planning:`, are not tags. A bare `:` is not a completed tag.
- Remove recognized tag words from the name and clean up surrounding whitespace. `:coding DayTape` becomes `DayTape`, not ` DayTape`. Handle tags at the beginning, middle, and end, including pasted input and multiple whitespace characters.
- Keep the input as editable plain text. Do not turn tags into chips while typing.
- Render `:tag` words in the name field with the native secondary text color, keeping task names and literal emoji-style words at normal brightness.
- Tag-only input such as `:coding :deepwork` is valid for searching. Creating an entry still requires a nonempty task name or choosing an existing task.
- Support the syntax when starting or switching tracking, saving drawn entries, and editing existing entries.
- The user confirmed existing task names do not contain tag-like words. No automatic conversion of existing saved names is needed. Load existing data without tags as untagged tasks.

### Creating and selecting tasks

- Starting or creating an entry for an existing task adds any explicitly typed tags to its existing tags. Omitting tags preserves them.
- Clicking a task suggestion during creation uses that task and adds the tags currently typed in the input, while preserving its existing tags.
- Reusing the currently running task with additional tags must update its tags without restarting or splitting its running entry.

### Editing and removing tags

- The entry editor shows the task name followed by all of its tags as plain text.
- Return saves the edited tag list for the task. Removing every tag clears the task's tags. Keep the editor compact without a visible explanatory label, as requested during review.
- When choosing a different task suggestion in the editor, load the destination task's name and tags for review. Return commits the reassignment and any subsequent edits. Do not carry the previous task's tags onto the destination task merely because they were prefilled in the editor.
- Preserve the existing task-reassignment behavior of name editing; this feature does not add global task renaming.
- Merely typing does not change saved tags. Canceling or dismissing the draft preserves saved data. Failed saves preserve the previous task tags and tracking records and show an error.

### Autocomplete and task search

- Typing `:` offers existing tags; typing a prefix such as `:de` narrows suggestions, case-insensitively. New tags can be entered without a matching suggestion.
- No autocomplete suggestion is selected initially. Arrow keys select a suggestion; Tab or Return accepts the selected tag as plain text followed by a space, without submitting the entry.
- Return with no selected tag suggestion submits the input, including any newly typed tag, subject to task-name validation.
- Escape first dismisses tag autocomplete without discarding the entry draft. Existing draft-dismissal behavior applies after suggestions are dismissed.
- Ordinary text filters task names. Completed tag tokens filter tasks that have all specified tags. Preserve the user's configured Task order within matching results.
- Keep an unfinished `:prefix` available for tag completion; treat it as a completed tag when explicitly completed or submitted. Completing autocomplete never submits the entry itself.
- An empty result list does not prevent submitting a valid new task or adding tags to an existing task by its full name.

### Display and scope

- Show saved tags as subtle `:tag` text beside task names in task suggestions and include them in timeline tooltips.
- Keep timeline labels and the running-task header focused on the task name.
- Keep the existing native appearance and keyboard/accessibility behavior. Long tag lists should not make the popover unbounded or obscure the task name.
- Projects, statistics, a dedicated tag-management page, global tag renaming, and per-entry overrides are outside this ticket.

## Acceptance criteria

- [x] Parse the example and tags in any position while preserving emoji-like words and ordinary colons, with clean task-name spacing.
- [x] Keep input as plain text; support keyboard-operated tag autocomplete without accidental entry submission.
- [x] Persist task-level tags, deduplicate them across case variants including Cyrillic, and load older stores without losing data.
- [x] Add tags when starting/creating for an existing task, preserve tags when omitted, and avoid splitting a running entry for tag-only changes.
- [x] Show and edit the complete tag list in the entry editor; support removal, cancellation, and reassignment without leaking source tags.
- [x] Search tasks by name and all completed tags while respecting configured ordering; support tag-only searches and require a task for submission.
- [x] Remove unused tags from storage and autocomplete after their last task association disappears.
- [x] Show tags in suggestions and tooltips, with readable layout and accessible keyboard interaction.
- [x] Verify parsing, Unicode matching, persistence, failed-save rollback, creation/editing flows, autocomplete Return/Tab/Escape behavior, and unused-tag cleanup with focused tests and native UI checks.
- [x] Update the application documentation, build, and relaunch for user review when implementation is authorized.

## Implementation context

Current entry points are `TrackingPopover`, `EntryEditor`, and the tracking operations in `TrackingStore`. Both task pickers already share `taskSuggestions(matching:)` and the configurable `TaskOrder`. Preserve atomic save behavior and task identity when adding tag metadata. Review task reconstruction paths, including color changes, so they retain tags.

Related: [task ordering](../20261021-103152/TASK.md), [application spec](../../docs/spec.md), and [task tracking workflow](../../docs/issue-tracker.md).

## Verification

- `swift test`: 99 tests in 11 suites passed, including parsing, Unicode normalization and case matching, completion token ranges, persistence, legacy decoding, shared tags, cleanup, and failed-save rollback.
- `LINE_SMOKE_CAPTURE=1 python3 scripts/smoke-test.py --tags`: passed. Exercises real native input, completion at the caret and by click, Tab/Return behavior, Cyrillic prefixes, tag-only filtering, cancellation, selection before confirmation, cleanup, and preservation of running entry identity.
- `python3 scripts/smoke-test.py --creation`: passed for historical and running creation, selection, cancellation, and popover anchoring.
- `python3 scripts/smoke-test.py --editing`: passed for reassignment, color changes, deletion, resizing, and anchoring. Updated preexisting resize test gestures to exceed the three-pixel drag threshold at default zoom and avoid floating-point ambiguity at a shared boundary.
- Inspected the native editor screenshot. The input stays plain text. Removed the explanatory tag label after user review.
- Release build and signing passed; gracefully relaunched `build/DayTape.app` for user review.
- Review refinement: dimmed inline tags with native secondary text color. Native tag smoke checks passed again, the updated editor screenshot was inspected, and the release app was rebuilt and relaunched.

Tags are stored on tasks; the autocomplete vocabulary is derived from current task tags, so unused tags require no separate registry cleanup. No projects, statistics, or tag-management page were added.
