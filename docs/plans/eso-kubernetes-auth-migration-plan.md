---
status: active
date: 2026-11-07
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/866
---

# ESO Kubernetes auth migration plan

**Related issues:** [#396](https://github.com/dmfdeploy/dmfdeploy/issues/396),
[#11](https://github.com/dmfdeploy/dmfdeploy/issues/11),
[#864](https://github.com/dmfdeploy/dmfdeploy/issues/864)

**Source:** the RFC in
[Discussion #851](https://github.com/orgs/dmfdeploy/discussions/851) and the
operator's decisions comment on it, dated 2026-11-07. The RFC holds the
evidence and the reasoning. This plan holds the work.

## Goal

Move External Secrets Operator's (ESO) main `openbao` ClusterSecretStore from
AppRole to OpenBao Kubernetes auth. ESO then requests a short-lived
ServiceAccount token at login, so no stored ESO credential can expire while a
cluster is off. This removes the failure that
[#396](https://github.com/dmfdeploy/dmfdeploy/issues/396) records for the
main store.

The benefit is narrow. After a long power-off the ServiceAccount token and the
OpenBao token still expire, and trust roots, the API server, and clocks all
have to work. The plan removes one stored credential from ESO's path. It does
not make the path failure-proof.

## Decided scope

These decisions come from the operator's comment on Discussion #851 and from
[#866](https://github.com/dmfdeploy/dmfdeploy/issues/866). Do not widen or
narrow them in a work package. If a work package needs a different scope,
stop and ask for a new decision.

1. **Experiment first, rollout later.** The prerequisite experiment, including
   its migration step, runs on a disposable environment. A production rollout
   needs a separate operator approval after the experiment passes.
2. **No standing identity writes the Kubernetes auth config.** A new install
   writes it with the initial root token, before that token is disposed of.
   On an installed environment, any later write uses a temporary root token
   from OpenBao's generate-root procedure (a quorum of unseal shares). The
   token is used for that change only, then revoked, and the use is audited.
   This keeps ADR-0021's separation of duties: no routine reconciler or administrator
   identity holds this power.
3. **Only the main store moves.** The two object-storage stores stay on
   AppRole. Moving them is separate later work with its own roles and
   isolation tests.
4. **Profile-scoped ADR.** The decision is recorded through the RFC-to-ADR
   path, with reciprocal supersession links. Hub and edge AppRole (ADR-0022)
   and remote TokenReview trust are out of scope.
5. **14-day rollback window.** The ESO AppRole stays for 14 days after the
   switch. The rotation job from the credential lifecycle plan renews it, so
   it cannot expire or lock out during the window. After that, the role and
   its SecretID are deleted.

## Binding constraints

- Follow ADR-0008, ADR-0021 and ADR-0028: credentials live in OpenBao, identities
  are named, scoped and separated by duty, and every action carries actor,
  role, request id, and reason.
- Do not print a SecretID, a root token, a ServiceAccount token, a userpass
  password or an unseal share in a task result, log, test fixture, or issue
  or PR body. Secret-bearing tasks use `no_log`. Values flow only through
  stdin, files with restrictive modes, or the Kubernetes and OpenBao APIs.
  Record token metadata only, such as expiry and binding claims.
- Run cluster writes only through the sanctioned playbook path.
- A work package changes a live environment only where its text says so.
  WP1, WP4 and WP5 are the only ones that do. WP5 changes one environment at
  a time, through the sanctioned playbook path, and only after the operator
  approves that environment's removal. The approval rests on the evidence
  that WP5 lists for the whole 14-day window.
- ADR-0008 stays binding until the successor ADR is accepted. The
  supersession links take effect at acceptance. No implementation that
  conflicts with ADR-0008 is merged enabled, and none is enabled anywhere but
  a disposable environment, before that acceptance. WP3 may merge only behind
  its off-by-default variable.
- The two object-storage stores, hub and edge AppRole, and every AppRole other
  than ESO's main one are not touched.
- Name no product as a design source. Cite standards and upstream
  documentation.

## Dependencies

- **[#11](https://github.com/dmfdeploy/dmfdeploy/issues/11) and
  [#396](https://github.com/dmfdeploy/dmfdeploy/issues/396), the rotation
  job.** The credential lifecycle plan
  ([openbao-approle-credential-lifecycle-plan](openbao-approle-credential-lifecycle-plan.md))
  ships the daily in-cluster job and the `external-secrets` registry entry
  first. That job keeps the ESO AppRole renewed during the 14-day window. The
  completing PR of this plan removes that registry entry. WP4 cannot start
  until the job is running on the target environment. WP5 removes the entry.
  The two object-storage targets stay in the registry.
- **[#864](https://github.com/dmfdeploy/dmfdeploy/issues/864), Tier 2 operator
  unseal.** The generate-root procedure needs a quorum of unseal shares. Until
  Tier 2 lands, it uses the existing shares under the current unseal
  procedure. Once Tier 2 lands, generate-root uses the phone unseal. This plan
  does not wait for it, and it does not design that flow.
- **The RFC's experiment properties.** WP1 follows the RFC's "Prerequisite
  experiment" section. Its outcomes decide whether the rest of the plan runs.

## Work packages

Each work package fits in one session. The sessions marked "operator present"
need the operator for an approval or for unseal shares.

| WP | Session | Needs from the operator |
|---|---|---|
| WP1 experiment | One live session on a disposable environment | The environment, permission to replace the OpenBao pod, and the unseal shares for the generate-root step |
| WP2 ADR | One writing session, no cluster | Review of the draft, then acceptance after WP1 passes |
| WP3 installer | One or two code sessions in the infra repo, no live writes | A review. The change stays off by default until WP4 |
| WP4 rollout | One live session per environment, operator present | A separate approval after WP1 and WP2, and the unseal shares |
| WP5 removal | A disposable-environment session, then one live session per environment, each 14 days or more after its WP4 | An approval for each environment's removal, based on the window evidence |

WP1 and WP2 can run at the same time. WP3 can start once WP1 has produced a
first result. Only WP4 needs WP1, WP2, and WP3 all done.

### WP1 prerequisite experiment on a disposable environment

**Goal.** Establish whether the token reviewer config on an OpenBao pod can
survive a pod replacement, and prove the temporary-root path for writing the
Kubernetes auth config.

**Inputs and dependencies.** A disposable, isolated environment that runs the
pinned OpenBao and ESO versions. The RFC's "Prerequisite experiment" section.
The sanctioned unseal procedure.

**Properties that must hold.** These are the RFC's properties. The
step-by-step protocol lives in the work order for this package.

- The reviewer mode is the local-file fallback. A version-verified config
  read shows `disable_local_ca_jwt=false` and no stored reviewer JWT.
  OpenBao's ServiceAccount holds TokenReview permission and nothing broader.
- The throwaway test client has no TokenReview permission, so a client-JWT
  review cannot mask the result.
- A baseline fresh login succeeds. After the OpenBao pod is replaced, a fresh
  login under the old config is recorded, and it is expected to fail.
- After the migration, a config read shows the fallback mode. A fresh login
  then succeeds after a pod replacement, before any reapply or repair of the
  reviewer config. Metadata shows that the local reviewer token used before
  has rotated or expired, and a later fresh login succeeds.
- The other Kubernetes-auth clients, including the snapshot job, still log in.
- The throwaway roles, accounts and tokens are removed.
- A least-disruptive recovery path is defined and verified before the run: an
  authorized privileged identity restores a working reviewer config,
  confirmed by a fresh login. A full storage restore is a separate
  contingency with wider effects, and a snapshot can contain the same
  pod-bound reviewer token.
- The migration step writes the auth config with a temporary root token from
  the generate-root procedure. The token is requested, used for that one
  write, revoked, and the use is audited. No other identity gains the power.
  Token values are never logged. The temporary-root path therefore gets the
  same evidence as the reviewer fix, including a check that the token no
  longer works after revocation.

**Outcomes.** Pass: every property is established. Inconclusive, which takes
precedence: the old-config login unexpectedly succeeds, or something
unrelated to the reviewer path fails. Investigate and draw no conclusion.
Fail: with the preconditions holding, a fresh login fails on the migrated
reviewer path. A fail stops the plan and goes back to the RFC for a new
decision.

**Verification evidence.** Redacted evidence in a comment on
[#866](https://github.com/dmfdeploy/dmfdeploy/issues/866): the config reads,
the login results with token metadata only, the audit entries for the
temporary root token (issued, used, revoked), and the cleanup listing.

**Done when.**

- [ ] The recovery path is defined and verified on the disposable environment.
- [ ] Every preceding property has recorded evidence, or the outcome is recorded
      as fail or inconclusive with the reason.
- [ ] The temporary root token was revoked and the audit shows issue, use and
      revoke.
- [ ] The throwaway objects are removed and the environment is back to its
      starting state.
- [ ] The evidence comment is on #866 and the Status section below is updated.

### WP2 profile-scoped ADR

**Goal.** Record the decision in an ADR that supersedes the parts of earlier
ADRs it changes, through the RFC-to-ADR path.

**Inputs and dependencies.** The converged RFC in Discussion #851 and the
decisions comment. The ADR template and conventions in
`docs/decisions/README.md`. WP1's outcome for the acceptance step.

**Properties that must hold.**

- The ADR carries a **Rule:** line that states the binding constraint in one
  imperative sentence, and an `## Enforcement` section that names the
  mechanism or says "discipline only."
- The scope is exactly the decided scope: the main ESO store, the
  generate-root write path, and the 14-day window. Hub and edge AppRole
  (ADR-0022) and the two object-storage stores are named as out of scope.
- Supersession links are reciprocal. ADR-0008's affected part is marked
  superseded and links forward. The new ADR links back to it. The links take
  effect when the ADR is accepted, and ADR-0008 stays binding until then. ADR-0021's
  separation of duties and ADR-0022's contract are cited as unchanged.
- The ADR has a row in the decision index and links the RFC thread.
- Status is Proposed until WP1 passes, and Accepted only after.

**Verification evidence.** The merged ADR, the index row, and the
announcement thread that the RFC process requires after merge.

**Done when.**

- [ ] The ADR draft is reviewed and merged as Proposed, with its links.
- [ ] After WP1 passes and the operator approves, the ADR is Accepted.
- [ ] The announcement thread is posted.
- [ ] The Status section below is updated.

### WP3 installer change

**Goal.** Make a new install use Kubernetes auth for the main store, and make
the same change available to an installed environment, behind a variable that
stays off until WP4.

**Inputs and dependencies.** WP1's first result. The RFC's Appendix A list of
what has to be built. The infra repo's OpenBao and external-secrets roles.

**Properties that must hold.**

- On a new install, the auth config is written with the initial root token
  before that token is disposed of. No standing identity gains the power to
  write it.
- The ESO role is bound to ESO's controller ServiceAccount in its namespace,
  with the same read policy the AppRole has, a short token TTL, and an
  audience that ESO also requests.
- The store applies a `kubernetes` auth block with a ServiceAccount
  reference. A test shows whether a changed auth block replaces or merges
  with the old `appRole` key on an existing store, and the result is handled
  explicitly.
- The switch is behind a variable. With the variable off, the output equals
  today's. With it on, the main store uses Kubernetes auth. The two
  object-storage stores never change.
- The AppRole inputs stay available while the window can still open, so a
  rollback has everything it needs. Every caller that depends on the AppRole
  inputs is listed and checked: bootstrap, restore and provisioning paths,
  the break-glass record of the role fields, and the rotation playbook.
- The existing-install path is idempotent. Reruns change nothing, and the
  order of first run and reruns is stated.
- The identity verifier covers the main store: a newly requested token with
  the right audience, a real fresh authentication, an ExternalSecret that
  refreshes with fresh observed data, and negative tests for a wrong
  ServiceAccount, namespace and audience. The object-storage stores are
  checked on their own.
- The reviewer config is cleared by an explicit, version-verified step if
  WP1 shows it is needed.
- Docs that describe the old shape are updated: the role README, the default
  comment, and the offline lane spec's seed list and auth methods.

**Verification evidence.** Test output for a fresh install and for an
installed environment, each with reapply and restart. Lint and syntax checks
as CI runs them. A list of every caller of the AppRole inputs with its
disposition. No live-environment change.

**Done when.**

- [ ] A fresh install on a disposable environment runs the main store on
      Kubernetes auth, and the verifier passes with the negative tests.
- [ ] The installed-environment path passes on a disposable environment,
      including reapply and restart.
- [ ] With the variable off, nothing changes for any existing environment.
- [ ] The caller list is complete and every caller is covered.
- [ ] The docs are updated and the Status section is updated.

### WP4 rollout to installed environments

**Goal.** Switch the main store on each installed environment, with a tested
way back.

**Inputs and dependencies.** WP1 passed. WP2 accepted. WP3 merged. The
rotation job running on the target environment, so the ESO AppRole is renewed
during the window. A separate, explicit operator approval for the rollout.

**Properties that must hold.**

- The operator's approval names the environment and the date. A passing WP1
  alone is not approval.
- The auth config is written with a temporary root token from generate-root,
  used for that one change, then revoked, with the use audited. No other
  identity writes it.
- The rollout runs through the sanctioned playbook path, one environment at a
  time.
- The verifier from WP3 passes after the switch, and the main store reads
  fresh data from a refreshed ExternalSecret.
- The 14-day window starts at the switch. During it, the ESO AppRole, its
  SecretID and the input contract stay in place, and the rotation job keeps
  the SecretID renewed.
- Rollback restores everything a login needs: the store's `appRole` block, the
  role and its role ID, the Kubernetes Secret, and the input contract. It
  works through an authorized, tested path. It is tested on the disposable
  environment before the first live rollout, and again before the AppRole is
  removed in WP5.
- A rollback that needs the temporary root token follows the same use,
  revoke and audit rule.

**Verification evidence.** For each environment: the approval reference, the
verifier output, the audit entries for the temporary token, the date the
window started, and the rollback test result.

**Done when.**

- [ ] The operator's approval is recorded on #866.
- [ ] The main store runs on Kubernetes auth on the approved environment and
      the verifier passes.
- [ ] The temporary root token is revoked and audited.
- [ ] The window start date is recorded and the rotation job is renewing the
      AppRole.
- [ ] The Status section is updated.

### WP5 remove the ESO AppRole after the window

**Goal.** Delete the ESO AppRole and its SecretID on an environment after a
clean 14-day window, make every install path stop depending on them, and
close out the plan.

**Needs from the operator.** An approval for each environment's removal,
based on the evidence below. A disposable environment for the recovery test.

**Inputs and dependencies.** WP4 done on the environment, and 14 days passed
since its switch. The rotation job from the credential lifecycle plan.

**Properties that must hold.**

- **Eligibility, per environment.** The evidence covers the whole 14-day
  window: ESO login failures, rotation health for the ESO AppRole, and the
  rollback history. The window qualifies only with no ESO login failure in it.
  A login failure, a gap in that coverage, or any rollback restarts the
  window. An environment with no evidence for part of the window is not
  eligible.
- **Recovery test first.** On a disposable environment, after the AppRole is
  removed, the AppRole is recreated, a fresh login succeeds, and the consumer
  is restored. The result is recorded before any production removal.
- **Removal.** The role and its SecretID are deleted on the environment, and
  the Secret, the input contract and the break-glass fields for them are
  removed. Any removal that needs a privileged write follows the temporary
  root token rule.
- **Convergence.** The installer, the restore path, the provisioning path and
  every other caller stop creating or expecting the ESO AppRole. Three runs
  after the removal prove it: a fresh install, a rerun, and a restore from a
  backup taken before the migration. The two object-storage AppRoles stay,
  and the proof shows them unchanged.
- The `external-secrets` entry is removed from the rotation registry. The two
  object-storage entries stay.
- The verifier no longer expects ESO's AppRole, and still passes.
- The flypack offline lane's factory seed no longer includes an ESO AppRole,
  or the spec says why it still does.

**Verification evidence.** Per environment: the window evidence and the
approval, the verifier output after removal, and the deletion audit entries.
Once: the recovery test, the registry diff, and the fresh-install, rerun and
pre-migration-restore results after removal.

**Done when.**

- [ ] The recovery test on a disposable environment is recorded before any
      production removal.
- [ ] Each environment's window evidence is complete and shows no ESO login
      failure, and the operator approved its removal.
- [ ] The role and SecretID are deleted and the leftovers are removed on each
      approved environment.
- [ ] The installer, restore, provisioning and callers no longer create or
      expect the ESO AppRole, proven by a fresh install, a rerun and a restore
      from a pre-migration backup after removal. The object-storage AppRoles
      are intact.
- [ ] The registry entry is gone and the object-storage entries are intact.
- [ ] The completing PR sets `status: executed` and an `executed:` date in the
      frontmatter, moves this plan to `docs/archive/plans/`, fixes the links
      to it, regenerates the plans index, and closes
      [#866](https://github.com/dmfdeploy/dmfdeploy/issues/866) with a
      qualified `Closes` reference.

## Status

Update this table as the work moves. Each row links the evidence.

| WP | Status | Links |
|---|---|---|
| WP1 experiment | not started | |
| WP2 ADR | not started | |
| WP3 installer | not started | |
| WP4 rollout | not started | |
| WP5 removal | not started | |

Allowed values: not started, in progress, done. Add the window start date to
the WP4 row when it begins.

## Out of scope

- The two object-storage stores. Their long-offline recovery stays with the
  credential lifecycle plan until a separate decision moves them.
- Hub and edge AppRole (ADR-0022) and remote TokenReview trust.
- The generate-root phone unseal, which belongs to
  [#864](https://github.com/dmfdeploy/dmfdeploy/issues/864).
- Choosing an ESO retry interval. The RFC proposes no number because none is
  shown to work across several stores and controllers.
