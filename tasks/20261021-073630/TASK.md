# Add an About page to the settings window

- STATUS: CLOSED
- PRIORITY: 100
- TAGS:

Add About below General in the settings sidebar, using the native grouped style. Display the app icon and description, bundled version/build, minimum system requirement, license, source links, and local-data information with a Finder action.

## Acceptance criteria

- [x] General and About switch the detail content and toolbar heading.
- [x] Back and Forward track page navigation, with correct enabled states.
- [x] About displays real bundle metadata and the repository's existing license/source information.
- [x] Verify sidebar and toolbar navigation, edit preservation, native rendering, and unchanged tracking.
- [x] Build and relaunch for review.

## Verification

The previous settings work was accepted and committed as `f4e7266` before starting this task.

- Debug and release builds passed; release bundle signed successfully.
- Inspected the composited About capture: app icon/name, grouped information rows, source/license links, and local-data section are visible. Version 0.1.0 and build 1 match the bundle.
- Toolbar checks use native mouse events because momentary segmented controls report no selected segment outside a click.
- `LINE_SMOKE_CAPTURE=1 python3 scripts/smoke-test.py --main-window`: passed across two fresh launches. Checks General/About sidebar selection, toolbar titles, Back/Forward, clearing forward history, committing a pending countdown edit when leaving General, unchanged sidebar width and tracking, accessible About actions, and restored slider/switch thumbs after returning. Existing settings and window lifecycle checks also pass.
- Relaunched `build/DayTape.app` for user review.

Accepted by the user on 2026-10-21. Implementation and verification complete.
