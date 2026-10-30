---
status: active
date: 2026-10-27
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/568
---

# dmf-cms exact-SHA release gate

## Outcome

A dmf-cms release runs unattended from CI. When a release-bump commit lands on
`main` and every required check passes on that exact commit, a release
workflow builds the image, publishes it, and creates the `v<VERSION>` tag. No
person starts the run, and no pre-merge result can stand in for a result on
the shipped commit. The run is reproducible from the workflow log and the
tagged source.

`VERSION` stays the version source. `scripts/release.sh` stays the bump path.
`scripts/build-image.sh` and `scripts/publish-to-ghcr.sh` stay the build and
publish path. Playbooks 630 (mirror) and 650 (deploy) stay operator-run, and
this work does not touch them. Rollback is a new version.

This plan authorizes no tag, push, mirror, deployment, or secret retrieval.

## Current evidence

- dmf-cms allows only rebase merges. `main-protection` is the only ruleset on
  a branch and covers only `main`. It requires one code-owner review and
  twelve contexts: `actionlint`, `commitlint`, `dco`, `gitleaks`,
  `issue-link`, `test (3.12)`, `test (3.13)`, `trivy`, `working-model`,
  `frontend`, `frontend-e2e`, and `review-comments`. The checks are not
  strict, so a merge does not require a fresh result on the rebased commit.
- The `automerge` workflow arms auto-merge with `GITHUB_TOKEN`. GitHub does
  not start workflows for events that this token causes, so the rebased
  commit on `main` never gets checks. This is the root cause in
  dmfdeploy/dmfdeploy#568. GitHub documents that a GitHub App installation
  token does not have this limit.
- `ci.yml` (`CI`) and `guard.yml` (`guard`) run on pushes to `main`. Of the
  ten jobs they hold, nine run on a push. The `commitlint` job in `guard.yml`
  has `if: github.event_name == 'pull_request'`, so it is skipped on a push.
  `dco.yml` (`DCO`) and `issue-link.yml` (`issue-link`) run only on pull
  requests, and `issue-link` has the same `if` on its job.
- Two tag rulesets are active. `tags-nonrelease-block` blocks creation,
  update, and deletion of tags other than `v*`. `tags-release-protect` blocks
  update and deletion of `v*` tags. Nothing blocks creating a `v*` tag, so a
  manual tag can skip publication.
- `CODEOWNERS` assigns `/.github/` to the maintainers team. The default
  workflow token permission is `write` today.

## Design

Two GitHub Apps owned by the `dmfdeploy` organization and installed only on
dmf-cms. The plan uses two so that the key that can create release tags
exists in one place only.

| App | Job | Key lives in |
|---|---|---|
| `dmf-cms-automerge` | Arms auto-merge on pull requests | Environment `automerge` |
| `dmf-cms-release` | Creates `v*` tags | Environment `release` |

Both environments allow deployment only from `main` and have no required
reviewers. Each environment holds its App's Client ID and private key as
secrets: `AUTOMERGE_APP_CLIENT_ID` and `AUTOMERGE_APP_PRIVATE_KEY` in
`automerge`, and `RELEASE_APP_CLIENT_ID` and `RELEASE_APP_PRIVATE_KEY` in
`release`. The token action takes the Client ID.

### Merge, which fixes #568

The `automerge` workflow mints an installation token for `dmf-cms-automerge`
and arms rebase auto-merge with it. A merge that GitHub performs for that
App is an event from an App token, so the push to `main` starts the normal
workflows on the rebased commit.

Arming has a fallback, so a release pull request never waits for a person.
The step tries `enablePullRequestAutoMerge`. If GitHub reports the clean
status, all required checks have already passed and the pull request is
mergeable, so the step merges it directly with the same App token and the
rebase method. A direct merge by the App is attributed to the App, so the push
workflows run on the merged commit. The workflow
retries on every later trigger, so a pull request whose arm failed for a
transient reason is armed again. Arming and merging are idempotent: an already
armed or already merged pull request is a success, and any other failure fails
the step and shows in Actions.

