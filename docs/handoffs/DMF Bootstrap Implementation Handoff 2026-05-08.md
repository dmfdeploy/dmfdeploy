# DMF Bootstrap Implementation Handoff

**Date:** 2026-05-08
**Status:** Implementation handoff — design landed, no code written yet
**Audience:** A freshly cleared agent picking up the bootstrap refactor
**Predecessor work:** Plan revisions 1–5 (2026-05-07 → 2026-05-08), design revisions 0–1 (2026-05-08), two peer reviews (one Codex consistency check, one compliance review against the security framework plan)

## Why you are here

The DMF platform bootstrap is being refactored end-to-end:

1. The Ansible lifecycle is split into **Bootstrap Provision** (install platform-local capabilities in vanilla form), **Bootstrap Configure** (wire apps together into one facility control plane), and **Bootstrap Verify** (real readiness gates).
2. The **pre-Bao secret pipeline** is being formalized: a SOPS/age-encrypted bundle outside any git tree, exported through a new `dmf-env/bin/bootstrap-secrets.sh` script, seeded into OpenBao between pre-seed and post-seed provision.
3. A **shared bootstrap admin identity** (`vault_bootstrap_admin_*`) replaces per-app `default('changeme')` / `default('admin')` fallbacks and the literal `dev`-username + `changeme`-password Forgejo pattern across all Layer 6 roles.

Two design docs are now mutually consistent and implementer-ready. **No code has been written yet.** Your job is to implement.

## Read these in order before doing anything

The repo's standard boot ritual (in [`CLAUDE.md`](../../CLAUDE.md)) applies — run it first. Then, specifically for this work:

1. [`docs/plans/DMF Bootstrap Provision Configure Split Plan 2026-05-07.md`](../plans/DMF%20Bootstrap%20Provision%20Configure%20Split%20Plan%202026-05-07.md) — Rev 5. The lifecycle split, role refactors, audit, fix list, acceptance criteria.
2. [`docs/plans/DMF Pre-Bao Bootstrap Secrets Design 2026-05-08.md`](../plans/DMF%20Pre-Bao%20Bootstrap%20Secrets%20Design%202026-05-08.md) — Rev 1. The secret pipeline canonical design.
3. ADRs (cited throughout both docs, mandatory): `0007-secrets-never-in-argv`, `0008-openbao-secrets-architecture`, `0009-shamir-dr-model`, `0010-run-playbook-as-sanctioned-entry`, `0011-auto-unseal-tradeoff`, `0012-configure-stage-distinct-from-provision`, `0016-awx-control-node-ssh-via-cloud-init-and-openbao`.
4. [`dmf-infra/docs/security-compliance-framework-plan.md`](../../dmf-infra/docs/security-compliance-framework-plan.md) — control-register baseline.
5. [`dmf-infra/docs/openbao-bootstrap-security-model.md`](../../dmf-infra/docs/openbao-bootstrap-security-model.md) — separation of duties (root-token disposal, ops-admin, ESO AppRole).
6. [`dmf-infra/docs/SECURITY-REMEDIATION-GUIDE.md`](../../dmf-infra/docs/SECURITY-REMEDIATION-GUIDE.md) and `dmf-infra/docs/archive/SECURITY-REMEDIATION-N1-AUDIT-LEAK.md` — prior remediations and audit-log sensitivity rules.
7. [`docs/reviews/dmf-move1-gate2-ssh-credential-incident-2026-05-05.md`](../reviews/dmf-move1-gate2-ssh-credential-incident-2026-05-05.md) — read this. A real ed25519 key was committed in plaintext; full Path-Y redeploy followed. Do not let it happen again.

## What "done" looks like

The plan and the design each end with their own Acceptance Criteria. Cross-cutting summary:

- A fresh reader can answer "what installs apps?" and "what wires apps together?" from wrapper names alone.
- No Layer 6 app boots with a literal default credential. The grep gate in the audit section returns zero credential-context hits.
- All enabled apps with a local admin surface use the same `vault_bootstrap_admin_*` identity. The same human, via OIDC, is admin/superadmin everywhere it makes sense.
- The encrypted bundle lives at `${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>.sops.yaml`, **outside any git tree**. `git ls-files` in `dmf-env` returns no `.sops.yaml` matches.
- Re-running bootstrap does not silently rotate `vault_k3s_token`, provider tokens, or the shared bootstrap admin password.
- Existing behavior is preserved unless a change is explicitly called out.

## Architectural decisions already made — do not relitigate without strong cause

These are settled in the docs (search for `RESOLVED 2026-05-08` in either):

