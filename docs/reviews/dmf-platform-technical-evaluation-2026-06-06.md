# DMF Platform — Technical Evaluation (2026-06-06)

**Reviewer mode:** Technical / cross-repo, whole-platform
**Inputs:** canonical architecture (`docs/architecture/DMF Platform Plan.md`,
`DMF EBU Mapping`), strategic frame (`docs/reviews/dmf-platform-strategic-review-2026-04-30.md`),
live state (`STATUS.md` operator notes), backlog (`TODOS.md`), recent handoffs,
ADR portfolio. Snapshot date: **2026-06-06**.
**Stage:** experiment phase (ADR-0004) — optimize for *falsifying evidence*, not polish.
**Purpose:** an honest current-state technical assessment, ending in forward-looking
options. This doc is the input artifact for the CEO/eng/design/DX review gauntlet.

---

## 1. Executive summary

DMF is an ambitious **EBU Dynamic Media Facility–aligned IP-media operations
platform** built on commodity k3s: NetBox as source of truth, AWX as the
commissioning engine, Authentik for identity, OpenBao for secrets, a React/FastAPI
operator console (dmf-cms), and a layered Ansible bootstrap — packaged as a 9-repo
estate (1 umbrella + 8 components) with a Day-0 bootstrap container (dmf-init).

**Where it is strong:** the *architecture* is real and coherent. The identity model,
secrets custody, NetBox-driven dynamic monitoring, and the catalog control-chain
(console → AWX → playbook → Helm → NetBox tag) all exist and several are
live-verified. The repo topology (generic code vs operator-local state), public-safe
hygiene, and ADR discipline are above the bar for a solo experiment.

