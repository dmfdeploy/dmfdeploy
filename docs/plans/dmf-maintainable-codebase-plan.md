---
status: active
date: 2026-11-14
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/913
---

# Maintainable codebase plan

**Related issues:** [#864](https://github.com/dmfdeploy/dmfdeploy/issues/864),
[#911](https://github.com/dmfdeploy/dmfdeploy/issues/911),
[#912](https://github.com/dmfdeploy/dmfdeploy/issues/912),
[#833](https://github.com/dmfdeploy/dmfdeploy/issues/833),
[#831](https://github.com/dmfdeploy/dmfdeploy/issues/831)

## Goal

More contributors and outside reviewers are expected. On 2026-11-14 the
operator set the priority for the `platform-debt` backlog: make the existing
code maintainable and easy to review, with a clear structure and logic, so
that it is pleasant to contribute to. The only large new function in scope is
the sandbox single-admin passkey unlock in
[#864](https://github.com/dmfdeploy/dmfdeploy/issues/864).

This plan orders the debt under that priority. Three tracks run now, in
parallel. The work after them follows exposure and dependency, across
repositories. A prerequisite that #864 needs runs when #864 needs it, whatever
group it sits in below.

## Decisions

These come from the operator on 2026-11-14. A track does not widen or narrow
them. If it needs a different scope, stop and ask for a new decision.

1. Maintainability and reviewability come first. #864 is the only large new
   function.
2. Contributor readiness is measured with agent walkthroughs of each repository
   from a fresh checkout. There is no human trial for now. A human trial can
   replace or confirm the walkthroughs later, as a new decision.
3. Housekeeping closes or narrows issues only with the operator's approval for
   each close. Parked issues stay open with `platform-debt` and no milestone.

## Done before this plan

The operator approved a housekeeping pass on 2026-11-14. It closed three
issues as overtaken or duplicate, narrowed six issues to what is left, and
concluded six settled Discussions with their outcome links.

## Track 1, the 2026-12-02 deadline

GitHub blocks `pull_request_target` by default in public repositories from
2026-12-02, unless a policy allows it. Every repository's auto-merge or
`hold` disarm workflow depends on that event.

Properties that must hold before 2026-12-02:

- Every repository has a repository-level policy that allows
  `pull_request_target` for its trusted workflows only, and each repository
  has a recorded successful run under that policy
  ([#833](https://github.com/dmfdeploy/dmfdeploy/issues/833)).
- Policy insights show no would-be block since the policies took effect, and
  no ineffective organization-level policy remains.
- The dmf-cms release rollout checks are recorded: a `hold` label clears
  auto-merge on an armed pull request, and the scheduled sweep clears it when
  `hold` is already present
  ([#831](https://github.com/dmfdeploy/dmfdeploy/issues/831)). That probe needs
  a pull request that is armed but not yet merged, so its design comes first.

## Track 2, reconcile #864 before sizing it

The plan for #864 must agree with every decision on it before its work is
sized. The plan's own rule applies: narrowing an approved decision needs a new
decision, and safety work is not dropped to make the scope look smaller.

Properties:

- The #864 plan, ADR-0029 and the RFC in Discussion #865 agree with the
  decisions of 2026-11-08, 2026-11-12, 2026-11-13 and 2026-11-14.
- Every remaining open item in the #864 plan has an owner work package.
- The ADR changes go through the RFC threads first: the ADR-0029 amendment
  and the ADR-0009 recovery-package amendment on Discussion #865, and the
  ADR-0051 clarification on Discussion #907.
- The prerequisites that the #864 work packages name are scheduled with them.
  The #864 plan's WP10 restore depends on the portable Kubernetes-auth
  configuration from WP3 of the plan for
  [#866](https://github.com/dmfdeploy/dmfdeploy/issues/866), so that work
  package runs before WP10, even while the tracks are still running.

## Track 3, contributor onboarding

A newcomer walkthrough of all nine repositories on 2026-11-14 reproduced each
repository's offline CI checks from a fresh checkout. It did not run anything
that needs a live cluster, a cloud account, an image build, `skopeo` or
secrets, and it did not reproduce the working-model sync job. Within that
scope, seven repositories passed. dmf-infra failed 13 unit tests on an
undeclared Python package, and dmf-env failed one test script on an
undeclared tool version. The walkthrough also found that the test commands
live in agent-only files or only in CI configuration, and that READMEs and
CONTRIBUTING files disagree.

Properties:

- Every repository passes its offline CI checks on a fresh checkout with only
  the documented prerequisites
  ([#911](https://github.com/dmfdeploy/dmfdeploy/issues/911)). Each repository
  says which of its checks need a live cluster, cloud credentials, an image
  build or CI only, so nobody reads a local pass as covering them. dmf-runbooks
  keeps its existing CI, including its ansible-core version matrix.
- Each repository's CONTRIBUTING.md names one test command that works on a
  fresh checkout, and CI runs the same command
  ([#912](https://github.com/dmfdeploy/dmfdeploy/issues/912)).
- Each CONTRIBUTING.md says what the issue-link check needs, how a contributor
  working from a fork gets past it, and how to install the hooks.
- READMEs link to CONTRIBUTING.md for development and testing instead of
  keeping their own copies.
- CONTRIBUTING asks for evidence in proportion to the change: behaviour tests
  for code changes, and a sweep for siblings of a defect class where one
  applies. A docs edit does not need the full review protocol.
- The existing LICENSE, NOTICE, SECURITY.md, CODEOWNERS and CONTRIBUTING files
  in every repository are audited for content. All nine repositories already
  have them.
- A map in the umbrella README says which repository a kind of task belongs
  to and what each repository needs installed.
- Each repository names a few representative contributor tasks, and for each
  one says whether it can be done and tested offline or needs a live
  environment.
- A second agent walkthrough after the changes repeats the first one's method
  on the same nine repositories and adds one representative task per
  repository. For each repository it records the test command run, its result,
  the checks left out and why, and whether the task could be completed from
  the documentation alone. The track is done when every repository passes that
  walkthrough or has a recorded reason it cannot.

## After the tracks

### Security and supply chain

One ranked list, ordered by real exposure:

- Secrets in arguments, logs and staged files:
  [#872](https://github.com/dmfdeploy/dmfdeploy/issues/872),
  [#885](https://github.com/dmfdeploy/dmfdeploy/issues/885),
  [#896](https://github.com/dmfdeploy/dmfdeploy/issues/896),
  [#897](https://github.com/dmfdeploy/dmfdeploy/issues/897).
- Unpinned images and an untracked chart:
  [#903](https://github.com/dmfdeploy/dmfdeploy/issues/903),
  [#889](https://github.com/dmfdeploy/dmfdeploy/issues/889).
- Installer provenance:
  [#843](https://github.com/dmfdeploy/dmfdeploy/issues/843).
- Authorization scope on operation detail:
  [#541](https://github.com/dmfdeploy/dmfdeploy/issues/541), ranked by its real
  exposure.
- Credential lifecycle, only where it carries real exposure or #864 needs it:
  [#11](https://github.com/dmfdeploy/dmfdeploy/issues/11),
  [#396](https://github.com/dmfdeploy/dmfdeploy/issues/396),
  [#866](https://github.com/dmfdeploy/dmfdeploy/issues/866) (its WP3 runs
  earlier, for #864),
  [#893](https://github.com/dmfdeploy/dmfdeploy/issues/893).
- Also: [#731](https://github.com/dmfdeploy/dmfdeploy/issues/731),
  [#234](https://github.com/dmfdeploy/dmfdeploy/issues/234),
  [#443](https://github.com/dmfdeploy/dmfdeploy/issues/443).

### Broken paths that are not security exposures

- [#873](https://github.com/dmfdeploy/dmfdeploy/issues/873): the OpenBao
  snapshot job uses plain HTTP against a TLS listener, a NetworkPolicy blocks
  it, its Kubernetes-auth role write needs a root token on a rerun, and it
  pins one pod. Its log leak is already fixed. Done when the job takes a
  snapshot on a TLS environment and a rerun converges without a root token.
- [#882](https://github.com/dmfdeploy/dmfdeploy/issues/882): dmf-init's
  setup-request gate and dmf-infra's receipt path both default off. Done when
  a fresh bootstrap passes the setup-request pause with the gate on.
- [#910](https://github.com/dmfdeploy/dmfdeploy/issues/910): the dmf-cms
  release gate fails on a digest read right after a push. Done when the gate
  retries a not-found read for a bounded time.

### Structure conventions and one measured restructure

- The code conventions are written down and enforced in CI
  ([#768](https://github.com/dmfdeploy/dmfdeploy/issues/768)), and files that
  are identical across repositories have one source
  ([#73](https://github.com/dmfdeploy/dmfdeploy/issues/73)).
- One behaviour-preserving restructure: cohesive route groups move out of
  `dmf-cms/src/dmf_cms/main.py`, the largest source file in the project at
  about 7,200 lines. Its dependencies are mapped and its behaviour is pinned by
  tests before anything moves.
- The other repositories are then measured for similar hot spots before more
  restructures are chosen. The walkthrough named candidates: a 3,951-line test
  playbook in dmf-runbooks and two shell scripts of about 2,100 lines each in
  dmf-env. A shared script exists in seven copies, and only two of them are
  identical.

### Accessibility, bounded

The console's durable UI substrate, which survives the planned layout
changes: its surface, border, status, radius and type tokens, shared
primitives, and touch affordances with their accessibility acceptance
([#740](https://github.com/dmfdeploy/dmfdeploy/issues/740)). Two defects in
the same layer:
[#526](https://github.com/dmfdeploy/dmfdeploy/issues/526) (the navigation clips
at 200% zoom but stays focusable by keyboard) and
[#529](https://github.com/dmfdeploy/dmfdeploy/issues/529) (a redundant
landmark).

### Console defects that need no redesign

[#487](https://github.com/dmfdeploy/dmfdeploy/issues/487) and
[#737](https://github.com/dmfdeploy/dmfdeploy/issues/737).
[#341](https://github.com/dmfdeploy/dmfdeploy/issues/341) stays parked under
its owner decision of 2026-11-05. Its risk: the deploy endpoint has no
server-side refusal, so a client guard working from a stale read is the only
protection against a duplicate deployment, and the workload-instance model
that a server-side fix depends on is undecided. This plan does not override
that decision.

### Kept open

[#6](https://github.com/dmfdeploy/dmfdeploy/issues/6) stays open until every
image producer and its tag trigger is inventoried, because dmf-media builds an
image too.

## Status

| Part | Status | Links |
|---|---|---|
| Track 1: #833 | in progress | dmf-cms confirmed on 2026-11-14. The policy insights and the organization setting still need a browser check. |
| Track 1: #831 | not started | The armed-PR probe needs its design. |
| Track 2: #864 | in progress | Plan reconciled in [#908](https://github.com/dmfdeploy/dmfdeploy/pull/908). ADR-0029 amendment v2 on Discussion #865; ADR-0051 RFC on Discussion #907. |
| Track 3: #911 | in progress | dmf-infra and dmf-env pull requests open. |
| Track 3: #912 | in progress | dmf-cms pull request open; the other repositories follow its layout. |
| Security and supply chain | not started | |
| Structure | not started | |
| Accessibility and UI substrate | not started | |
| Broken paths | not started | |
| Console defects | not started | |

Allowed values: not started, in progress, done.

## Done when

This plan orders the work. It is complete when each part above is done by its
properties, or closed with a recorded reason. The underlying issues close on
their own evidence, and an issue that this plan deliberately keeps open, such
as #6 or #341, does not hold the plan open.

- [ ] Track 1 is done before 2026-12-02.
- [ ] Track 2 is done: the #864 plan, its ADRs and its RFCs agree, and its
      prerequisites are scheduled.
- [ ] Track 3 is done by its second walkthrough.
- [ ] Each later group is done, or closed with a recorded reason, in the
      status table.
- [ ] The completing PR sets `status: executed` with an `executed:` date, moves
      the plan to `docs/archive/plans/`, fixes the links to it, regenerates the
      plans index, and closes #913 with `Closes dmfdeploy/dmfdeploy#913`.

## Out of scope

- New large functions other than #864.
- Work under a frozen v0.1 non-goal in `docs/OPEN-QUESTIONS.md`.
- Redesign of console surfaces that a later layout replaces.
