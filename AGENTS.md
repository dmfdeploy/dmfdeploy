# AGENTS.md — dmfdeploy umbrella

This is the umbrella repo of the dmfdeploy project: the knowledge base
(`docs/`) and the coordination point for the component repos. The 8 component
repos are siblings under a common parent directory (`../dmf-cms`,
`../dmf-infra`, and so on), not nested here. "DMF" means the EBU Dynamic Media
Facility reference architecture.

## Boot steps

1. `git pull`, run `bin/generate-status.sh`, then read
   `STATUS.digest.local.md` (open `STATUS.local.md` for one section only).
2. Read the tracking issue you claim, comments included. Notes from earlier
   sessions are operator-local, and `docs/handoffs/` is a frozen archive.
3. Skim [docs/decisions/INDEX.md](docs/decisions/INDEX.md) and apply any ADR
   that fits your task.
4. Run `git status` in each component repo you will touch. Ask before you
   modify one with uncommitted changes.
5. Run `bin/install-hooks.sh` once per clone.

## Where things live

| Question | Look in |
|---|---|
| What is this and why? | `docs/THESIS.md`, `docs/GLOSSARY.md`, `docs/architecture/DMF Platform Plan.md` |
| What is frozen or undecided? | `docs/decisions/architectural-commitments-v1.md`, `docs/OPEN-QUESTIONS.md` |
| What is the active task? | [GitHub Issues](https://github.com/dmfdeploy/dmfdeploy/issues) |

## Rules that are easy to miss

- Edit docs here and code in the component repos. Do not move files between
  component repos without checking.
- Keep public text free of real IPs, hostnames, private repo names and env
  ids. Use `dmf.example.com` and `<placeholder-name>` values.
- Author skills only in `.agents/skills/`. The `.claude/skills/` and
  `.qwen/skills/` views are generated.
- On a feature branch, run `bin/mxl-sync-check.sh` before you build.
- Never use the local homelab cluster. The current env is in `STATUS.local.md`.

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
   Discussions first); STATUS.md = committed notes; STATUS.local.md = live repo snapshot.
<!-- WORKING-MODEL-BLOCK-END -->
