# Add interactive task and tag statistics

- STATUS: OPEN
- PRIORITY: 100
- TAGS:

Implement the approved standalone mockup as a native Statistics section above General and About. Keep the current window lifecycle and existing initial General selection.

## Acceptance criteria

- [x] Day / Week / Month, previous/next period and return to current period; start on current week.
- [x] Total tracked time with a task-colored day timeline and daily bars for weeks/months. Select a bar to inspect a day or a session to select its task.
- [x] Searchable Tasks / Tags breakdown sorted by duration, including Untagged. Selecting a row highlights matching time and shows a removable filter. Switching grouping explores the selection.
- [x] Count every session once in totals; overlapping tags each receive the full duration. Clip sessions at period boundaries and now; split at local midnights, respecting daylight saving and calendar week boundaries.
- [x] Reflect edits, tag changes and running time without writing statistics into the tracking store.
- [x] Native appearance, keyboard/accessibility labels, small-window layout, menu shortcut, existing back/forward navigation.
- [x] Test aggregation and native UI with isolated data; build and relaunch for review.

Custom date ranges, comparisons, exports, editing from statistics and saved filters are outside this version.

## Verification

- `swift test`: 106 tests in 12 suites passed. Statistics coverage includes overlapping tags, cross-group filtering, current task metadata, Unicode search, period clipping, running time, empty data, year/leap-month boundaries, 23/25-hour days, and tag color inheritance across periods, filters and metadata changes.
- `LINE_SMOKE_CAPTURE=1 python3 scripts/smoke-test.py --statistics`: passed. Opened the page through its status-menu action, selected tags and sessions, drilled into a day, searched tasks, moved between periods and pages, and confirmed tracking records were unchanged.
- `LINE_SMOKE_CAPTURE=1 python3 scripts/smoke-test.py --main-window`: passed across two processes. Existing settings controls, back/forward, direct page menu actions, window restoration, Dock policy, and tracking continuity remain intact.
- Inspected week, filtered week, month, day, minimum-width and light-appearance screenshots from the isolated test app.
- Removed instructional captions and the “Daily totals” / “Your day at a glance” subtitles at the user's request. Kept the active filter and total context.

- Release build and ad-hoc signing passed. Gracefully replaced the production bundle and relaunched DayTape for review.

Implementation is ready for user review; keep this task open until accepted.

Review refinement: tag dots, duration bars and filtered chart highlights inherit the current task color of the earliest recorded entry with that tag, across all history. Period changes and filtering do not change that choice. Untagged uses neutral gray.

Color refinement verification: 105 tests passed; the native Statistics smoke check passed and its colored chart/rows screenshot was inspected. Release build and signing passed.

Visual refinement: removed the visible “Tracked time” heading and switched the large total from rounded, monospaced digits to the standard system font. Retained its descriptive accessibility label.

Visual refinement: aligned the tracked-time total with the period picker on the first row and changed its font weight to regular.

Chart refinement: stack weekly/monthly bars by the selected Tasks / Tags grouping. Divide multi-tag sessions equally between their tags for visualization only; keep total bar height equal to tracked time and keep full overlapping tag durations in the breakdown. A selected tag shows its full matching time, with unrelated time gray. Hover describes the shares.

Stack verification: 106 tests passed, including conservation of tracked time with overlapping tags and filtered stacks. Native Statistics checks passed; inspected task/tag stack screenshots. Release build and signing passed, and DayTape was relaunched.

Layout refinement: align the grouping picker with content using its natural width. Replace custom rows with a native SwiftUI Table and alternating row backgrounds. Keep the chart and table controls fixed; only table rows scroll. Use a compact chart in short windows so the table remains accessible.

Native-table verification: Statistics smoke checks passed with 28 isolated entries, including native selection, alternating-row configuration, search preserving active filters, independent scrolling, and full viewport containment at 640 × 420 for both day and week. Inspected normal, scrolled, and compact screenshots. Release build/signing passed and the app was relaunched. The smoke run emitted one AppKit reentrant-table delegate warning; all interaction and layout checks completed successfully.

Visual refinement: removed only the native table’s enclosing scroll-view border, preserving full-width alternating rows and existing content alignment.

Visual refinement: the Time column displays durations only, with the proportional colored lines removed.

Visual refinement: left-align Time values. Share the same appearance-aware surface between cards and base table rows, retaining native alternating stripes and selection in both dark and light appearance. Refresh recycled rows after scrolling.