Triggers. Today `automerge` runs on `pull_request_target`. GitHub plans to
block that event by default in public repositories on 2026-12-02 unless an
Actions event policy allows it. The new design does not use it. The workflow
runs on `workflow_run` when `CI` completes, and on a `schedule` that sweeps
open pull requests. Both run from the default branch, so the `automerge`
environment, limited to `main`, can release the App key, and neither needs an
event policy. This keeps the key out of reach of pull request code with the
least privilege, and it needs no setting that a Free-plan repository may lack.
The schedule covers the changes that start no `CI` run: a draft marked ready,
and a `hold` label removed.

The workflow never checks out or runs pull request code. Both paths read the
pull request itself through the API and never trust an event payload. Every
pull request must pass the shared eligibility rule: open, ready for review, base
`main`, head in this repository, and no `hold` label. Each path then adds its
own selection and expected head.

- **Event path (`workflow_run` on `CI`).** Only a `CI` run of a pull request
  starts work. A `CI` run of a push is skipped. The pull requests API selects
  the pull request for `workflow_run.head_sha`. The expected head is that SHA, and
  the pull request's live head must equal it.
- **Schedule path.** The sweep lists open pull requests into `main`, 100 per
  page, and follows pagination to the end. For each one it reads the live head
  SHA, which becomes the expected head. It acts only if the Actions runs for
  that head SHA and the `CI` workflow include a completed run with conclusion
  `success`. A missing, in-progress, cancelled, or failed `CI` run means it
  does nothing for that pull request and reports no error. GitHub still checks
  the other required contexts and the review when it arms or merges.

On both paths, arming passes the expected head as `expectedHeadOid` and the
direct merge passes it as `sha`. If the head changes after the read, the call matches
nothing, and the next run handles the new head. One pull request's error does
not stop the sweep, and the run ends non-zero if any pull request hit an
unexpected error. The sweep runs every 10 minutes, at minutes 3, 13, 23, 33,
43, and 53 of the hour, off the top of the hour when scheduled runs queue up.
A pull request that becomes eligible waits at most one interval, plus any delay
GitHub adds to scheduled runs under load.

The `hold` label stops a merge. Two paths disarm auto-merge. A separate
`hold-disarm` workflow runs on `pull_request` `labeled` for the `hold` label.
It uses only `GITHUB_TOKEN` with `pull-requests: write`, no environment, and no
secrets, and it checks out nothing. For a pull request from a fork, the token is
read-only and the call fails, which is acceptable because `automerge` never arms
a fork pull request. The sweep also disarms any held pull request that has
auto-merge enabled, whether or not its `CI` run passed, so a failed disarm is
corrected within one interval. A failed disarm fails the run so it shows in
Actions.

Three required contexts have no passing run on a push today: `dco`,
`issue-link`, and `commitlint`. Each reads pull request data from the event
payload, which a push does not carry. On a push, each of them finds the merged
pull request from the commit and validates it and all its commits. An empty or
unresolvable result fails, and so does a commit that several merged pull
requests claim. A bot push with no pull request therefore fails these three
contexts. The lookup retries up to four times, five seconds apart, because the
commit-to-pull-request association can lag behind the push. `dco` and
`issue-link` gain a push trigger on
`main`. `commitlint` already has one, through `guard`, and loses its
pull-request-only condition.

Property: for every merge to `main`, each of the twelve required contexts has
a completed `success` check run from GitHub Actions on the merged commit, under
that exact context name. A skipped run does not count, so every required job
runs on push. For `dco`, `issue-link`, and `commitlint`, the run is produced by
validating the merged pull request and its commits for that SHA.

This table lists what each context does on a push to `main` today.

| Context | Workflow (display name) | Runs on push today | Change |
|---|---|---|---|
| `test (3.12)` | `CI` | Yes | None |
| `test (3.13)` | `CI` | Yes | None |
| `frontend` | `CI` | Yes | None |
| `frontend-e2e` | `CI` | Yes | None |
| `review-comments` | `CI` | Yes | None |
| `working-model` | `CI` | Yes | None |
| `gitleaks` | `guard` | Yes, scans the tree | None |
| `trivy` | `guard` | Yes | None |
| `actionlint` | `guard` | Yes | None |
| `commitlint` | `guard` | Skipped | Run on push and validate the merged pull request's commits |
| `dco` | `DCO` | No, no push trigger | Add the push trigger and validate the merged pull request's commits |
| `issue-link` | `issue-link` | No, no push trigger, job skipped | Add the push trigger, drop the job condition, and validate the merged pull request |

