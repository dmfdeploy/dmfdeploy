# DMF Platform Umbrella — AI Agent Rules

This is the **umbrella repo** for the DMF Platform: the consolidated
knowledge base (`docs/`) and multi-repo coordination (`STATUS.md`, `CLAUDE.md`).
The 8 component repos are checked out as **siblings of this repo under a common
parent directory** (`../dmf-cms`, `../dmf-infra`, …) — not nested inside it.

## Context for All Agents

**Before any non-trivial change:**

1. `git fetch && git pull` (umbrella)
2. `bin/generate-status.sh` — writes `STATUS.local.md` (gitignored)
3. Read `STATUS.local.md` — it's the local snapshot of what's happening across all 9 repos (umbrella + 8 components)
4. Read the tracking issue you are claiming, comments included — the live
   handoff surface (R4); `docs/handoffs/` is a frozen archive
   ([INDEX](docs/handoffs/INDEX.md)) and session-continuity notes are
   operator-local (outside this repo)
5. Skim [docs/decisions/INDEX.md](docs/decisions/INDEX.md) — note any ADRs applicable to your task

## What Lives Where

| Question | Answer | Agent |
|----------|--------|-------|
| What is the DMF Platform supposed to be? | `docs/THESIS.md`, then `docs/architecture/DMF Platform Plan.md` | Claude/Codex |
| What's the active task? | [GitHub Issues](https://github.com/dmfdeploy/dmfdeploy/issues) + Active section of `docs/plans/INDEX.md` | Claude |
| What's the strategic frame? | `docs/decisions/architectural-commitments-v1.md` (+ `docs/reviews/dmf-platform-technical-evaluation-2026-06-06.md`) | Claude |
| Who handed off what? | the tracking issue's comments (live); `docs/handoffs/` is a frozen pre-R4 archive | Claude |
| What changed during rebuild? | `docs/sessions/` | Claude |
| What decisions are binding? | `docs/decisions/INDEX.md` | Codex (for compliance audits) |

## Component Repos at a Glance

Each is a separate git repo with its own CLAUDE.md and AGENTS.md:

| Repo | Purpose | Agent-Friendly? |
|------|---------|---|
| `dmf-cms` | React + FastAPI operator console | **Codex** for React review; Claude for API |
| `dmf-infra` | Ansible playbooks & roles | **Codex** for infra review; Claude for problem-solving |
| `dmf-env` | Generic env tooling (per-env state is operator-local) | Claude only (secrets-sensitive) |
| `dmf-central` | Central services scaffold | **Codex** for review; Claude for design |
| `dmf-media` | Media domain modules | **Codex** for review; Claude for design |
| `dmf-runbooks` | Thin AWX launcher playbooks + `nmos-cpp` role | **Codex** for infra review; Claude for design |
| `dmf-init` | Day-0 init/bootstrap container (React + FastAPI) | **Codex** for review; Claude for design |
| `dmf-promsd` | NetBox-driven Prometheus service-discovery | **Codex** for review; Claude for design |

## Documentation Standards

**All documentation file names are preserved verbatim from the original operator note store.**
Many docs reference each other by display name; **don't rename without sweeping callers.**

**Per-repo CLAUDE.md files still reference `<note-store>/Projects/...` paths — these are stale.**
**Treat them as pointing at `../docs/<subdir>/<file>` in this umbrella.**
Cleanup is deferred; agents should flag these during reviews.

## Multi-Repo Coordination

**Git topology:**
- The 8 component repos are siblings of the umbrella under a common parent
  directory — independent repos, never nested (ADR-0001, amended 2026-06-11)
- Doc edits go in this umbrella
- Code edits go in component repos
- Cross-cutting task specs and reviews go in `docs/plans/` or `docs/reviews/` here

**When you touch a component repo:**
1. Check its `git status` — ask the user before modifying dirty state (another session's work)
2. Read its CLAUDE.md + AGENTS.md
3. Apply any relevant ADRs from `dmfdeploy/docs/decisions/`
4. If you change cross-repo state, update `STATUS.md` before finishing

## When to Use Codex

**Codex is the primary agent for:**
- **Infrastructure code review** — dmf-infra playbooks and roles for idempotency, error handling, best practices
- **React/frontend review** — dmf-cms for component architecture, TypeScript safety, design system compliance
- **Multi-file refactoring** — moving code between repos or large-scale reorganization
- **Diagnostic help** — analyzing error logs, git diffs, cluster state dumps
- **Architecture & design review** — across multiple files/repos, spotting inconsistencies

**Use Claude for:**
- **Planning & strategy** — new features, architectural decisions, multi-repo coordination
- **Documentation** — writing ADRs, README updates, high-level design docs
- **Secrets & policy** — anything involving OpenBao, auth, or deployment credentials (Codex skips these)
- **One-off problem-solving** — quick bugs, script generation, interactive troubleshooting

## Agent Context Files

Each agent has a persona file:

- **CLAUDE.md** — umbrella boot ritual, workspace structure, secrets discipline
- **AGENTS.md** — this file + per-repo agent rules for Codex and other tools

When an agent starts a session in this workspace, it should read BOTH files.

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

## Key Principles

1. **Relative paths everywhere** — no hardcoded `/Users/<operator>` or `/Volumes` in code
2. **Variables for environment-specific config** — IPs, URLs, sockets go in dmf-env inventory
3. **Idempotency first** — all Ansible plays must be safe to re-run
4. **Canonical docs in umbrella** — component repos reference back, not vice versa
5. **Secrets stay in OpenBao** — never commit credentials, always use `vault_*` variables
6. **Current phase: v0.1 committed** — experiment phase closed 2026-06-06
   (`docs/decisions/architectural-commitments-v1.md`); choose work that makes the
   proven core runnable and legible to an outsider
7. **Backlog lives on GitHub** — Issues are canonical for liveness, plan
   frontmatter for design state; a completing PR **auto-closes its issue** (the
   daily `issue-close-reconciler` honors the qualified `Closes dmfdeploy/dmfdeploy#N`
   ref, cross-repo included; manual close is fallback) and you **flip the
   frontmatter by hand** in the same change (`bin/check-docs.sh` gates commits)

## Running Playbooks

```bash
# From dmf-env with the wrapper (DO THIS)
cd ../dmf-env
bin/run-playbook.sh hetzner-arm ../dmf-infra/k3s-lab-bootstrap/playbooks/300-k3s.yml

# Direct kubectl (DON'T DO THIS)
kubectl get pods  # Will fail — no local kubeconfig wired up
```

## Codex-Specific Notes

- **When reviewing dmf-infra:** Check for hardcoded paths, broken heredocs, missing idempotency guards
- **When reviewing dmf-cms:** Check for design system compliance, TypeScript safety, query hook usage
- **When analyzing errors:** Read from the bottom up (the bottom usually has the root cause)
- **When suggesting refactors:** Verify the change works locally first (ask for a --check run)
