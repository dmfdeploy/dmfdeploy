# ADR-0051: ESO's main store authenticates to OpenBao with Kubernetes auth

**Status:** Accepted
**Date:** 2026-11-07
**Deciders:** operator
**Amended:** 2026-11-09: the `eso-reader` policy no longer grants certificate issuance, and Enforcement names the verifier. See §Amendment 2026-11-09. Also 2026-11-18: generate-root needs an authenticated caller; the approval executor and a standing revoker get their own identities, and `ops-admin` loses the `generate-root` policy. See §Amendment 2026-11-18.
**Supersedes/amends:** [ADR-0008](0008-openbao-secrets-architecture.md), for the External Secrets Operator (ESO) login method of the main store only.
**Rule:** Authenticate the main `openbao` ClusterSecretStore with Kubernetes auth, and write its auth config only with the initial root token on a new install or with a short-lived token traded from a generate-root token for that one change, then explicitly revoked and audited.

## Context

ESO's main store logs in with an AppRole ([ADR-0008](0008-openbao-secrets-architecture.md) Decision) whose SecretID has a 720-hour TTL
([credential lifecycle plan](../plans/openbao-approle-credential-lifecycle-plan.md), "Current state and gap"). A cluster that stays off longer than the TTL restarts with an expired SecretID, and no rotation job could have run. [#396](https://github.com/dmfdeploy/dmfdeploy/issues/396) records this failure on a sandbox environment. The argument is in the RFC, [Discussion #851](https://github.com/orgs/dmfdeploy/discussions/851), in its "Problem" section.

Kubernetes auth removes that stored credential. Two facts make the move more than a store edit. The config the installer writes today stores the OpenBao pod's own token as the reviewer credential, and the experiment in the plan's WP1 showed that this token fails after a pod replacement ([evidence](https://github.com/dmfdeploy/dmfdeploy/issues/866#issuecomment-6712869189)). And on an installed environment no standing identity is meant to hold that power. A read-only check found that the ops-admin user and the two [ADR-0021](0021-openbao-approle-reconciler-identity.md) reconcilers each get 403 when they read `auth/kubernetes/config`, and the root token is disposed of after init ([RFC comment, 2026-11-07](https://github.com/dmfdeploy/dmfdeploy/discussions/851#discussioncomment-19454657)). That check covers reads only. The rule that no standing identity writes the config comes from the operator's decision below.

## Decision

The operator decided these points on 2026-11-07 ([decisions comment](https://github.com/dmfdeploy/dmfdeploy/discussions/851#discussioncomment-19459895)).

1. **Main-store login.** The main `openbao` ClusterSecretStore uses the OpenBao [Kubernetes auth method](https://openbao.org/docs/auth/kubernetes/). The role binds to ESO's controller ServiceAccount in its namespace. It carries the AppRole's `eso-reader` policy, a short token TTL, and an audience that ESO also requests (items 1 and 2 of the "Proposal" section in the RFC). That policy reads the application secret paths and grants nothing on the PKI mount (§Amendment 2026-11-09).
2. **Reviewer mode.** OpenBao runs as its own ServiceAccount. A ClusterRole grants that account `create` on `tokenreviews` and nothing else, so it is not bound to `system:auth-delegator`, which also grants SubjectAccessReviews. The mount reviews tokens through the [TokenReview API](https://kubernetes.io/docs/reference/kubernetes-api/authentication-resources/token-review-v1/) with the pod's local token file: `token_reviewer_jwt_set=false` and `disable_local_ca_jwt=false`. OpenBao re-reads that file, so a rotated token keeps working.
3. **Config writer.** On a new install, the installer writes the config with the initial root token before that token is disposed of. On an installed environment, a later write needs a root token from the [generate-root procedure](https://openbao.org/docs/api/system/generate-root/). The procedure needs an authenticated caller and a quorum. From OpenBao 2.6 the command calls only the authenticated endpoints, so the caller holds a token with the `generate-root` policy, which grants those endpoints and nothing else. The quorum is the unseal shares under a Shamir seal, or the recovery keys under an auto-unseal seal. In the sandbox lane, one enrolled administrator device meets the recovery threshold alone.

   Only the approval executor holds the `generate-root` policy (§Amendment 2026-11-18). It can start or cancel a request. It finishes one only with recovery keys that an enrolled device releases for one approved session. Before it finishes the request, it writes an intent entry to the audit record; no root token is created unless that entry is written. With the root token the procedure returns, the executor at once creates one orphan token with the root policy, a lifetime of 15 minutes at most, and no renewal, records both accessors, and revokes the generated token before the first write. It revokes the orphan token when the change ends. The orphan token isn't revoked with its parent, so its explicit revocation and the standing revoker are what bound it. No other identity can finish a root token request.

   The installer's initial root token is the one root token created outside the executor. It exists before the audit record does. The installer revokes it when the install ends and writes the record's first entry, which says so.
4. **Rollback window.** The ESO AppRole stays for at least 14 days after the switch. The rotation job from the [credential lifecycle plan](../plans/openbao-approle-credential-lifecycle-plan.md) renews its SecretID, so it cannot expire or lock out in that time. Removing the role and its SecretID from an installed environment is conditional. It needs a full 14-day window with complete evidence and no ESO login failure, the operator's approval for that environment, and a recorded recovery test from a disposable environment before the first such removal. A login failure, an evidence gap or a rollback restarts the window ([plan](../plans/eso-kubernetes-auth-migration-plan.md), WP5).
5. **Rollout.** This ADR approves no rollout. Each environment needs its own operator approval after the experiment passes ([plan](../plans/eso-kubernetes-auth-migration-plan.md), WP4).

**Out of scope.** The two object-storage stores stay on AppRole. Hub and edge AppRole ([ADR-0022](0022-flypack-online-thin-edge-agent.md)) and remote TokenReview trust are separate decisions.

**Unchanged.** ADR-0021's separation of duties holds: no routine reconciler or administrator identity holds the `generate-root` policy, and no standing identity writes the Kubernetes auth config. ADR-0022's per-edge AppRole contract holds.

## Consequences

- Positive: no stored ESO credential expires while a cluster is off. The gain is narrow. The ServiceAccount token and the OpenBao token still expire, and trust roots, the API server and clocks must work after a restart.
- Negative: each login needs the API server, and each installed-environment config write needs a generate-root quorum: unseal shares under a Shamir seal, or recovery keys under an auto-unseal seal, which one enrolled admin device meets in the sandbox lane once the [Tier 2 operator unseal plan](../plans/operator-unlock-tier2-plan.md) lands. A write is a planned change and never a routine operation.
- Neutral: the reviewer config is shared by every Kubernetes-auth login on the mount. The plan's WP4 requires the real snapshot job and every other client to log in, and the API server audit log to show a rejected TokenReview, before an environment switches.

## Enforcement

The identity verifier, `dmf-infra/k3s-lab-bootstrap/playbooks/verify-openbao-identity-model.yml`, checks the main store. It logs in as ESO with a newly requested ServiceAccount token, forces an ExternalSecret to refresh through the store, and shows that a wrong ServiceAccount, namespace or audience is refused. A negative write probe shows that each standing identity gets 403 when it writes `auth/kubernetes/config`. Another probe shows that the ESO token has no capability on the PKI issue path. In either ESO auth mode, the verifier also reads the live `eso-reader` policy and fails on any stanza that covers the PKI mount. The policy files in `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/files/policies/` bound the paths each identity can use. The identity verifier fails if an auth method outside its allowlist is enabled. The allowlist is a variable of the verifier playbook and holds the methods the OpenBao role enables. On each enabled method, and on identity groups, it fails if any principal other than the executor carries the `generate-root` policy, or any principal other than the revoker carries the revoker's policy. The revocation of each root token after its change is backed by the standing revoker.

### Amendment 2026-11-09

Reopens no decision. Two corrections:

- **The policy grants no certificate issuance.** Decision 1 kept the `eso-reader` policy unchanged, and that policy also granted issuance on the internal CA. A check found no user of that grant: no ExternalSecret, PushSecret or generator points at a PKI path, no issuer uses OpenBao, and the PKI mount has no issuer configured. The grant is removed, and the verifier checks that the ESO token holds no capability on the PKI issue path ([#881](https://github.com/dmfdeploy/dmfdeploy/issues/881)).
- **Enforcement names the verifier.** The plan's WP3 verifier coverage has landed, so Enforcement names the playbook and its probes, as the section required.

### Amendment 2026-11-18

Accepted by the operator in [RFC Discussion #907](https://github.com/orgs/dmfdeploy/discussions/907) ([acceptance](https://github.com/orgs/dmfdeploy/discussions/907#discussioncomment-19713213)). It records the authenticated generate-root caller and two identities that the [operator unseal plan](../plans/operator-unlock-tier2-plan.md) and its [WP5/WP9 build plan](../plans/operator-unlock-wp5-wp9-build-plan.md) add (decision 55).

- Authenticated caller. From OpenBao 2.6, generate-root needs a token with the `generate-root` policy as well as a quorum (#902, dmf-infra#147). An identity with the policy and no quorum can start and cancel a request, and can't finish one.
- Approval executor. A Kubernetes auth role bound to the executor's ServiceAccount. Its only policy is `generate-root`. It holds no stored credential: it logs in with its projected ServiceAccount token for each approved session and revokes its login token on every exit path. A NetworkPolicy admits only cluster-internal callers.
- Standing revoker. A Kubernetes auth role bound to the revoker's ServiceAccount. Its policy grants `list` with `sudo` on `auth/token/accessors`, and `update` on `auth/token/lookup-accessor` and `auth/token/revoke-accessor`, and no other path. It revokes every executor token that outlives its change. It also revokes every token with the root policy whose accessor the audit record doesn't hold, when the record has no open intent entry or the token is older than 5 minutes. It scans every minute. The executor abandons any request that runs longer than 2 minutes, so the grace period covers every request still in progress. Token age is measured from the token's creation time on the OpenBao server. A token left by a crash between the mint and the record write lives 6 minutes at most. Slice B tests both bounds. The revoker starts only after the install has finished. These grants are wide: a compromised revoker can list every token's metadata and revoke any token, which can deny service. It can't create a token or read a secret.
- `ops-admin` loses the `generate-root` policy on an environment once the executor is live there. The playbook that deploys the executor removes the policy from `ops-admin` in the same run, after the executor passes its check, and the 2.6 preflight then requires the policy on the executor's role. From then on, the password and the recovery keys together are no second path to a root token. The callers move with it: the credential rotation becomes an entry in the executor's catalogue, the `dmf-env` temporary root helper retires on that environment, and the role README's manual procedure points to a rebuild. Until then, `ops-admin` keeps the policy and the callers of 2026-11-14 keep working.
- When the executor can't run, no normal path to a root token remains. OpenBao's recovery mode with the recovery keys gives only a short-lived recovery token for repairs to storage. It gives no root token, and the procedure is hazardous. In the sandbox lane, a rebuild is the accepted way back. Long-lived sites decide their way back before they drop the policy from `ops-admin`.

## Status

Accepted, 2026-11-08, by the operator. Proposed 2026-11-07, after the plan's WP1 passed with a snapshot-job stand-in. ADR-0008 is Partially superseded by this ADR.

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0051-eso-main-store-kubernetes-auth.md).
