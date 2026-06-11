# QWEN.md — dmfdeploy umbrella

Companion to [CLAUDE.md](CLAUDE.md), tuned for Qwen Code. Same boot ritual,
same workspace, same skills — Qwen doesn't have Claude's `/skill-name`
invocation, so "using a skill" here means **reading the relevant
`.claude/skills/<name>/SKILL.md` as authoritative guidance when you start
that kind of work**, then following its sections like instructions.

## Boot ritual (every session, every time)

Before touching any DMF repo:

1. `cd "$DMFDEPLOY_UMBRELLA" && git fetch && git pull` (umbrella)
2. `bin/generate-status.sh` — refreshes [STATUS.md](STATUS.md), then read it
3. Read the most recent file in [docs/handoffs/](docs/handoffs/) — prior session intent
4. Skim [docs/decisions/INDEX.md](docs/decisions/INDEX.md) — apply any ADRs relevant to your task
5. Run `git status` in any sub-repo you're about to touch. **Ask the user
   before modifying any sub-repo with dirty (uncommitted) state.**
6. If you're going to run cluster ops, retrieve secrets, or release dmf-cms,
   read the §0 Secrets Discipline section of the relevant skill (see below)
   **first** — it has hard rules about argv, /tmp, transcripts, and what
   patterns leak.

End-of-session: if you changed shared cross-repo state, update the
`<!-- HUMAN-START -->` section of [STATUS.md](STATUS.md) before stopping.

## Workspace at a glance

| Path | Role | Stack | State |
|---|---|---|---|
| `dmfdeploy/` (here) | umbrella — docs, decisions, skills | git only | active |
| `dmf-cms/` | Layer 6 — operator console | React 18 + TS + FastAPI | v0.10.0, active |
| `dmf-infra/` | Layers 1–3 + verticals | Ansible + Helm | active, public, generic |
| `dmf-env/` | generic env tooling + Layer 1 | Terraform + Ansible | active; per-env state operator-local (ADR-0035) |
| `dmf-central/` | central services | Ansible | scaffold (Phase 0 step 5) |
| `dmf-media/` | Layers 4–5, catalog metadata | Ansible + Helm | active; `nmos-cpp` landed (Move 1), v2 fns scaffolded |
| `dmf-runbooks/` | Layers 4–5 — AWX launchers | Ansible | active; thin launchers + `nmos-cpp` role |
| `dmf-init/` | Day-0 bootstrap container | React + FastAPI | active (v0.1.x) |
| `dmf-promsd/` | Monitoring — NetBox Prometheus SD | Python | active (ADR-0038) |

For component-specific guidance, read each repo's local `CLAUDE.md` and
`QWEN.md`. They share boot ritual; per-repo specifics differ.

## Skills — when to read each

Qwen reads SKILL.md as documentation. Each skill is structured: the §0
Secrets Discipline (where applicable) is **hard rules**, sections after
that are workflow + decision tree + concrete commands. Read top-to-bottom
when working in that domain.

| Skill | Read this when… | Path |
|---|---|---|
| **dmf-cluster-access** | inspecting/modifying live cluster state, running playbooks, troubleshooting | `.claude/skills/dmf-cluster-access/SKILL.md` |
| **dmf-cms-build-and-release** | bumping version, building, releasing, or pushing dmf-cms images | `.claude/skills/dmf-cms-build-and-release/SKILL.md` |
| **dmf-openbao-unseal** | OpenBao seal-status check or manual 3-share unseal | `.claude/skills/dmf-openbao-unseal/SKILL.md` |

Skills cross-reference each other and the ADRs (`docs/decisions/`). When a
skill says "see ADR-NNNN" or "see sibling skill X", follow the link before
proceeding.

## Architecture decisions (ADRs)

`docs/decisions/INDEX.md` lists the current ADRs (0001–0039 as of 2026-06-04).
Apply the ones relevant to your task. The most consequential for daily work:

- **ADR-0001** — umbrella as docs home; component repos remain independent gits
- **ADR-0002** — two-repo model (public dmf-infra vs private dmf-env)
- **architectural-commitments-v1** — v0.1 committed (closed ADR-0004's experiment
  phase 2026-06-06); the work filter is "runnable + legible to an outsider"
- **ADR-0005** — dmf-cms VERSION as single source of truth
- **ADR-0006** — cluster is the truth, not local kubectl
- **ADR-0007** — secrets never in argv / env / /tmp / AI transcripts
- **ADR-0010** — `bin/run-playbook.sh` is the only sanctioned ansible entry point
- **ADR-0011** — auto-unseal trades Shamir defense-in-depth for operational tolerability (known weakness, accepted in experiment phase)

## Qwen-specific working rules

### Plan mode
- Enter plan mode for any non-trivial task (3+ steps, architectural decisions, new pages, anything touching shared state across repos).
- STOP and re-plan if something goes sideways. Don't barrel through a broken assumption.
- After any correction: update the relevant CLAUDE.md / QWEN.md / ADR / GitHub issue so the lesson sticks.

### Backlog + plan state
- The live backlog is [GitHub Issues](https://github.com/dmfdeploy/dmfdeploy/issues)
  (org board Project #1) — not TODOS.md (retired 2026-06-10), not `docs/agentic/`.
- New work: issue → on-disk spec in `docs/plans/` with `tracking_issue`
  frontmatter → the completing PR closes the issue and flips the frontmatter in
  the same change. Issues win for liveness; frontmatter wins for design state.

### Verification before done
- Never mark a task complete without proving it works.
- For dmf-cms: run `scripts/sync-version.sh --check` and build the frontend (`cd frontend && npm ci && npm run build`); confirm no compile errors.
- For cluster changes: run `bin/unseal-openbao.sh --status` and the relevant playbook with `--check --diff` first; confirm clean.
- For doc changes: run `bin/generate-status.sh --check`,
  `bin/generate-scripts-catalog.sh --check`, and `bin/check-docs.sh`; confirm no
  drift and that plan-doc frontmatter parses (the pre-commit + CI gate rejects it
  otherwise).

### Docker / Colima (dmf-cms builds only)
- All Docker commands target Colima: `DOCKER_HOST=unix://$HOME/.colima/docker-build/docker.sock`
- Colima instance name: `docker-build` (not the default profile)
- Start: `colima start docker-build &` then wait for `docker info` to succeed before invoking docker.

### Git hygiene
- One repo, one purpose per commit. Don't bundle unrelated changes across files.
- Component repos are independent gits — when you change cross-repo state,
  commit each repo separately with related messages so the history is
  navigable.
- The umbrella's pre-commit hook auto-refreshes `STATUS.md` and
  `docs/SCRIPTS.md`; don't bypass with `--no-verify` unless you have a
  reason and document it.

## End-of-session

If you changed cross-repo state (new ADR, scaffold role implementation,
script that other repos will reference), update the `<!-- HUMAN-START -->`
section of [STATUS.md](STATUS.md) with one bullet: what changed, where,
and (if applicable) what's left in flight. The auto-generated parts
refresh next run; the operator notes section is hand-edited and survives.

For lessons learned that should change future-Qwen behavior, update this
file or the relevant skill's SKILL.md.
