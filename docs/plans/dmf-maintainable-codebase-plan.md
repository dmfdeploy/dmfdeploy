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
repositories.

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
- The ADR changes go through the RFC threads first: ADR-0029 on Discussion
  #865, and the ADR-0051 clarification on Discussion #907.

## Track 3, contributor onboarding

A newcomer walkthrough of all nine repositories on 2026-11-14 found that seven
pass their CI checks on a fresh checkout. Two depend on tools that only the CI
runner image provides. It also found that the test commands live in agent-only
files or only in CI configuration, and that READMEs and CONTRIBUTING files
disagree.

Properties:

- Every repository passes its CI checks on a fresh checkout with only the
  documented prerequisites
  ([#911](https://github.com/dmfdeploy/dmfdeploy/issues/911)).
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
- A second walkthrough after the changes shows the gaps closed.

## After the tracks

### Security and supply chain

One ranked list, ordered by real exposure:

- Secrets in arguments, logs and staged files:
  [#872](https://github.com/dmfdeploy/dmfdeploy/issues/872),
  [#873](https://github.com/dmfdeploy/dmfdeploy/issues/873) (check first
  whether merged work already closes it),
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
  [#866](https://github.com/dmfdeploy/dmfdeploy/issues/866),
  [#893](https://github.com/dmfdeploy/dmfdeploy/issues/893),
  [#882](https://github.com/dmfdeploy/dmfdeploy/issues/882).
- Also: [#731](https://github.com/dmfdeploy/dmfdeploy/issues/731),
  [#234](https://github.com/dmfdeploy/dmfdeploy/issues/234),
  [#443](https://github.com/dmfdeploy/dmfdeploy/issues/443),
  [#910](https://github.com/dmfdeploy/dmfdeploy/issues/910).

### Structure conventions and one measured restructure

- The code conventions are written down and enforced in CI
  ([#768](https://github.com/dmfdeploy/dmfdeploy/issues/768),
  [#73](https://github.com/dmfdeploy/dmfdeploy/issues/73),
  [#740](https://github.com/dmfdeploy/dmfdeploy/issues/740)).
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

Two defects in the console's durable layout:
[#526](https://github.com/dmfdeploy/dmfdeploy/issues/526) (the navigation clips
at 200% zoom but stays focusable by keyboard) and
[#529](https://github.com/dmfdeploy/dmfdeploy/issues/529) (a redundant
landmark).

### Console defects that need no redesign

[#487](https://github.com/dmfdeploy/dmfdeploy/issues/487) and
[#737](https://github.com/dmfdeploy/dmfdeploy/issues/737).
[#341](https://github.com/dmfdeploy/dmfdeploy/issues/341) stays parked under
its owner decision of 2026-11-05. The plan records its risk and does not
override that decision.

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
| Accessibility | not started | |
| Console defects | not started | |

Allowed values: not started, in progress, done.

## Out of scope

- New large functions other than #864.
- Work under a frozen v0.1 non-goal in `docs/OPEN-QUESTIONS.md`.
- Redesign of console surfaces that a later layout replaces.
