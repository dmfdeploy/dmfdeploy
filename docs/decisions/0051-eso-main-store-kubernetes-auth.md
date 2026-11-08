# ADR-0051: ESO's main store authenticates to OpenBao with Kubernetes auth

**Status:** Proposed
**Date:** 2026-11-07
**Deciders:** operator
**Supersedes/amends:** [ADR-0008](0008-openbao-secrets-architecture.md), for the External Secrets Operator (ESO) login method of the main store only. The supersession takes effect when this ADR is Accepted. Until then ADR-0008 binds.
**Rule:** Authenticate the main `openbao` ClusterSecretStore with Kubernetes auth, and write its auth config only with the initial root token on a new install or with a generate-root token used for that one change, then explicitly revoked and audited.

## Context

ESO's main store logs in with an AppRole ([ADR-0008](0008-openbao-secrets-architecture.md) Decision) whose SecretID has a 720-hour TTL
([credential lifecycle plan](../plans/openbao-approle-credential-lifecycle-plan.md), "Current state and gap"). A cluster that stays off longer than the TTL restarts with an expired SecretID, and no rotation job could have run. [#396](https://github.com/dmfdeploy/dmfdeploy/issues/396) records this failure on a sandbox environment. The argument is in the RFC, [Discussion #851](https://github.com/orgs/dmfdeploy/discussions/851), in its "Problem" section.

Kubernetes auth removes that stored credential. Two facts make the move more than a store edit. The config the installer writes today stores the OpenBao pod's own token as the reviewer credential, and the experiment in the plan's WP1 showed that this token fails after a pod replacement ([evidence](https://github.com/dmfdeploy/dmfdeploy/issues/866#issuecomment-6712869189)). And on an installed environment no standing identity is meant to hold that power. A read-only check found that the ops-admin user and the two [ADR-0021](0021-openbao-approle-reconciler-identity.md) reconcilers each get 403 when they read `auth/kubernetes/config`, and the root token is disposed of after init ([RFC comment, 2026-11-07](https://github.com/dmfdeploy/dmfdeploy/discussions/851#discussioncomment-19454657)). That check covers reads only. The rule that no standing identity writes the config comes from the operator's decision below.

## Decision

The operator decided these points on 2026-11-07 ([decisions comment](https://github.com/dmfdeploy/dmfdeploy/discussions/851#discussioncomment-19459895)).

1. **Main-store login.** The main `openbao` ClusterSecretStore uses the OpenBao [Kubernetes auth method](https://openbao.org/docs/auth/kubernetes/). The role binds to ESO's controller ServiceAccount in its namespace. It carries the same read policy as the AppRole, a short token TTL, and an audience that ESO also requests (items 1 and 2 of the "Proposal" section in the RFC).
2. **Reviewer mode.** OpenBao runs as its own ServiceAccount. A ClusterRole grants that account `create` on `tokenreviews` and nothing else, so it is not bound to `system:auth-delegator`, which also grants SubjectAccessReviews. The mount reviews tokens through the [TokenReview API](https://kubernetes.io/docs/reference/kubernetes-api/authentication-resources/token-review-v1/) with the pod's local token file: `token_reviewer_jwt_set=false` and `disable_local_ca_jwt=false`. OpenBao re-reads that file, so a rotated token keeps working.
3. **Config writer.** On a new install, the installer writes the config with the initial root token before that token is disposed of. On an installed environment, any later write uses a temporary root token from the [generate-root procedure](https://openbao.org/docs/api/system/generate-root/). That procedure needs a quorum of unseal shares under a Shamir seal, and a quorum of recovery keys under an auto-unseal seal. In the sandbox lane, one enrolled admin device meets the recovery threshold alone once the posture in the [Tier 2 operator unseal plan](../plans/operator-unlock-tier2-plan.md) lands. Use the token for one change, revoke it, and leave audit entries for its issue, use and revoke. No other identity gains this power.
4. **Rollback window.** The ESO AppRole stays for at least 14 days after the switch. The rotation job from the [credential lifecycle plan](../plans/openbao-approle-credential-lifecycle-plan.md) renews its SecretID, so it cannot expire or lock out in that time. Removing the role and its SecretID from an installed environment is conditional. It needs a full 14-day window with complete evidence and no ESO login failure, the operator's approval for that environment, and a recorded recovery test from a disposable environment before the first such removal. A login failure, an evidence gap or a rollback restarts the window ([plan](../plans/eso-kubernetes-auth-migration-plan.md), WP5).
5. **Rollout.** This ADR approves no rollout. Each environment needs its own operator approval after the experiment passes ([plan](../plans/eso-kubernetes-auth-migration-plan.md), WP4).

**Out of scope.** The two object-storage stores stay on AppRole. Hub and edge AppRole ([ADR-0022](0022-flypack-online-thin-edge-agent.md)) and remote TokenReview trust are separate decisions.

**Unchanged.** ADR-0021's separation of duties holds: no routine reconciler or administrator identity holds the power in point 3. ADR-0022's per-edge AppRole contract holds.

## Consequences

- Positive: no stored ESO credential expires while a cluster is off. The gain is narrow. The ServiceAccount token and the OpenBao token still expire, and trust roots, the API server and clocks must work after a restart.
- Negative: each login needs the API server, and each installed-environment config write needs a generate-root quorum: unseal shares under a Shamir seal, or recovery keys under an auto-unseal seal, which one enrolled admin device meets in the sandbox lane once the [Tier 2 operator unseal plan](../plans/operator-unlock-tier2-plan.md) lands. A write is a planned change and never a routine operation.
- Neutral: the reviewer config is shared by every Kubernetes-auth login on the mount. The plan's WP4 requires the real snapshot job and every other client to log in, and the API server audit log to show a rejected TokenReview, before an environment switches.

## Enforcement

Discipline only: nothing yet checks that the main store uses Kubernetes auth, or that a standing identity gets 403 when it writes `auth/kubernetes/config`. The plan's WP3 adds verifier coverage for the main store: a fresh login and negative tests for a wrong ServiceAccount, namespace and audience. When it lands, this section must name that playbook and its probes. No planned work checks the writer prohibition, so that part stays discipline only until a probe for it is added.

## Status

Proposed, 2026-11-07. The plan's WP1 passed with a snapshot-job stand-in. The ADR becomes Accepted when the operator approves it. On acceptance, ADR-0008 becomes Partially superseded by this ADR.

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0051-eso-main-store-kubernetes-auth.md).
