# ADR-0051 archive: ESO's main store authenticates to OpenBao with Kubernetes auth

This file holds the alternatives and the implementation pointers for [ADR-0051](../../decisions/0051-eso-main-store-kubernetes-auth.md). The ADR is the binding record. This file is history and is not maintained.

## Alternatives considered

The RFC, [Discussion #851](https://github.com/orgs/dmfdeploy/discussions/851), section "Alternatives", lists three options. They are not exclusive, and the first two stay available for any AppRole consumer that remains.

- Catch-up rotation on start. Keep AppRole. A least-privilege Kubernetes-authenticated rotator renews an expired SecretID after unseal. It needs a recovery state machine and the same reviewer and API server dependency as the chosen option. The lifecycle plan rejects an expired target that has no recovery state, so this recovery does not exist today.
- Longer TTLs for offline profiles. Set a TTL for each offline profile from a defined operational bound. The change is small, but a cliff remains at the bound, a leaked SecretID stays useful longer, and a lockout still follows an expiry.
- Status quo with daily rotation. Ship the lifecycle plan as written. A long power-off then stays an operator recovery task with break-glass access.

## Where the work lives

- Plan: [eso-kubernetes-auth-migration-plan](../../plans/eso-kubernetes-auth-migration-plan.md). WP3 builds the installer change and the verifier. WP4 rolls out one environment at a time. WP5 removes the AppRole after the window.
- Tracking issue: [#866](https://github.com/dmfdeploy/dmfdeploy/issues/866).
- Experiment evidence: [WP1 result](https://github.com/dmfdeploy/dmfdeploy/issues/866#issuecomment-6712869189) and the [scope decision](https://github.com/dmfdeploy/dmfdeploy/issues/866#issuecomment-6709798849) that allowed direct transient operations and a snapshot-job stand-in.
