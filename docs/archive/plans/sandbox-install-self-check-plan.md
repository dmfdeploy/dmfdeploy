---
status: executed
date: 2026-11-27
executed: 2026-11-27
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/1031
---

# Sandbox install self-check plan

## Outcome

The plan is executed. Two rounds ran on one fresh sandbox install from
2026-11-27, and their results are on
[#1031](https://github.com/dmfdeploy/dmfdeploy/issues/1031) and
[#1020](https://github.com/dmfdeploy/dmfdeploy/issues/1020):

- The verify step prints the self-check summary, and each check has its test.
- The sign-in check design was posted and is parked.
- [#1026](https://github.com/dmfdeploy/dmfdeploy/issues/1026) is closed.
  [#1025](https://github.com/dmfdeploy/dmfdeploy/issues/1025),
  [#1027](https://github.com/dmfdeploy/dmfdeploy/issues/1027) and
  [#1028](https://github.com/dmfdeploy/dmfdeploy/issues/1028) stay open, each
  with its gap named on #1031.

The plan below is kept as it was during the work.

## Why

The batch 2 install passed its verify step, but three breaks still reached
`main`: OIDC sign-ins failed on an empty `grant_types` default, the AWX SAML
sign-in looped on a renamed issuer field, and the node scrape jobs got 403
after a chart dropped `nodes/proxy`. Someone found each one by hand after CI
and review had passed. The install should report this class of break itself.

## Properties each step must meet

Step numbers match dmfdeploy/dmfdeploy#1031.

### The four defect fixes (step 2)

- Each of dmfdeploy/dmfdeploy#1025, dmfdeploy/dmfdeploy#1026,
  dmfdeploy/dmfdeploy#1027 and dmfdeploy/dmfdeploy#1028 meets its own
  Done-when.
- The fixes for dmfdeploy/dmfdeploy#1025 and dmfdeploy/dmfdeploy#1026 each need
  a release: a console patch release and a dmf-promsd release.
- The operator approves each of the two image publications.
- The design choice in dmfdeploy/dmfdeploy#1027 goes to the operator before
  implementation starts.

### The verify summary (step 3)

- The sandbox verify step prints a prominent summary.
- The summary names each expected scrape target of a deployed component that is
  down.
- The summary names each firing alert that is absent from the repo allowlist.
- The summary names each error state from the console's own routes for Forgejo
  repository, commit and pull request reads, Grafana and AWX.
- A clean run says so in one line.
- Each check has a test. The test reports a broken input and stays quiet on a
  good one.
- The pull request shows that the target and alert checks would have reported
  the batch 2 node scrape break.
- Each reported case counts as a finding when the Done-when is judged.

### The sign-in design (step 4)

- The design covers sign-in through the identity provider to Forgejo, Grafana,
  NetBox, AWX and Zot.
- The design says how the check would catch both batch 2 sign-in breaks. A
  provider-settings read-back alone isn't enough.
- A test account exists only in the sandbox profile.
- No secret enters a repo.
- The check doesn't weaken real users' passkey requirement.
- The design estimates the pull requests and lines, and says whether the check
  fails the step or reports.
- The design gets a review. Then the operator decides whether to build or park
  it, and the build starts only on a yes.
- If the design is parked, hands-on sign-in remains with the operator.

### The fresh install (step 5)

- One fresh sandbox install runs from `main` on a second spot instance with the
  new checks on. The live environment stays untouched.
- The work lists the execution-environment job templates that use
  `kubernetes.core`, runs each one that is safe on the sandbox, and records the
  job IDs. Each unrun template has a reason and stays unproven.
- The operator gets precise instructions and pass criteria for passkey
  enrollment and a short visual walk.
- At most two install attempts run. After that, ask before continuing.

### The results (step 6)

- Results go on dmfdeploy/dmfdeploy#1031 and dmfdeploy/dmfdeploy#1020. They
  cover console reads, targets, probe lanes and `kubernetes.core`.
- The operator's confirmation of the second identity-provider fix is recorded.
- Each Done-when is judged against its issue text, line by line. An issue closes
  only where evidence proves it. Otherwise the gap is named.

## Decisions already made

- The new checks report. They don't fail the verify step.
- Each allowlist entry says why the alert fires by design. A real defect never
  goes on the allowlist.
- The sign-in design comes first. It's built only after a separate operator
  decision.

## Out of scope

Only dmfdeploy/dmfdeploy#1031, dmfdeploy/dmfdeploy#1020 and the four defect
issues change under this work. Other findings go in the handoff for later and
don't widen it. An update that arrives during this work is outside scope.

## Issues

- dmfdeploy/dmfdeploy#1031: this work
- dmfdeploy/dmfdeploy#1020: the batch 2 install
- dmfdeploy/dmfdeploy#1025: console Changes page slices the Forgejo reply
- dmfdeploy/dmfdeploy#1026: dmf-promsd image has no `/metrics` route
- dmfdeploy/dmfdeploy#1027: AWX probe lane fails while AWX is scaled to zero
- dmfdeploy/dmfdeploy#1028: Grafana Nodes dashboard is empty on a hostname
  mismatch