`CI` and `guard` cancel an in-progress run when another push to `main` arrives.
A cancelled run is not a success, so the older commit fails the check gate and
is never released. A newer push to `main` supersedes it.

### Release, which runs unattended

The `release` workflow starts on `workflow_run` when `CI`, `guard`, `DCO`, or
`issue-link` completes. These are the exact `name:` values of the workflow
files. `workflow_run.workflows` matches display names, so a different spelling
starts no run. The workflow acts only on runs with event `push` on branch
`main`. `workflow_run` workflows run
from the default branch, so only reviewed code on `main` defines the trigger.
The workflow has no `workflow_dispatch`, no inputs, and no user-selected ref.
It reads the commit from `github.event.workflow_run.head_sha`. The value of
`github.sha` is the head of `main`, which can differ.

The workflow has two jobs. The `verify` job has no concurrency group, no
environment, and read-only permissions. It decides readiness: the commit is a
release bump, is reachable from `main`, and has a fresh `success` for every
required context. A non-release push, and a run that is not the last required
workflow to complete, ends in `verify` as a no-op and never enters a group. The
`release` job has `needs: verify` and runs only when `verify` reports ready.
It alone carries the job-level `concurrency` group, with
`cancel-in-progress: false`, the `release` environment, and the write
permissions. It takes only the SHA from `verify` and repeats checks 1 to 3
below from that SHA. Check 4 and the tag creation then run in the serialized
step.

The repository variable `RELEASE_ENABLED` gates `verify`. While it is not
`true`, `verify` is skipped, so `release` is skipped too and the workflow is
inert. An owner sets it last in the rollout. `verify` also acts only on a `push`
run on `main` whose head repository is this repository.

Property: the release run that starts when the last required workflow
completes on the push SHA sees every required context green and continues. Each
earlier run ends without releasing and without a failure, and writes only a
notice that names the contexts still pending. A required context that finished
with a failure or a cancellation is a failure of the run for that SHA.

Invariant: a `v*` tag names a release-bump commit that is an ancestor of `main`
when the tag is created, has a `success` result for every required context on
that exact SHA, and has a version that no existing `v*` tag exceeds. The tagged
commit does not have to be the head of `main` at tag time. The release job
cannot make "head of `main`" and "create the tag" one atomic step, because the
tag API takes no condition on another ref, so a merge can land between the
check and the tag. Such a merge only means a newer commit exists. The tag
still names a commit that passed the full gate, and the image, its labels, and
its attestation all name that same commit. The remaining harm is a tag on a
commit that is not the newest. The next release supersedes it, and rollback is
a new version, so the harm is acceptable.

The `verify` job runs checks 1 to 3. The `release` job runs them again and
then check 4.

1. **Reachable from `main`.** The commit is an ancestor of `main` (or equals
   it), checked with the compare API now and again immediately before the tag
   is created. A commit that is not reachable ends the run without a tag. On a
   protected `main` this cannot happen, and the check stays as a guard.
2. **Release bump.** The commit subject is exactly `chore(release): v<VERSION>`,
   the commit changes `VERSION`, and `VERSION` at that commit reads the same
   version. A qualified issue reference is on the commit or on its merged pull
   request.
3. **Every required check.** The job reads the live `main-protection` ruleset
   and requires each listed context to have a fresh, completed `success` check
   run from the GitHub Actions app (integration ID 15368) on that exact commit.
   Each check run must belong to the check suite of the push run of the owning
   workflow on `main` for that SHA, so a result from a pull request run or a
   re-run on another ref does not count. Each ruleset entry's `integration_id`
   must be empty or 15368. Missing, failed, skipped, neutral, stale, and
   foreign-app runs fail the check, and so do duplicate or empty context names
   and anything but exactly one active `main-protection` ruleset. A second
   ruleset that requires status checks on `main` fails the check, and so does a
   live context list that differs from the contexts mapped to the four
   workflows. A context whose run has not finished counts as pending.
   Results on the pull request head do not count.
