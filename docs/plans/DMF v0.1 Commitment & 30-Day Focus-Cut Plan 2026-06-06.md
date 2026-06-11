---
status: active
date: 2026-06-06
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/36
---
# DMF v0.1 Commitment & 30-Day Focus-Cut Plan (2026-06-06)

**Status:** Active task spec (supersedes the experiment-phase backlog framing).
**Decision basis:** [architectural-commitments-v1](../decisions/architectural-commitments-v1.md)
+ the 2026-06-06 technical evaluation + CEO/eng review (dual-voice CONFIRMED).
**Operator decisions:** D1 commit now · D2 credibility-signal first · D3
reproducibility-then-publish · D4 produce commitments + review + this plan.
**Goal of the next 30 days:** make the *already-proven* core **runnable and legible by
a stranger**, then publish. Not more surface area.

---

## The single move

> **Narrow Option A to the reproducibility slice, in service of Option E:**
> a stranger clones → runs one command → gets DMF on a blank node → deploys NMOS/MXL
> from the console → inspects the receipts. Then publish v0.1 + a one-page thesis.

This reconciles the only CEO dual-voice disagreement: codex ("prove it runs before you
publish — else it's theater") and the Claude subagent ("the proven thesis is already
credible — publish now"). The eng analysis dissolves it: publishing something a stranger
can't reproduce is *negative* credibility signal, but the reproducibility bar is **cold-boot
determinism**, not in-place upgrade. So: do the small reproducibility slice, then publish.

---

## FREEZE list (do not touch for 30 days)

Each of these is a real surface that, if worked, expands the proof area instead of making
the existing proof legible. Frozen ≠ deleted — these are reservations (see
[architectural-commitments-v1](../decisions/architectural-commitments-v1.md) non-goals).

| Freeze | Why | Re-open trigger |
|---|---|---|
| **dmf-central / federation (#2)** | All-scaffold; opens a 2–4 week lane for an audience of zero | Post-v0.1, as a ≤1-day spike |
| **HA / cloud as a release claim** | Repeatedly stalled (capacity/teardown); single-node is the wedge | A real multi-site need |
| **Argo+AWX hybrid actuator** | Reverses ADR-0025 for a no-user platform; the trap | Post-v0.1 spike, if AWX hits a wall |
| **In-place upgrade (`main~N→main`)** | Rebuild-only is the committed model | Real upgrade-without-rebuild requirement |
| **dmf-media catalog-v2 roles** | ebu-list / flow-exporters / ptp-monitor / netbox-media-plugin — future depth | Post-v0.1 |
| **dmf-init feature work** | Installer is good enough; only v0.1-install-path bugs allowed | v0.1 shipped |
| **drift meta-harness (beyond minimal CI)** | Friction wall for a solo operator | A collaborator joins |

## v0.1 WORK QUEUE (the only in-scope work)

Ordered. Reproducibility slice first (gates the publish), then the front door.

> **Progress 2026-06-07** (see handoff `DMF First Container-Driven VPS Deploy + Passkey UX
> Handoff 2026-06-07.md`): first full **non-Lima** bootstrap succeeded end-to-end, driven
> through the **dmf-init container**, on a real ARM64 Debian-13 VPS (env `tzje-voik`) — node
> Ready, full app stack up, `bootstrap-sandbox-verify` green, operator passkeys 2/2. Two
> `dmf-infra` fixes committed (`a8c804e` netbox lookup, `2f7741d` landing-page base64). New
> plan: `DMF Sandbox Zero-Setup Addressing (sslip.io) Plan 2026-06-07.md` (sslip.io base domain
> kills the `/etc/hosts` step; passkeys stay mandatory).

### Phase 1 — Reproducibility slice (prove it runs)
1. ✅ **Stand up one durable env** and keep it. (Stops the "no cluster → can't verify" loop.)
   **DONE 2026-06-07** — `tzje-voik` live on a real VPS (non-Lima), durable.
2. ◑ **Fix `seed-bao bundle_set`** (re-bootstrap blocker; root cause still unproven —
   instrumentation already landed, needs a live run to confirm + validate idempotency).
   **Advanced 2026-06-07** — `seed-bao` + checkpoint-2/3 backups ran clean on the live
   **sandbox** env; the long-standing "needs a live env to confirm" blocker is cleared for the
   sandbox lane. Cloud-lane `bundle_set` write-back + idempotency still unproven.
3. **Catalog per-entry cross-action lock** — kills the double-launch TOCTOU +
   deploy↔finalise race. Needs one dmf-cms image build.
   (Source: memory `project_dmf_catalog_deploy_finalise_race`; TODOS §catalog correctness.)
4. **Live-verify the paused work** that gates the demo: mxl-hello single-node
   deploy/finalise from the console; confirm cold-boot is clean end-to-end.
5. ◑ **Cold-bootstrap smoke gate** — one automated check so the recurring first-boot-bug
   class stops being found by luck. **Seeded 2026-06-07** — the container-driven VPS run *was*
   a manual cold boot and caught the whole first-boot class (dmf-init image missing
   yq/dig/helm/htpasswd/py-libs; macOS-isms in `unseal-openbao.sh` + `base64 -i`; Debian-13
   PyYAML pip conflict). These are the exact checks the gate must assert — see the handoff's
   "Open productization items" + memory `project_dmf_init_container_bootstrap_gaps`.

### Phase 2 — Public-tag install path (make it cloneable)
6. **dmf-init quickstart from public GitHub tags**, not LAN Forgejo `file://`.
7. **GitHub org + repos + scrub/prune + dry-run sync** for the public components
   (TODOS §"Release & compliance" — operator-gated account work).
8. **Minimal CI** — dmf-cms CI (the placeholder), doc-link check, the cold-boot smoke gate.

### Phase 3 — The front door (make it legible) → PUBLISH
9. **One-page product thesis** — who it's for, the first pain it solves, what a stranger
   validates in <1 hour. *If it doesn't fit on one page, the system is still too broad.*
10. **Public umbrella README / quickstart** — the single entry point to the whole system.
11. **One writeup on the proven thesis** — "NMOS IS-04/05 on commodity k3s, the EBU DMF
    way," with the catalog control-chain as the demo. This is the credibility artifact;
    the thesis is confirmed and currently invisible.
12. **Publish v0.1.**

---

## Definition of done (v0.1)

A reviewer/employer/OSS adopter can, from public artifacts alone:
clone → one command → DMF on a blank node → deploy NMOS + MXL from the console →
read a one-page thesis that says why it matters. Cold boot is deterministic; the
console's headline workflow has no known races; nothing in the FREEZE list was touched.

## Out of scope (explicit)

Everything in the FREEZE list. The April P0s (alerts, backups, token rotation) come
*after* v0.1 ships — they harden committed architecture, which is now allowed.
