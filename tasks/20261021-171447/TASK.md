# Configure the statistics day boundary

- STATUS: CLOSED
- PRIORITY: 100
- TAGS:

Add General → Statistics → Day starts at, an hourly time menu defaulting to midnight. A day ends at the same local time on the following date. Apply the boundary to all statistics, including existing records, without editing time entries.

## Acceptance criteria

- [x] Persist the setting, retain midnight for older stores, and preserve tracking/recovery data on success or failure.
- [x] Day, week, and month totals use the configured boundary, with dates named for when the day starts.
- [x] Navigation, current-period state, day drilldown, and three-hour timeline marks use the same boundary.
- [x] Correctly split boundary-crossing entries and handle daylight saving, week/month/year edges, and live entries.
- [x] Verify core behavior and native settings/statistics UI; build and relaunch for review.

## Verification

- Full core suite: 115 tests passed. Follow-up statistics suite: 13 tests passed after clarifying DST fixture dates.
- Coverage includes the 04:00 cutoff, entries crossing midnight and the cutoff, ongoing entries, weekly totals, month/year edges, 23/25-hour days, missing/repeated cutoff hours, timeline marks, preference persistence, older stores, and failed saves preserving recorded work.
- Native Statistics checks passed, including changing the boundary while the chart is visible, next-morning marks, navigation before the cutoff, and unchanged tracking data. Inspected the shifted timeline screenshot.
- Release build passed.
- Native General settings checks passed across two fresh processes, including all 24 hourly choices, immediate saves, persisted 04:00 choice, and unchanged tracking records. Inspected the settings screenshot.
- The first full settings run reached the second launch but failed in the existing short-break menu check. A repeat with a more descriptive assertion passed both launches without changing picker behavior; the intermittent interaction failure remains unexplained.
- Static-text accessibility lookup now checks accessibilityValue as well as label/title. Native menus are checked after opening because their items are populated lazily.
- Built, relaunched, and accepted by the user.