4. **Version order and tag state.** No existing `v*` tag is higher than
   `VERSION`. An existing tag equal to `VERSION` is accepted only when it names
   the same verified SHA. Then tag creation is a no-op and the job continues
   to image verification and publication. An equal tag at a different SHA, or
   any higher tag, is a hard failure. The job lists the tags in the serialized
   step that creates the tag (see Concurrency and stuck states), so the list
   cannot go stale.

The job then:

1. Checks out the exact commit, builds with `scripts/build-image.sh`, and
   checks the image's version and revision labels against `VERSION` and the
   commit. A mismatch fails before any push. This covers
   dmfdeploy/dmfdeploy#667.
2. Publishes through the shared helper, with the job's short-lived token on
   standard input and a terminating newline:

   ```sh
   printf '%s\n' "$publisher_token" | scripts/publish-to-ghcr.sh
   ```

   The job sets `GHCR_USER` to `github.actor` and
   `DOCKER_HOST=unix:///var/run/docker.sock` for the hosted runner's Docker
   daemon. If the image already exists, the job verifies its labels and never
   overwrites a mismatched image.
3. Creates the provenance attestation for the published digest (see
   Provenance).
4. Creates `v<VERSION>` as `dmf-cms-release`, last. The tag push does not
   start another workflow.

Only a job in the `release` environment can read the `dmf-cms-release` key.
The job passes it to the token action as an input, so it never enters the
environment, and requests only the permission it needs.

### Concurrency and stuck states

- **Order between releases.** One concurrency group serializes release runs
  without cancelling the one in progress. The version-order check and the tag
  creation run inside the same job in that group, so no other release run can
  create a tag between them. Creating a ref that exists fails, so two tags for
  one version cannot both exist. A run that finds its own tag at the verified
  SHA skips the creation and continues. GitHub keeps one running and one
  pending job per group, and a newer pending job replaces an older pending one.
  Only a ready release reaches the group, so a non-release push can never
  replace a pending ready release. A later ready release can replace an earlier
  pending one. That is acceptable: the later release commit contains the
  earlier one, the version rule allows a skipped version, and the replaced run
  releases nothing. No run tags a version below an existing tag or over a tag
  at another commit. No person has to re-run anything for this case.
- **Order against merges.** A merge to `main` after verification and before the
  tag does not stop the release, and the release tags the verified commit. See
  the invariant above. A change merged after a release bump, before its checks
  finish, does not make the bump stale by itself. If the bump's checks were
  cancelled by the newer push, open a new release PR.
- **CI fails on the merged commit.** No release. The failed run is visible in
  Actions and on the commit. Fix forward with a new release PR.
- **A required check is still running.** The run ends without a tag. The
  workflow that completes last continues.
- **App token cannot be minted.** The run fails before any build or push.
  No tag exists. The run fails visibly. The next ready release recovers, and
  re-running the failed run from the Actions page is a safe shortcut.
- **Re-run.** A re-run is a convenience, never a requirement. Re-running the
  workflow repeats every check. It takes no input.
  It succeeds only if the commit is still reachable from `main` and the
  version rule above still holds. After a successful tag, a re-run finds the
  tag at the same SHA, does not recreate it, and continues.
- **Image exists, tag does not.** The job verifies the image labels and
  digest, then creates the tag.
- **Tag exists, image does not.** The tag can exist only at the verified
  commit, because only `dmf-cms-release` can create it. The version rule
  accepts the tag as a no-op. The job builds and publishes, then verifies.

### Tag ruleset

A new ruleset, `tags-release-create`, restricts creation of `refs/tags/v*`.
Its only bypass actor is `dmf-cms-release`, an `Integration` actor. Keep
`tags-nonrelease-block` and `tags-release-protect` as they are. The repository-wide
GitHub Actions bypass is not used.

