# Open settings sections from the menu bar context menu

- STATUS: CLOSED
- PRIORITY: 100
- TAGS:

Replace Open Tape in the menu bar secondary-click menu with one item for each current sidebar section. Use General Settings… followed by About Tape, then a separator and Quit Tape. Retain normal left-click popover behavior.

## Acceptance criteria

- [x] Menu items follow sidebar order and open their corresponding page directly.
- [x] Section menu items use the same SF Symbol icons as the settings sidebar.
- [x] Reuse the main window, restoring it from minimized or closed states.
- [x] Preserve the existing draft dismissal, pending-continuation handling, and tracking behavior when opening.
- [x] Verify native menu actions, build, and relaunch for review.

## Verification

- `LINE_SMOKE_CAPTURE=1 python3 scripts/smoke-test.py --main-window`: passed across two fresh launches. Asserts menu order and separator placement, restores a minimized General window directly to About, switches directly to General in the same window, and reopens a closed window directly to About without changing tracking. Existing sidebar/history, settings, and native thumb checks also pass.
- Release build and signing passed; relaunched `build/Tape.app` for review.

Accepted by the user after reviewing the section shortcuts and matching sidebar icons.
