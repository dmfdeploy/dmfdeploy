# Repo Profile — detect → confirm → cache (with evidence)

The engine relies on per-repo conventions (commit rules, required checks, issue
close behavior, default branch, tracker). The #1 failure mode is **silent
confidence**: inferring a convention, being wrong, and acting on it. This protocol
exists to make that impossible.

## The iron rule

**Every convention carries `{value, evidence, confidence, expiry}`. Unknown ⇒ block
or ask. Never silently default. Absence ≠ policy.**

- A 403 / missing branch-protection response is **UNKNOWN**, not "no protection".
- `low` confidence is a **confirmation gate**, not a default.

## What to detect (and where the *evidence* must come from)

| Convention | Evidence source (NOT a guess) | Trap |
|---|---|---|
| Default branch | `gh repo view --json defaultBranchRef` | — |
| Required checks | **branch protection / rulesets** API | CI YAML ≠ required checks (reusable workflows, bots, path filters, status names) |
| Merge method + auto-merge | rulesets + repo settings | rebase auto-merge can sever keyword auto-close |
| Admin bypass allowed | ruleset `bypass_actors` | green ≠ mergeable if bypassable |
| Close-keyword behavior | **probe** (see below), not docs | base branch, PR-vs-commit body, target repo, cross-repo perms all matter |
| Commit hygiene (DCO, no co-author, ref style) | **recent merged PRs/commits**, the DCO/commitlint check configs | may be social/bot/historical, not in any config file |
| Tracker + issue location | remote URL + org docs | "work starts at a GitHub issue" is not universal |

## Close-keyword: probe, don't infer

Whether a merged PR auto-closes its referenced issue is structural and
platform-side. Determine it from **observed history**: do recently-merged PRs in
this repo that said `Closes <ref>` actually show the issue closed-by-PR? Cross-repo
(`owner/other#N`) almost never auto-closes — record that as a *detected capability*,
not an assumption. (In this org it does **not** — see `dmf-profile.md` and #47.)

## Conflicting docs

`CLAUDE.md` / `AGENTS.md` / `CONTRIBUTING` / `WORKING-MODEL.md` drift is normal.
Read all, record a **precedence + conflict report**, and gate to the human on any
material conflict rather than picking one silently.

## Caching with fingerprints (so staleness is detectable)

Cache the confirmed profile keyed by **evidence fingerprints**, not time-once:
`{ workflow file SHAs, branch-rule hash, default branch, remote URL, tracker }`.
**Revalidate before opening the PR.** If any fingerprint changed (e.g. a workflow
SHA moved), the convention reverts to `unknown` and re-gates — don't ship on a stale
profile.

## Output

A short profile object the run reads from. Surface it once at preflight
(detect→**confirm**), and list anything that resolved to `unknown`/`low` as
explicit confirmation gates before the run proceeds.
