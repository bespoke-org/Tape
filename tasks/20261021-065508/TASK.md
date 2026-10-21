# Configure login startup, automatic resume, and short breaks

- STATUS: CLOSED
- PRIORITY: 100
- TAGS:

Add native settings in General for login startup, automatic resume, and the short-break threshold. Preserve current resume behavior by default. See the [spec](../../docs/spec.md).

## Acceptance criteria

- [x] Launch at login uses SMAppService.mainApp, reports actual status, exposes approval guidance, and refreshes after returning from System Settings. Merely launching or opening settings never registers the app.
- [x] Automatic resume defaults on; disabling cancels pending continuation after a successful save, without stopping current tracking. Lock/sleep still stops tracking.
- [x] Short-break threshold uses a native 0–60 minute stepper, default 5. Zero means never include breaks; equality starts a new entry. Changes affect the next offer.
- [x] Dependent controls disable while automatic resume is off and preserve saved values.
- [x] Verify persistence, save failures, continuation boundaries, native controls, and login registration state handling.
- [x] Build and relaunch for review.

## Verification

Actual login after logout and registration approval on this Mac remain manual checks. Automated checks exercise the service boundary with injected status/actions and read actual status without changing the user's login items.

- `swift test`: 88 tests in 9 suites passed. Covers threshold boundaries including Never, unchanged active-offer thresholds, disable/re-enable cancellation, legacy defaults, persistence, save failures, and retrying failed stops while automatic resume is disabled.
- Packaged Settings check passed across two fresh launches. Operated the native switch and steppers, checked dependent-control disabling and saved values, and confirmed tracking records stayed unchanged.
- Login-service checks cover registration/unregistration results, failures, approval guidance, external status refresh, and a missing service. The real macOS registration status is read; automated checks do not register the development bundle.
- Inspected the composited Settings capture. Native switches and steppers appear in grouped Tracking and Startup sections.
- Final `LINE_SMOKE_CAPTURE=1 python3 scripts/smoke-test.py --main-window` passed across two launches after the startup-error adjustment. Release build and signing passed; relaunched `build/DayTape.app` for review.

Accepted by the user on 2026-10-21 when requesting the settings commit and moving on to About. Actual login and approval remain manual platform checks in ticket 07.

## First-opening switch rendering fix

The user reported missing white switch thumbs on first opening after launch. Reproduced with `LINE_SMOKE_CAPTURE=1 python3 scripts/smoke-test.py --main-window` and a capture before any settings interaction. Both native switches showed only their tracks. The previous capture happened after interaction and missed this state.

Refreshing each NSSwitch subtree's layout after the Settings hosting controller appears restores the native thumbs without changing values or sending actions. The slider uses the same layout refresh helper. The visual regression check now examines both switch tracks on the initial capture, covering enabled and disabled states.

The check failed before the fix at brightness 0.610 and passed across two fresh processes after the fix at 0.947 and 0.909 for the two thumbs. Native switch/stepper interactions, saved preferences, window lifecycle, and unchanged tracking checks also passed. The first-opening capture was visually inspected.

## Short-break menu

Replaced the threshold stepper with the requested menu: Never, 30 seconds, 1, 2, 5, 10, 15, 30, and 60 minutes, plus Custom. The Custom sheet accepts an exact duration in seconds, with Save and Cancel. Non-preset saved values appear in the menu.

Thresholds are now stored in seconds. Legacy minute values retain their durations; reading them does not rewrite the file. A newly saved threshold replaces the legacy field, and second values take precedence if both fields exist. Existing continuation timing, strict boundary comparison, and saved entry handling are unchanged.

- `swift test`: 88 tests passed, including 30-second and custom 45-second boundaries, persisted seconds, legacy conversion, defaults, bounds, and failed-save preservation.
- Native menu checks exercise Never, 30 seconds, and 60 minutes, custom 45-second input, Cancel, and selecting a preset after Custom. The picker retains explicit presentation state so cancelling Custom restores the saved selection instead of leaving the menu on Custom.
- Final `LINE_SMOKE_CAPTURE=1 python3 scripts/smoke-test.py --main-window` passed across two fresh launches, including restoring the 30-second threshold. Tracking records and dependent settings remained intact; native thumb rendering checks passed. Inspected the Settings capture. Release build and signing passed, and DayTape was relaunched for review.
