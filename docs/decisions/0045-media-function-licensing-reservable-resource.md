# ADR-0045: Media function licences are IAMT leases from an external control plane, which the platform orchestrates; v0.2 declares them only

**Status:** Proposed
**Date:** 2026-07-07. Revised 2026-10-25 onto the IAMT Dynamic Software Licensing model ([dmfdeploy/dmfdeploy#761](https://github.com/dmfdeploy/dmfdeploy/issues/761)).
**Deciders:** @znerol2, design conversation with Claude (2026-07-07) while re-anchoring v0.2 on the EBU facility-orchestration model; adversarially reviewed by codex (RESCOPE round, P1.2/P2 folded). The 2026-10-25 revision is a draft for the RFC, corrected after a codex review.
**Relates to:** ADR-0003 (EBU taxonomy), ADR-0013 (media function catalog model), ADR-0028 (identity and authority chain: C5 actor record, and the workload identity this ADR depends on), ADR-0037 (Media Workloads are NetBox instance inventory), ADR-0047 (packages: the chart carries the licence agent). Issues: [#634](https://github.com/dmfdeploy/dmfdeploy/issues/634) (descriptor schema), [#751](https://github.com/dmfdeploy/dmfdeploy/issues/751) (`software_licence`), [#245](https://github.com/dmfdeploy/dmfdeploy/issues/245) (capability classes).
**Rule:** Treat a media function licence as an IAMT lease that an external control plane owns: declare the entitlement in the descriptor's `licence:` block, keep lease state out of NetBox, and close leases only through a `LicenceControlPlaneAdapter` that a later slice builds, so v0.2 builds nothing beyond the declaration.

> **RFC status:** this revision goes to a Discussions RFC before it can move to Accepted ([RFC before ADR](README.md#propose-a-decision-with-an-rfc)). This ADR decides only what the IAMT text settles. The rest are RFC questions, and they block the adapter slice (decision 9).

## Context

The dmfdeploy platform has no licensing model yet. Today's functions need no entitlement, and the console's "Licenses" rail slot is empty. The first version of this ADR parked licensing behind a four-method reservation seam. Since then, IAMT published *Dynamic Software Licensing Best Practices* v1.0.0 (2026-09-07), an industry model for exactly this problem ([summary and relevance note](../references/iamt-dsl-v1-0-0-summary-and-relevance.md), [PDF](../references/iamt-dynamic-software-licensing-best-practices-v1.0.0.pdf)). It splits the durable commercial **entitlement** from the time-bounded, signed **lease** that binds part of it to one running workload (§07.01, §11.02). The old seam reserved ahead of runtime and bound to an inventory id; the IAMT model does neither. The descriptor is being designed now (#634), so this is the cheap moment to change shape. Section numbers below (§, Annex) are IAMT's. Background, the superseded seam and the deliberation are in the [archive record](../archive/decisions/0045-media-function-licensing-reservable-resource.md).

## Decision

1. **Role: orchestration client.** The control plane belongs to the vendor or the customer and is the ledger for entitlements, leases, policy and usage (§07.02, §07.07). The platform plays the IAMT system-integrator and workspace-operator part: it triggers lease acquisition at provisioning, which §10.02 allows, and takes part in teardown (INT-2, §09.09). Hosting a control plane is outside this ADR. Observing alone is too little, because agents don't revoke their own leases (§10.05) and teardown has to return the licence.

2. **Issue and identity.** The function's licence agent calls Issue from inside the workload, with the workload's own identity evidence (§07.04, §07.07, §10.02, §11.06). The lease binds to that identity (IDB-1, IDB-2), and renewal re-checks it (IDB-3). The launcher never holds or presents identity evidence. The package's chart ships the agent (ADR-0047). The launcher gives the agent the Issue inputs it owns: an opaque `workId` and the descriptor's entitlement fields. How it delivers them is an RFC question. This depends on the identity work: the control plane must trust the cluster's token issuer, and the platform grants the vendor no standing access (IDB-6). ADR-0028 may be stale on identity direction, so this ADR uses only its C5 actor record.

3. **Correlation.** The platform supplies `workId`, an opaque string that correlates one function instance's run for idempotency and audit and never binds anything (§07.01, §10.01, INT-4). Its exact construction, encoding, owner, persistence, and rules for retry, restart and tenant namespacing are an RFC question. Each adapter call is authorised and audited per ADR-0028 C5. That record (actor, role, request id, reason) stays the platform's, linked to the lease through `workId`, because IAMT audits lease events and not the human who asked (§10.05).

4. **Lifecycle mapping.**
   - **Plan holds nothing.** IAMT checks quota only at Issue (§10.02) and has no hold call (Annex B), so a platform-side hold couldn't stop another consumer from taking the slot. Annex B also has no entitlement query; whether Plan gets one is an RFC question, and until then Plan shows entitlement coverage as unknown.
   - **Provision.** Issue enters ISSUED or ACTIVE (Annex D). What counts as "ready" (a lease state, token receipt or local validation) is an RFC question. A quota or entitlement error at Issue (§10.08) fails the launch with the problem detail.
   - **Finalise and failed launch.** IAMT's one closing call is Revoke: `DELETE /v1/leases/{leaseId}` with a required reason, and the lease becomes REVOKED (§10.05). Teardown sends reason `decommissioned`. Rollback revokes any lease the failed attempt got, and with no lease there's nothing to close. Annex D keeps TERMINATED as a separate state for a controlled end of use, but no baseline call reaches it. Whether teardown needs TERMINATED through a backend extension is an RFC question.
   - **Closing per input state.** A lease that is already REVOKED, EXPIRED or TERMINATED counts as closed, so a repeated close succeeds. A lease that is ISSUED, ACTIVE or RENEWED gets the Revoke call. A lease that is REISSUING, or a close the control plane refuses for lack of authority, is a failure the operator sees.

5. **The adapter seam** is a later slice. This ADR fixes its duties and leaves the call contracts to the RFC. It supplies the agent's Issue inputs, reads lease state, revokes with a reason, and reads usage records, which agents submit (§07.07). How it finds a lease (by `workId` through a backend extension, or by a `leaseId` the agent reports) and the authority it closes leases with are RFC questions. The authority must be a control-plane principal allowed to revoke (§10.05).

6. **The descriptor's `licence:` block** states entitlement intent. It's optional, and absent means the function needs no entitlement. `software_licence` is a separate, required field that holds SPDX metadata for the software itself (#751).

   ```yaml
   licence:                          # optional; no other keys
     app: <string>                   # required: the publisher's IAMT application id
     modality: <project class>       # required: see below
     term: <string>                  # optional: sent as IAMT licenseModality, such as hourly
     dimensions:                     # required, at least one; names unique
       - name: <UPPER_SNAKE>         # publisher-documented (MTR-1), such as CHANNELS
         quantity: <integer ≥ 1>     # one instance's request at Issue (§10.02)
   ```
   `modality` is a project classification built on the §04.03 modality concepts (time-based, process-based, outcome-based, credit or unit pool). It's distinct from §10.02's `licenseModality` values such as `hourly`, which `term` carries. The exact enum, and how dimension names and units line up with the capability classes on #245, are RFC questions. Grace policy, lease type and limits belong to the entitlement in the control plane (OFG-3, §11.02), so the descriptor holds none of them.

7. **Monitoring.** Grace countdown and grace exhaustion, with the action taken (DRAIN, DEGRADE or STOP), reach the operator as console alarms (OFG-6, OFG-7). IAMT evaluates grace in the workspace plane (§07.04) and fans alerts out from the control plane (§07.02). Grace runs while the control plane is unreachable, so the console can't rely on the control plane alone. Which component emits each alarm, which signed fields it uses, the time source and the behavior on stale telemetry are RFC questions. "Leaked" leaves the vocabulary, because an abandoned lease expires on its own (Annex D). In its place, the project adds its own reconciliation rule, the **unreleased lease**: one still active whose `workId` matches no live instance. Its source of truth and race window are RFC questions.

8. **Conformance.** v0.2 claims no IAMT conformance. A later adapter slice targets interface conformance as an automation adapter (§08.01) at Profile B (§08.04), with reissue, failover and usage submission out of scope, as §08.02 asks a claim to state. Any backend is measured against Annex B endpoints, Annex C claims, Annex D states, OFG-2 policy fields and the §10.08 error model.

9. **v0.2 is declared-only, and the adapter slice is blocked.** The descriptor may carry the `licence:` block, schema-checked, and the console may show it as declared intent. That is the whole v0.2 scope: no adapter, no control-plane call, no launch gate and no lease state anywhere. v0.2 text says "licence declared"; the claim "licensed" waits for the adapter slice. That slice starts only when a function that needs an entitlement exists, or the operator asks for a spike. It also waits until the RFC answers these questions: the `workId` contract; entitlement query and lease lookup; the closing authority; whether teardown needs TERMINATED; the readiness predicate; the grace display contract; the unreleased-lease rule; the modality enum and the #245 alignment. The slice must then show a quota error failing a launch, one lease per `workId` across retries, no active lease after a failed launch, teardown revoking the lease, and the grace alarms.

10. **NetBox records inventory, and the control plane records leases.** NetBox keeps which function runs and how many instances (ADR-0037), and may hold `workId` or `leaseId` as a reference. Lease state, counts, expiry and grace live only in the control plane. A NetBox tag such as `licence:assigned` would claim state NetBox can't hold, so the platform writes none.

## Consequences

- **Positive:** outside publishers build against a published industry model and not a private seam. Lease mechanics, signing and grace stay with the control plane, so the platform builds no ledger.
- **Negative:** the adapter slice waits on the RFC questions in decision 9 and on workload identity the control plane trusts. v0.2 can't claim licensed functions.

## Enforcement

No mechanical enforcement exists yet. discipline only: no schema carries the `licence:` block today. [#634](https://github.com/dmfdeploy/dmfdeploy/issues/634) owns the `licence:` contract in `dmf-media/schemas/dmf-function.schema.json`. The change that adds the block must also add these cases to `dmf-media/tests/conformance/cases.yaml`, with fixtures under `dmf-media/tests/conformance/fixtures/`: good `licence-dimensions-valid` and `licence-absent-valid`; bad `licence-bare-count-rejected` (the old `{class, count}` shape), `licence-duplicate-dimension-rejected`, `licence-zero-quantity-rejected` and `licence-unknown-key-rejected`. It must also update the existing bad case `old-licence-name` (SPDX keys under `licence:`) to expect the entitlement-shape error. Once those cases exist, this section names them as the check.

## Status

Proposed. Revised 2026-10-25 onto the IAMT model; RFC pending.

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0045-media-function-licensing-reservable-resource.md).
