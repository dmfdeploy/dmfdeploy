# DMF Profile (this environment's confirmed facts)

The concrete profile instance for the DMF platform. These are **profile facts, not
engine facts** — a different org would supply its own. Still subject to the
evidence/expiry rule in `repo-profile.md`: confirm on first use per session,
revalidate before PR.

## Topology

- **Canonical backlog = the umbrella repo** (`dmfdeploy/dmfdeploy`) Issues. Code
  lives in **sibling component repos** (`dmf-cms`, `dmf-env`, `dmf-init`, …) checked
  out next to the umbrella, each its own remote.
- Non-trivial work also gets a plan doc in umbrella `docs/plans/` with
  `tracking_issue` frontmatter; the completing PR flips it.

## Conventions

- **Refs:** from a component repo, reference umbrella issues **fully qualified** —
  `Closes dmfdeploy/dmfdeploy#N`. A bare `#N` targets the component repo's own
  issues (and the `issue-link` guard requires the qualified form).
- **Commit hygiene:** DCO sign-off required (`git commit -s`); **no
  `Co-Authored-By`**, no "Generated with" trailer — sign-off is the only trailer.
  Conventional-commit subject (commitlint gate).
- **Close behavior:** cross-repo PRs **do not auto-close** umbrella issues (GitHub
  limitation), and rebase auto-merge can sever even same-repo keyword close. **Close
  the umbrella issue manually** after merge with a PR-linked comment. (Tracked for
  mechanization in umbrella #47.)
- **Merge:** approval-driven rebase auto-merge; PRs gate on `REVIEW_REQUIRED` +
  required checks. A force-push does not clear a standing `CHANGES_REQUESTED`.

## Trio harness

- Agents run in tmux panes driven by `agent-bridge`
  (`~/.claude/skills/agent-bridge/bin/agent-bridge`). Default roster: `qwen-left`
  (implementer), `codex` (adversary), `claude` (orchestrator). Verify with
  `agent-bridge list` / `ping`. See `harness-ops.md`.

## Shared-checkout hazard (important)

The umbrella working tree is **shared** by multiple agents/sessions. Concurrent
edits on one tree clobber each other, and switching its branch moves everyone's
HEAD. **Before any write, check `git status`/branch; if another agent is active or
the tree is dirty, isolate in a dedicated `git worktree`** off the default branch
and work there. Never assume the shared checkout is on `main`.

## Trio-suitable issue filter (Phase 1 selection)

Prefer: single-repo, offline-verifiable (has a local test runner), concrete defect
with a precedent to mirror. Avoid for the offline flow: needs a live cluster / CMS
image build (e.g. "verify on next live env"), multi-repo sweeps, or decision-first
items (need an ADR/RFC before code).

## Boot ritual + docs

Run the umbrella boot ritual first (CLAUDE.md): `git pull`, `bin/generate-status.sh`,
read the latest `docs/handoffs/` file, skim `docs/decisions/INDEX.md`. The
working model is canonical in `docs/WORKING-MODEL.md`.
