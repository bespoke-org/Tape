# Configure task picker ordering

- STATUS: CLOSED
- PRIORITY: 100
- TAGS:

Add Task order in General’s Tracking section with Recently used as the default, Alphabetical, and Most used. Use the same ordering for creation and editing suggestions, including search results.

## Acceptance criteria

- [x] Sort by latest entry start, natural alphabetical name, or entry count, with alphabetical ties and unused tasks last for recency and usage.
- [x] Save the choice automatically, default older/unknown preferences to Recently used, and preserve tracking and the previous choice on save failure.
- [x] Apply ordering to both pickers and recompute after changes to recorded entries.
- [x] Verify core behavior and native settings interaction; build and relaunch for review.

## Verification

- `swift test`: 93 tests in 10 suites passed. Covers sorting, ties, search, historical insertion, reassignment, deletion, running tasks, persisted choices, old/unknown preferences, and failed saves.
- `LINE_SMOKE_CAPTURE=1 python3 scripts/smoke-test.py --main-window`: passed across two fresh launches. Exercises every Task order option through the native menu, verifies saved preferences and unchanged tracking records, and retains existing settings/window checks.
- Release build and signing passed. Inspected the settings screenshot and relaunched `build/Tape.app` for review. The first graceful quit was canceled; a retry exited normally before replacing the bundle.

- Added the explanatory subtitle, rebuilt, and relaunched successfully.

Accepted by the user; implementation complete.