Native table correction: removed custom row colors, background overrides, scroll observation, and hidden scroll content background. The table container now uses the system control background, matching the native base rows; AppKit owns alternating stripes and scrolling. The earlier background-property test did not exercise the reported bounce and was removed. Native Statistics smoke checks passed and dark/light screenshots were inspected. Physical trackpad bounce remains unverified by automation.

Row height refinement: removed vertical cell padding so populated rows match the native empty stripes. The native smoke check compares every populated row rectangle with the standard row height plus intercell spacing; it passed with the existing Statistics checks. Release build passed.

Chart styling: match the menu bar timeline with 23% color fills and full-color outlines in stacked bars and day entries. Honor increased contrast and reduced transparency, and use a thicker outline on the selected task. Statistics smoke checks passed; day and week screenshots inspected; release build passed.

Stack outline refinement: draw rounded top corners only on the highest segment and rounded bottom corners only on the lowest segment, including the gray remainder. Single-segment bars round all four corners. Removed whole-stack clipping so the outline follows the corners. Statistics smoke checks and release build passed.

Search refinement: use NSSearchField for the native magnifying-glass icon, clear button, and focus appearance. Keep live filtering and the accessible search label. Native smoke checks passed, including typing through the field editor and checking the resulting filter; release build passed.

Native chart card: replace the custom NSColor blend with SwiftUI background.secondary. Compared native grouped Form, GroupBox, and semantic backgrounds in real dark/light windows; the secondary background closely matches native cards without fixed RGB values. Keep the table on its native control background. Statistics smoke checks and release build passed.

Period control: replace the segmented Day / Week / Month picker with a compact native menu picker. Native Statistics smoke checks and the release build passed.

Header refinement: place the period menu and previous/current/next navigation together beside the total. Use regular native control sizing and text-backed symbols so arrow buttons match the other controls in height. Statistics smoke checks passed; inspected normal and compact layouts; release build passed.

Tag labels: omit the input colon and uppercase the first character for Statistics rows, filter labels, and bar tooltips. Keep task names, stored tags, and tag matching unchanged. Statistics smoke checks and release build passed.

Selection refinement: remove the filter pill and secondary total above the chart. Clicking the selected native table row again clears the filter from either column; clicking another row switches the filter. Keep compact chart height stable during selection. Native click smoke checks passed for tags, tasks selected from the chart, switching rows, and search preserving filters.

Total heading: add a small regular-weight “Time tracked” label above the total, with one combined accessible description. Normal and compact screenshots inspected; release build passed. The first smoke run failed at the first row click; an instrumented repeat passed all native interactions with no behavior changes. Temporary logging removed; the intermittent click failure remains unexplained.

Header spacing: top-align the period controls beside the Time tracked block, with the date directly beneath the controls. This removes the separate date row and frees chart/table space. Native Statistics checks passed, including normal and minimum layouts; screenshots inspected and release build passed.

Period navigation: group previous/current/next actions in a native momentary segmented control with internal dividers. Keep regular sizing beside the period menu and disable forward navigation in the current period. Native mouse-click navigation and small-window smoke checks passed; normal and compact screenshots inspected; release build passed.

Period controls: place navigation before the Day / Week / Month menu. Disable the center button while viewing the current period, and re-enable it after navigating away. Native navigation and minimum-window smoke checks passed; release build passed.

Day chart height: reduce the normal timeline from 165 to 116 points, matching the menu bar timeline with a 64-point strip and 46-point entries. Preserve the shorter compact layout. Native Statistics smoke checks and release build passed; day screenshot inspected.

Day markers: show every three hours from 03:00 through 21:00, omitting midnight endpoints. Keep configured time formatting and centered labels. Native Statistics checks and release build passed; compact screenshot inspected.

Day timeline corners: match the menu bar timeline with an 8-point track radius and 4-point entry radius. Release build passed.

Stack selection refinement: keep every segment in the same order and at the same height when selecting a task or tag in week/month views. Gray out nonmatching shares in place, retaining separate segment outlines and outer corner rounding. Across groupings, highlight only the matching share within a segment. Keep full matching durations in the total and table. All 116 core tests passed, including stable geometry for both periods and overlapping tags; native Statistics checks and release build passed. Inspected filtered week/month screenshots and relaunched DayTape.

Excluded segment styling: use the native tertiary label color for a darker, quieter gray in dark appearance, retaining stronger gray when Increase Contrast is enabled. Release build passed.
