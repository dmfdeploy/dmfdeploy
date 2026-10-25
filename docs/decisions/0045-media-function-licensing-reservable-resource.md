# ADR-0045: Media function licences are IAMT leases from an external control plane, which the platform orchestrates; v0.2 declares them only

**Status:** Proposed
**Date:** 2026-07-07. Revised 2026-10-25 onto the IAMT Dynamic Software Licensing model ([dmfdeploy/dmfdeploy#761](https://github.com/dmfdeploy/dmfdeploy/issues/761)).
**Deciders:** @znerol2, design conversation with Claude (2026-07-07) while re-anchoring v0.2 on the EBU facility-orchestration model; adversarially reviewed by codex (RESCOPE round, P1.2/P2 folded). The 2026-10-25 revision is a draft for the RFC.
**Relates to:** ADR-0003 (EBU taxonomy), ADR-0013 (media function catalog model), ADR-0028 (identity and authority chain: C5 actor record, and the workload identity this ADR depends on), ADR-0037 (Media Workloads are NetBox instance inventory), ADR-0047 (packages: the chart carries the licence agent). Issues: [#634](https://github.com/dmfdeploy/dmfdeploy/issues/634) (descriptor schema), [#751](https://github.com/dmfdeploy/dmfdeploy/issues/751) (`software_licence`), [#245](https://github.com/dmfdeploy/dmfdeploy/issues/245) (capability classes).
**Rule:** Treat a media function licence as an IAMT lease that an external control plane owns: declare the entitlement in the descriptor's `licence:` block, let the `LicenceControlPlaneAdapter` correlate and close leases, keep lease state out of NetBox, and in v0.2 build nothing beyond the declaration.

> **RFC status:** this revision goes to a Discussions RFC before it can move to Accepted ([RFC before ADR](README.md#propose-a-decision-with-an-rfc)).

## Context

The dmfdeploy platform has no licensing model yet. Today's functions need no entitlement, and the console's "Licenses" rail slot is empty. The first version of this ADR parked licensing behind a four-method reservation seam. Since then, IAMT published *Dynamic Software Licensing Best Practices* v1.0.0 (2026-09-07), an industry model for exactly this problem ([summary and relevance note](../references/iamt-dsl-v1-0-0-summary-and-relevance.md), [PDF](../references/iamt-dynamic-software-licensing-best-practices-v1.0.0.pdf)). It splits the durable commercial **entitlement** from the time-bounded, signed **lease** that binds part of it to one running workload (§07.01, §11.02). The old seam reserved ahead of runtime and bound to an inventory id; the IAMT model does neither. The descriptor is being designed now (#634), so this is the cheap moment to change shape. Section numbers below (§, Annex) are IAMT's. Background, the superseded seam and the deliberation are in the [archive record](../archive/decisions/0045-media-function-licensing-reservable-resource.md).

## Decision

1. **Role: orchestration client.** The control plane belongs to the vendor or the customer and is the ledger for entitlements, leases, policy and usage (§07.02, §07.07). The platform plays the IAMT system-integrator and workspace-operator part: it triggers lease acquisition at provisioning, which §10.02 allows, and takes part in teardown (INT-2, §09.09). Hosting a control plane is outside this ADR. Observing alone is too little, because agents don't revoke their own leases (§10.05) and teardown has to return the licence.

2. **Issue and identity.** The function's licence agent calls Issue, from inside the workload, with the workload's own identity evidence: on this platform, a projected Kubernetes service-account token (§07.04, §10.02, §11.06). The lease binds to that identity (IDB-1, IDB-2), and renewal re-checks it (IDB-3), so the launcher never presents evidence on the workload's behalf. The package's chart ships the agent (ADR-0047). The launcher hands the agent its Issue inputs: `app`, `tenantId`, `workId`, `licenseModality` and the requested `dimensions`. This depends on the identity work: the control plane must trust the cluster's token issuer, and the platform grants the vendor no standing access (IDB-6). ADR-0028 may be stale on identity direction, so this ADR uses only its C5 actor record.

3. **Correlation.** `workId` replaces `ctx.idempotency_key` in the same role: idempotency, audit and correlation, and never a binding (§07.01, §10.01, INT-4). The launcher derives it from the launch request's `request_id` and the NetBox instance id. That value stays the same for retries and restarts of one instance, differs for two functions in one request, and changes on a new launch. The NetBox instance id moves from binding to correlation. Each adapter call is authorised and audited per ADR-0028 C5. That record (actor, role, request id, reason) stays the platform's, linked to the lease through `workId`, because IAMT audits lease events and not the human who asked (§10.05).

4. **Lifecycle mapping.**
   - **Plan.** "Ensure licence availability" is an advisory entitlement query that returns `covered`, `uncovered` or `unknown` (§05.05 WF-01 step 3, §11.02). Plan holds nothing. IAMT checks quota only at Issue (§10.02), so a platform-side hold couldn't stop another consumer from taking the slot. A Plan-stage hold doesn't exist.
   - **Provision.** The agent issues; the launch counts as running only when the lease for its `workId` reads ACTIVE or RENEWED (Annex D). A quota or entitlement error (§10.08) fails the launch with the problem detail.
   - **Finalise.** Teardown closes the lease with Annex D's *Terminate* intent. Annex B has one closing call, `DELETE /v1/leases/{leaseId}`, so the adapter sends it with reason `decommissioned` (§10.05).
   - **Failed launch.** Rollback *revokes* any lease the attempt got, through the same call with a reason that marks the failure. No lease means nothing to do.
   - The adapter treats "already revoked, terminated or expired" as success, so closing stays idempotent.

5. **The adapter seam**, interface only, with no implementation in v0.2:

   ```
   LicenceControlPlaneAdapter:
     query_entitlement(app, modality, dimensions) -> covered | uncovered | unknown   # read only (API-8)
     issue_inputs(function, ctx)                  -> {app, tenantId, workId, licenseModality, dimensions}
     inspect(work_id)                             -> [{leaseId, status, expiresAt, policy}]   # Annex D states
     close(lease_id, reason)                      -> status   # DELETE with decommissioned, or the failure reason
     usage(app?, window)                          -> usage records   # read only; agents submit (§07.07)
   ```

6. **The descriptor's `licence:` block** declares the entitlement's shape, and the bare word `licence` names it (#751). `software_licence` stays the SPDX field. Absent means the function needs no entitlement.

   ```yaml
   licence:
     app: <string>                   # the publisher's IAMT application id
     modality: time | process | outcome | credit-pool   # IAMT §04.03 class
     term: <string>                  # optional; sent as licenseModality, such as hourly
     dimensions:                     # one instance's request at Issue (§10.02)
       - name: <UPPER_SNAKE>         # publisher-documented (MTR-1), such as CHANNELS
         quantity: <integer ≥ 1>
   ```
   Grace policy, lease type and limits belong to the entitlement in the control plane (OFG-3, §11.02), so the descriptor holds none of them.

7. **Monitoring.** The console raises an alarm at each grace countdown threshold (OFG-7, §11.03 `alertThresholds`) and another when grace runs out, naming the action: DRAIN, DEGRADE or STOP (OFG-6). Grace runs when the control plane is unreachable, so the countdown comes from the last lease snapshot (`expiresAt` plus `offlineGraceSeconds`) or from the agent, and not only from the control plane. "Leaked" leaves the vocabulary: an abandoned lease expires on its own (Annex D). The console instead shows an **unreleased lease**, one still active whose `workId` matches no live instance (§05.05 WF-13, §13.03), and the operator closes it.

8. **Conformance and backends.** The platform claims the IAMT *interface* target, as an automation adapter (§08.01), at Profile B (Cloud Native, §08.04). The Annex A rows it claims are Automation, API behavior and Auditability. Reissue and failover (IDB-4, LPR-7) and usage submission fall outside the claim, as §08.02 asks a claim to state. Any backend is measured against Annex B endpoints, Annex C claims, Annex D states, OFG-2 policy fields and the §10.08 error model; a backend that binds to anything but workload identity fails.

9. **v0.2 is declared-only.** The descriptor may carry the `licence:` block, schema-checked, and the console may show it as declared intent. That is the whole v0.2 scope: no adapter, no control-plane call, no launch gate and no lease state anywhere. v0.2 text says "licence declared"; the claim "licensed" waits for the adapter slice. That slice starts when a function that needs an entitlement exists, or when the operator asks for a spike. It must show a quota error failing a launch, one lease per `workId` across retries, no active lease after a failed launch, teardown closing the lease, and the grace alarms.

10. **NetBox records inventory, and the control plane records leases.** NetBox keeps which function runs and how many instances (ADR-0037), and may hold `workId` or `leaseId` as a reference. Lease state, counts, expiry and grace live only in the control plane. A NetBox tag such as `licence:assigned` would claim state NetBox can't hold, so the platform writes none.

## Consequences

- **Positive:** outside publishers build against a published industry model and not a private seam. Lease mechanics, signing and grace stay with the control plane, so the platform builds no ledger.
- **Negative:** the adapter slice depends on workload identity the control plane trusts, and on an inspection call by `workId` that Annex B's baseline lacks. v0.2 can't claim licensed functions.
- **Open:** the RFC carries the questions this draft couldn't close.

## Enforcement

discipline only: nothing mechanical checks this rule yet. The descriptor schema `dmf-media/schemas/dmf-function.schema.json` has no `licence:` block. When it adopts one, a good and a bad fixture under `dmf-media/tests/conformance/fixtures/`, listed in `dmf-media/tests/conformance/cases.yaml`, become this rule's check, and this section names them.

## Status

Proposed. Revised 2026-10-25 onto the IAMT model; RFC pending.

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0045-media-function-licensing-reservable-resource.md).