1. **Three-phase fresh-bootstrap flow**: Phase A (`init`/`doctor`) → Phase B (`bootstrap-provision-pre-seed.yml` through OpenBao+ESO) → Phase C (`seed-bao`) → Phase D (`bootstrap-provision-post-seed.yml`, Layer 6 install) → Phase E (`bootstrap-configure.yml`) → Phase F (`bootstrap-verify.yml`). Orchestrated from `dmf-env`. `lifecycle-provision.yml` remains an Ansible compatibility wrapper for already-seeded clusters; **it is not the canonical first-run path**.
2. **Bundle outside dmf-env**. `dmf-env` is private, no-remote, operator-local, treated as temporary. The bundle's path is `${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>.sops.yaml`, default a sibling of the OpenBao break-glass material under the operator's secure JuiceFS mount. The script must refuse to run if the resolved bundle directory is inside any git working tree.
3. **SOPS + age encryption**. Public recipients in `dmf-env/.sops.yaml`. Private key in operator Keychain. ADR-0011 layered laptop-state risk is explicitly accepted, scoped to experiment phase (ADR-0004).
4. **Shared bootstrap admin** (`vault_bootstrap_admin_username/email/password`) is identical across every Layer 6 app with a local admin surface. App-local Bao paths (`secret/apps/<app>/admin`) are compatibility copies — same value as `secret/platform/bootstrap_admin`.
5. **AWX control-node SSH key is NOT in the generic bundle in v1**. A dedicated `dmf-env` operator-bootstrap step seeds `secret/apps/awx/control_node_ssh`. The AWX consumer side (today reads only operator-local file) needs a read-from-Bao path.
6. **seed-bao collision behavior**: missing path → write; same value → no-op; differing **platform** path → fail and require explicit `rotate`; differing **app-local admin** path → fail and require an explicit app-account migration play that updates both the app's user and the Bao value. Never silently overwrite app-local admin paths.
7. **Authentik `akadmin`** is not silently renamed or deleted on re-bootstrap. The role creates/verifies the new shared admin first; deprecation of `akadmin` is a separate hardening step (timing is plan Open Q9).
8. **Bao-first wrapper lookup**. After seed, repeated runs of `bootstrap-secrets.sh export-vars` return the same `k3s_token` and `bootstrap_admin.password`. Silent rotation of stable IDs is the bug being fixed.

## Recommended implementation order

The plan and design each have phase-mapping tables. The pragmatic execution order:

**Tier 1 — static, no cluster touched**

1. Phase 0 baseline: capture current `--list-tasks` output of `lifecycle-provision.yml` for diff comparison after refactor.
2. Design Step 1 — scaffolding: `dmf-env/.sops.yaml`, `dmf-env/bin/bootstrap-secrets.sh` skeleton, `${DMF_BOOTSTRAP_BUNDLE_DIR}` directory creation logic, git-tree refusal check.
3. Design Step 2 — implement `init`, `doctor`, `export-vars`. Acceptance: repeated `export-vars` returns the same k3s token and admin password; no secret in stdout/logs/git diff; encrypted bundle decrypts only with the authorized age key.
4. Plan Phase 1 — entrypoint scaffolding: add `bootstrap-provision-pre-seed.yml`, `bootstrap-provision-post-seed.yml`, `bootstrap-configure.yml`, `bootstrap-verify.yml`. Make `lifecycle-provision.yml` a compatibility wrapper. Correct `site.yml` comments.

**Tier 2 — touches the live cluster (use the cluster-access skill first)**

5. Design Step 4 — `seed-bao` plus the small generic dmf-infra seeding play. Acceptance: platform paths exist in Bao after OpenBao readiness; idempotent on identical reruns; fails on differing platform/app-local-admin paths.
6. Plan Phase 2 — move existing whole-playbook imports (`vertical-security/191-zot-oidc.yml`, `691-netbox-sot.yml`, `692-forgejo-bootstrap.yml`, `693-awx-integration.yml`, `694-born-inventory.yml`, the three CMS-token plays) into `bootstrap-configure.yml`. Move smoke/E2E checks into `bootstrap-verify.yml`.
7. Plan Phase 3 + Design Step 5 — split mixed app roles and remove every `default('changeme')`, `default('admin')`, `dev` literal. App targets: `forgejo`, `forgejo-bootstrap`, `netbox`, `netbox-sot`, `grafana` (base/), `awx`, `awx-integration`, `zot`. One role at a time; preserve current behavior between commits. Run the grep gate after each role.
8. Design Step 6 — Bootstrap Configure OIDC admin seeding (Authentik first, then app providers).
9. Specific Fix #19 — extend the Kubernetes audit policy to cover `secret/platform/*` and `secret/apps/*/admin` at Metadata level. Add the verify-stage assertion.
10. Plan Phase 5 — clean stale paths (operator-local `<home>/...`, `/Volumes/...`), retire `lifecycle-configure.yml` or repoint it.

