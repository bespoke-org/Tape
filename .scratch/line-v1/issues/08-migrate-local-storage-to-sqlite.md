# 08: Migrate local storage to SQLite

**Spec:** [Line v1 — local durability and lifecycle](../spec.md#local-durability-and-lifecycle)

**What to build:** Replace the JSON store with SQLite so checkpoints update only the running entry and timeline browsing queries the visible time range instead of loading all history.

**Blocked by:** [02: Browse and zoom the timeline](02-browse-and-zoom-the-timeline.md).

**Status:** ready-for-agent

**Execution:** not started

**Scheduling:** deferred; revisit after history browsing. This ticket does not block the existing v1 tickets.

## Acceptance criteria

- [ ] Use a versioned SQLite database in Line's application-data directory, keeping persistence behind the existing tracking operations. Choose the Swift SQLite integration at implementation time.
- [ ] Migrate existing JSON data without changing task/entry IDs, names, colors, timestamps, links, or any preferences and recovery state present at migration time. Retain the original JSON as a backup.
- [ ] Make migration safe to retry after interruption or failure: avoid duplicate imports, preserve the original data, and activate the database only after a successful migration. Report failures clearly.
- [ ] Preserve atomic start/stop/switch operations, overlap rules, five-second checkpoints, clean-quit behavior, and recovery through the last saved point. Preserve any lifecycle behavior implemented by then.
- [ ] Update checkpoints without rewriting completed history. Query entries intersecting the visible time range using appropriate indexes, including running entries and entries spanning the range boundaries.
- [ ] Verify migration, retry behavior, failed writes, reopening, checkpoint recovery, and range queries against real temporary databases. Re-run the existing tracking and packaged-app checks.

Keep this focused on local persistence. Sync, accounts, reports, and speculative storage abstractions are outside this ticket.
