---
status: historical
date: 2026-06-06
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/36
---
# DMF v0.1 Commitment & 30-Day Focus-Cut Plan (2026-06-06)

**Status:** **Historical, not executed.** Verified item-by-item 2026-08-27 (see
"Post-hoc verification" below): 5 of 12 queued items are DONE with hard
evidence, 3 are partial, and 4 — including the plan's own capstone, a discrete
**"publish v0.1" release** — never happened. That publish goal now lives on,
open-ended, as the `v0.1-polish` milestone (25 open issues as of 2026-08-27,
still gaining and losing items today). Its tracking issue closed 2026-07-17
because the umbrella scope moved on to the milestone system, not because this
queue completed. Retained as history; current scheduling lives in the
milestones, not here.
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
1. ◑ **Stand up one durable env** and keep it. (Stops the "no cluster → can't verify" loop.)
   **DONE 2026-06-07** — `tzje-voik` live on a real VPS (non-Lima), durable.
   **Correction 2026-08-27** — `tzje-voik` itself was superseded within ~24h (the
   2026-06-08 handoff already calls it "the old `tzje-voik`") and the env has churned
   8+ times since (most recently rebuilt 2026-08-16 after spot reclamation, commit
   `a2ae35a`). The *goal* — a durable env always exists — has held throughout; the
   specific claim that `tzje-voik` was that durable env did not.
2. ◑ **Fix `seed-bao bundle_set`** (re-bootstrap blocker; root cause still unproven —
   instrumentation already landed, needs a live run to confirm + validate idempotency).
   **Advanced 2026-06-07** — `seed-bao` + checkpoint-2/3 backups ran clean on the live
   **sandbox** env; the long-standing "needs a live env to confirm" blocker is cleared for the
   sandbox lane. Cloud-lane `bundle_set` write-back + idempotency still unproven.
   **Confirmed still open 2026-08-27** — `docs/OPEN-QUESTIONS.md` still lists the
   cloud-lane gap; no PR or issue closing it was found in `dmf-env`/`dmf-infra`/umbrella.
