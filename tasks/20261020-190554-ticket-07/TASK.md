# 07: Finish personal installation and verify complete workflows

- STATUS: OPEN
- PRIORITY: 100
- TAGS:
- LEGACY-ID: 07

**Spec:** [DayTape v1](../../docs/spec.md)

**What to build:** Optional launch at login, reproducible local build/install instructions, and verification of the packaged app, native appearance/accessibility, persistence, and combined tracking workflows.

**Blocked by:** [06: Resume interrupted work with a cancellable countdown](../20261020-190554-ticket-06/TASK.md).

## Acceptance criteria

- [ ] Offer launch at login, initially off, through supported macOS facilities; reflect the actual registration state. Login launches idle.
- [ ] Provide reproducible build, launch, and local installation instructions and a runnable app bundle that retains data independently of the checkout.
- [ ] Run applicable automated checks, then verify packaged-app workflows combining tracking, historical corrections, lock/sleep continuation, rejection, quit/relaunch, and recovery.
- [ ] Check native controls/materials, light/dark appearance, contrast/transparency/motion settings, readable task colors, keyboard editing, accessible labels, and Dock visibility only while the main window is open or minimized. Fix discovered issues within the agreed scope.
- [ ] Record what was verified and any remaining platform limitations; do not claim manual checks that were not performed.

Native macOS appearance, Liquid Glass use, and accessibility follow the spec and apply to every UI change in this ticket.

## Carried verification

Tickets 01, 02, and 03 are accepted as done. Complete their remaining manual checks during final verification, including physical timeline drawing/scroll/pinch/double-tap delivery and the full appearance/accessibility matrix. See [ticket 01 verification](../../docs/ticket-01-verification.md), [ticket 02 verification](../../docs/ticket-02-verification.md), and [ticket 03 verification](../../docs/ticket-03-verification.md).

Also verify physical Command-drag overwrite and its striped preview from ticket 09 in the same appearance/accessibility matrix. See [ticket 09 verification](../../docs/ticket-09-verification.md).

Ticket 04 was accepted as done on 2026-10-20. Complete its remaining physical entry-click/edge-resize, keyboard/VoiceOver, appearance, and repeated-hour timeline checks. Timestamp fields were removed from the approved UI. See [ticket 04 verification](../../docs/ticket-04-verification.md).

Ticket 05 was accepted as done on 2026-10-20 after the user reported it working. Repeat the full lock/sleep matrix, including combined lock/sleep with an open editor, display-off without lock, and awake external-display use with the lid closed. The user did not enumerate every scenario as tested. See [ticket 05 verification](../../docs/ticket-05-verification.md).

Ticket 06 was accepted as done on 2026-10-20, resolving this ticket's blocker. Complete its physical continuation checks, including hover pause, menu bar highlighting, OK/Reject and outside clicks, focus, wake/unlock ordering, Spaces, monitor arrangements, and appearance/accessibility. See [ticket 06 verification](../../docs/ticket-06-verification.md).

The [main-window task](../20261020-194050/TASK.md) adds remaining manual checks for physical Dock/app-switcher navigation, Spaces, VoiceOver, light/high-contrast/reduced-transparency appearance, and window geometry and floating behavior. Automated lifecycle and persistence checks passed.