Before the release job creates the tag, and before it builds or pushes an
image, it reads the rulesets with its own token and fails closed unless exactly
one ruleset named `tags-release-create` is active, has target `tag`, includes
exactly `refs/tags/v*` with no narrowing exclude, and has the `creation` rule.
A missing, duplicate, disabled, or drifted ruleset means no tag and no image.
The job cannot read the bypass actors, because GitHub returns `bypass_actors`
only to a caller with write access to the ruleset. The property that
`dmf-cms-release` is the sole bypass actor is therefore a rollout check by the
owner (rollout step 4).

### Provenance

In scope now: the release job attaches a GitHub build-provenance attestation
to the published digest, from the same run that built it. Property: the
digest has an attestation that verifies against this repository, the `release`
workflow, and the commit. Only the release job gets `id-token: write` and
`attestations: write`. Playbook 630 can verify the attestation and digest
before a mirror; wiring that check into 630 is a separate issue and changes
no playbook here.

Follow-up, out of scope now: a separate `cosign` keyless signature on the image.
The attestation is already a Sigstore-signed statement, so a second signature
adds a verification path without a new property.

### Trust boundary and residual risk

Only a job that runs in the `release` environment on `main` can use the
`dmf-cms-release` key, so only reviewed code on `main` can create a `v*` tag.
A fork, another workflow, and another branch cannot mint the token.

These people stay inside the boundary: anyone who can change the `release`
environment settings, and anyone who can merge to `main` without review. The
mitigations are `main-protection` with code-owner review, `CODEOWNERS` on
`/.github/`, and the environment's branch policy. `file_path_restriction` is
not available for a public repository, and no rule requires review for
workflow files on branches other than `main`. Those branches stay a residual
risk for the `dmf-cms-automerge` key only, which cannot create a `v*` tag and
cannot merge without approval and passing checks.

The default workflow token permission is `read`. Every workflow declares a
top-level read-only `permissions` block. A job requests write only where it
needs it: `pull-requests: write` for `hold-disarm`, which uses only
`GITHUB_TOKEN`; `packages: write`, `id-token: write`, and `attestations: write` for the
release job. The `automerge` job reads with `actions: read` and makes every
write with the App token. The `verify` job of the release workflow requests only read
permissions and uses no environment.

### Local publication

Remove the documented local GHCR publication path. The component wrapper fails
closed outside the release workflow. Package access must let the dmf-cms
workflow publish and keep the package public.

The release workflow does not change `scripts/publish-to-ghcr.sh`, so the
lockdown is a follow-up. While `RELEASE_ENABLED` is not `true`, the manual tag
and publish steps in the component's build rules stay as a labelled fallback. A
follow-up change after the first unattended release removes that fallback and
makes the wrapper fail closed outside the workflow. That change closes this
section.

## App permissions

| App | Permission | Why |
|---|---|---|
| `dmf-cms-automerge` | Pull requests: write | Enable auto-merge on a pull request |
| `dmf-cms-automerge` | Contents: write | GitHub requires it to merge the pull request |
| `dmf-cms-release` | Contents: write | Create the tag reference |

Neither App has Administration, Workflows, Actions, or Packages permission.
Metadata: read is implicit. The release job requests the token with only
`contents: write`. GitHub does not document whether auto-merge needs
`Contents: write` in addition to `Pull requests: write`. The test used both,
so the plan keeps both. The rollout may try the narrower set.

## Required tests

All tests use fixtures or mocked GitHub and Docker interfaces.

- Trigger test for `automerge`: it fails if the workflow uses
  `pull_request_target`, if `workflow_run` lists a name other than the `CI`
  workflow, or if the workflow has a checkout step. Event-path fixtures show
  it acts only on the pull request whose live head equals the run's SHA, and
  skips a fork, a draft, a closed pull request, a `hold` label, and a pull
  request whose head moved after the lookup.
- Schedule fixtures. An open pull request whose head has no matching `CI` run
  is neither armed nor merged, with no error. A `CI` run that is in progress,
  cancelled, or failed does the same. If the head changes between the sweep's
  read and the arm or merge call, the call carries the stale expected head,
  matches nothing, and the next run handles the new head. A draft marked ready
  with a passing `CI` run on its head is armed or merged. A pull request whose
  `hold` label is removed is handled the same way. The sweep follows
  pagination past the first page. An error on one pull request does not stop
  the others, and the run ends non-zero.