## Skills to invoke

These skills are pre-registered. Use them, don't reinvent.

- **`dmf-cluster-access`** — required before any kubectl, ansible-playbook, or `run-playbook.sh` invocation against the live `hetzner-arm` cluster. Encodes how to inspect, change, and recover state authoritatively.
- **`dmf-openbao-unseal`** — required if OpenBao is sealed when you start work. 3-of-5 Shamir quorum from JuiceFS shares 1+2 + Keychain share 3, executed via `dmf-env/bin/unseal-openbao.sh`. Do not improvise.
- **`dmf-cms-build-and-release`** — only if you touch `dmf-cms` (you probably won't during bootstrap work).

## Open questions that gate specific phases

These are in the plan/design but worth surfacing here as a checklist:

- **Plan Q2** (rotation timing): resolve before declaring Phase 4 complete. Recommendation in the question — keep rotation out of bootstrap, document in `lifecycle-operate.yml` + maintenance runbook in `dmf-env/docs/`.
- **Plan Q9** (Authentik `akadmin` deprecation timing): resolve before Phase 3 lands the Authentik role change. Recommendation — explicit hardening play in `lifecycle-operate.yml` + Bootstrap Verify warning.
- **Plan Q11 / Design Q7** (audit-policy verification ownership): resolve when implementing Specific Fix #19. Recommendation — `bootstrap-verify.yml` assertion plus day-zero documentation check.
- **Plan Q1, Q3, Q4** (cosmetic — `lifecycle-configure.yml` retention, monitoring base ordering, `219-host-verify` rename): defer or decide opportunistically.
- **Plan Q10 / Design Q6** (per-secret data classification): defer to a follow-up framework-plan doc; do not absorb classification work into this implementation.
- **Design Q5** (wizard credential reveal UX): defer until DMF Console wizard work begins.

## Operational guardrails

- **ADR-0007**: never put secrets in argv, env, `/tmp` (without no_log + cleanup), transcripts, or screenshots. Stdin transport only (`printf '%s' "$x" | tool`).
- **ADR-0010**: live runs through `dmf-env/bin/run-playbook.sh hetzner-arm <playbook>`. Direct `ansible-playbook` invocations are reserved for `--syntax-check` and `--list-tasks` (static).
- **ADR-0011**: laptop-state risk acceptance is scoped to experiment phase (ADR-0004). Do not normalize the layered risk; revisit if the project goes public/OSS or onboards external collaborators.
- **gitleaks pre-commit**: runs on every staged commit (see `.githooks/pre-commit`). The encrypted bundle is outside any tree, so this should not fire on it. **Verify with a throwaway commit before assuming a clean run.**
- **Pre-commit hooks per clone**: run `bin/install-hooks.sh` once after a fresh clone. The hook keeps `STATUS.md` fresh on commit.
- **Public-publish gates** (see `docs/handoffs/DMF Public Publish Readiness Handoff 2026-05-07.md`): four critical gates before any GitHub push. **`dmf-env` must stay private.** Run `bin/scrub-public-repos.sh` before push.

## Cross-repo coordination

| Repo | Touched by this work? | What |
|---|---|---|
| `dmfdeploy` (umbrella) | Docs only | Update STATUS.md HUMAN-START section; add a follow-up handoff if you stop mid-implementation. |
| `dmf-env` | Yes (private, operator-local) | `bin/bootstrap-secrets.sh`, `.sops.yaml`, optional fresh-bootstrap orchestrator script, `docs/initial-data-gathering.md` updates. Local commits are expected — treat like any private repo. **Do not add a remote** without explicit user approval; the repo has none today. **Do not commit secret values** (the bundle lives outside the tree, so this is naturally avoided). "Treated as temporary" means bundle persistence cannot depend on the clone surviving, **not** "don't commit." |
| `dmf-infra` | Yes | New wrappers (`bootstrap-provision-pre-seed.yml`, `bootstrap-provision-post-seed.yml`, `bootstrap-configure.yml`, `bootstrap-verify.yml`); role refactors (forgejo, netbox, grafana, awx, awx-integration, zot, authentik); generic seed play if implemented dmf-infra-side; audit-policy update. |
| `dmf-runbooks` | No | Owns workload lifecycle (catalog launchers via AWX). Do not put media-launch logic into bootstrap. Bootstrap may **publish** AWX templates but must not invoke them. |
| `dmf-cms` | No (until OIDC client wiring) | Console is OIDC-only; no first-boot credential. The OIDC client wiring lands in Bootstrap Configure, not Provision. |
| `dmf-central`, `dmf-media` | No | Out of scope. |

## Test and verification

- **Static**: `ansible-playbook --syntax-check` and `--list-tasks` against each new wrapper. Direct invocation is OK for these flags only.
- **Static credential gate**: ```grep -rnE "default\(\s*['\"](changeme|admin|password|dev)['\"]" dmf-infra/k3s-lab-bootstrap/roles/ | grep -vE 'acme_email|@example\.com'``` returns zero credential-context hits.
- **Static bundle-not-in-git gate**: `git ls-files` in `dmf-env` returns no matches for `*.sops.yaml` or any `secrets/` path.
- **Live**: `bootstrap-verify.yml` covering k3s Ready, ESO `ClusterSecretStore` Ready, OpenBao paths populated, audit-policy assertion (Specific Fix #19), local admin login works where supported, OIDC operator identity has admin/superadmin in every supported app, no Layer 6 app booted with a default credential.
- **Compliance verify**: framework-plan Phase 1 deliverables — secret artifact hygiene, separation of duties, no fallback creds.

## Things you should NOT do without asking first

- Do not move `nmos-cpp` back into `dmf-infra` (ADR-0014/0016).
- Do not commit anything to public repos without running the scrub script.
- Do not invoke `ansible-playbook` directly for live runs (use `run-playbook.sh`).
- Do not amend other agents' commits — create new commits.
- Do not rebase/force-push shared branches.
- Do not put plaintext secrets anywhere on disk outside `${DMF_BOOTSTRAP_BUNDLE_DIR}` (which is encrypted) or OpenBao.
- Do not declare a phase complete if its acceptance criteria are not all green — particularly the credential-grep gate.
- Do not commit the encrypted bundle to **any** repo. Bundle persistence comes from operator-local secure storage, not git.
- Do not relitigate the architectural decisions in the "do not relitigate" list without surfacing the rationale to the user first.

## Coordination model with peer agents

This work has been reviewed by Codex (peer agent) twice already. Expect the same pattern during implementation:

- Codex may do read-only reviews of your in-flight work and report back through the user.
- Both docs carry explicit `RESOLVED YYYY-MM-DD` markers — these are settled positions, not invitations to revisit.
- If a peer review surfaces a real issue that requires a doc change, bump the revision header and add a dated revision note (do not silently rewrite). Existing examples: plan Rev 1–5, design Rev 0–1.
- If you have a strong case to overturn a `RESOLVED` decision, escalate to the user before editing the doc.

## End-of-session checklist

When you stop work — whether mid-task or done:

1. Run `bin/generate-status.sh` to refresh STATUS.md.
2. If you changed shared state (cross-repo decisions, in-flight work another agent might trip over), update STATUS.md `<!-- HUMAN-START -->` section.
3. If you stopped mid-implementation, write a follow-up handoff at `docs/handoffs/DMF Bootstrap Implementation Handoff <date>.md` describing what's done, what's in progress, and what's still queued.
4. If you committed, the pre-commit hook will run `gitleaks` and refresh STATUS.md automatically. Don't bypass it.
5. Don't `git push` to any public remote without running `bin/scrub-public-repos.sh` first.

## Quick environment sanity check

Before your first edit, verify environment matches expectations:

```bash
# Cluster context (DMF runs on hetzner-arm; never confuse with the local RPi homelab)
kubectl config current-context

# Umbrella status fresh
cd <repos>/dmfdeploy && git fetch && git pull

# Bundle directory exists / is reachable / is NOT inside any git tree
echo "${DMF_BOOTSTRAP_BUNDLE_DIR:?DMF_BOOTSTRAP_BUNDLE_DIR not set}"
test -d "${DMF_BOOTSTRAP_BUNDLE_DIR}" || echo "directory missing — bootstrap-secrets.sh init will create it"
( cd "${DMF_BOOTSTRAP_BUNDLE_DIR}" 2>/dev/null && git rev-parse --is-inside-work-tree 2>/dev/null && echo "FAIL: bundle dir is inside a git tree" || echo "OK: not in git" )

# Pre-commit hook installed (per-clone)
git config core.hooksPath
```

If any of these surprise you, stop and ask the user before proceeding. The cost of pausing is low; the cost of bootstrapping the wrong cluster is large.
