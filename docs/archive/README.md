# docs/archive/

This directory holds documents that no longer guide current work: executed,
historical and superseded plans, point-in-time audits, baselines, inventories,
reviews, session notes and raw question ledgers. They stay in the repository
as the record of how the project got here.

- **Public, tracked content.** Everything here is published with the rest of
  the repository. Moving a file here is not a way to hide it.
- **Same safety checks.** Vale style rules don't apply here, but gitleaks and
  `bin/scrub-public-repos.sh` scan this directory in full.
- **Original sub-path.** Each file keeps the sub-path it had under `docs/`:
  `docs/plans/<file>` is now `docs/archive/plans/<file>`. No file was renamed
  in the move, and links to moved files point here.
- **Not maintained.** Archived documents are not updated when the project
  changes. For current state, start at [docs/INDEX.md](../INDEX.md).

Plans that are still `active` or `draft` live in [docs/plans/](../plans/INDEX.md).
