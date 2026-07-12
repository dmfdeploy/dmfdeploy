---
status: active
date: 2026-07-12
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/200
---
# DMF v0.2 Presentable Journey Execution Plan (2026-07-12)

> **STATUS: ACTIVE.** Execution-sequencing supplement to the
> [`DMF v0.2 EBU Facility-Orchestration Re-anchor Plan 2026-07-07.md`](DMF%20v0.2%20EBU%20Facility-Orchestration%20Re-anchor%20Plan%202026-07-07.md)
> (#189). That plan owns the **north star and WP definitions**; this one owns
> **order, acceptance gates, and demo readiness** for the presentable
> end-to-end journey. It defines no new scope beyond the demo-readiness
> workstream (#203) and the parallel RFC writing track (#204). If the two
> plans ever disagree on scope, the re-anchor plan wins.

## 1. Purpose — what "presentable" means

A stranger-viewable demo of the complete user journey on one env:

> Enroll an operator (passkey invitation) → see the declared **Design/Plan**
> state of the `videotest` Media Workload (legibility, not authoring) →
> **Provision** → **Configure** → **Operate**: watch live tiles/preview and
> **switch the viewer between two test-pattern sources** → **Finalise**,
> with the **Security** beats (viewer-role 403s, reason-required writes, C5
> audit trail) and **Monitor** beats (NetBox-derived targets, alerts,
> preview) shown along the way.

This is the re-anchor plan's north star minus the two honest deferrals it
already names: live IS-05 switching (coarse `reconnect` actuator instead) and
licence *enforcement* (declared-only). The journey's missing climax today is
the switch — everything before it shipped in v0.2a (A–E, #185).

## 2. Work packages, in priority order

| # | WP | Issue | State | Depends on |
|---|---|---|---|---|
| J1 | **Switch beat**: multi-source videotest topology + launcher source selection + coarse connection-intent switch. **Spec doc first** (umbrella `docs/plans/`, codex-gated), then build. | [#201](https://github.com/dmfdeploy/dmfdeploy/issues/201) | open | — (spec); J2 capacity data helps |
| J2 | **Workload-entity tail + safety**: grouped-API flip [#199](https://github.com/dmfdeploy/dmfdeploy/issues/199), tag-preservation test [#196](https://github.com/dmfdeploy/dmfdeploy/issues/196), mxl-hello retirement [#193](https://github.com/dmfdeploy/dmfdeploy/issues/193); then L3 preflight + rollback. | [#202](https://github.com/dmfdeploy/dmfdeploy/issues/202) (+ the three above) | open | — |
| J3 | **Standing demo env + written demo runbook**; runbook written against current state, upgraded when J1 lands. | [#203](https://github.com/dmfdeploy/dmfdeploy/issues/203) | open | env: none; final runbook: J1 |
| J4 | **RFC writing track** (parallel, design-only): media-function packaging, catalog sources, trust tiers — paired with the ADR-0045 licensing RFC. | [#204](https://github.com/dmfdeploy/dmfdeploy/issues/204) | open | none (must not displace J1–J3) |
| J5 | **First out-of-tree media function** enters via the J4 package path (demo upgrade + contribution-path validation). | opens when J4 has a draft format | later | J4 draft, J1 |

Sequencing rules:

- **J1 spec is the next code-adjacent artifact.** Nothing else on the critical
  path is unspecced.
- **J2 small slices (#199/#196/#193) are fair game any time** — they're
  independent and already designed (ADR-0046).
- **L3 (#202) must land before or with the J1 demo build** — the demo scenario
  is exactly the shape that previously hit 96% CPU requests and wedged AWX
  (MXL revival plan §7 follow-ups).
- **J3's env can start immediately** (it also unblocks live verification for
  everything else); the runbook is written incrementally, not at the end.
- **J4 never blocks or displaces J1–J3.** It is a writing track; its only code
  footprint in this round is the cheap-now catalog-schema hooks named in #204.
- **J5 does not start in this round** — it opens its own issue when J4 has a
  draft package format. The first out-of-tree function must *not* be wired the
  current three-repo way (catalog in dmf-media + launchers in dmf-runbooks +
  JT seeding in dmf-infra); entering through the package path is the point.

## 3. Acceptance gate for the track (#200)

The demo runbook (#203) executes end-to-end on the standing env **by someone
who didn't build the platform**, including the live switch beat (#201),
without wedging the node (#202), with the Security and Monitor beats
observable as described. When that holds, #200 closes and this plan flips to
`done`.

## 4. Non-goals in this round (already decided elsewhere — do not reopen)

- Live IS-05 switching / nmos-cpp↔MXL adapter (re-anchor plan: own workstream).
- Licence *enforcement* / reservation provider build (ADR-0045: declared-only
  in v0.2; provider slice follows the paired RFCs).
- Design/Plan *authoring* engines (operator decision 2026-07-07: legibility
  only).
- Contribution-model *build* beyond the #204 cheap-now schema hooks.
- Crosspoint switchability (stays visible-only per its executed plan; the J1
  switch is the console/launcher seam, not IS-05).

## 5. Working agreements for agents on this track

Standard working model applies (issue → branch → codex cross-check → PR closes
issue + flips frontmatter). Specifics for this track:

1. **Boot**: run the umbrella boot ritual, then read this plan §2 to pick the
   highest-priority unclaimed WP. Liveness lives in the issues, never here —
   this table's State column is refreshed by the PRs that close the issues.
2. **Claim by commenting on the issue** before starting, so parallel sessions
   don't collide.
3. **Spec-first WPs (J1, J4)**: the spec/RFC is itself codex-gated before any
   build starts.
4. **End of session**: write a handoff in `docs/handoffs/` if the WP is
   in-flight; update the issue with concrete state (what's merged, what's
   next command to run).
5. **Public-safety**: runbook and RFC content follow the umbrella placeholder
   conventions (no real IPs/DNS/identity); everything in this track is
   public-trajectory.
