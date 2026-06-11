# The journey so far

*Written 2026-06-10, as part of making this repository legible to outsiders. This is
the narrative layer over the record — every claim links into the reviews, ADRs,
handoffs, and plans that document it. If you want the current technical assessment,
read the [2026-06-06 technical evaluation](reviews/dmf-platform-technical-evaluation-2026-06-06.md);
this document explains how the project got there.*

---

## What this is, in one paragraph

DMF is my attempt to find out whether the EBU's *Dynamic Media Facility* reference
architecture — the broadcast industry's blueprint for software-defined,
IP-based media facilities — can be built on commodity hardware and commodity
open-source infrastructure: k3s, Ansible, NetBox, AWX, Authentik, OpenBao, a React
operator console. Not a demo of one media app, but the whole operational fabric:
identity, secrets custody, source-of-truth inventory, a deployable media-function
catalog, and a Day-0 installer that takes a blank machine to a running facility.
I build it solo, working with AI agents as a deliberate part of the method (more
on that [below](#working-with-agents-the-method)).

## Before the record begins

The project predates this repository. Through early 2026 it lived as a working
Hetzner ARM lab plus a private operator note store, rebuilt and re-verified
piece by piece — the [rebuild session notes of 2026-04-22](sessions/DMF%20Rebuild%20Session%20Notes%202026-04-22.md)
are the oldest document in the tree and capture that phase's texture: thirty-odd
numbered playbooks run in order against a fresh cluster, each failure fixed and
recorded. On 2026-04-25 the playbook taxonomy was aligned to the EBU DMF V2.0
vocabulary ([ADR-0003](decisions/0003-ebu-v2-taxonomy.md),
[mapping doc](architecture/DMF%20EBU%20Mapping%20%282026-04-25%29.md)) — layers,
verticals, lifecycle stages — so the platform speaks the domain's reference
language instead of inventing its own. The notes were consolidated into this
umbrella on 2026-05-03; filenames were preserved verbatim, which is why the doc
titles read like a lab notebook. They are one.

## The reframe: experiments, not polish (2026-04-30)

In mid-April, two independent reviews flagged the same P0s: the console-to-AWX
loop had never closed, no alerts, no backups, a token in plaintext. Two weeks
later none of them were fixed — and the
[strategic review of 2026-04-30](reviews/dmf-platform-strategic-review-2026-04-30.md)
made the call that shaped everything since: **stop treating that as a hardening
backlog.** In an experiment phase, the right metric is not "is the system
hardened" but *"what irreversible decisions am I de-risking before I commit?"*
The review named three **thesis-killers** — the assumptions that, if false, would
make DMF a fundamentally different product:

1. **Does NMOS IS-04/05 actually deploy on commodity k3s?** (the media-domain
   thesis — at the time, `dmf-media` was empty)
2. **Does Authentik federate cross-cluster with passkey enrollment?** (the
   multi-site `dmf-central` thesis)
3. **Does the EBU layer/vertical/lifecycle taxonomy survive a hard case** — a
   function that genuinely spans two layers?

It prescribed two falsifying moves — an NMOS spike (Move 1) and one real vertical
slice through the console (Move 2) — and, crucially, a **commit gate**: when both
moves close, write `architectural-commitments-v1.md` and *stop reshaping the
foundations*. That stance was codified as
[ADR-0004](decisions/0004-experiment-phase-stance.md). Everything between
2026-04-30 and 2026-06-06 happened inside that frame.

## Move 2: the vertical slice (closed 2026-05-04)

The first experiment was the cheaper one: wire one console page end-to-end to a
real AWX job running against NetBox-derived inventory
([learnings](reviews/dmf-platform-move-2-learnings-2026-05-04.md)). It closed in
days and confirmed the data-flow thesis — with instructive friction: NetBox v4 had
quietly changed the `Service` model from a direct foreign key to a generic
relation, breaking the planned schema; and the console's `app-contract` survived
contact with a live backend by *narrowing* into a navigation manifest rather than
widening into a service catalog. The catalog source of truth settled on NetBox.
That asymmetry — plans bending on contact, the architecture holding — became the
recurring pattern.

## Move 1: NMOS on commodity k3s (closed 2026-06-04)

The big one. Sony's `nmos-cpp` registry, built from source for ARM64, deployed
through the full catalog control chain: catalog YAML → Provision → AWX job →
launcher playbook → Helm → health probe → Finalise → NetBox lifecycle tag
(Provision/Configure/Finalise are the catalog's lifecycle stages —
[ADR-0012](decisions/0012-configure-stage-distinct-from-provision.md),
[ADR-0013](decisions/0013-media-function-catalog-model.md)). The
[Move 1 learnings](reviews/dmf-platform-move-1-learnings-2026-06-04.md) test six
architectural assumptions; five confirmed outright, one (the drift detector
firing on live divergence) still rests on code inspection rather than an observed
failing run — recorded as an evidence gap.

**Thesis-killer #1 did not fire.** NMOS runs on commodity ARM k3s, driven from
the console.

The most valuable finding wasn't the confirmation — it was the
[**Path A pivot**](handoffs/DMF%20Move%201%20Gate%202%20Path%20A%20Pivot%20Handoff%202026-05-06.md)
(2026-05-06, named for the execution-transport option that won): the task spec
assumed lifecycle stages would live in wrapper playbooks; reality put them in
the *role*, invoked by a thin AWX launcher with a stage variable. Two planned deliverables were obviated mid-move, and the lesson
generalized: **lifecycle-stage identity belongs to the unit that owns the
workload, not to an orchestration wrapper.** The pivot is told in the record as a
finding, not a failure — [ADR-0014](decisions/0014-awx-project-layout.md),
[ADR-0016](decisions/0016-awx-control-node-ssh-via-cloud-init-and-openbao.md) and
later [ADR-0025](decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md)
carry the corrected shape.

Move 1 also surfaced the platform's rough edges: a NetBox write needed its
own scoped service identity ([ADR-0032](decisions/0032-catalog-launcher-scoped-netbox-writer.md));
running air-gapped taxed every layer (collections baked into the execution
environment, pinned on inventory sources too —
[ADR-0034](decisions/0034-internal-ansible-collection-source.md)); and two
concurrency races in the deploy/teardown path were found by actually clicking
the buttons fast — one fixed, one still open (see
[OPEN-QUESTIONS](OPEN-QUESTIONS.md)).

## What got built around the moves

The experiments forced supporting architecture into existence, each piece with
its decision record (the [reading guide](decisions/READING-GUIDE.md) sequences
them; the [digests](decisions/digests/) hold consolidated truth):

- **Identity & authority chain** ([ADR-0028](decisions/0028-identity-and-authority-chain.md)):
  Authentik as sole human identity authority, passkey-first; a two-layer model
  separating the operator/human from per-app local admins — hardened against a
  real break-glass-hijack class found live.
- **Secrets custody** ([ADR-0008](decisions/0008-openbao-secrets-architecture.md),
  [ADR-0009](decisions/0009-shamir-dr-model.md),
  [ADR-0029](decisions/0029-tiered-unseal-posture.md)): OpenBao behind External
  Secrets Operator, 3-of-5 Shamir custody across physical locations, an honest
  ADR about what auto-unseal trades away.
- **NetBox-driven dynamic monitoring** ([ADR-0038](decisions/0038-netbox-driven-dynamic-monitoring.md)):
  Prometheus targets generated from the source of truth, live-verified end to end.
- **Operator-local environments** ([ADR-0035](decisions/0035-operator-local-self-contained-envs.md)):
  every environment's state lives outside the repos; the public tree stays
  generic by construction.
- **dmf-init** ([ADR-0036](decisions/0036-dmf-init-thin-control-container.md)):
  a Day-0 stateless installer container that takes a blank node to a full
  facility and restores from passphrase-wrapped backups. On 2026-06-07 it ran
  its first full bootstrap against a real cloud VPS — not the development
  sandbox — end to end.

## The third thesis-killer, unfinished

The **MXL spike** (Media eXchange Layer — the EBU/LF effort for in-host media
exchange) is the deliberate hard case for thesis-killer #3: two media functions
(a source and a viewer) sharing a data plane, genuinely spanning layers
([ADR-0017](decisions/0017-mxl-intra-host-data-plane.md),
[plan](plans/DMF%20MXL%20On-Demand%20Media%20Function%20Cycle%20Plan%202026-06-01.md)).
Its single-node control chain is code-complete; live verification is **paused**.
Thesis-killer #2 (cross-cluster federation) was **never started** — `dmf-central`
remains scaffold. Neither is hidden: both are explicitly frozen or paused in
[OPEN-QUESTIONS](OPEN-QUESTIONS.md), with re-open triggers.

## Working with agents: the method

This platform is built by one operator orchestrating AI agents, openly and on
purpose. The working model that survived contact with reality:

- **Claude orchestrates and verifies; other agents lift.** Mechanical multi-file
  work goes to worker agents (qwen panes, subagents); an adversarial second
  voice (codex) reviews plans and decisions. Every major review in the record is
  **dual-voice** — two independent models had to agree, and their disagreements
  were surfaced to me as taste decisions rather than silently resolved.
- **Never trust a DONE report.** Worker output is grep-verified against the tree,
  every time. This rule exists because it was earned.
- **Knowledge must survive sessions.** Agents have no memory between sessions, so
  the project runs on a boot ritual: regenerate STATUS, read the latest handoff,
  apply the ADRs. The discipline that makes agents effective — short-lived
  context, durable written decisions — turns out to be exactly the discipline
  that makes a project legible to strangers. You are reading its output.
- **Process machinery gets mothballed when it loses to simpler tools.** I built a
  full agentic harness — backlog queue, decision queues, tick loop, guards
  ([plan](plans/DMF%20Agentic%20Harness%20Plan%202026-05-11.md), preserved under
  [docs/agentic/](agentic/README.md)). It worked — it ran real shifts — and it
  was retired within a month because GitHub Issues plus direct dispatch did the
  same job with less ceremony. The artifacts stay in the tree as provenance.

The repository's conventions — handoffs as append-only lab notebook, ADRs with
reciprocal supersession links, generated indexes, commit-blocking hygiene gates —
all come from this: they are the interface between me, the agents, and now you.

## The gate fires (2026-06-04 → 2026-06-06)

Move 1's closing write-up noted that the commit gate defined on 2026-04-30 had
quietly been met. The [technical evaluation of 2026-06-06](reviews/dmf-platform-technical-evaluation-2026-06-06.md)
made it official — and uncomfortable. Its scorecard is candid: architecture
coherence 8/10, identity and secrets 8/10 — and **external legibility 1/10**. The
dual-voice CEO/eng review confirmed the diagnosis from both sides: the gate had
fired weeks earlier ("stale," said one voice; "evasive," said the other), the
project was still choosing work under experiment-phase rules, and the single
biggest omission was that *no stranger could validate any of it in an hour*.

The result is [architectural-commitments-v1](decisions/architectural-commitments-v1.md)
(2026-06-06), which closed the experiment phase for the committed core:
single-node/Flypack is the proof surface (a *Flypack* is the portable
facility-in-a-flight-case / OB-truck deployment profile), AWX is the catalog
actuator, NetBox
tags are lifecycle state, dmf-init is the installer, rebuild-only is the
lifecycle model. Equally important is what it *freezes*: federation, HA/cloud
release claims, an Argo hybrid actuator, in-place upgrade, deeper media roles —
named non-goals so they stop re-entering as "experiments." The work-selection
rule flipped from *"produce falsifying evidence"* to **"make the proven core
runnable and legible to an outsider."**

## Which review is current, and why both were right

The [2026-06-06 evaluation](reviews/dmf-platform-technical-evaluation-2026-06-06.md)
is the current assessment. The
[2026-04-30 strategic review](reviews/dmf-platform-strategic-review-2026-04-30.md)
is superseded — but it was right for its moment: it stopped a premature
hardening push, aimed the project at its real risks, and defined the gate that
ended its own regime. The evaluation graded the work the review commissioned.
Read them in that order and the project's two phases explain each other.

## Where it stands now

The [v0.1 plan](plans/DMF%20v0.1%20Commitment%20%26%2030-Day%20Focus-Cut%20Plan%202026-06-06.md)
is one move: **reproducibility, then publish** — a stranger clones, runs one
command, gets DMF on a blank node, deploys a media function from the console,
and inspects the receipts. The first container-driven cold bootstrap on a real
VPS succeeded 2026-06-07 and caught an entire class of first-boot bugs, which is
exactly what it was for. The eight component repositories went public on
2026-06-09/10 as clean imports; this umbrella — the knowledge base you are
reading — is the last piece, made public with its history of pivots,
mothballed machinery, and honest evidence gaps intact, because the record *is*
the product of the method.

What remains open, frozen, or unproven is curated in
[OPEN-QUESTIONS.md](OPEN-QUESTIONS.md). The live backlog is
[GitHub Issues](https://github.com/dmfdeploy/dmfdeploy/issues). If you want to
understand the decisions, start with the
[ADR reading guide](decisions/READING-GUIDE.md).

---

## Timeline at a glance

| When | What |
|---|---|
| ≤ 2026-04 | Private lab + notes; Hetzner ARM cluster rebuilt playbook by playbook |
| 2026-04-25 | EBU DMF V2.0 taxonomy adopted (ADR-0003) |
| 2026-04-30 | Strategic review: experiment phase, three thesis-killers, commit gate (ADR-0004) |
| 2026-05-04 | Move 2 closed — console → AWX → NetBox vertical slice confirmed |
| 2026-05-06 | Path A pivot — lifecycle stages move from wrappers into roles |
| 2026-05-11/12 | Agentic harness built + run; mothballed 2026-06-04 in favor of GitHub Issues |
| 2026-05-29 → | MXL spike (thesis-killer #3 pressure test); single-node chain code-complete, live verify paused |
| 2026-06-04 | Move 1 closed — NMOS on commodity ARM k3s **confirmed** (thesis-killer #1) |
| 2026-06-06 | Technical evaluation + dual-voice review → architectural-commitments-v1; experiment phase closed |
| 2026-06-07 | First container-driven cold bootstrap on a real VPS (dmf-init) |
| 2026-06-09/10 | Component repos published; umbrella front-door work (this document) |
