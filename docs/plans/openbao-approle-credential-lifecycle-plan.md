---
status: active
date: 2026-10-26
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/11
---

# OpenBao AppRole credential lifecycle plan

**Related issues:** [#396](https://github.com/dmfdeploy/dmfdeploy/issues/396),
[#727](https://github.com/dmfdeploy/dmfdeploy/issues/727)

## Goal

Close [#11](https://github.com/dmfdeploy/dmfdeploy/issues/11) and
[#396](https://github.com/dmfdeploy/dmfdeploy/issues/396) as one lifecycle:
every AppRole SecretID with a finite TTL is inventoried, rotated before expiry,
delivered to every consumer without exposing its value, monitored independently
of the orchestration backend, and backed by evidence that bootstrap root-token
material is not durable.

The immediate failure to prevent is the observed 30-day ESO credential expiry:
once repeated failed AppRole logins trigger OpenBao lockout, minting a new
SecretID is not an immediate recovery. Rotation must therefore happen before
expiry; alerts provide the backstop.

This plan implements the first two rows of Phase 1 in
[the platform-debt work order](platform-debt-work-order.md), in that order.
It does not begin the later Phase-1 issues.

## Binding constraints

- Follow ADR-0008: runtime credentials live in OpenBao and reach consumers by
  the runtime path; break-glass material is outside that path.
- Follow ADR-0021 and ADR-0028: identities are named, scoped, documented,
  and separated by duty. A scheduled rotation must not require an operator or
  a break-glass credential.
- Do not print a SecretID, root token, userpass password, or Shamir share in a
  task result, log, test fixture, or issue/PR body. Secret-bearing tasks use
  `no_log`; values flow only through stdin, files with restrictive modes, or
  Kubernetes/OpenBao APIs.
- The local break-glass JSON is not a steady-state distribution channel for a
  cluster consumer. It may seed first bootstrap only. Runtime rotation must
  update the consumer's authoritative protected store. A workstation copy is
  bootstrap material only.
- Run cluster writes only through the sanctioned playbook path after the
  relevant `dmf-cluster-access` and `dmf-openbao-unseal` procedures have been
  read. This plan performs no cluster operation.

## Current state and gap

`dmf-infra` currently gives the `external-secrets` and `born-inventory`
AppRoles a 720-hour SecretID TTL. The object-storage AppRoles have a one-year
TTL. The existing `110-eso-secret-rotation.yml` can mint and install a new ESO
credential, but it uses operator break-glass credentials, covers ESO only, and
is not a periodic steady-state controller. The older `dmf-env` AppRole helper
scripts write a workstation Keychain value and do not update the cluster
consumer, so they are not a substitute for this lifecycle.

The OpenBao bootstrap role already creates a sanitized break-glass record and
revokes the first-bootstrap root token when
`openbao_dispose_root_token: true`. #11 is therefore an audit and convergence
task: prove that the normal path leaves no durable root-token artifact, close
any residual or restore-path gaps, and never add a second root-token path.

## Target contract

### AppRole rotation registry

`dmf-infra` owns one declarative registry of every role that sets a finite
`secret_id_ttl`. A target contains only non-secret metadata:

- stable target name and OpenBao AppRole name;
- TTL and calculated rotation/alert thresholds;
- consumer type and its exact authoritative destination, such as a named
  Kubernetes Secret key or an approved OpenBao ESO-binding record;
- readiness check that proves the consumer accepted the replacement; and
- the location of its metadata record.

The registry initially accounts for `external-secrets`, `born-inventory`, and
each generated `object-storage-*` role. Before implementation it is generated
or checked against every AppRole declaration in `dmf-infra`; a finite TTL not
represented in the registry is a hard failure. Each legacy role has an explicit
disposition. An operator-only consumer is either migrated to a managed
destination or removed before its finite TTL can remain in scope.

Each target has a non-secret OpenBao metadata record under a dedicated
`platform/approle-rotation/` prefix. It records the role name, target version,
SecretID accessor, issued-at time, expiry time, TTL, last successful rotation,
and last failure time/reason code. It never records the SecretID, a token, or
an application secret. The accessor is treated as sensitive operational
metadata and never appears in metrics or normal task output.

### Least-privilege identities

The scheduler uses a dedicated Kubernetes-authenticated workload identity. It
is distinct from `ops-admin`, the root token, and the existing
`approle-reconciler` identity.
Its OpenBao policy is rendered from the registry and may only:

- read role configuration needed to validate a listed target;
- mint a replacement SecretID and inspect or destroy an accessor for that
  exact role;
- read and update that target's rotation metadata and an explicitly declared
  OpenBao consumer binding, where applicable.

It has no `sys/*`, policy-writing, auth-method administration, arbitrary
AppRole, application-secret, or unrelated KV access. Its Kubernetes service
account may update only the named consumer Secrets and the single coordination
Lease required by this lifecycle. The policy has explicit paths; it does not
use a broad AppRole wildcard.

`dmf-promsd` receives a separate Kubernetes-authenticated observer identity.
It can read the metadata prefix only. It cannot mint, look up, destroy, or
deliver a SecretID, and cannot read application data. Both identities have
short-lived OpenBao login tokens and TLS verification enabled.

### Safe rotation transaction

The one reusable rotation playbook accepts a registry target. It serializes
runs with a Kubernetes Lease and follows this order:

1. Read the target's metadata and current consumer state without logging a
   credential. Refuse unknown, incomplete, or expired-without-recovery-state
   targets.
2. Mint one replacement SecretID and retain its accessor in process memory.
3. Atomically update every declared authoritative consumer destination. Do not
   make a local break-glass file the sole or current runtime copy.
4. Restart or reconcile the consumer only where its target contract requires
   it, then wait for its readiness and an authenticated healthy state.
5. Persist the replacement metadata and a successful timestamp, then destroy
   the previous accessor. A failed consumer check leaves the previous accessor
   valid and reports failure; it never destroys the only known-good credential.

The transaction is idempotent and records a state that lets the next scheduled
run reconcile an interrupted delivery. It must not issue an unbounded series
of new SecretIDs. The legacy ESO-only playbook and the workstation helper are
either made thin callers of this contract or retired with a documented
break-glass-only recovery path; they must not remain competing rotation paths.

## Implementation sequence

### A. #11: credential hygiene and root-token disposal

1. **Inventory and registry.** In `dmf-infra`, locate every finite
   `secret_id_ttl` assignment and its consumer. Add the registry, the
   completeness check, and target-specific readiness/delivery adapters. The
   review must identify whether the current `born-inventory` and
   `object-storage-*` credentials are consumed from Kubernetes or an OpenBao
   binding before moving them; do not infer a destination from a name.

2. **Create the two identities and policies.** Add the scheduler and observer
   Kubernetes-auth roles, service accounts, exact RBAC, and rendered explicit
   OpenBao policy paths. Extend the OpenBao identity verifier with positive
   login probes and negative probes for application-secret reads, policy
   writes, unrelated AppRoles, and `sys/*`. Preserve ADR-0021's restricted
   `approle-reconciler` scope; do not broaden it to solve this task.

3. **Implement the registry-driven transaction.** Replace the ESO-only
   procedure with the transaction above, retaining its useful consumer
   readiness behavior. The playbook must run safely once per target and as a
   complete sweep. Test normal delivery, a duplicate invocation, a failed
   consumer readiness check, an interrupted run, and a target with no prior
   accessor. Tests assert that the old accessor is destroyed only after a
   successful replacement.

4. **Converge bootstrap root-token handling.** Audit the OpenBao init output,
   break-glass writer, dmf-init backup/restore inputs, pre-Bao bundles, and
   rotation helpers. The first-bootstrap root token may exist only long enough
   to establish named non-root identities and the sanitized, mode-0600
   break-glass record. Before revocation, assert the durable record has no
   root-token field; after revocation, assert success without emitting the
   token. Remove or fail closed on any residual durable root-token field,
   including a restore path that would reintroduce one. Never print a file to
   decide whether it contains a root token; use a local field-presence check.

5. **Bootstrap and recovery documentation.** Update the OpenBao security model
   and the operator runbook to distinguish first-bootstrap custody,
   break-glass recovery, and steady-state rotation. The documented expired
   SecretID recovery path must say that lockout timing is measured from the
   triggering failure and that a rotation does not shorten an active lockout.

### B. #396: pre-expiry monitoring and scheduled rotation

6. **Expose metadata-only metrics in `dmf-promsd`.** Add a small OpenBao
   metadata client using the observer identity and emit:

   - `dmf_openbao_approle_secret_id_expires_at_seconds{role,target}`;
   - `dmf_openbao_approle_rotation_last_success_seconds{role,target}`; and
   - `dmf_openbao_approle_rotation_last_failure{role,target,reason}`.

   No metric label, log line, health response, or error body includes an
   accessor, SecretID, token, namespace-specific secret value, or OpenBao
   response payload. If metadata cannot be read, the collector exports a
   failure signal rather than stale success.

7. **Add Prometheus-side alerts.** Install alert rules with the metric in the
   monitoring stack, independent of AWX or a successor scheduler. A target is
   due at two-thirds of its TTL. Alert warning when less than one quarter of
   TTL remains, critical when less than one tenth remains, and alert immediately
   when the latest scheduled rotation fails or metadata is absent/stale. These
   ratios apply to each target's declared TTL; the effective values for the
   30-day roles and yearly object-storage roles appear in the runbook and rule
   tests. The alert annotation names the target and runbook, never a secret.

8. **Schedule the playbook.** The scheduler contract is one daily, non-
   overlapping invocation of the registry sweep. It rotates a target at the
   two-thirds threshold, giving the 30-day roles at least ten days of retry
   window. The current backend supplies only the schedule adapter; the playbook
   interface, registry, metrics, and rules have no AWX-specific dependency.
   If the execution backend changes, the replacement adapter must invoke the
   same playbook with the same service account and retain the daily/no-overlap
   guarantee. The scheduler also records a run heartbeat so an absent scheduler
   is visible before a credential becomes due.

9. **Prove steady state.** After a controlled non-production rotation, collect
   redacted evidence that every registry target has a future expiry, a recent
   successful rotation timestamp, a healthy consumer, the expected metric
   series, and no firing pre-expiry/failed-rotation alert. Exercise one
   simulated delivery failure to prove that the alert fires and the previous
   credential remains valid. Record the evidence on #11 and #396 without
   secret values or accessors.

## Verification gates

Implementation is complete only when all of the following pass:

- Static registry coverage proves that every finite-TTL AppRole declaration
  belongs to exactly one managed target.
- Unit tests cover expiry calculation, two-thirds scheduling, warning/critical
  thresholds, stale metadata, metric redaction, and alert expressions.
- Role/playbook tests cover permitted and denied OpenBao paths, consumer update
  ordering, no-overlap locking, retry after interruption, and root-token
  field rejection. Run syntax checks, `ansible-lint`, and `yamllint` from
  `dmf-infra/k3s-lab-bootstrap/`.
- `dmf-promsd` tests use a fake metadata endpoint and prove it neither logs nor
  exposes sensitive fields. Its existing test suite remains green.
- A read-only live pre-flight confirms the selected control-node context and
  the registry's declared consumer objects before any write. A sanctioned
  playbook run then supplies the redacted steady-state evidence in step 9.
- A root-token disposal test follows the bootstrap path with a fixture token,
  checks only field names and revocation result, and proves no durable output
  retains that field.

## Deferred decisions and boundaries

- [#568](https://github.com/dmfdeploy/dmfdeploy/issues/568) needs an operator
  decision about release CI for the exact tagged SHA. No release workflow,
  ruleset, or alternative publication path is changed by this plan.
- [#758](https://github.com/dmfdeploy/dmfdeploy/issues/758) needs an operator
  decision on granting the trusted issue-link workflow `actions: write`. No
  workflow permission or rerun workaround is introduced here.
- [#782](https://github.com/dmfdeploy/dmfdeploy/issues/782) is intentionally
  held pending Discussion #762 and is outside this plan. Do not edit its ADR
  draft.
- This plan does not rekey Shamir shares, alter unseal posture, or make a live
  cluster change while planning.

## Completion and handoff

Implement in reviewable cross-repo slices (`dmf-infra`, `dmf-promsd`, and only
where necessary `dmf-env`), each referencing the umbrella issues in qualified
form. The final umbrella documentation PR records the redacted evidence,
updates this plan's status, and uses `Closes dmfdeploy/dmfdeploy#11` and
`Closes dmfdeploy/dmfdeploy#396` only after every verification gate passes.
