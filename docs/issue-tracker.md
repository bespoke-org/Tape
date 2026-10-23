# Task tracking

Tape uses [tatr](https://github.com/tsoding/tatr) to manage Markdown tasks in Git. The authoritative tasks live in [`tasks/`](../tasks/README.md), one `TASK.md` per generated task directory.

## Workflow

1. Agree on the work and its acceptance criteria. Feature specs and proposed breakdowns live in `docs/`; a proposal is not a task.
2. Create an agreed task with `tatr new "Task title"`. Edit the resulting `TASK.md` to describe the work, link its spec and any blockers, and add acceptance checkboxes.
3. Choose the next task together. Check that its blockers are closed, then implement it and keep its notes and acceptance criteria current.
4. Close the task when its work is complete and accepted. Record verification results and move any agreed remaining work into another task before closing.
5. Commit task updates with the corresponding code or documentation changes.

Use only `OPEN` and `CLOSED`. An open task may be waiting or being worked on; it does not need another status, execution field, or workflow tag. Leave `TAGS` empty and keep the default priority of `100`. Dependencies remain links in the description; tatr does not enforce them.

Edit task descriptions directly as Markdown. Use tatr to find tasks and change their open/closed status. Closing a task does not change the parent spec.

## Commands

Run these from the repository root or one of its subdirectories:

```sh
tatr ls                       # Open tasks
tatr ls -c                    # Closed tasks
tatr summary                  # Open-task counts
tatr new "Task title"          # Create an open task
tatr find TASK_ID              # Find an open or closed task
tatr find -path-only TASK_ID   # Print its TASK.md path
tatr ls -update close TASK_ID  # Close one task
tatr ls -c -update open TASK_ID # Reopen one closed task
tatr help
tatr ls -help
```

Replace `TASK_ID` with the generated directory name. Always include the intended ID when updating a single task: omitting the query applies the update to every task in the selected list.

## Existing plans and records

- The [Tape v1 spec](spec.md) remains the implementation reference.
- The [approved breakdown](ticket-plan.md) records the original scope and dependency plan. Current task status lives only in `TASK.md`.
- Tickets 01–09 were migrated into tatr. Their titles and `LEGACY-ID` properties preserve the old ticket numbers used in conversations and verification documents. New tasks use generated IDs without needing another sequential number.
- Acceptance checkboxes, completion notes, and links to verification records were preserved. Previously accepted tasks remain closed, including those whose remaining manual checks were explicitly carried to ticket 07.
- Keep `tasks/` and the planning documents in `docs/` in Git. Maintain task status only in `tasks/`.
