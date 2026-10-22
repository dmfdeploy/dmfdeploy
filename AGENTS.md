# AGENTS.md for the dmfdeploy umbrella

This is the umbrella repo of the dmfdeploy project: the knowledge base
(`docs/`) and the coordination point for the component repos. The 8 component
repos are siblings of this repo under a common parent directory (`../dmf-cms`,
`../dmf-infra`, and so on). "DMF" means the EBU Dynamic Media Facility
reference architecture.

## Boot steps

1. `git pull`, run `bin/generate-status.sh`, then read
   `STATUS.digest.local.md` (open `STATUS.local.md` for one section only).
2. Read the tracking issue you claim, comments included. Notes from earlier
   sessions are operator-local, and `docs/handoffs/` is a frozen archive.
3. Skim [docs/decisions/INDEX.md](docs/decisions/INDEX.md) and apply any ADR
   that fits your task.
4. Run `git status` in each component repo you will touch, and ask before you
   modify one with uncommitted changes. Before you change one, read its own
   AGENTS.md and CLAUDE.md: they carry component-scoped rules.
5. Run `bin/install-hooks.sh` once per clone. `STATUS_HOOK_SKIP=1` skips the
   doc gates on commit, but never secret scanning.

## Where things live

| Question | Look in |
|---|---|
| What is this and why? | `docs/THESIS.md`, `docs/GLOSSARY.md`, `docs/architecture/DMF Platform Plan.md` |
| What is frozen or undecided? | `docs/decisions/architectural-commitments-v1.md`, and the open questions page that [docs/README.md](docs/README.md) links |
| What is the active task? | [GitHub Issues](https://github.com/dmfdeploy/dmfdeploy/issues) |

## Rules that are easy to miss

- Before you push any dmfdeploy repo to a public GitHub mirror, read
  `docs/handoffs/DMF Public Publish Readiness Handoff 2026-05-07.md`. Its
  orphan rebase and push-mirror refspec gate keep pre-publish history private.
- `dmf-env` is public. Env material never enters a repository; it lives in the operator-local store (ADR-0035).
  Before you publish, run `bin/dmf-env-public-surface-gate.sh` from the umbrella root. It fails on unlisted paths, banned files, and identity leaks.
- Write in the project voice: [docs/README.md](docs/README.md) links the style guide. Run `bin/check-voice.sh` on every draft; errors block.
- Edit docs here and code in the component repos. Check before you move files between repos.
- Keep public text free of real IPs, hostnames, private repo names and env
  ids. Use `dmf.example.com` and `<placeholder-name>` values.
- Author skills only in `.agents/skills/`. The `.claude/skills/` and
  `.qwen/skills/` views are generated. New skills enter through `_inbox/`.
- On a feature branch, run `bin/mxl-sync-check.sh` before you build.
- Never use the local homelab cluster. Use the env id recorded in
  `STATUS.local.md`, and run `kubectl config current-context` before any
  cluster command.
- Before you retrieve secrets, run cluster operations or release dmf-cms,
  read section 0 of the matching skill in `.agents/skills/`:
  `dmf-cluster-access`, `dmf-openbao-unseal` or `dmf-cms-build-and-release`.
- Keep doc filenames verbatim. Before you rename a doc, update every file that refers to it.
- Before a decision that rests on layer or vertical assumptions, read the canonical doc in `docs/architecture/`.
- Before you stop, record changes to shared state (cross-repo decisions,
  in-flight work) in the pinned Operator notes issue.
- The agentic harness under `docs/agentic/` is mothballed. Its `backlog.yaml`,
  `decisions-open.md` and `issues.yaml` are not live queues; issues are the backlog.

<!-- vale off -->
<!-- WORKING-MODEL-BLOCK-START — generated from umbrella docs/templates/working-model-block.md; do not edit copies, edit the template and run bin/check-working-model-sync.sh -->
## Working model (mandatory)

Canonical: [docs/WORKING-MODEL.md](https://github.com/dmfdeploy/dmfdeploy/blob/main/docs/WORKING-MODEL.md)
in the umbrella repo. The three rules that matter mid-task:

1. **Work starts at an issue** in the canonical backlog
   ([dmfdeploy/dmfdeploy issues](https://github.com/dmfdeploy/dmfdeploy/issues)):
   `component:*`/`workstream:*` labels **always**, plus a milestone **only if
   the work is scheduled** — unscheduled work gets `platform-debt` and no
   milestone (§2). Non-trivial work gets a plan doc in umbrella `docs/plans/`
   with `tracking_issue` frontmatter.
2. **The completing PR auto-closes its issue; you still flip the plan
   frontmatter by hand in that PR.** Reference umbrella issues **fully
   qualified** — `Closes dmfdeploy/dmfdeploy#N` (bare `#N` targets the wrong
   repo); the daily issue-close reconciler honors that ref, cross-repo
   included. Manual close is a fallback.
3. **Never invent a local backlog** (TODO files, ad-hoc trackers). Issues =
   liveness; plan frontmatter = design state; ADRs = decisions (RFC in
   Discussions first); STATUS.md = pointer file (operator notes live in pinned issue #618);
   STATUS.local.md = live repo snapshot.
<!-- WORKING-MODEL-BLOCK-END -->
<!-- vale on -->
