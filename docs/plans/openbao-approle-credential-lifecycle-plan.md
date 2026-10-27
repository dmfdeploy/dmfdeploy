---
status: active
date: 2026-10-26
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/11
---

# OpenBao AppRole credential lifecycle plan

**Related issues:** [#396](https://github.com/dmfdeploy/dmfdeploy/issues/396),
[#727](https://github.com/dmfdeploy/dmfdeploy/issues/727)

**Disposition approved 2026-10-27:** `born-inventory-netbox-reader` is a
setup-only credential. Its explicit playbook consumers were checked in
`dmf-infra`: the 694 NetBox inventory survey is called by bootstrap configure
and the lifecycle Layer 6 test. It is not a long-running application identity.
It is excluded from continuous rotation and expiry monitoring. Every deliberate
rerun of those survey paths must obtain a fresh credential through the
documented operator-triggered setup path; it must not rely on a cached
break-glass SecretID surviving its TTL. The issuance path, expiry, revocation,
and failure recovery still need implementation and tests. If a new continuous
consumer is found, stop and request a new disposition instead of adding it to
the setup-only exception by assumption.

## Goal

Close [#11](https://github.com/dmfdeploy/dmfdeploy/issues/11) and
[#396](https://github.com/dmfdeploy/dmfdeploy/issues/396) as one lifecycle:
every continuously used finite-TTL AppRole SecretID is inventoried, rotated
before expiry, delivered to every runtime consumer without exposing its value,
and monitored independently of the orchestration backend. Setup-only credentials
have an explicit operator-triggered issuance and cleanup path instead of
continuous rotation. The lifecycle is also backed by evidence that bootstrap
root-token material is not durable.

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
TTL. The approved setup-only disposition excludes `born-inventory` from the
periodic runtime registry; its per-invocation fresh-credential path remains to
be implemented. The existing `110-eso-secret-rotation.yml` can mint and install
a new ESO credential, but it uses operator break-glass credentials, covers ESO
only, and is not a periodic steady-state controller. The older `dmf-env`
AppRole helper scripts write a workstation Keychain value and do not update the
cluster consumer, so they do not implement this lifecycle.

The OpenBao bootstrap role already creates a sanitized break-glass record and
revokes the first-bootstrap root token when
`openbao_dispose_root_token: true`. #11 is therefore an audit and convergence
task: prove that the normal path leaves no durable root-token artifact, close
any residual or restore-path gaps, and never add a second root-token path.

## Target contract

### AppRole rotation registry

`dmf-infra` owns one declarative registry of every continuously used role that
sets a finite `secret_id_ttl`. Setup-only roles appear in a separate explicit
disposition inventory and are not silently omitted. The runtime registry
targets contain only non-secret metadata:

- stable target name and OpenBao AppRole name;
- TTL and calculated rotation/alert thresholds;
- consumer type and its exact authoritative destination, such as a named
  Kubernetes Secret key or an approved OpenBao ESO-binding record;
- readiness check that proves the consumer accepted the replacement; and
- the location of its metadata record.

The registry initially accounts for `external-secrets` and each generated
`object-storage-*` role. The separate disposition inventory records
`born-inventory-netbox-reader` as setup-only, with its checked Ansible
entrypoints, fresh-on-rerun requirement, and issuance/revocation verification.
Before implementation, a static check compares every finite-TTL AppRole
declaration in `dmf-infra` against exactly one of these inventories; a role in
neither or both is a hard failure. Each other legacy role also has an explicit
disposition. An operator-only consumer is either migrated to a managed
destination or removed before its finite TTL can remain in scope.

The setup-only issuance path is operator-triggered and runs as part of each
694 survey invocation, including the lifecycle Layer 6 test. It uses a separate
Kubernetes-authenticated issuer identity bound to a dedicated ServiceAccount in
the `openbao` namespace. The invoking runner obtains a short-lived TokenRequest
JWT for that ServiceAccount, authenticates to OpenBao, and mints a fresh
SecretID for the read-only NetBox runtime lookup. The issuer policy is limited
to assigning, looking up, and destroying SecretIDs for
`born-inventory-netbox-reader`; it cannot read NetBox data, change the AppRole,
or mint credentials for another role. Each SecretID create request sets a
one-use limit and a one-hour maximum TTL. OpenBao policy `required_parameters`
and `allowed_parameters` enforce that only `secret_id`, `ttl=1h`, and
`num_uses=1` are accepted on this path. The ID is used only for that
invocation, and its accessor is revoked in an `always` cleanup path after the
lookup or on a handled failure. A crash leaves at most a one-use credential
that expires within one hour; recovery starts with a new run and does not
depend on the old SecretID. The playbook fails closed if the OpenBao version
does not accept these per-ID bounds or if the create response does not confirm
them. The issuer cannot write the AppRole configuration or change its
policies.
The SecretID is never written to a persistent workstation file, Keychain, or
application Secret. A setup run requires trusted C5 attribution context and
fails closed when identity, reason, request id, issuance, or cleanup is
unavailable. Tests cover normal completion and interruption between issuance,
use, and revocation. The setup issuer has no access to the scheduled rotation
registry and is not a second periodic rotator. The authenticated manual
dispatcher derives actor and role and requires a reason. It records one fixed
694 action in the immutable request receipt described below. The existing
operator SSH executor accepts the opaque receipt id through the bootstrap
configure invocation. Direct playbook invocation without that trusted context
fails before OpenBao writes.

The manual dispatcher is an authenticated `dmf-cms` action. dmf-init accepts
the returned opaque request id only as the gate token for the configure run;
the caller cannot supply attribution fields or arbitrary Ansible variables.
The dispatcher derives the
actor from the authenticated OIDC subject and the authorized role from the
session's effective authorization policy (including any active view-as
downgrade), requires only a bounded non-secret reason, and generates a UUID
request id. It rejects development login, break-glass/local authentication,
cross-origin requests, unknown or extra request fields, and missing session
authorization. The v1 request has no workflow context field; its action is
fixed to `born-inventory-secretid-issue`. It cannot select an environment,
actor, role, playbook, or namespace. Before acknowledging the request,
dmf-cms writes an immutable ConfigMap to `dmf-setup-requests`, named
`request-<request_id>`, where the id is 32 lowercase hexadecimal UUID
characters generated by the server. Its exact string `data` keys are
`schema_version`, `request_id`, `action`, `env_id`, `cluster_uid`, `actor`,
`role`, `reason`, `issued_at`, and `expires_at`. The schema version is `1`;
timestamps are Unix UTC decimal seconds. The receipt expires 15 minutes after
issuance. The environment id is the canonical value from
[ADR-0039](../decisions/0039-environment-identity-netbox-site-cluster.md),
wired into dmf-cms by the 650 deployment as server-only configuration. The
cluster binding is the UID of the live `kube-system` Namespace, obtained at
deployment time and checked by the executor against the current cluster.
Receipt creation stays disabled until both values are configured. Neither
binding is accepted from the request body. Reject extra or missing data keys,
an invalid id/name match, mutable ConfigMaps, wrong action/schema, empty or
control-bearing C5 strings, future/stale times, and any expiry window longer
than 15 minutes. The executor revalidates the complete receipt, including
`immutable: true`, namespace, name, UID, action, environment id and current
`kube-system` UID. It atomically creates the immutable
`claim-<request_id>` ConfigMap in the same namespace with exact string data
keys `schema_version`, `request_id`, `action`, `receipt_name`, `receipt_uid`,
and `claimed_at`. A claim create conflict means the request was already
consumed and fails closed. CMS and executor cannot update or delete receipts
or claims. The CMS pod uses the dedicated `dmf-cms-setup-requests`
ServiceAccount. Its RoleBinding grants create/get on ConfigMaps only in
`dmf-setup-requests`; it cannot list them. The receipt provides append-only
application evidence. It has no WORM guarantee; platform administrators
remain trusted. The
operator-side 694 executor receives only the opaque request id, reads the
authoritative receipt, validates its schema, action, binding, expiry and
attribution, then atomically creates the claim before any credential
operation. A missing, expired, mismatched, already-consumed, or unreadable
receipt fails closed. Interrupted work is retried only with a fresh
authenticated request.

The CMS deployment passes these values through `DMF_CONSOLE_SETUP_REQUEST_ENV_ID`
and `DMF_CONSOLE_SETUP_REQUEST_CLUSTER_UID`. The latter is read by the
deployment from the live `kube-system` Namespace. The dedicated ServiceAccount
name and the receipt/claim schema above are the shared dmf-cms/dmf-infra
interface; changes require coordinated versioned updates and tests on both
sides.

During new-environment bootstrap, the initial Authentik invitation and CMS
OIDC deployment from post-seed make the CMS action available before configure.
dmf-init must stop after post-seed for the operator to establish the first
passkey and obtain the CMS receipt, then pass only the opaque request id to the
configure invocation that runs 694. Configure may not fall through to 694
without consuming that receipt. The existing passkey-enrollment convergence
after playbook 696 remains after configure; it is a second check/enrollment
pause and must not be moved before 696. The C5 receipt gate precedes
configure's first 694 call, while the later passkey convergence preserves the
current 696 dependency.

This ordering preserves ADR-0044: the checkpoint-2 export gate remains before
unseal, seed-bao, and post-seed, and no host-persistent dmf-init cursor or
receipt copy is introduced. A restore from checkpoint 2 replays post-seed and
must obtain a fresh passkey-authenticated receipt before configure; any prior
receipt that was not consumed is allowed to expire and is never replayed from
the recovery bundle. Within one container lifetime the opaque request id may
travel only in the in-memory pause/resume payload and as
`DMF_SETUP_REQUEST_ID` in the configure process environment; it is not emitted
to logs or included in the exported recovery bundle.

Each target has a non-secret OpenBao metadata record under a dedicated
`platform/approle-rotation/` prefix. It records the role name, target version,
SecretID accessor, issued-at time, expiry time, TTL, last successful rotation,
last failure time/reason code, and the non-secret C5 attribution quartet for
the latest run: actor, role, request id, and reason. It never records the
SecretID, a token, or an application secret. The accessor is treated as
sensitive operational metadata and never appears in metrics or normal task
output. Metrics do not use attribution fields as labels.

### Least-privilege identities

The scheduler uses a dedicated Kubernetes-authenticated workload identity. It
is distinct from `ops-admin`, the root token, and the existing
`approle-reconciler` identity.
Its OpenBao policy is rendered from the registry and may only:

- read role configuration needed to validate a listed target;
- assign a caller-supplied custom SecretID at the exact role's
  `custom-secret-id` endpoint with registry-bounded `ttl` and `num_uses`, look
  it up by the same candidate, and destroy only its accessor;
- read and update that target's rotation metadata and an explicitly declared
  OpenBao consumer binding, where applicable; and
- create, read, and delete the single transaction-scoped staging secret for
  that target, with no list access to other staging records.

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

The one reusable rotation playbook accepts a registry target, a non-secret run
id, and C5 attribution metadata: actor, role, request id, and reason. The
request id is the run id and remains stable when a scheduler retries or
recovers that logical invocation. The playbook rejects missing or untrusted
context before its first OpenBao or Kubernetes write. It also serializes runs
with a Kubernetes Lease and follows this order:

1. Read the target's metadata and current consumer state without logging a
   credential. Refuse unknown, incomplete, or expired-without-recovery-state
   targets.
2. Generate a high-entropy candidate SecretID with a cryptographically secure
   random source. Before asking OpenBao to accept it, persist the candidate in
   a dedicated, access-controlled staging secret for the target and transaction,
   plus a non-secret `pending-create` intent containing the transaction id and
   staging path. The staging secret is the durable, protected recovery copy
   needed to resume after process loss. It is readable only by the rotation
   identity, never logged or returned by metrics, and deleted only after the
   transaction reaches `active` or a safe undelivered abort.
3. Look up the candidate through the exact AppRole `secret-id/lookup` endpoint.
   If it exists, recover its accessor and verify its TTL/use limit. If it does
   not exist, assign that same candidate through `custom-secret-id` with the
   target's one-use and TTL bounds. If the create response is lost, look up the
   same candidate before retrying; if a concurrent create reports that the
   candidate is already registered, look it up and resume. Never generate a
   second candidate while the transaction is pending. Persist the resulting
   accessor and transition metadata to `issued-pending-delivery` before any
   consumer write. Do not grant access to the random `secret-id` generation
   endpoint or to list SecretID accessors.
4. Update every declared authoritative consumer destination from that same
   staged SecretID, stamping the transaction id/version with the credential.
   Do not make a local break-glass file the sole or current runtime copy.
5. Persist delivery progress and classify the transaction as
   `issued-pending-delivery` (no destination has its transaction marker) or
   `delivered-pending-readiness` (one or more destinations have the marker).
   Once any destination has received the replacement, never destroy it as an
   automated recovery action. Retry delivery to remaining destinations from
   the staged copy, then restart or reconcile the consumer only where its
   target contract requires it. Wait for consumer readiness and
   transaction-specific acceptance at every destination; a stamped
   transaction id/version without passing readiness is insufficient.
6. Mark metadata `active` with a successful timestamp only after every
   destination acknowledges the transaction and its consumer passes readiness.
   Then destroy the previous accessor and delete the staging secret. A failed
   readiness check leaves the transaction `delivered-pending-readiness`; later
   runs retry readiness with the same replacement and alert on the failure.
   They do not mint another SecretID, promote the replacement, or destroy
   either accessor while delivery/readiness is unresolved.

The transaction is idempotent and records enough protected state for the next
scheduled run to resume with the same candidate. The candidate is protected in
staging before OpenBao creates it. A lost create response is resolved by
looking up that candidate; a duplicate-create response uses the same lookup.
Validate this protocol against the deployed OpenBao version and fixture-driven
API behavior before relying on it. The persisted transaction id identifies a
replacement across scheduler attempts. Duplicate triggers and retries after a
lost response inspect the target's existing transaction and resume with its
staged candidate; they never generate a second candidate while that transaction
is pending. Requests and results
carry only target names, run/transaction ids, C5 fields, and sanitized status
or reason codes. SecretIDs, tokens, accessors, staging payloads, and application
credentials never enter runner history, logs, or returned results. For
`issued-pending-delivery`, the next run inspects every destination: if none has
the transaction marker, it may resume delivery from the staged SecretID; if
any has it, it transitions to `delivered-pending-readiness` and retains the
replacement. Only a safe-abort check proving no destination received the
transaction may destroy that replacement and its staged copy, while retaining
the prior accessor and recording failure. For `delivered-pending-readiness`,
the next run retries delivery to missing destinations and required
readiness/acceptance checks using the same staged SecretID. It promotes only
after all checks pass. If readiness remains down, the transaction remains
pending and alerts; it never creates an unbounded series of SecretIDs or
strands an updated consumer by revoking its credential. The legacy ESO-only
playbook and the workstation helper are
either made thin callers of this contract or retired with a documented
break-glass-only recovery path; they must not remain competing rotation paths.

## Implementation sequence

### A. #11: credential hygiene and root-token disposal

1. **Inventory and registry.** In `dmf-infra`, locate every finite
   `secret_id_ttl` assignment and its consumer. Add the runtime registry,
   setup-only disposition inventory, completeness check, and target-specific
   readiness/delivery adapters. The review identified `born-inventory` as an
   Ansible-only setup consumer and `object-storage-*` credentials as requiring
   target-by-target destination evidence; do not infer a destination from a
   name. Implement and test the setup-only fresh-on-rerun
   issuance/use/revocation path separately from periodic rotation.

2. **Create scoped identities and policies.** Add the setup-only issuer,
   scheduler, and observer Kubernetes-auth roles and ServiceAccounts with
   exact OpenBao policy paths. The setup issuer can adjust only the target's
   create/lookup/destroy IDs for that target, and cannot read application data
   or change AppRole configuration or policies. The scheduler and observer
   keep their distinct permissions. Extend the OpenBao
   identity verifier with positive login probes and negative probes for
   application-secret reads, policy writes, unrelated AppRoles, and `sys/*`.
   Preserve ADR-0021's restricted `approle-reconciler` scope; do not broaden it
   to solve this task.

3. **Implement the registry-driven transaction.** Replace the ESO-only
   procedure with the transaction above, retaining its useful consumer
   readiness behavior. The playbook must run safely once per target and as a
   complete sweep. Test normal delivery, a duplicate invocation, interruption
   before mint, lost create response, interruption before delivery, partial
   delivery, delivered-but-unready recovery, and a target with no prior
   accessor. Tests assert that a pre-mint intent and staged candidate make a
   lost response resumable, an undelivered replacement is safely recoverable
   from staging, a delivered replacement is retained through readiness
   failure, and the old accessor is destroyed only after a successful
   replacement.

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

8. **Schedule and run the playbook.** A Kubernetes CronJob runs once daily,
   directly executing the reusable rotation playbook in the approved,
   digest-pinned Ansible execution image. This credential-maintenance runner
   does not call the AWX API or autoscale helper, so it runs while AWX is
   scaled to zero. The scheduled actor is the authenticated Kubernetes
   service-account identity; its role is the fixed
   `approle-rotation-scheduler` role. Its reason is the fixed,
   non-secret `scheduled-pre-expiry-rotation` value. The CronJob supplies a
   stable non-secret request id/run id for each logical invocation and reuses
   it after retries or recovery; caller-supplied variables cannot override the
   actor, role, or reason. Place the CronJob in a protected runtime namespace
   with a dedicated service account. Its Kubernetes permissions are limited to
   the named consumer Secrets and the coordination Lease; its OpenBao identity
   follows the least-privilege policy above.

   A manual run is accepted only through an authenticated `dmf-cms` operator
   action. It writes the immutable
   [ADR-0028](../decisions/0028-identity-and-authority-chain.md) request
   receipt, derives the human actor from the authenticated Authentik subject
   and the authorized role from the session's effective authorization
   context, requires a non-secret reason, and generates the request id. It
   does not create a Kubernetes Job. During bootstrap, dmf-init accepts the
   resulting opaque request id at a dedicated pause and passes it only to the
   existing operator SSH configure executor. The executor loads and validates
   the authoritative receipt and atomically claims its request id before it
   asks for a short-lived TokenRequest JWT for the fixed issuer ServiceAccount.
   The CMS API does not accept caller-supplied actor or role fields, and
   dmf-init does not accept arbitrary extra-vars. Direct playbook invocation
   without a valid, unconsumed receipt fails before OpenBao or Kubernetes
   writes. If the trusted origin or C5 context is absent, the executor fails
   closed. The scheduled CronJob identity and operator SSH executor identity
   remain distinct and scoped to their respective issuance paths.

   The runner carries the C5 quartet in its durable non-secret run receipt and
   Job/Pod annotations. Kubernetes Secret mutations carry the request id and
   attribution annotations so Kubernetes audit events correlate with the run.
   OpenBao audit context carries the request id where the supported audit path
   accepts it. Otherwise, the run receipt records the target, authenticated
   OpenBao identity, operation time, and outcome for correlation with native
   OpenBao audit events; the plan does not assume unsupported per-request audit
   fields. The runner identity does not use CMS identities, labels, or helper
   ingress.

   The playbook Lease remains the semantic no-overlap guard across scheduled,
   duplicate, and manual invocations. The runner records a success heartbeat
   only after successful completion. A failed-run signal or stale/missing
   heartbeat alerts through the independent monitoring stack. Rotation occurs
   at the two-thirds threshold, giving the 30-day roles at least ten days of
   retry window. The registry, rotation transaction and safety gates, run
   request/result, and telemetry are backend-neutral. The evaluation in
   [#760](https://github.com/dmfdeploy/dmfdeploy/issues/760) and
   [RFC #792](https://github.com/orgs/dmfdeploy/discussions/792) may recommend
   a future Temporal or other orchestration runner only if it preserves the
   stable non-secret run identity, transaction recovery, shared
   no-overlap Lease, and telemetry. Workflow history may contain only
   non-secret request fields and sanitized outcomes. This runner does not
   replace AWX catalog or media actuation, or extend the AWX-only availability
   contract to other workloads; those changes require their own architectural
   decision.

9. **Prove steady state.** After a controlled non-production rotation, collect
   redacted evidence that every registry target has a future expiry, a recent
   successful rotation timestamp, a healthy consumer, the expected metric
   series, and no firing pre-expiry/failed-rotation alert. Exercise one
   simulated delivery failure to prove that the alert fires and the previous
   credential remains valid. Record the evidence on #11 and #396 without
   secret values or accessors.

## Verification gates

Implementation is complete only when all of the following pass:

- Static inventory coverage proves that every finite-TTL AppRole declaration
  belongs to exactly one runtime-managed target or an explicitly approved
  setup-only disposition. Tests prove that the setup-only NetBox survey obtains
  a fresh credential per invocation and does not persist it beyond that run.
- Unit tests cover expiry calculation, two-thirds scheduling, warning/critical
  thresholds, stale metadata, metric redaction, and alert expressions.
- Role/playbook tests cover permitted and denied OpenBao paths, consumer update
  ordering, no-overlap locking, retry after interruption, and root-token
  field rejection. The lost-create-response case must use the same protected
  candidate and prove no second SecretID is minted. Run syntax checks,
  `ansible-lint`, and `yamllint` from
  `dmf-infra/k3s-lab-bootstrap/`.
- Runner tests prove the rotation executes with AWX scaled to zero and makes no
  AWX API or autoscale-helper calls. Cover scheduled machine attribution and
  the authenticated dmf-cms manual path against its immutable request record;
  verify the quartet reaches the run receipt, Kubernetes annotations, consumer
  mutation audit, and supported OpenBao audit correlation. Missing or
  caller-forged context must fail before writes. Cover concurrent invocations
  through the shared Lease, duplicate and
  lost-response retries through the same request id and transaction, and prove
  that only a successful run records a success heartbeat. Assert that no
  SecretID, token, accessor, or staging value appears in attribution metadata,
  logs, metrics, or results.
- CMS receipt tests reject unauthenticated, development-login,
  break-glass/local, cross-origin, extra-field, malformed-reason, and
  unauthorized effective-role requests. They prove actor/role come from the
  OIDC session and active view-as policy, a server-generated request UUID is
  used, and a Kubernetes write failure never returns an acknowledged receipt.
  The receipt serializer is exact-schema and the persisted ConfigMap is
  immutable. Executor fixtures reject an unbound, expired, malformed,
  unreadable, or already-consumed receipt; competing calls prove the
  consumption record permits one winner. Tests verify that dmf-init passes the
  opaque id without placing it in logs or the exported checkpoint bundle.
- Bootstrap-order tests prove that the checkpoint-2 export gate stays before
  post-seed; initial passkey enrollment and receipt creation pause after
  post-seed and before configure/694; and the existing post-configure passkey
  convergence remains after 696. Restore from checkpoint 2 must require a
  fresh receipt before replaying configure; receipt ids are never restored
  from an exported bundle.
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
where necessary `dmf-env` and `dmf-cms` for the authenticated manual-dispatch
path), each referencing the umbrella issues in qualified form. The final
umbrella documentation PR records the redacted evidence,
updates this plan's status, and uses `Closes dmfdeploy/dmfdeploy#11` and
`Closes dmfdeploy/dmfdeploy#396` only after every verification gate passes.
