# ADR-0024 archive: Two-identity admin model + live-state read for K8s-Secret-backed admins

This file holds material moved out of [ADR-0024](../../decisions/0024-two-identity-admin-model.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Context (continued)

The retired `hetzner-arm` and `aliyun-123` envs had previously exhibited
admin-username drift between cluster state and role defaults (App Admin
Drift Audit 2026-05-14). Those clusters are now torn down, so no live drift
envs exist today. The Path 3 "live-state read" pattern was however still
worth codifying for two reasons: (a) it eliminates a class of failure where
re-running a wrapper script regenerates `vault_*` material that doesn't
match what the app was created with, and (b) the existing inline pattern
in `roles/stack/operator/awx-integration/tasks/main.yml` was the only place
in the tree that already did it, ad hoc, and only for the password.

ADR-0024 was reserved on 2026-05-17 in the Aliyun-123 Lifecycle-Configure
Follow-Ups Plan §B.1 anticipating exactly this codification.

## Alternatives considered

- **Fresh rollout of any drift env.** Heavy. Rejected as the *only* path
  because it leaves drift latent and forces a destructive recovery every
  time wrapper-exported `vault_*` material diverges. Not precluded by
  this ADR; just made optional.
- **Inline live-state reads per role.** Replicates the AWX-integration
  pattern N times. Rejected on DRY grounds; the helper centralises the
  ADR-0007 compliance (no_log, no argv) too.
- **Read live state in role defaults.** Would make every role default a
  runtime cluster dependency. Rejected because greenfield + tests should
  not require a running cluster to evaluate defaults.
- **Generalise the helper to read OpenBao too.** Plausible, and would
  let NetBox + Forgejo opt into the same abstraction. Initially
  deferred on ADR-0007 grounds. **Superseded 2026-05-24 by
  [ADR-0028](../../decisions/0028-identity-and-authority-chain.md)** and realised by
  the [Unified App-Admin Helper Plan v3](../../plans/DMF%20Unified%20App-Admin%20Helper%20Plan%202026-05-23.md).
  Implementation landed in `dmf-infra` 2026-05-24 as PR 1a / 1b / 2 /
  3 (`30dfad5`, `52b261d`, `bc6699b` + `2e13cb3`, `f74533b`). The
  kubectl-exec / bao-CLI / stdin pattern composes cleanly across
  `common/openbao-session` + a generalised `common/app-admin-facts`
  with a new `live-read` mode; the originally-cited ADR-0007 concern
  is resolved by clarifying that task-scoped Ansible `environment:`
  blocks are the canonical pattern (not argv-visible). See ADR-0028
  D1 / D5 and the architecture doc's §ADR-0007 reading for the
  current binding stance. The live-read mode implements
  source-atomic resolution — each fallback layer must supply BOTH
  username and password or the layer is rejected — eliminating
  cross-layer username/password mixing of the kind the pre-helper
  inline patterns silently permitted.

## Cross-references

- ADR-0007 — secrets never in argv. Helper compliance.
- ADR-0010 — `run-playbook.sh` sanctioned entry.
- ADR-0021 — OpenBao AppRole reconciler identity. Adjacent identity ADR.
- `docs/plans/DMF Pre-Bao Bootstrap Secrets Design 2026-05-08.md` §3
  — design source ("One shared bootstrap admin identity").
- `docs/plans/DMF App Admin Account Drift Audit and Realignment Plan 2026-05-14.md`
  — drift catalog from the retired-cluster era.
- `docs/handoffs/DMF Two-Identity Admin Model Implementation Handoff 2026-05-22.md`
  — implementation handoff (the helper's scope ended up narrower than
  the handoff anticipated because NetBox + Forgejo turned out to be
  OpenBao-backed, not K8s-Secret-backed).

## Context — survey and fix commits (moved from the ADR)

A wider survey confirmed this was the only role-level divergence; the same
class of bug existed in `698-cms-netbox-forgejo-tokens.yml` (literal `dev`
fallback for Forgejo). Narrow PR1 fixes landed in `dmf-infra@142f819`
(697) and `dmf-infra@4f7f505` (698) the same day.

## Decision item 4 (amendment 2026-05-28) — worked examples (moved from the ADR)

   Examples on env `<env>` (`cert_manager_cluster_domain =
   e2e.dmf.test`):

   - `netbox-<env>@e2e.dmf.test`
   - `forgejo-<env>@e2e.dmf.test`
   - `awx-<env>@e2e.dmf.test`
   - `grafana-<env>@e2e.dmf.test`
   - `zot-<env>@e2e.dmf.test`

## Decision item 4 (amendment 2026-05-28) — live evidence (moved from the ADR)

Observed live on `<env>`
   2026-05-28: NetBox break-glass row showed `Username =
   netbox-break-glass`, `Full Name = <full-name>`, `Email = <redacted-email>`,
   `Superuser = ✓`, with the `(netbox-break-glass, oidc, <full-name>)`
   UserSocialAuth row attached.

## Decision item 4 (amendment 2026-05-28) — live-state remediation for deployed envs (moved from the ADR)

   - **Live-state remediation for already-deployed envs.** Updating
     `secret/apps/<app>/admin.email` does NOT propagate into the live
     app's User row (the chart's create-superuser job only runs at
     first deploy). Existing envs need a one-shot per-app email update
     via the app's API/manage.py plus deletion of any
     `(<app>-break-glass, oidc, <operator-sub>)` UserSocialAuth row
     that the email-collision hijack created. The procedure for
     `<env>` (run interactively on 2026-05-28) is captured at
     `docs/reviews/DMF Passkey Invitation Policy Alignment Survey
     2026-05-28.md` § next-steps.

## Enforcement — K8s-Secret backend consumers (moved from the ADR)

Consumers:

- `roles/stack/operator/awx-integration/tasks/main.yml` — gated on
  `awx_integration_read_admin_password_from_cluster` (default `true`).
- `playbooks/697-cms-awx-token.yml` — always runs (no gate); 697 needs
  to work across both greenfield and any future drift state.

## Enforcement — OpenBao backend, materialize consumers (moved from the ADR)

  Consumers (as of 2026-05-24):
  - `playbooks/vertical-security/110-authentik.yml` × 2
    (`secret/apps/authentik/admin` and `secret/apps/authentik/breakglass`)
  - `playbooks/vertical-security/191-zot-oidc.yml` (`secret/apps/zot/admin`)

## Enforcement — OpenBao backend, live-read consumers (moved from the ADR)

Consumers (as of 2026-05-24):
  - `playbooks/698-cms-netbox-forgejo-tokens.yml` (Forgejo half;
    NetBox half deliberately stays on the bespoke OpenBao read because
    it targets `secret/apps/netbox/runtime`, not `/admin`)
  - `roles/stack/operator/forgejo-bootstrap/tasks/main.yml`
