# CLAUDE.md — dmfdeploy umbrella

This is the **umbrella repo** for the DMF Platform: the consolidated
knowledge base (`docs/`) and cross-repo coordination point. Since the public
release (2026-06-11) the 8 component repos are **siblings of this repo under a
common parent directory** (`../dmf-cms`, `../dmf-infra`, …) — they are no
longer nested inside the umbrella.

## Boot ritual (every session, every agent)

> **🛑 If your task involves pushing any DMF repo to a public GitHub mirror,
> first read [`docs/handoffs/DMF Public Publish Readiness Handoff 2026-05-07.md`](docs/handoffs/DMF%20Public%20Publish%20Readiness%20Handoff%202026-05-07.md).**
> The orphan-rebase to `v0.1.0` and the push-mirror refspec gate are non-obvious
> and skipping the handoff risks leaking pre-publish history.

Before touching any DMF repo:

1. `cd "$DMFDEPLOY_UMBRELLA" && git fetch && git pull` (umbrella)
2. `bin/generate-status.sh` — writes `STATUS.local.md` (gitignored), then read it.
3. Read the most recent file in [docs/handoffs/](docs/handoffs/) — it's the
   prior session's intent, recorded for you.
4. Skim [docs/decisions/INDEX.md](docs/decisions/INDEX.md) — note any ADRs
   relevant to your task. Apply them.
5. Run `git status` in any component repo (`../dmf-*`) you're about to touch.
   **Ask the user before modifying any component repo with dirty (uncommitted)
   state** — that's in-progress work from another session/agent.
6. If you're going to retrieve secrets, run cluster operations, or release
   dmf-cms, read the §0 of the relevant skill first:
   `dmf-cluster-access`, `dmf-openbao-unseal`, `dmf-cms-build-and-release`.

> **Skills (ADR-0042):** the one canonical, agent-neutral store is
> `.agents/skills/`; `.claude/skills/` and `.qwen/skills/` are **generated,
> gitignored views** rebuilt by `bin/sync-skills.sh --apply` (also on SessionStart).
> Author or edit skills only in `.agents/skills/`; never hand-edit a view. New
> auto-minted skills go through `.agents/skills/_inbox/` → `--promote` → PR.

> **Feature-branch work (e.g. the mxl spike):** also run `bin/mxl-sync-check.sh`
> — a read-only checker that fetches all five mxl-spike repos and reports how far
> each is behind `origin/main` (with a conflict preview + the exact merge command),
> so you sync *before* building on a stale base. It never mutates anything.

End-of-session: if you changed shared state (cross-repo decisions, in-flight
work that another agent might trip over), update the `<!-- HUMAN-START -->`
section of [STATUS.md](STATUS.md) before stopping. The live repo snapshot is
local-only and will refresh next run; the committed operator notes section won't.

### One-time hook install per clone

A pre-commit hook runs staged secret scans, refreshes deterministic generated
docs, and checks documentation/frontmatter consistency. Activate once:

```bash
bin/install-hooks.sh
```

Sets `core.hooksPath = .githooks`. Per-clone setting, so re-run after each
fresh clone. Skip umbrella doc refresh/check steps with
`STATUS_HOOK_SKIP=1 git commit ...` for emergencies.

## ⚠️ Cluster Target

The **DMF Platform runs on Hetzner CAX21 ARM64** in nbg1 region under a rotating
test-env identifier — env ids are short-lived (we cut new ones as the build
shifts). The **current env id and its concrete details live in
`STATUS.local.md` after running `bin/generate-status.sh`**, not here. SSH access via
`k3s-admin@<control-node-public-ip>`. Playbooks invoke via
`dmf-env/bin/run-playbook.sh <env-name>` — substitute the current env from
`STATUS.local.md`.

The local RPi k3s cluster (<lan-ip>) is an unrelated homelab — **never use it for DMF work**.
Always verify kubectl context with `kubectl config current-context` before running cluster commands.

## What lives where

| Question | Look in |
|---|---|
| What is the DMF Platform supposed to be? | `docs/architecture/DMF Platform Plan.md` |
| What is the EBU layer/vertical/lifecycle vocabulary? | `docs/architecture/DMF EBU Mapping (2026-04-25).md` |
| What's the active task? | [GitHub Issues](https://github.com/dmfdeploy/dmfdeploy/issues) + the Active section of `docs/plans/INDEX.md` (umbrella plan: `DMF v0.1 Commitment & 30-Day Focus-Cut Plan 2026-06-06.md`) |
| What's the strategic frame for current decisions? | `docs/decisions/architectural-commitments-v1.md` + `docs/reviews/dmf-platform-technical-evaluation-2026-06-06.md` (the 2026-04-30 strategic review is superseded) |
| New here — what is this and how did it get here? | `docs/THESIS.md` → `docs/JOURNEY.md` → `docs/decisions/INDEX.md` (§Start here) |
| What do these project words mean? | `docs/GLOSSARY.md` |
| What's frozen / unproven / undecided? | `docs/OPEN-QUESTIONS.md` |
| How must the operator console look/feel/behave? | `docs/design/DMF Console UX Constitution 2026-05-25.md` (principles + §3 hard gates; points to alarm/danger/audit/glossary specs in `docs/design/`) |
| Who handed off what? | `docs/handoffs/` (most recent file is canonical) |
| What changed during the rebuild? | `docs/sessions/DMF Rebuild Session Notes 2026-04-22.md` |