**Where it is fragile:** the project has a **persistent "code-complete but not
live-verified" gap** — exactly the failure mode the 2026-04-30 strategic review
warned about ("structural elaboration winning over hardening of unfinished
foundations"). Most live validation happens on a **single-node sandbox**; the
**multi-node HA and cloud (Hetzner) paths repeatedly stall** (capacity, teardown,
upgrade-in-place). Cold-bootstrap is the most critical and least-tested path, and
keeps surfacing first-boot-only bugs one at a time.

**Thesis scorecard (the only metric that matters this phase):**

| Thesis-killer | Status | Evidence |
|---|---|---|
| **#1 NMOS IS-04/05 on commodity k3s** | ✅ **Confirmed** | Move 1 closed 2026-06-04; nmos-cpp deploy/teardown runtime-verified on ARM k3s. |
| **#2 Authentik cross-cluster federation** | ❌ **Not started** | `dmf-central` is still all-scaffold. Largest remaining unknown. |
| **#3 EBU taxonomy survives a hard (two-layer/two-function) case** | 🟡 **Open** | Single registry entry didn't exercise it; carried by the MXL spike (src+view fabric). |

**One-sentence verdict:** the platform has crossed from "plausible architecture" to
"working single-node prototype with a confirmed media thesis," but is gated on three
things before it can claim to be a *platform* rather than a *demo* — federation (#2),
a proven multi-node/cloud + upgrade path, and closing the live-verification debt.

---

## 2. Architecture overview

### 2.1 The DMF/EBU frame
Vocabulary is aligned to the EBU *Dynamic Media Facility Reference Architecture* V2.0:
playbooks are numbered by **layer** (2xx host platform, 3xx container platform,
6xx application/UI), **vertical** (security, monitoring, orchestration), and
**lifecycle** (provision/operate/finalise). `site.yml` + the three lifecycle wrappers
are the canonical entry points. This is a genuine differentiator — the platform speaks
the domain's reference language rather than inventing its own.

### 2.2 Deployment profiles (the flexibility requirement)
One codebase, profile-driven: **Flypack** (1 node, disconnected, OB truck),
**Site/facility** (3+ HA LAN), **Cloud** (3+ HA WAN). This is the central design
constraint and the source of much complexity (offline-first, Shamir custody, generic
vs operator-local split).

### 2.3 Repo topology (9 repos)
- **dmfdeploy** (umbrella) — docs/, STATUS, ADRs, boot ritual, scrub/gitleaks gates.
- **dmf-infra** — generic Ansible playbooks/roles (public). The bootstrap engine.
- **dmf-env** — generic env tooling; per-env state is **operator-local** under
  `~/.dmfdeploy/envs/<env>/` (ADR-0035). Nothing per-env committed.
- **dmf-cms** — React + FastAPI operator console (v0.10.0).
- **dmf-runbooks** — thin AWX launcher playbooks + authoritative `nmos-cpp` role.
- **dmf-media** — catalog metadata + (future) Layer-5 media roles. Mostly scaffold.
- **dmf-central** — cross-cluster central services. **All scaffold.**
- **dmf-init** — Day-0 stateless bootstrap container (React/FastAPI) wrapping the
  dmf-env wizard + toolchain, with passphrase-wrapped dual-remote backup/restore.
- **dmf-promsd** — NetBox-driven Prometheus service discovery (active, live-verified).

**Assessment:** the separation is principled (independent release cycles, public-safe
by construction). The cost is **cross-repo change coordination** — a single feature
(MXL catalog entry) routinely touches 4–5 repos (media chart + runbook + AWX JT +
630 seed + cms view), and the only thing keeping them in sync is operator discipline
+ STATUS prose. There is no pinned/submodule reproducibility and no cross-repo CI.

---

## 3. Component-by-component technical state

### 3.1 dmf-infra (bootstrap engine) — **mature, but cold-path undertested**
The layered role structure (base/ + stack/operator/ + modules/ + charts/) and the
numbered lifecycle playbooks are the backbone. Bootstrap reliably drives a blank
Debian node → full platform (k3s, cert-manager, OpenBao, ESO, Authentik, NetBox,
Forgejo, AWX, dmf-cms, Prometheus/Loki/Grafana) + ~330 configure tasks.

**Risk:** a recurring class of **first-bootstrap-only bugs** keeps surfacing one cold
start at a time — token persisted empty (printf with no matching `read`),
born-inventory create-path id-loss, sops `--config` path mismatch. Each was real,
each only manifests on a true cold start, and each was found by luck of running a
fresh env. This means the **most critical path (cold bootstrap) is the least
exercised**, and there is no automated cold-bootstrap regression gate.

### 3.2 dmf-env (env lifecycle) — **refactored, partially unverified**
ADR-0035 made every env operator-local with per-env SSH keys; `prevent_destroy`
deadlock removed; wizard + validate-env + remove-env lifecycle. **Code-complete but
the new model has open live-verification debt** (the refactor and the upgrade-in-place
+ unseal rewrites are structurally validated only — "no cluster" recurs in the notes).

**Keystone risk: upgrade-in-place is unproven.** `seed-bao`'s `bundle_set` fails on
the cloud lane (exit 1, root cause UNPROVEN per memory); mitigations landed but
unvalidated. Until a controlled `main~N → main` skew env converges, the platform has
**no demonstrated upgrade story** — only fresh builds.

### 3.3 dmf-cms (console) — **shipping, with known concurrency gaps**
v0.10.0 published to GHCR; OIDC via Authentik; catalog page reads YAML + NetBox tags.
The vertical slice (console → AWX → NetBox) is closed and operator-confirmed via the
passkey browser path.

**Known defects:** catalog **double-launch** TOCTOU (sub-second find→launch not
locked) and the **deploy↔finalise race** (different JTs, dedup doesn't serialize
them) — both need a per-entry cross-action lock and a cms image build. CI workflow is
a placeholder. These are correctness bugs in the platform's headline workflow.

### 3.4 dmf-promsd + NetBox-driven monitoring — **strong, live-verified**
The best-validated recent feature: Prometheus targets generated dynamically from
NetBox tags via an http_sd adapter; token flows OpenBao → ESO → adapter with no manual
injection; 10/10 svc-DNS targets up on a from-scratch bootstrap (env `zmlj-sikn`).
Image public + multi-arch. **Open:** dynamic-catalog launcher stamping (WP6 — only the
static born-inventory path is validated) and per-app probe-path tuning.

### 3.5 The catalog / control-chain — **thesis #1 proven, #3 pending**
catalog YAML → Provision → AWX JT → launcher playbook → Helm → health_probe →
Finalise → NetBox lifecycle tag. nmos-cpp proven; mxl-hello single-node
**code-complete, live verify PAUSED** (no env). The actuator's future is an **open
architectural fork**: the recommended direction (memory + plan 2026-06-05) is an
**Argo-for-k8s + AWX-glue hybrid, spike-gated**, which would *reverse ADR-0025 §9*.
This is the single biggest pending design decision.

### 3.6 dmf-init (Day-0 bootstrap container) — **impressive, ahead of its docs**
Thin control container (ADR-0036): bakes only the toolchain + app; clones repos at a
selected ref at runtime; pulls app images from GHCR; passphrase-wrapped dual-remote
backup with checkpoints; full Create + Manage (restore→lock→drift→actions) lifecycle;
hermetic test suite + live sandbox exercise. This is genuinely strong engineering.
**Gap:** its only doc is `ARCHITECTURE.md`; its backlog lives in the umbrella TODOS.
Several UX/robustness nits (raw 500 on bad remote, duplicate orphan envs on
re-submit, two-click start, teardown doesn't decommission the node).

### 3.7 dmf-central — **the unbuilt thesis**
All roles are scaffold. This reserves thesis-killer #2 (cross-cluster Authentik
federation). Until something stands up here, the multi-cluster / central-services
story — a core part of the DMF vision — is **entirely unvalidated**.

### 3.8 dmf-media — **scaffold beyond the one proven role**
nmos-cpp landed (relocated to dmf-runbooks per Path A). ebu-list, flow-exporters,
ptp-monitor, netbox-media-plugin remain scaffold (catalog v2). The deep media-domain
value (flow-level monitoring, 2110-21 timing, PTP topology) is **future work**.

---

## 4. Cross-cutting strengths

1. **Two-layer identity model** (operator/human vs per-app local admin, ADR-0024/0028)
   — hardened against a real **break-glass-email-hijack class** found and fixed live;
   seed-bao auto-heals legacy leaks. This is mature security thinking.
2. **Secrets custody** — OpenBao with 3-of-5 Shamir (JuiceFS + Keychain + USB), ESO
   projection, scoped AWX tokens minted *as* the service identity (empirical ownership
   rule codified). The 69x "sibling-wipe" write hazard was found and fixed (patch, not
   whole-secret PUT).
3. **Public-safe by construction** — no IPs/DNS in public repos; gitleaks + scrub
   pre-commit; example-domain convention. Lowers the cost of eventual OSS release.
4. **Operator-local vs generic split** (ADR-0035) — clean reproducibility boundary.
5. **ADR discipline + boot ritual + STATUS generator** — knowledge survives across
   sessions and agents better than most solo projects.

## 5. Cross-cutting risks / debt

1. **Live-verification debt (systemic).** A large fraction of recent work is
   "code-complete, not live-verified" (env-lifecycle refactor, upgrade-in-place,
   unseal rewrite, mxl-hello, catalog-actuator direction). The frequent "no cluster"
   note means the feedback loop that catches first-boot bugs is intermittent.
2. **Single-node bias.** Almost all green checkmarks are single-node sandbox. HA and
   cloud are capacity/teardown/upgrade-blocked. The flexibility *requirement* (3
   profiles) is validated for 1 of 3 in practice.
3. **No upgrade story.** Fresh-build only until the bundle_set/upgrade-in-place
   keystone is proven on a skew env.
4. **No meaningful CI.** dmf-cms CI is a placeholder; cross-repo coordination is
   manual; the drift-prevention harness (boot-ritual single-source, doc-link checker,
   lint gates) is deferred. For a 9-repo estate this is the highest-leverage missing
   safety net.
5. **Catalog concurrency correctness.** Double-launch + deploy/finalise races are open
   in the headline workflow.
6. **Orchestration is ad-hoc.** The agentic harness is mothballed; work now flows
   through manual codex/qwen dispatch + dmf-init. Effective, but undocumented as a
   repeatable process and dependent on operator-in-the-loop discipline.
7. **Public-publish incomplete.** Only dmf-runbooks is on GitHub; umbrella publish
   deferred pending scrub+prune. The credibility/OSS goal (i)/(iii) is blocked on this.

---

## 6. Maturity scorecard (0–10, experiment-phase calibrated)

| Dimension | Score | Note |
|---|---|---|
| Architecture coherence | 8 | EBU-aligned, principled repo split, ADR discipline. |
| Identity & secrets | 8 | Two-layer model + Shamir + scoped tokens; real bugs found & fixed. |
| Media thesis (#1) | 7 | NMOS proven on k3s; deeper media-domain still scaffold. |
| Federation thesis (#2) | 1 | dmf-central unbuilt. |
| Taxonomy hard-case (#3) | 4 | Carried by MXL spike; not yet closed. |
| Bootstrap (cold path) | 6 | Works, but undertested; first-boot bugs recur. |
| Multi-node / cloud / HA | 3 | Repeatedly stalled; single-node is the real surface. |
| Upgrade / lifecycle | 3 | No proven in-place upgrade; keystone bug unproven. |
| Console (dmf-cms) | 6 | Ships + vertical slice closed; concurrency bugs open. |
| Observability | 7 | NetBox-driven dynamic monitoring live-verified. |
| Day-0 (dmf-init) | 8 | Strong; ahead of its docs. |
| CI / drift safety | 2 | Placeholder CI; manual cross-repo sync. |
| Public-readiness / OSS | 4 | Public-safe by design, but publish path incomplete. |

**Weighted read:** strong on *design and the proven thesis*, weak on *operational
proof beyond single-node* and *the safety nets that let a 9-repo estate scale*.

---

## 7. Forward-looking options (for the CEO / eng review to engage)

These are framed as **falsifying experiments + de-risking moves**, consistent with
the experiment-phase doctrine. The review gauntlet should pressure-test scope,
sequencing, and whether any of these is actually the wrong thing to do now.

**Option A — Close the live-verification loop (de-risk the systemic debt).**
Stand up one durable env and burn down the "code-complete, not verified" pile:
env-lifecycle refactor, upgrade-in-place (the keystone), unseal rewrite, mxl-hello.
*Falsifies:* whether the recent quarter of work actually runs. Highest-confidence ROI.

**Option B — Attack thesis-killer #2 (Authentik federation in dmf-central).**
Stand up one central Authentik; federate the cluster Authentik as downstream; passkey
through the chain. *Falsifies:* the multi-cluster thesis — the largest remaining
unknown and the one that most changes what dmf-central *is*.

**Option C — Close thesis-killer #3 + the actuator fork (MXL two-function fabric).**
Run the MXL src+view spike that genuinely spans two functions/layers, and use it to
resolve the **Argo-vs-AWX actuator** decision (the spike kill-switch). *Falsifies:*
the EBU taxonomy under a hard case *and* settles the biggest pending architecture fork.

**Option D — Install the safety net (CI + drift harness + upgrade proof).**
Boot-ritual single source, doc-link checker, lint gates, dmf-cms CI, and a
cold-bootstrap regression gate. *Falsifies:* nothing — but it's the missing
infrastructure that makes a 9-repo estate survivable and stops the first-boot-bug
whack-a-mole. Tension with experiment-phase "don't harden yet" doctrine — the review
should rule on whether the forcing function has now arrived.

**Option E — Finish the public-publish path (credibility/OSS goal).**
Org + repos + scrub/prune + dry-run sync. *Serves:* goals (i) and (iii) directly;
serves the thesis not at all. A strategic-priority call.

**Open architectural decisions the reviews should weigh:**
- Catalog actuator: adopt **Argo-for-k8s + AWX-glue hybrid** (reverses ADR-0025 §9),
  spike-gated? Or hold ADR-0025?
- Cross-repo reproducibility: stay loose (current) or move to submodules/pins?
- Upgrade model: invest in idempotent in-place, or commit to immutable rebuild-only?
- When does experiment phase *end* — what is the commit gate, and have we hit it?

---

## 8. The single sentence

The architecture is sound and the media thesis is proven; the project's real risk is
no longer "will it work?" but **"does it work anywhere other than one laptop-sized
sandbox, and can it be changed without breaking on the next cold boot?"** — and the
next moves should buy *operational proof and safety nets*, not more surface area.

---

# Review verdict (CEO + Eng gauntlet, 2026-06-06)

Run via `/autoplan` (SELECTIVE EXPANSION). Dual-voice: Claude subagent (independent)
+ codex CLI v0.136.0 (adversarial). Design + DX phases auto-skipped (no UI / no
developer-API scope — the "form" scope hits were `platform`). Operator gate answers:
**D1 commit now · D2 credibility-signal first · D3 reproducibility-then-publish.**

## CEO dual-voice consensus

| Dimension | Claude subagent | codex | Consensus |
|---|---|---|---|
| Commit gate fired / exit experiment phase? | Yes (gate met 2026-06-04, unnoticed) | Yes ("stale," "evasive") | ✅ CONFIRMED |
| Real blind spot the eval omits | External legibility (1/10) | External legibility ("what can a stranger validate in an hour") | ✅ CONFIRMED |
| A–E framed correctly? | No — re-rank by goal impact | No — "not peer choices" | ✅ CONFIRMED |
| Federation (B) now? | Trap — later artifact | Trap — all-scaffold | ✅ CONFIRMED |
| Argo+AWX hybrid actuator (the open fork)? | The trap — commit AWX | "Don't build a hybrid to avoid choosing" | ✅ CONFIRMED |
| Overbuilt (9 repos + Day-0 + custom actuator)? | Yes — front door, not submodules | Yes — active-surface budget | ✅ CONFIRMED |
| **The single move** | **E reframed** (publish proven NMOS now) | **A narrowed hard** (prove cold-boot first) | ❌ DISAGREE → taste decision (D3) |

## Eng review (architecture/feasibility — compressed; strategy doc, no code diff)

1. **Rebuild-only is sound as a committed choice** — dmf-init already rebuilds blank →
   full → restore (proven hermetically + one live sandbox). codex's "built on sand"
   reduces to **"cold bootstrap must be deterministic,"** not "in-place upgrade." That
   shrinks Option A to a **reproducibility slice** and removes the real scope creep.
2. **Commit AWX as actuator.** Proven end-to-end; the Argo hybrid reverses ADR-0025 for
   a no-user platform (explicit-over-clever).
3. **Catalog races are load-bearing for v0.1** — a stranger driving the console hits the
   double-launch TOCTOU + deploy↔finalise race. Per-entry lock is the one mandatory bit
   of "A debt."
4. **Decisive failure mode:** publish-without-reproducibility → stranger hits a first-boot
   bug, can't recover → worse signal than silence. This is *why* D3 resolves to
   reproducibility-then-publish, not publish-now.

## Resolution (the single move)

**Narrow Option A to the reproducibility slice, in service of Option E.** Then publish
v0.1 + a one-page thesis. Federation (B), in-place upgrade, the Argo hybrid, HA/cloud
claims, and media-v2 are **explicit v0.1 non-goals.** Full plan:
[`docs/plans/DMF v0.1 Commitment & 30-Day Focus-Cut Plan 2026-06-06.md`](../plans/DMF%20v0.1%20Commitment%20%26%2030-Day%20Focus-Cut%20Plan%202026-06-06.md).
Commitments: [`docs/decisions/architectural-commitments-v1.md`](../decisions/architectural-commitments-v1.md).

## Decision audit trail

| # | Phase | Decision | Class | Basis | Rejected |
|---|---|---|---|---|---|
| 1 | CEO | Exit experiment phase, write commitments-v1 | User gate (D1) | Commit gate fired 2026-06-04; both voices | Stay in experiment phase |
| 2 | CEO | Optimize for credibility-signal first | User gate (D2) | Stated goal priority (i)>(iii)>(ii) | OSS-first; lab-first |
| 3 | CEO | Commit AWX actuator; freeze Argo hybrid | Auto (P5 explicit, both voices) | Reverses ADR-0025 for no users | Build Argo+AWX hybrid |
| 4 | CEO | Defer federation (B) + media-v2; freeze dmf-central | Auto (P3, both voices) | Audience-of-zero now | Open dmf-central now |
| 5 | Eng | Rebuild-only; in-place upgrade = non-goal | Auto (P5) | dmf-init rebuild proven | Chase upgrade keystone |
| 6 | Eng | Catalog per-entry lock is in v0.1 | Auto (P1 completeness) | Headline-workflow race | Defer the lock |
| 7 | CEO/Eng | The single move = reproducibility-then-publish | User taste (D3) | Reconciles both voices | Publish-now; prove-everything-first |
| 8 | Gate | Produce commitments + this synthesis + 30-day plan | User (D4) | — | Review only, no files |
