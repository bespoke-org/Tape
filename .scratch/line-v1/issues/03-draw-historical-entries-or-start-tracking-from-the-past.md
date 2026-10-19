# 03: Draw historical entries or start tracking from the past

**Spec:** [Line v1](../spec.md)

**What to build:** Drag empty space, type/select a task, save historical time or keep running when drawing through now; support cancellation and reject overlaps without modifying existing entries.

**Blocked by:** [02: Browse and zoom the timeline](02-browse-and-zoom-the-timeline.md).

**Status:** ready-for-agent

**Execution:** done

## Acceptance criteria

- [x] Drag empty space to select historical time with zoom-dependent snapping and open the combined task-name/search field. Support reverse drags and Escape cancellation without creating records.
- [x] Drawing through now preserves running intent through delayed task selection and starts from the selected past instant, including picker time.
- [x] Stop drawn selections at neighboring completed or running entries and revalidate overlaps on commit. Silently cancel empty selections and reject positive-duration wholly future selections; allow adjacent endpoints.
- [x] Preserve accurate live timestamps and provide readable validation feedback. Persist accepted entries and verify them after reopen.
- [x] Test creation through application operations and verify gesture behavior manually.

Native macOS appearance, Liquid Glass use, and accessibility follow the spec and apply to every UI change in this ticket.

## Verification

- All 22 core tests pass. Packaged-app creation, tracking, and timeline smoke checks pass with isolated data and bounded runtimes.
- Standards and spec reviews found no actionable findings or unnecessary complexity.
- Accepted by the user on 2026-10-19 after exercising drawing and refining selection boundaries, snapping, and cancellation. The full hardware and appearance/accessibility verification matrix remains deferred to ticket 07, not claimed as passed. See [the verification record](../../../docs/ticket-03-verification.md).