3. ✅ **Catalog per-entry cross-action lock** — kills the double-launch TOCTOU +
   deploy↔finalise race. Needs one dmf-cms image build.
   (Source: memory `project_dmf_catalog_deploy_finalise_race`; TODOS §catalog correctness.)
   **DONE 2026-07-18** — issue [dmfdeploy/dmfdeploy#24](https://github.com/dmfdeploy/dmfdeploy/issues/24)
   closed; `dmf-cms` PR #40 merged (`06dee0f`), shipped in `v0.16.0`.
4. ✅ **Live-verify the paused work** that gates the demo: mxl-hello single-node
   deploy/finalise from the console; confirm cold-boot is clean end-to-end.
   **DONE 2026-07-04/05** — issue [dmfdeploy/dmfdeploy#17](https://github.com/dmfdeploy/dmfdeploy/issues/17)
   closed; `DMF MXL Single-Node Revival Plan 2026-07-03.md` Amendment C confirms a clean
   deploy→finalise round-trip. (`mxl-hello` was itself later retired 2026-07-09 in an
   unrelated console refactor — the verification event still stands.)
5. ◑ **Cold-bootstrap smoke gate** — one automated check so the recurring first-boot-bug
   class stops being found by luck. **Seeded 2026-06-07** — the container-driven VPS run *was*
   a manual cold boot and caught the whole first-boot class (dmf-init image missing
   yq/dig/helm/htpasswd/py-libs; macOS-isms in `unseal-openbao.sh` + `base64 -i`; Debian-13
   PyYAML pip conflict). These are the exact checks the gate must assert — see the handoff's
   "Open productization items" + memory `project_dmf_init_container_bootstrap_gaps`.
   **Still not automated 2026-08-27** — no CI workflow in any repo boots a fresh node;
   `dmf-init/test/e2e/e2e.sh` exists but is a manual local script, never wired into CI.
   `docs/OPEN-QUESTIONS.md` confirms: "the gate itself isn't automated yet."

### Phase 2 — Public-tag install path (make it cloneable)
6. ◑ **dmf-init quickstart from public GitHub tags**, not LAN Forgejo `file://`.
   **Partial 2026-06-18** — the source-scheme half landed: commit `da6458b` (closing
   issue #86) made `https://github.com/dmfdeploy` the default `repo_base_url`, replacing
   the LAN-only `file://` path. The "**tags**" half did not: `dmf_init/repos.py`
   `DEFAULT_REFS` still pins every repo to `main`; open issue
   [dmfdeploy/dmfdeploy#158](https://github.com/dmfdeploy/dmfdeploy/issues/158)
   (opened 2026-07-01) tracks the still-missing pinned/versioned install.
7. ✅ **GitHub org + repos + scrub/prune + dry-run sync** for the public components
   (TODOS §"Release & compliance" — operator-gated account work).
   **DONE 2026-06-10/11** — org + 8 component repos + `.github` + umbrella live via
   scrubbed orphan imports (`bin/export-scan.sh`); scrub tooling hardened through PRs
   #213/#214/#219/#222, still active through #361 (2026-08-05). The literal "dry-run
   sync" tool was deliberately retired 2026-06-09 (ADR-0041) in favor of a one-time
   scrub-import plus normal PR-merge as the steady state — functionally equivalent,
   not the same mechanism.
8. ◑ **Minimal CI** — dmf-cms CI (the placeholder), doc-link check, the cold-boot smoke gate.
   **Partial 2026-08-27** — dmf-cms CI is real (test + frontend + working-model jobs,
   frontend gate landed via PR #85, 2026-08-12) and the doc-link check is real
   (`bin/check-docs.sh`, PR #149 closing #84, 2026-06-25). The cold-boot smoke gate is
   the same NOT-DONE item as #5 above.

### Phase 3 — The front door (make it legible) → PUBLISH
9. ✅ **One-page product thesis** — who it's for, the first pain it solves, what a stranger
   validates in <1 hour. *If it doesn't fit on one page, the system is still too broad.*
   **DONE 2026-06-11** — `docs/THESIS.md`, ~72 lines / 521 words.
10. ✅ **Public umbrella README / quickstart** — the single entry point to the whole system.
    **DONE 2026-06-11, stale since** — a real single-command entry point via `dmf-init`
    exists and resolves, but the README's last substantive edit was 2026-06-13; ~2.5
    months unrevised despite dmf-cms reaching `v0.29.0` and a console rework since.
11. ❌ **One writeup on the proven thesis** — "NMOS IS-04/05 on commodity k3s, the EBU DMF
    way," with the catalog control-chain as the demo. This is the credibility artifact;
    the thesis is confirmed and currently invisible.
    **NOT DONE 2026-08-27** — no standalone writeup exists anywhere in the org (`docs/THESIS.md`
    itself still says "stranger-reproducibility has not happened yet"). It evolved into the
    WO-379 demo-journey runbook rewrite (issue #379, still open); that rewrite's PR
    [dmfdeploy/dmfdeploy#397](https://github.com/dmfdeploy/dmfdeploy/pull/397) remains an
    open draft.
12. ❌ **Publish v0.1.**
    **NOT DONE AS SCOPED 2026-08-27** — the `v0.1.0` git tag is the initial-publish squash
    commit from item #7 above (2026-06-11), not a completion release: no GitHub Release
    object exists (`gh api .../releases` → `[]`), and the `v0.1-polish` milestone that was
    meant to gate this claim is still **open**, 25 open / 75 closed issues, with items
    landing as recently as today. "Publish v0.1" as this plan scoped it — a discrete,
    gated release event — never happened.

---

## Definition of done (v0.1)

A reviewer/employer/OSS adopter can, from public artifacts alone:
clone → one command → DMF on a blank node → deploy NMOS + MXL from the console →
read a one-page thesis that says why it matters. Cold boot is deterministic; the
console's headline workflow has no known races; nothing in the FREEZE list was touched.

**Not fully met as of 2026-08-27** — "cold boot is deterministic" has no automated
gate (item #5), and the credibility writeup this definition implies (item #11) was
never produced. See "Post-hoc verification" below.

## Out of scope (explicit)

Everything in the FREEZE list. The April P0s (alerts, backups, token rotation) come
*after* v0.1 ships — they harden committed architecture, which is now allowed.

---

## Post-hoc verification (2026-08-27)

The frontmatter was flipped to `status: executed` on 2026-08-27 based on a summary,
without reading this plan's own queue — a review caught the contradiction. This
section is the item-by-item audit that replaced that flip with `status: historical`.
Evidence standard: a commit, a shipped artifact, a closed issue, or a successor doc —
not "probably".

| # | Item | Verdict | Evidence |
|---|---|---|---|
| 1 | Stand up one durable env | ◑ Partial | Goal held in spirit (a durable env has continuously existed, most recently rebuilt `a2ae35a` 2026-08-16) but the specific `tzje-voik` claim was wrong — superseded within ~24h. |
| 2 | Fix `seed-bao bundle_set` | ◑ Partial | Sandbox lane cleared 2026-06-07; cloud-lane write-back/idempotency still unproven per current `docs/OPEN-QUESTIONS.md`. |
| 3 | Catalog per-entry cross-action lock | ✅ Done | Issue [#24](https://github.com/dmfdeploy/dmfdeploy/issues/24) closed 2026-07-18; `dmf-cms` PR #40 merged (`06dee0f`), shipped `v0.16.0`. |
| 4 | Live-verify mxl-hello / cold-boot | ✅ Done | Issue [#17](https://github.com/dmfdeploy/dmfdeploy/issues/17) closed 2026-07-05; `DMF MXL Single-Node Revival Plan 2026-07-03.md` Amendment C confirms a clean round-trip. |
| 5 | Cold-bootstrap smoke gate (automated) | ❌ Not done | Manually run once 2026-06-08; no CI workflow in any repo automates it; `docs/OPEN-QUESTIONS.md` confirms the gap is still open. |
| 6 | dmf-init quickstart from public tags | ◑ Partial | Public-source half done (`da6458b`, closes #86); pinned-tags half open (`DEFAULT_REFS` still `main`, issue [#158](https://github.com/dmfdeploy/dmfdeploy/issues/158)). |
| 7 | GitHub org + repos + scrub/prune + sync | ✅ Done | Org + repos live via scrubbed imports 2026-06-10/11; scrub tooling hardened through PR #361 (2026-08-05). Literal dry-run tool retired 2026-06-09 per ADR-0041, replaced by an equivalent mechanism. |
| 8 | Minimal CI | ◑ Partial | dmf-cms CI + doc-link check real (PR #85, PR #149); cold-boot smoke gate is the same not-done item as #5. |
| 9 | One-page product thesis | ✅ Done | `docs/THESIS.md`, ~72 lines / 521 words, since 2026-06-11. |
| 10 | Public umbrella README/quickstart | ✅ Done (stale) | Working single-command entry point since 2026-06-11; content unrevised since 2026-06-13 (~2.5 months). |
| 11 | Writeup on the proven thesis | ❌ Not done | No standalone artifact found anywhere in the org; evolved into the WO-379 runbook rewrite, whose PR [#397](https://github.com/dmfdeploy/dmfdeploy/pull/397) remains an open draft. |
| 12 | Publish v0.1 | ❌ Not done as scoped | The `v0.1.0` tag is the item-#7 initial-publish squash commit, not a completion release; no GitHub Release exists; the `v0.1-polish` milestone remains open (25 open / 75 closed issues, still moving today). |

**Tally:** 5 done, 3 partial, 4 not done (of 12).

**Verdict:** not executed. Item #12 — the plan's own capstone, a discrete "publish
v0.1" release — never happened; instead the "v0.1" concept diffused into an
open-ended `v0.1-polish` milestone that is still gaining and losing issues today,
2.5 months later. That is scope drift, not completion, and not the same failure
mode as the FREEZE list's non-goals (nothing here was actively abandoned by
decision — it was just never chased to ground once scheduling moved to the
milestone system). `historical` is the correct status: most of the narrow
reproducibility slice landed piecemeal over the following six weeks, but this
document is no longer a live driver of work and should not be read as a record
of full completion. Current scheduling lives in the `v0.1-polish` /
`episode-001-capture` / `v0.2` milestones, not here.
