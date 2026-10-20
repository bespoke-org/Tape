# Local issue tracker

DayTape uses Markdown files in this repository as its issue tracker. No external service is configured.

- Feature plans live under `.scratch/<feature-slug>/`.
- The DayTape v1 spec is `.scratch/line-v1/spec.md`.
- Proposed ticket breakdowns are stored as `ticket-plan.md` beside the spec. A proposal is not an approved ticket set.
- After approval, publish one ticket per file under `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered in dependency order. Each ticket links to its spec and lists its blockers, status, and acceptance criteria.
- Use the canonical triage labels unchanged: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`.
- Approved implementation tickets start with `Status: ready-for-agent`. Track execution separately as not started, in progress, or done; keep acceptance checkboxes current.
- A ticket is eligible to start only when its blockers are done. Finishing tickets does not automatically close or alter the parent spec.
- Keep plans and tickets in the repository, including when version control is initialized. Do not ignore this project's `.scratch/` planning records.
