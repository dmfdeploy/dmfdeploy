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
  the [Unified App-Admin Helper Plan v3](../../plans/dmf-unified-app-admin-helper-plan.md).
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
- `docs/plans/dmf-pre-bao-bootstrap-secrets-design.md` §3
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
     `docs/reviews/dmf-passkey-invitation-policy-alignment-survey.md` § next-steps.

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

## Moved from the ADR on 2026-10-23

### Decision item 4 (email convention), full text

4. **Per-app local-admin email convention (amendment 2026-05-28).** The
   email stored at `secret/apps/<app>/admin.email` and materialised into
   each app's break-glass User row MUST follow the synthetic per-app,
   per-env pattern:

   ```
   <app>-<dmf_env_id>@<cert_manager_cluster_domain>
   ```

   Authentik keeps its bootstrap-convention email `akadmin@<base-domain>`
   (per the sanctioned exception above; akadmin is the Authentik admin
   identity, not the human's OIDC identity).

   **Why the synthetic pattern is binding (not just the username).** The
   operator's real email is `authentik_bootstrap_passkey_email` — the
   day-to-day OIDC identity. App social_auth pipelines key on email for
   account linking:
   - NetBox's default `SOCIAL_AUTH_PIPELINE` includes
     `social_core.pipeline.social_auth.associate_by_email` (see
     `roles/stack/operator/netbox/templates/values.yml.j2:32`).
   - Forgejo's OAuth2 `account_linking: auto` (set in the chart values
     under `gitea.config.oauth2_client.ACCOUNT_LINKING`) merges by email.
   - AWX's default SAML pipeline matches via `associate_by_email`
     unless the env overrides `SOCIAL_AUTH_PIPELINE` (D3 implementation
     `dmf-infra@c426dc0` is the SAML-pipeline analogue).

   When the break-glass User row carries the operator's email, the
   pipeline silently merges the operator's first OIDC sign-in INTO the
   break-glass row — username stays `<app>-break-glass` but the profile,
   social_auth link, and role bindings become the operator's. The
   break-glass account is now compromised AND the operator is being
   used routinely (C4 violation in spirit). Live evidence: see the [archive record](0024-two-identity-admin-model.md).

   Adoption mechanics:
   - **Seed (`dmf-env/bin/bootstrap-secrets.sh seed-bao`)** writes the
     canonical pattern to `secret/apps/<app>/admin.email` for every
     non-Authentik app at first seed AND auto-heals legacy values
     (the operator email, empty string, or `admin@example.com`) on
     re-seed. The fix landed 2026-05-28.
   - **Role defaults** (`netbox_superuser_email`, `awx_admin_email`,
     `forgejo_admin_email`) derive the same pattern from `dmf_env_id +
     cert_manager_cluster_domain` when `vault_<app>_*_email` is unset.
     The previous fallback to `vault_bootstrap_admin_email` is removed;
     reintroducing it requires amending this ADR. The fix landed
     2026-05-28.

   - Live-state remediation for already-deployed envs: see the [archive record](0024-two-identity-admin-model.md).

### Consequences

- **Positive** — Codifies what was already implicit. New playbooks have a
  single answer for "what is the admin username/password fallback chain?"
- **Positive** — Replaces ~28 lines of inline K8s-Secret reading in
  `awx-integration` with a 12-line `include_role` call; same pattern in
  `697-cms-awx-token`.
- **Positive** — Resolves the wrapper-vs-cluster-password drift class for
  AWX without requiring fresh rollout of envs that may drift in future.
- **Negative** — Adds one new role and a small amount of indirection. The
  helper's K8s-Secret scope means it doesn't help NetBox or Forgejo;
  those apps stay on their OpenBao-read patterns (no regression — they
  were never broken).
- **Neutral** — Greenfield envs (`<env>` and future wizard-generated
  envs) see the same effective behaviour: helper resolves the K8s Secret,
  which carries the wizard-set values, identical to the prior vault-only
  chain.

#### Enforcement

Two backend-specific helper roles split on **where the credential lives**,
not on lifecycle. Each is the canonical implementation for its backend.
All tasks touching passwords carry `no_log: true`; both helpers satisfy
ADR-0007 (env-var-via-stdin pattern, no argv exposure).

##### K8s-Secret backend: `common/admin-identity-resolve`

For apps whose local admin credentials live in a Kubernetes Secret
(currently only AWX, via `<instance>-admin-password`). Reads via
`kubernetes.core.k8s_info` with `kubeconfig: /etc/rancher/k3s/k3s.yaml`.

Consumer list: see the [archive record](0024-two-identity-admin-model.md).

##### OpenBao backend: `common/app-admin-facts` (two modes)

For apps whose local admin credentials live in OpenBao at
`secret/apps/<app>/admin`. Pre-condition: caller must have included
`common/openbao-session` (`mode: operator`) earlier in the same play;
`app-admin-facts` consumes `_openbao_session_pod` +
`_openbao_session_client_token` from play scope. Two modes:

- **`materialize`** (default, original behaviour) — read-or-generate-
  and-write. Used at install time to seed `secret/apps/<app>/admin`.

- **`live-read`** (new 2026-05-24, PR 1b of the Unified Helper Plan) —
  read-only. Used at runtime/provisioning. **Source-atomic** fallback:
  each candidate layer must supply BOTH `username` AND `password` or
  the layer is rejected. Resolution order: OpenBao → paired
  `app_admin_fallback_candidates` list → scalar
  `app_admin_fallback_username`/`_password` → empty (`<prefix>_source:
  no-fallback`). Never writes, never generates, never emits
  `<prefix>_email`.

##### Code locations that intentionally do NOT use either helper

- NetBox / netbox-sot roles — read `secret/apps/netbox/runtime` for
  DB / Valkey / superuser-API-token material. Runtime/data secrets,
  not admin identity; out of scope for both helpers. A future
  `common/app-runtime-facts` sibling could address the bespoke
  per-role runtime-read pattern, but that is a separate design
  problem.
- `roles/stack/operator/awx/tasks/main.yml` install path — admin
  password sync via `awx-manage update_password`. Not identity
  resolution; tangential.
- `playbooks/verify-oidc-admin-bridge.yml` — reads a single-token K8s
  Secret (`AUTHENTIK_BOOTSTRAP_TOKEN`), not a username/password pair.
  Both helpers expect paired credentials; a future
  `common/k8s-secret-key-resolve` for single-key lookups is deferred
  until a second use case appears.