- Fast-check race for `automerge`: the required checks complete before the
  arm, arming fails with the clean status, and the fallback merges the pull
  request with the rebase method. A transient arm failure is retried on the
  next `CI` completion or schedule run. Arming and merging an already armed or merged pull request
  succeed without change. Any other error fails the step.
- Hold fixtures. The `hold-disarm` workflow runs only when the added label is
  `hold`, uses only `GITHUB_TOKEN`, and has no environment, secret, or
  checkout. The sweep disarms a held pull request that has auto-merge enabled.
  A pull request without `hold` is not disarmed.
- With `RELEASE_ENABLED` unset or not `true`, `verify` and `release` do not
  run. With it `true`, a ready release runs.
- The check gate fails a check run that belongs to a pull request run, or to a
  push run of another workflow, even when its name and conclusion match. It
  accepts a ruleset `integration_id` that is empty or 15368 and fails any other
  value.
- On a push, a commit with no merged pull request fails the three contexts, and
  so does a commit that several pull requests claim. A lookup that is empty on
  the first attempt and filled on a later one passes.
- The release workflow triggers only on `workflow_run` for `main` push runs.
  It has no `workflow_dispatch`, ignores tag creation, and reads no SHA,
  version, or ref from user input.
- A trigger-level test parses `workflow_run.workflows` in the release workflow
  and fails unless every entry equals the `name:` of an existing file under
  `.github/workflows/`, so a typo or a rename fails the test. It also fails if
  any of the four workflows that produce the twelve required contexts is
  missing from the list.
- A workflow-to-context test maps every context in `main-protection` to the
  workflow job that produces it, and fails when a job carries an `if` that
  excludes `push`, or when its workflow has no push trigger for `main`.
- Two release-run fixtures for one SHA: the run triggered by the first
  workflow to complete ends without a tag and without a failure, and the run
  triggered by the last one releases.
- The check gate fails when the commit is not reachable from `main`, is not a
  release bump, or has a version below an existing tag. It also fails for
  a missing context, a non-success conclusion, a skipped or neutral run, an
  old run, a run for another SHA, a foreign check app, a success on the pull
  request head only, duplicate or empty context names, and zero or several
  active `main-protection` rulesets. It passes when all twelve contexts pass.
- A failed or incomplete check produces no tag and no image. A mismatched
  existing tag or image fails without change. A matching tag or image allows
  a safe retry in each of the two partial states above.
- The image label check fails when the version or revision label differs from
  `VERSION` or the commit, before any push.
- A workflow-to-wrapper-to-shared-helper test runs the actual publish block
  with a fake Docker CLI. The newline-terminated token reaches login, tag, and
  push with `GHCR_USER` and `DOCKER_HOST` set. The old pipeline without the
  final newline fails before Docker login.
- Version-rule fixtures: a retry after a successful tag at the same SHA
  proceeds to image verification and publication and does not recreate the
  tag. An equal tag at a different SHA fails. A higher tag fails. A lower tag
  does not block.
- Two release fixtures in sequence for one version produce exactly one tag.
  The second run finds the tag at the same SHA, skips creation, and continues.
- Interleaving: a merge to `main` lands between verification and tag creation.
  The release tags the verified commit and leaves the new head untagged. If the fixture makes
  the verified commit unreachable from `main`, the run exits without a tag.
  In a second fixture, a tag for a higher version appears between two runs, and
  the lower version is not tagged.
- A ready release is pending in the group while a non-release `main` push run
  arrives. The non-release run ends in `verify`, the pending release is not
  replaced, and it runs.
- Two ready releases queue. The later one replaces the earlier pending one,
  the later version is tagged, and the earlier version is skipped. A re-run of
  the replaced run fails the version rule and tags nothing.
- A `verify` job that finds the commit not ready never starts the `release`
  job. The `release` job repeats checks 1 to 3 from the SHA alone and does not
  trust any other value from `verify`.
