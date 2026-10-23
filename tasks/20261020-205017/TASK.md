# Add System, 12-hour, and 24-hour time formats

- STATUS: CLOSED
- PRIORITY: 100
- TAGS:

Add a Time format menu in General with System, 12-hour, and 24-hour choices. Default to System and preserve the user's calendar and time zone.

## Acceptance criteria

- [x] Save the choice automatically and restore it after relaunch; older records default to System.
- [x] Apply the choice to timeline labels, entry tooltips, and time-bearing accessibility descriptions. Keep midnight date markers.
- [x] Preserve tracking, entries, zoom, and recovery checkpoints when changing this preference; report failed saves without applying them.
- [x] Verify midnight/noon, explicit formats across locales, persistence, and the native picker. Build and relaunch for user review.

## Verification

- `swift test`: 76 tests passed, including explicit hour cycles, midnight/noon, time zones, locale-driven System output, midnight date markers, old records, persistence, and failed-save preservation.
- `LINE_SMOKE_CAPTURE=1 python3 scripts/smoke-test.py --main-window`: passed across two fresh launches. Opens the actual native popup with a mouse event and selects each format with keyboard events. Checks immediate saves, unchanged tracking entries, and restored 24-hour choice on relaunch.
- Inspected the composited Settings capture: Time format appears as a native menu row below Default zoom. The initial slider thumb regression check still passes.
- Release build and signing passed. Relaunched `build/Tape.app` for user review.

Accepted by the user on 2026-10-21 when requesting the settings commit and moving on to About.