## Component repos

Each is a separate git repo with its own remote:

- `dmf-cms/` — operator console (React + FastAPI). Active.
- `dmf-infra/` — generic Ansible playbooks/roles. Active. Public.
- `dmf-env/` — **generic env tooling**: `bin/` scripts, `terraform/modules/` + generic per-provider roots (`terraform/<provider>/`), neutral `tasks/`/`templates/`. Per-env state (inventory, manifest, bundle, tfvars, SSH keys, TF state) is **operator-local** under `~/.dmfdeploy/envs/<env>/` — nothing per-env is committed (ADR-0035, 2026-06-01). Live env id is in generated `STATUS.local.md`.
- `dmf-central/` — central services (scaffold, Phase 0 step 5).
- `dmf-media/` — media-domain catalog metadata + (future) Layer 5 roles. Currently scaffold; `nmos-cpp` role relocated to `dmf-runbooks` per 2026-05-06 Path A pivot.
- `dmf-runbooks/` — thin AWX launcher playbooks + currently-authoritative `nmos-cpp` role (ADR-0014, ADR-0016). Active.
- `dmf-init/` — **Day-0 stateless init/bootstrap container** (React + FastAPI, HTTPS/secure-context) that wraps `dmf-env`'s wizard + `bin/` toolchain behind a localhost web UI, with a passphrase-wrapped backup/restore lifecycle delivered as browser downloads + file-upload restore (sandbox-first; the earlier dual-remote rclone model was removed 2026-06-08). Spec in `docs/plans/DMF Init Bootstrap Container Plan 2026-06-02.md`. Public-safe.
- `dmf-promsd/` — **NetBox-driven Prometheus service-discovery** component (dynamic monitoring targets from NetBox SoT). Active; model in ADR-0038 + `docs/plans/DMF Dynamic NetBox-Driven Monitoring Plan 2026-06-04.md`. Catalog launcher stamping + probe tuning are open (tracked in [umbrella issue #5](https://github.com/dmfdeploy/dmfdeploy/issues/5)).

## Conventions

- **Don't move files between component repos** without checking. Each has its own
  release cycle and downstream references.
- **Always read the canonical doc** in `docs/architecture/` before making decisions
  that depend on layer/vertical assumptions. Several plans were drafted against the
  pre-EBU-vocabulary scheme and may use stale terminology.
- **Doc filenames preserved verbatim** from the original operator note store. Many docs reference
  each other by display name; don't rename without sweeping callers.
- **Component-repo agent files** (`CLAUDE.md`, `AGENTS.md`, `QWEN.md`) may still carry stray
  `<note-store>/...` references — most are cleaned, but spot-check before quoting any
  cross-repo path. The `dmf-cms` mockup reference at `<note-store>/tmp/dmf-portal-mockup-2025.png`
  is the known remaining one (tracked in [umbrella issue #26](https://github.com/dmfdeploy/dmfdeploy/issues/26)).
- **No specific IPs or DNS in public repos.** Code/configs use variables (e.g.
  `cert_manager_cluster_domain`) with example-domain defaults. Prose uses the
  fictitious example domain `dmf.example.com` and `<placeholder-name>` style for
  IPs (`<control-node-public-ip>`, `<node-public-ip>`, `<lb-public-ip>`,
  `<lan-ip>`, `<wg-mesh-ip>`, `<headscale-host>`). Concrete values live only in
  `dmf-env` (private). Pre-commit gitleaks + `bin/scrub-public-repos.sh` enforce
  this on every commit. When adding new docs, follow the convention; existing
  content was swept on 2026-05-07.

<!-- WORKING-MODEL-BLOCK-START — generated from umbrella docs/templates/working-model-block.md; do not edit copies, edit the template and run bin/check-working-model-sync.sh -->
## Working model (mandatory)

Canonical: [docs/WORKING-MODEL.md](https://github.com/dmfdeploy/dmfdeploy/blob/main/docs/WORKING-MODEL.md)
in the umbrella repo. The three rules that matter mid-task:

1. **Work starts at an issue** in the canonical backlog
   ([dmfdeploy/dmfdeploy issues](https://github.com/dmfdeploy/dmfdeploy/issues);
   milestone + `component:*`/`workstream:*` labels). Non-trivial work gets a
   plan doc in umbrella `docs/plans/` with `tracking_issue` frontmatter.
2. **The completing PR auto-closes its issue; you still flip the plan
   frontmatter by hand in that PR.** Reference umbrella issues **fully
   qualified** — `Closes dmfdeploy/dmfdeploy#N` (bare `#N` targets the wrong
   repo); the daily issue-close reconciler honors that ref, cross-repo
   included. Manual close is a fallback.
3. **Never invent a local backlog** (TODO files, ad-hoc trackers). Issues =
   liveness; plan frontmatter = design state; ADRs = decisions (RFC in
   Discussions first); STATUS.md = committed notes; STATUS.local.md = live repo snapshot.
<!-- WORKING-MODEL-BLOCK-END -->

## Backlog + working model (GitHub-native)

- **Live backlog = [GitHub Issues](https://github.com/dmfdeploy/dmfdeploy/issues)**
  (org board: [Project #1](https://github.com/orgs/dmfdeploy/projects/1));
  TODOS.md was retired into Issues on 2026-06-10. Discussions host Q&A + the
  RFC-before-ADR pipeline (see [CONTRIBUTING.md](CONTRIBUTING.md)).
- **Milestones schedule the backlog:** `v0.1-polish` (items gating the v0.1
  claim) and `v0.2` (post-v0.1 scope). New issues get a milestone and a
  `component:*` + `workstream:*` label pair. The org board (Project #1) is a
  **human curation surface**, not a filing requirement — people add significant
  issues and track Status; nothing auto-adds or reconciles it, and labels stay
  canonical (see `docs/WORKING-MODEL.md` §3).
- **Gotcha:** `gh project` subcommands may 401 — use raw `gh api graphql`
  (Project #1 node id `PVT_kwDOENb9uM4BaPY-`).
- **New-work convention:** open (or claim) an issue → write the on-disk spec in
  `docs/plans/` with `tracking_issue` frontmatter → the completing PR
  **auto-closes the issue** (the `bin/close-completed-issues.sh` reconciler,
  scheduled daily via `issue-close-reconciler.yml`, honors the qualified
  `Closes dmfdeploy/dmfdeploy#N` reference — cross-repo included; manual close is
  fallback only) **and must flip the plan's frontmatter in the same change** —
  the frontmatter flip is not automated.
- **Split-brain precedence rule:** GitHub Issues are canonical for
  scheduling/liveness ("is anyone working on this?"); in-repo frontmatter is
  canonical for design/decision state. On disagreement the issue wins for
  liveness and the frontmatter must be flipped. `bin/check-docs.sh` (wired into
  pre-commit + CI) is the offline drift detector — plan docs need parseable
  frontmatter or the commit is rejected.

> **Agentic harness — mothballed 2026-06-04.** The former tick-loop harness is
> preserved for provenance under [`docs/agentic/`](docs/agentic/README.md);
> do not treat its state files (`backlog.yaml`, `decisions-open.md`,
> `issues.yaml`) as live queues.

## Git topology

- The 8 component repos live as **siblings of the umbrella** under a common
  parent directory; each remains an independent repo (ADR-0001, amended
  2026-06-11). Nothing is nested inside the umbrella anymore — the old
  `.gitignore` entries for `dmf-*` remain only as a safety net for legacy
  nested clones. `bin/` tooling resolves component repos in either layout
  (sibling canonical, nested fallback). If you ever want pinned versions for
  reproducible builds, convert them to git submodules (a one-way decision
  worth a discussion first).
- **All 9 repos use `main` as the default branch** (renamed from `master` on
  2026-05-07 for the three that still had it). On Forgejo, the default-branch
  setting must match — flip via Settings → Branches if a freshly-cloned repo
  still shows `master`.
- Doc edits go in this umbrella. Code edits go in the component repos. Reviews
  and cross-cutting task specs go in `docs/plans/` or `docs/reviews/` here.

## Current phase: v0.1 committed

The experiment phase **closed 2026-06-06** —
[`docs/decisions/architectural-commitments-v1.md`](docs/decisions/architectural-commitments-v1.md)
froze the v0.1 architecture and named the explicit non-goals (federation,
HA/cloud claims, Argo hybrid actuator, in-place upgrade, media-v2).
Work-selection rule: **"choose work that makes the proven core runnable and
legible to an outsider."** Active plan:
`docs/plans/DMF v0.1 Commitment & 30-Day Focus-Cut Plan 2026-06-06.md`.