- `dco`, `issue-link`, and `commitlint` on a push validate the merged pull
  request and all its commits, and each produces a completed `success` check
  run under its exact context name on the push SHA. A commit with a missing
  trailer, a non-conventional subject, or no issue reference fails its own
  context. An empty or unresolvable pull request lookup fails all three.
- A workflow lint test fails if a workflow lacks a top-level `permissions`
  block, grants write at the top level, or grants `packages: write`,
  `id-token: write`, or `attestations: write` to any job but the release job.
  It also fails unless only the `release` job of the release workflow has the
  concurrency group, the `release` environment, and any write permission. It
  also fails if any workflow other than `release` references the
  `dmf-cms-release` secrets, or if a secret is passed through `env` instead
  of a step input.
- A ruleset fixture shows tag creation for `v*` restricted with the release
  App as the only bypass actor, and update and deletion still blocked.
- Tag ruleset check fixtures. The check passes for one active
  `tags-release-create` ruleset. That ruleset has target `tag`, the include
  pattern `refs/tags/v*` only, and the `creation` rule. The `bypass_actors` field is absent, which is the normal
  case for this token. The check fails, with no tag and no image, in each of
  these cases: the ruleset is missing, including the live situation where only
  `tags-release-protect` exists; two rulesets share the name; the ruleset is
  disabled; the target or pattern differs, or an exclude narrows it; the
  `creation` rule is missing; the API returns an error. The check runs before the
  image build and before tag creation.
- A provenance check, run at rollout against a disposable build, verifies the
  attestation for the digest and fails for a different workflow or SHA.

## Rollout

An organization owner creates the Apps. Nothing in this plan creates them, and
the implementation changes no setting. Complete these steps in order. The
release workflow stays inert until step 9.

1. Create `dmf-cms-automerge` and `dmf-cms-release` as `dmfdeploy`
   organization Apps with the permissions above. Install each only on dmf-cms.
2. Run a disposable-PR probe on dmf-cms: arm auto-merge with a
   `dmf-cms-automerge` token and confirm that the push to `main` starts `ci`
   and `guard`. The design rests on this. A throwaway repository showed it
   (see Observed behavior), and this step repeats it on the real repository.
   Also record the merge actor on the commit. Repeat the probe with checks that
   finish before the arm and confirm that the direct merge by the App succeeds
   and starts `ci` and `guard`. If the direct merge fails or starts no
   workflows, merge from a schedule run with the App token instead. Also
   confirm that a `workflow_run` run of the new `automerge` workflow starts and
   reads the `automerge` environment secret, and that Settings, Actions,
   Policies, Policy insights lists no blocked run for it. Do this before the
   `pull_request_target` workflow is removed. Also add `hold` to an armed
   pull request and confirm that both disarm paths clear auto-merge: the
   `hold-disarm` workflow and the sweep's disarm mutation. Tests cover both
   only against fakes so far.
3. Create environments `release` and `automerge`, each limited to `main`, with
   no required reviewers, and add each App's Client ID and private key as secrets of
   its own environment only (`AUTOMERGE_APP_CLIENT_ID`,
   `AUTOMERGE_APP_PRIVATE_KEY`, `RELEASE_APP_CLIENT_ID`,
   `RELEASE_APP_PRIVATE_KEY`).
4. Create the `tags-release-create` ruleset with `dmf-cms-release` as the
   only bypass actor. The owner confirms the bypass list in the ruleset
   settings, because the release job cannot read it.
5. Set the default workflow token permission to `read`.
6. Add the push path for `dco`, `issue-link`, and `commitlint` and confirm
   that all twelve contexts complete with `success` on a push to `main`.
   Confirm that the workflow's `GITHUB_TOKEN` can read the `rulesets` and
   `rules/branches/main` endpoints. If GitHub refuses, `verify` fails closed
   and nothing releases.
   On a throwaway repository, create two ready-release runs and a non-release
   run, and confirm that the non-release run never enters the job-level group,
   the pending ready release is not replaced by it, and a later ready release
   replaces an earlier pending one.
