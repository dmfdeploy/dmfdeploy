# Open questions

*A curated, honest view of what is deliberately frozen, what is built but
unproven, and what is known-broken or undecided — as of 2026-06-10. The live
backlog is [GitHub Issues](https://github.com/dmfdeploy/dmfdeploy/issues); raw
question logs stay in [docs/questions/](questions/). This page is the map, not
the record.*

The authority for the frozen list is
[architectural-commitments-v1](decisions/architectural-commitments-v1.md) and the
[v0.1 plan](plans/DMF%20v0.1%20Commitment%20%26%2030-Day%20Focus-Cut%20Plan%202026-06-06.md)'s
FREEZE table. Frozen ≠ abandoned: each entry names its re-open trigger.

## Frozen — explicit v0.1 non-goals

| What | Why frozen | Re-open trigger |
|---|---|---|
| **Cross-cluster Authentik federation** (thesis-killer #2) — [#8](https://github.com/dmfdeploy/dmfdeploy/issues/8) | `dmf-central` is all-scaffold; a multi-week lane for an audience of zero. The largest untested part of the original vision. | Post-v0.1, as a ≤1-day spike |
| **Multi-node HA / cloud as a release claim** | Repeatedly stalled (capacity, teardown); single-node is the proof surface ([ADR-0031](decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md)). | A real multi-site need |
| **Argo+AWX hybrid catalog actuator** | Would reverse [ADR-0025](decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md) for a platform with no users yet. AWX is the committed actuator; the hybrid recommendation stands as future direction only. | Post-v0.1 spike, if AWX hits a wall |
| **In-place upgrade** (`main~N → main` skew convergence) | Rebuild-only is the committed lifecycle model (commitment 6). | A real upgrade-without-rebuild requirement |
| **dmf-media catalog-v2 roles** (ebu-list, flow-exporters, ptp-monitor, netbox-media-plugin) | Deeper media-domain value, but new surface area before the core is legible. | Post-v0.1 |
| **dmf-init feature work** | The installer is good enough; only v0.1-install-path bugs are in scope. | v0.1 shipped |
| **Drift-prevention meta-harness** (beyond the thin doc/hygiene gates) | Friction wall for a solo operator; the mothballed [agentic harness](agentic/README.md) is the cautionary tale. | A collaborator joins |

## Paused — thesis-killer #3

**Does the EBU taxonomy survive a genuinely two-function, shared-data-plane
case?** The MXL spike (src + view fabric) is the designed pressure test
([#9](https://github.com/dmfdeploy/dmfdeploy/issues/9)). Its single-node control
chain is code-complete; **live verification is paused** pending an env. The
console-side Flows view and catalog entries are also absent
([#17](https://github.com/dmfdeploy/dmfdeploy/issues/17)). Until this runs live,
thesis-killer #3 is open — the one experiment-phase question that was never
answered.

## Built but unproven — live-verification debt

These exist in code and are believed correct; none has a recorded live run
proving it. The [2026-06-06 evaluation](reviews/dmf-platform-technical-evaluation-2026-06-06.md)
calls this the project's systemic risk.

- **Cloud-lane `seed-bao` re-bootstrap** — the `bundle_set` write-back aborted on
  the cloud lane and the root cause is still unproven; mitigations landed
  2026-06-01 unvalidated. The sandbox lane ran clean 2026-06-07, so the blocker
  is cleared for the v0.1 release profile — but cloud-lane write-back +
  idempotency remain unproven.
- **Catalog drift detector firing on real drift** — built and schema-sound, but
  the fault-injection run (delete a Helm release, watch the check fail and name
  the entry) was never recorded ([Move 1 learnings](reviews/dmf-platform-move-1-learnings-2026-06-04.md) Q6).
- **Cold-bootstrap regression gate** — the first-boot-bug class keeps being found
  by luck on fresh envs, not by an automated check. The 2026-06-07 container-driven
  VPS run seeded the checklist; the gate itself isn't automated yet.
- **Multi-node anything** — nearly every green checkmark in the record is
  single-node. The 3-profile flexibility requirement is validated for 1 of 3.

## Known races and bugs in the headline workflow

- **Catalog per-entry cross-action lock**
  ([#24](https://github.com/dmfdeploy/dmfdeploy/issues/24)) — deploy and finalise
  are different AWX job templates, so the same-action dedup (shipped in dmf-cms
  0.9.2 for the double-launch TOCTOU) does not serialize them; near-simultaneous
  opposite actions race into "pods up + tag active + a finalise that tore down
  nothing." A stranger driving the console can hit this; it is in-scope for v0.1.
- **dmf-init duplicate orphan envs** on create-form re-submit
  ([#19](https://github.com/dmfdeploy/dmfdeploy/issues/19)).
- **Sandbox teardown leaves the node dirty** — no decommission step
  ([#18](https://github.com/dmfdeploy/dmfdeploy/issues/18)).
- **Dynamic monitoring residue** — catalog-launcher target stamping + per-app
  probe tuning ([#5](https://github.com/dmfdeploy/dmfdeploy/issues/5)).

## Undecided — open architectural questions

- **Proposed ADRs without a forcing function** (see
  [INDEX.md §Open decision debt](decisions/INDEX.md)):
  managed-service and flypack modes ([ADR-0020](decisions/0020-deployment-scope-and-regulatory-posture.md) B/C),
  flypack-online edge agent ([ADR-0022](decisions/0022-flypack-online-thin-edge-agent.md)),
  provider descriptors ([ADR-0026](decisions/0026-provider-descriptors.md)),
  console i18n/air-gap posture ([ADR-0030](decisions/0030-console-i18n-and-airgap-posture.md)).
  Each stays Proposed until a customer, partner, or roadmap item forces it.
- **dmf-init ↔ dmf-cms convergence** — two React+FastAPI apps with overlapping
  concerns; strategic question, needs an ADR
  ([#29](https://github.com/dmfdeploy/dmfdeploy/issues/29)), with a shared UI
  framework as the tactical half ([#28](https://github.com/dmfdeploy/dmfdeploy/issues/28)).
- **Post-v0.1 hardening backlog** — OpenBao HA-raft migration, re-key + DR drill
  ([#12](https://github.com/dmfdeploy/dmfdeploy/issues/12)), AppRole secret-id
  rotation + root-token disposal ([#11](https://github.com/dmfdeploy/dmfdeploy/issues/11)).
  Deliberately *after* v0.1 per the commitments — these harden committed
  architecture, so they queue behind the publish.
- **Cross-repo reproducibility** — the 9-repo estate is coordinated by discipline,
  not pins/submodules. Held as-is by commitment 5; revisit if coordination cost
  grows.

## How this page stays honest

When an item closes, it leaves this page in the same change that closes its
issue. Anything frozen that gets re-opened goes through an amendment to
[architectural-commitments-v1](decisions/architectural-commitments-v1.md) first —
that's the deal that keeps the freeze meaningful.
