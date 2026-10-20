# Add a main window with Settings and configurable default zoom

- STATUS: CLOSED
- PRIORITY: 100
- TAGS:

Agreed on 2026-10-20 after the design interview. Add an explicitly opened main window for Settings, with space for future sections. Statistics and other settings are outside this task.

## Acceptance criteria

- [x] Add a plain gear icon to the popover controls, labeled and help-texted “Open DayTape.” Add “Open DayTape” to the status item's secondary-click menu and “Settings…” with Command-comma to the application menu.
- [x] Open one native, resizable window with “DayTape” as its accessibility/window-menu title, initially 900 × 600 with a roughly 200-point, always-visible sidebar. Follow System Settings visually: hide the app title, place native window controls inside the full-height sidebar, and use a compact General heading above grouped controls. Use green-button zoom without full screen, allowing AeroSpace to float the window automatically. General is its only selected section. Remember window size and position.
- [x] Launch with only the menu bar icon. Show the Dock icon and app-switcher entry while the main window is open, including minimized. Repeated opening restores and focuses that window. Closing it returns to menu-bar-only operation and keeps tracking running.
- [x] Opening the window dismisses the popover, discards unfinished drafts, preserves saved edits and running time, and accepts pending continuation consistently with other explicit app opening.
- [x] Add a native “Default zoom” slider with seven stops at 1, 2, 4, 8, 12, 16, and 24 hours, initially 8. Place the description beside the slider and labels underneath only 1, 8, and 24 hours. Save automatically and report persistence failures without claiming success.
- [x] Apply the configured default on the next timeline opening or reset. Opening follows Now; resetting preserves the viewed center, and a second reset follows Now. Pinching is temporary and retains its wider range. Existing last-used zoom does not become the new default.
- [x] Verify persistence, existing records, reset/reopen behavior, single-window lifecycle, keyboard access, tracking continuity, and the packaged app. Record any remaining manual checks.

## Verification

Implemented with a native AppKit window and split view, a SwiftUI Settings form, and one shared window controller. The app uses regular activation while the window is open and accessory activation after closing it. The configured default is stored as `defaultZoomHours` in the existing atomic JSON store; legacy `timelineSpan` is ignored. Pinch gestures no longer persist zoom.

- `swift test`: all 69 tests passed. Added default zoom bounds, failed-save preservation, and persistence/recovery coverage; retained legacy-store coverage.
- `python3 scripts/smoke-test.py --main-window`: passed across two fresh processes. Exercises the actual native slider at 1, 24, and 12 hours, popover button, menu action, Command-comma, Command-W, sidebar selection, window reuse, minimize/restore, Dock reopen callback, saved geometry, draft cancellation, and continued tracking.
- `python3 scripts/smoke-test.py --timeline`: passed across two fresh processes. Covers temporary pinch zoom, configured-default reopening and reset, preserved browsing center, return to Now, animation interruption, and popover stability.
- `python3 scripts/smoke-test.py`: passed the baseline native task entry, tracking, popover lifecycle, and anchoring checks.
- Release build and ad-hoc signing passed. Built `build/main-window/DayTape.app` separately because `build/DayTape.app` was already running. Quit the running copy before opening the new bundle with the same personal records.
- Inspected a composited capture of the running Settings window in dark appearance. The native sidebar, selected Settings row, window controls, slider, endpoints, and current value render correctly. The optional capture is available through `LINE_SMOKE_CAPTURE=1` on the main-window smoke check.

AeroSpace 0.21.3-Beta is active on the verification Mac. After the System Settings appearance follow-up, its CLI reports DayTape’s test window as `floating` without configuration changes. The installed version’s `isDialogHeuristic` explicitly identifies System Settings through the absence of an enabled full-screen button; DayTape uses the same public AppKit behavior, `.fullScreenNone`, while retaining resizing and normal green-button zoom. It remains a normal-level window. Native frame preferences save and survive relaunch. Manually verify physical Dock/app-switcher navigation, Spaces, VoiceOver, and light/high-contrast/reduced-transparency appearances. These checks remain part of [ticket 07](../20261020-190554-ticket-07/TASK.md).

Accepted by the user and closed on 2026-10-21. Remaining manual integration and accessibility checks stay in ticket 07.

## System Settings appearance follow-up

Matched the supplied System Settings reference and verified AeroSpace classification. Source: [AeroSpace dialog heuristic at the installed revision](https://github.com/nikitabobko/AeroSpace/blob/d56e1637c3a1ed660d0cadd7534e94fb3218d1c3/Sources/AppBundle/model/AxUiElementWindowType.swift).

Updated release build and ad-hoc signing passed. The new bundle is `build/settings-style/DayTape.app`.

Verified the updated composited window capture: traffic lights sit within the sidebar, the app title is hidden, Settings is a compact detail-toolbar heading, and the zoom control uses the native grouped form. AeroSpace reports the test window as `floating`. The updated focus smoke run was interrupted by external application focus; diagnostics reported `front=com.apple.SFSymbols`, with the test window still visible and the app using regular activation. The earlier complete lifecycle run passed before this appearance follow-up; repeat the focus checks with no other desktop interaction.

Popover icon follow-up: use `gearshape` at semibold weight, following the final icon choice.

Navigation follow-up: added native grouped back and forward buttons before the General toolbar heading. Both remain disabled because General is the only page and has no navigation history.

Slider follow-up: matched the reference with a gray native slider, seven equally spaced stops, and a description alongside it. Narrow windows keep the row side by side, wrapping the description and shrinking the slider. Earlier saved values map to the nearest preset, with ties choosing the lower value. Verified all 70 core tests and the main-window smoke check across two fresh launches, including every preset and persistence. Inspected the composited capture; labels use the native thumb width to stay aligned during resizing.

First-open slider rendering fix: reproduced the dark thumb with a screen capture before interaction. The native thumb’s hosted drawing layer was empty until interaction; marking its view subtree for layout after window attachment initializes it correctly. The fix uses public NSView layout APIs and preserves the saved value. Added a first-open screenshot assertion to the opt-in capture check. `LINE_SMOKE_CAPTURE=1 python3 scripts/smoke-test.py --main-window` now passes across two fresh launches, with sampled thumb brightness increasing from 0.193 before the fix to 0.899 after it.