7. Confirm the GHCR package access mode.
8. Assign key rotation: an organization owner rotates both private keys every
   90 days and after any change of owners or of who can edit environments, and
   records the date in the pinned operator-notes issue (dmfdeploy/dmfdeploy#618).
   An expired or revoked key shows as a failed token step: the release run
   fails before any build, or auto-merge is not armed and the pull request
   waits. Recovery is to generate a new key, replace the environment secret,
   delete the old key, and re-run. For a suspected leak, delete the key first,
   then list `v*` tags and the App's recent activity for anything unexpected.
9. Set the repository variable `RELEASE_ENABLED` to `true`, after every step
   above. Until then the manual tag and publish steps stay the labelled
   fallback.
10. Run the first release as a deliberate, owner-approved exercise. No
    existing version is tagged or published retroactively.

## Observed behavior

Observed on 2026-10-30 on throwaway repositories: a public repository in a
Free-plan personal account, and a public repository in the Free-plan
`dmfdeploy` organization. Both were archived afterwards, and the test Apps
were removed. The tests repeat in the rollout, on the real Apps and dmf-cms.

- **Environment branch policy.** An environment with a custom deployment
  branch policy that allows only `main`, holding a secret, works on a Free-plan
  public repository. A job on `main` read the secret. A job on another branch
  never started, and its annotation read: Branch "other" is not allowed to
  deploy to release due to environment protection rules.
- **Attestations.** A build attestation works on a Free-plan public repository.
  It verified with `gh attestation verify`, and its certificate named the
  workflow file at `refs/heads/main`, the commit SHA, and the `push` trigger.
- **App-armed merge starts workflows.** On a repository with rebase-only
  merges and a required check, three pull requests were armed three ways.
  Armed by a workflow with `GITHUB_TOKEN`, the merge was made by the
  `github-actions` bot and the push workflow did not run on the merged commit,
  which reproduces the problem in #568. When a user merged an already-passing pull request directly, the push
  workflow ran.
  Armed by an App installation token, GitHub recorded the App as the merger
  and the committer, and the push workflow ran on the merged commit.
- **App permissions.** An App with `contents: write` and `pull-requests: write`
  armed auto-merge through the GraphQL `enablePullRequestAutoMerge` mutation.
  Arming fails with "Pull request is in clean status" when the required checks
  have already passed. The design handles this with a direct merge (see Merge).
- **Bypass actor.** A Free-plan organization accepted an App owned by that
  organization as the only bypass actor of a tag creation ruleset. A user who
  is an organization admin could not create a matching tag. The App could, and
  could also create a tag outside the pattern. A workflow on a stray branch
  with `contents: write` and `GITHUB_TOKEN` could not create a matching tag.
  A personal account and its repositories refuse the GitHub Actions
  integration as a bypass actor, and so did the organization repository, so
  an App is the only way to scope the bypass.
- **Private App scope.** A private App owned by a personal account installs
  only on that account's repositories. The release Apps are organization Apps.

Still unconfirmed:

- Whether artifact attestations bind to the digest of a container image in
  GHCR. The test attested a file. The rollout checks this on the first release.
- Whether a direct merge by an App token starts the push workflows. A merge
  armed by an App and a direct merge by a user both did. The rollout probe
  confirms the direct App merge on dmf-cms.
- Whether the default policy treats `workflow_run` as affected. GitHub's
  documentation names `pull_request_target` only. The rollout probe checks the
  policy insights for the new workflow before the old one is removed.
- Whether a job that ends at its `needs` or `if` condition never enters a
  job-level concurrency group. GitHub's documentation says "at most one job or
  workflow run can be `pending` in the concurrency group" and that an existing
  pending run "is canceled and replaced", but it does not say how skipped jobs
  count. The rollout probe confirms the ordering.
- Whether the `GITHUB_TOKEN` of the `verify` job can read the `rulesets` and
  `rules/branches/main` endpoints. The job requests no administration
  permission. If GitHub refuses, `verify` fails closed with an error and
  nothing releases. The rollout probe confirms the read.
- Whether the `hold-disarm` workflow and the sweep's disarm mutation clear an
  armed pull request. Tests use fakes. The rollout probe adds `hold` to an
  armed pull request.
