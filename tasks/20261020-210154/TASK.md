# Configure the resume countdown duration

- STATUS: CLOSED
- PRIORITY: 100
- TAGS:

Add Resume countdown to General → Tracking as a native stepper. Allow 1–60 seconds in one-second increments, preserving the current nine-second default. See the [spec](../../docs/spec.md).

## Acceptance criteria

- [x] Save automatically and restore after relaunch; older records use nine seconds.
- [x] Use the selected duration for the next unlock/wake countdown, preserving an active countdown and hover pause.
- [x] Preserve immediate OK/Reject, short-break continuation, and recording from return time.
- [x] Keep entries and recovery checkpoints unchanged when saving; retain the previous value on save failure.
- [x] Verify the native control, build, and relaunch for user review.

## Verification

- `swift test`: 81 tests passed. Added persistence, legacy defaults, bounded values, failed-save preservation, configured deadlines, and changes during a paused offer.
- `LINE_SMOKE_CAPTURE=1 python3 scripts/smoke-test.py --main-window`: passed across two fresh launches. Actual clicks on the native stepper save increments and decrements; the second process restores the selected duration. Tracking records remain unchanged.
- Inspected the Settings capture: the grouped Tracking section displays the description, seconds value, and native stepper.
- Release build and signing passed; relaunched `build/Tape.app` for user review.

Accepted by the user on 2026-10-21 when requesting the settings commit and moving on to About.

## Numeric countdown input

At the user's request, replaced the countdown stepper with a native text field followed by “seconds”. The short-break threshold retains its stepper. The field keeps only digits and commits on Return or focus loss, retaining the 1–60 second range. Empty input restores the saved duration, and failed saves display the stored value.

Verified with `LINE_SMOKE_CAPTURE=1 python3 scripts/smoke-test.py --main-window` across two fresh launches. The native field editor filters mixed input to digits, commits on Return and focus loss, restores empty input, bounds zero and overflowing input, disables with Automatic resume, and preserves tracking. Saved values survive relaunch. The switch and slider first-opening rendering checks still pass. Inspected the Settings capture; release build/signing passed and Tape was relaunched.
