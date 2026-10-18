# 01: Track tasks on a live timeline

**Spec:** [Line v1](../spec.md)

**What to build:** A runnable native menu bar app; create/search tasks, start/stop/switch, and watch entries grow on a four-hour timeline following now; preserve data and stop safely on quit or recovery.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

**Execution:** implemented; manual appearance and accessibility verification pending

## Acceptance criteria

- [x] Build and run a native Swift app bundle on this Mac without a Dock icon; show a compact status item and a dismissible popover with system controls and materials.
- [x] Type to create or search reusable tasks; enforce trimmed, nonempty, case-insensitively unique names and persist a random legible color.
- [x] Start, stop, and switch tasks with a single-running-entry invariant, adjacent switch timestamps, elapsed display, and a running indicator. Closing the popover does not stop tracking.
- [x] Show saved and growing entries with readable task labels/colors on a basic four-hour timeline centered on now. Follow time automatically beneath the now marker, with enough date/time context to read the strip.
- [ ] Verify that starting a task grows its entry on the timeline, stopping fixes its endpoint, and switching produces adjacent entries. Keep the basic timeline legible in light/dark appearance and with accessibility preferences; closed popovers do not need continuous rendering.
- [x] Save mutations atomically; persist five-second running checkpoints; reopen the store; clean quit ends tracking and relaunch starts idle. Unexpected-exit recovery stops at the saved point rather than counting downtime.
- [ ] Verify through observable tracking operations and real storage reopening, plus a manual smoke test of the app bundle. Provide initial build/run instructions with the slice.

Native macOS appearance, Liquid Glass use, and accessibility follow the spec and apply to every UI change in this ticket.

## Verification

- Eight tracking/persistence tests pass, including task reuse, adjacent switches, live versus stopped duration, invalid names, recovery, unknown store versions, failed writes, and clock reversal.
- The bounded packaged-app smoke check passes native field submission, start/switch/Stop actions, menu bar activation policy/icon, popover close/reopen, tracking while closed, removal of the hidden rendering schedule, and the elapsed timer's accessibility value. It uses isolated data and exits automatically, with a 20-second watchdog in the runner.
- Standards and spec reviews each found the same elapsed-time accessibility issue. It was fixed and the spoken value is covered by the smoke check.
- Release build, app signature, and bundle metadata are checked separately. Build and run instructions are in the project README.
- The unchecked criteria retain their manual component: inspect the composited UI in light/dark appearance and with contrast/transparency/motion settings, check outside-click dismissal, and use VoiceOver. External desktop automation and reliable window capture were unavailable in this session; in-process checks do not replace these visual checks.

See [the verification record](../../../docs/ticket-01-verification.md).
