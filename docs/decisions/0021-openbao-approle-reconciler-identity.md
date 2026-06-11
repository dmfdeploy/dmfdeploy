# ADR-0021: OpenBao AppRole reconciliation uses a dedicated bootstrap identity

**Status:** Accepted
**Date:** 2026-05-13
**Deciders:** @<handle> (with Codex analysis)

## Context

The `base/object-storage-credentials` post-seed role needs to reconcile
consumer-declared OpenBao AppRoles and ESO binding records after the root token
has been revoked. Commit `dmf-infra@6f6cee8` correctly moved ACL policy writes
to `policy-reconciler`, but the next live run showed that neither
`ops-admin` nor `policy-reconciler` should create `object-storage-*` AppRoles
or generate their `secret-id`s under the current separation-of-duties model.

The tension is between experiment-phase simplicity and a security model that can
survive later managed-service and flypack scrutiny. Granting AppRole write
capability to either existing identity is faster, but it broadens a standing
credential across duties that should remain separate.

## Decision

Add a dedicated `approle-reconciler` userpass identity for bootstrap-time
AppRole and ESO binding reconciliation. Its initial scope is the
`object-storage-*` AppRoles and their `secret/platform/eso-bindings/object-storage-*`
records only. It must not write ACL policies, read application secret data, or
inherit `ops-admin` app-secret powers. Any future expansion beyond
`object-storage-*` requires an explicit ADR update or successor ADR.

## Consequences

- **Positive** — Preserves NIST 800-53 AC-5 separation of duties: ACL policy
  reconciliation, AppRole reconciliation, and app-secret administration remain
  separate technical duties.
- **Positive** — Gives a cleaner ISO 27001 / managed-service story: a leaked
  bootstrap credential has a narrower and easier-to-explain blast radius than a
  combined "bootstrap-reconciler" identity.
- **Positive** — Keeps `ops-admin` as an operator/app-secret identity and
  `policy-reconciler` as policy-as-code only.
- **Negative** — Adds one more bootstrap identity, one more password in the
  break-glass JSON, and one more rotation/test path.
- **Negative** — `base/object-storage-credentials` needs an additional OpenBao
  session and more explicit token routing.
- **Neutral** — The current `common/openbao-session` mode pattern remains the
  mechanism; it gains a third mode rather than being replaced.

## Alternatives considered

- **Broaden `policy-reconciler` into a general bootstrap reconciler.** Simpler
  operationally, but one identity would then rewrite ACLs, create AppRoles, and
  write ESO binding records. Rejected because it blurs the security boundary
  that `policy-reconciler` was created to preserve.
- **Extend `ops-admin`.** Fastest, but operator credentials would gain platform
  identity powers. Rejected because an operator-credential compromise could mint
  AppRoles and escalate into broad app-data access.
- **Reintroduce root for post-seed.** Rejected because ADR-0009 and the OpenBao
  bootstrap model deliberately treat root as first-bootstrap-only material.

## Enforcement

`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/tasks/main.yml` must
create the `approle-reconciler-writer` policy and `approle-reconciler` userpass
user, and must persist `approle_reconciler_username` /
`approle_reconciler_password` in the break-glass JSON outside git.
Because OpenBao policy glob `*` is only valid at the end of a policy path, the
role must generate explicit policy blocks for each supported object-storage
AppRole rather than using mid-path patterns such as
`auth/approle/role/object-storage-*/secret-id`.

`dmf-infra/k3s-lab-bootstrap/roles/common/openbao-session/` must expose
`openbao_session_mode: approle-reconciler`.

`dmf-infra/k3s-lab-bootstrap/roles/base/object-storage-credentials/` must route
ACL policy writes through `policy-reconciler`, AppRole and ESO binding writes
through `approle-reconciler`, and Kubernetes object writes through the Kubernetes
API without relying on OpenBao powers.

Live verification must include probes that `ops-admin` still receives `deny` or
403 for `sys/policies/acl/*` and representative AppRole secret-id paths such as
`auth/approle/role/object-storage-app-backups/secret-id`.
Until a CI policy audit exists, enforcement is via code review, live probes, and
the acceptance criteria in the AppRole reconciler plan.

**Verified live on `g2r6-foa9` 2026-05-23** via
`dmf-infra/k3s-lab-bootstrap/playbooks/verify-openbao-identity-model.yml`
(read-shaped assertion playbook). The verifier confirms: three identity
logins succeed (ops-admin / policy-reconciler / approle-reconciler); five
AC-5 negative probes all return `deny`; two ClusterSecretStores Ready; six
ExternalSecrets Ready across six target namespaces. See
[`docs/handoffs/DMF OpenBao AppRole-Reconciler Live Verification Handoff 2026-05-23.md`](../handoffs/DMF%20OpenBao%20AppRole-Reconciler%20Live%20Verification%20Handoff%202026-05-23.md).
Run on any new env as part of post-seed verification.
