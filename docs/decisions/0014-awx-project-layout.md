# ADR-0014: AWX project layout — hybrid (launchers + mirrored source repos)

**Status:** Accepted
**Date:** 2026-05-04
**Deciders:** @<handle>, planning session with Claude

## Context

AWX runs Ansible playbooks sourced from "projects" (AWX terminology),
each of which SCM-syncs from a git URL. Move 2 established an in-cluster
Forgejo pattern: the `awx-integration` role
(`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/`)
publishes runbook playbooks to a `dmf-runbooks` Forgejo repo, and AWX
SCM-syncs that repo as a project. This worked for one self-contained
runbook (`eso-openbao-health-check`). The catalog model (ADR-0013)
needs Configure playbooks that `import_role` from media-function
source repos (`dmf-media` initially), so the single-`dmf-runbooks`-
repo pattern doesn't generalise: copying roles into runbooks creates
drift; symlinking doesn't survive SCM sync.

## Decision

AWX runs **multiple projects**, all SCM-synced from in-cluster Forgejo:

- **`dmf-runbooks`** — operator-facing thin launcher playbooks. A
  `launch-<key>.yml` is a small wrapper (≤10 lines) that delegates
  to the canonical role from the corresponding source-repo project.
  This is the auditable, operator-readable surface.
- **`dmf-media`** — Forgejo mirror of the canonical
  `dmf-media` repo. Provides Layer 4–5 roles and the per-function
  Configure/Finalise playbooks.
- **`dmf-infra`** — Forgejo mirror of the canonical `dmf-infra`
  repo. Provides Layer 2–3 + Layer 6 roles and shared common roles.
- (Additional projects added when new source repos appear, e.g.
  `dmf-central` for federation work.)

In-cluster Forgejo mirrors are populated by mirror-push from the
canonical remotes (Forgejo's built-in mirror feature, configured in
`692-forgejo-bootstrap.yml`'s repo provisioning step). AWX is
configured with `roles_path` (per AWX inventory or per job-template
extra-vars) so launcher playbooks in `dmf-runbooks` can resolve roles
from the mirrored source-repo projects.

Job templates reference launcher playbook paths (e.g.
`dmf-runbooks/launch-nmos-cpp.yml`), keeping the operator-facing AWX
UI uncluttered while the heavy lifting stays canonical.

## Consequences

- **Positive** — operator-facing surface stays small. `dmf-runbooks`
  is auditable as a single repo of thin wrappers; the diff per entry
  is a 5–10 line file.
- **Positive** — source repos remain canonical. No copy/sync of roles
  into runbooks; no drift.
- **Positive** — survives the dmf-central federation transition: when
  a central Forgejo replaces per-cluster mirrors, AWX SCM URLs change
  but project structure does not.
- **Positive** — multi-cluster scenarios reuse the same pattern; each
  cluster's AWX has the same project layout, all syncing from central
  Forgejo.
- **Negative** — AWX projects multiply with source repos. Each new
  project requires a deploy step (Forgejo mirror config + AWX project
  add via the `awx-integration` role).
- **Negative** — `roles_path` configuration is one more place to keep
  aligned with project layout. A misconfigured path means launcher
  playbooks fail at role-resolution time, not at job-template-create
  time, so misconfigurations surface late.

## Alternatives considered

- **Option A — single `dmf-runbooks` repo with role copies.** Rejected
  — role drift across copies becomes unmanageable as the catalog grows
  beyond the first few entries.
- **Option B — one project per source repo, no `dmf-runbooks` layer.**
  Rejected — operator-facing audit needs a thin launcher layer; raw
  role-invocation from an AWX job template makes the operator-facing
  diff harder to review and conflates "what's published for operator
  use" with "what's available in the source tree".

## Enforcement

The Move 1 task spec implements the first multi-project AWX setup
(`dmf-runbooks` + `dmf-media` + `dmf-infra`). The
`awx-integration` role evolves to manage multiple projects rather than
one. Documented in `docs/architecture/DMF Function Catalog Model.md`
§"AWX wiring".
