# 07: Finish personal installation and verify complete workflows

**Spec:** [Line v1](../spec.md)

**What to build:** Optional launch at login, reproducible local build/install instructions, and verification of the packaged app, native appearance/accessibility, persistence, and combined tracking workflows.

**Blocked by:** [06: Resume interrupted work with a cancellable countdown](06-resume-interrupted-work-with-a-cancellable-countdown.md).

**Status:** ready-for-agent

**Execution:** not started

## Acceptance criteria

- [ ] Offer launch at login, initially off, through supported macOS facilities; reflect the actual registration state. Login launches idle.
- [ ] Provide reproducible build, launch, and local installation instructions and a runnable app bundle that retains data independently of the checkout.
- [ ] Run applicable automated checks, then verify packaged-app workflows combining tracking, historical corrections, lock/sleep continuation, rejection, quit/relaunch, and recovery.
- [ ] Check native controls/materials, light/dark appearance, contrast/transparency/motion settings, readable task colors, keyboard editing, accessible labels, and no Dock icon. Fix discovered issues within the agreed scope.
- [ ] Record what was verified and any remaining platform limitations; do not claim manual checks that were not performed.

Native macOS appearance, Liquid Glass use, and accessibility follow the spec and apply to every UI change in this ticket.

## Carried verification

Tickets 01, 02, and 03 are accepted as done. Complete their remaining manual checks during final verification, including physical timeline drawing/scroll/pinch/double-tap delivery and the full appearance/accessibility matrix. See [ticket 01 verification](../../../docs/ticket-01-verification.md), [ticket 02 verification](../../../docs/ticket-02-verification.md), and [ticket 03 verification](../../../docs/ticket-03-verification.md).

Also verify physical Command-drag overwrite and its striped preview from ticket 09 in the same appearance/accessibility matrix. See [ticket 09 verification](../../../docs/ticket-09-verification.md).
