# DMF Platform — Strategic Review (Experiment Phase)

> **Point-in-time review (2026-04-30).** For the current assessment see [dmf-platform-technical-evaluation-2026-06-06.md](dmf-platform-technical-evaluation-2026-06-06.md).

**Date:** 2026-04-30
**Scope:** dmf-cms, dmf-infra, dmf-env, dmf-central, dmf-media (rpi-k3s-cluster excluded as out of scope)
**Reviewer mode:** CEO / strategy, cross-repo
**Stated goals:** (i) career/credibility signal, (iii) eventual product/OSS, (ii) working lab platform — secondary for now
**Stated stage:** experiment phase, no commitment yet, testing before locking in

---

## Reframe

In experiment mode, the right metric isn't "is the system hardened" — it's **"what irreversible decisions am I de-risking before I commit?"** Hardening (alerts, backups, token rotation) is reversible/addable later and adds soft lock-in (dashboards built on it, runbooks expecting it) without testing any architectural assumption. So I retract the alerts-and-backup push from the prior recommendation. You're right to defer that.

But not all of the prior mode A was hardening. Some of it was disguised architecture validation. The reframing follows.

---

## What the experiment phase is actually for

Three classes of risk to burn down right now, in order:

### 1. Thesis-killer risks (highest priority, hardest to recover from)

- **Does NMOS IS-04/05 + EBU LIST 2110 actually deploy on commodity k3s?** This is the biggest unknown in the entire architecture. If the media-domain story doesn't land cleanly, "DMF on k3s" is a fundamentally different product. Untested — `dmf-media` is empty.
- **Does Authentik actually federate cross-cluster with passkey enrollment in a way you'd commit to?** Right now Authentik deploys per-cluster. Plan says federate. If federation's hard or weird, the whole `dmf-central` thesis changes.
- **Does the EBU V2.0 layer / vertical / lifecycle taxonomy survive a hard case?** Right now every playbook fits because they were written with the taxonomy in mind. The taxonomy fails at the first playbook that genuinely spans two layers or two verticals. Find that case.

### 2. Interface-commitment risks (medium priority)

- **Does the NetBox SoT data model match what AWX's inventory plugin needs and what dmf-cms's UI wants?** If not, you'll be reshaping NetBox custom fields and tags painfully later. Test by closing one end-to-end loop.
- **Does the dmf-cms `app-contract` data model survive contact with reality?** Right now it's a static YAML fixture. The real test is plugging it into one live backend (AWX or NetBox) and seeing what attributes you actually need.

### 3. Plan-visibility risk (cheap to fix, blocks both goals)

- **The DMF Platform Plan is invisible.** For (i) credibility and (iii) OSS, the plan being external is a poison pill. No outsider can read your architecture. No future-you can iterate on it as a tracked artifact. Commit it now, even as draft.

---

## Recommendation — three moves, in priority order

Each move is a **falsifying experiment**, not a polish pass.

### Move 1 — Burn down the biggest thesis risk first (pick one)

Either:

**(a) NMOS IS-04/05 spike in `dmf-media`.**
Deploy one NMOS registry (e.g. `nmos-cpp-registry` or BBC's `nmos-cpp`) on the lab cluster. Wire it into NetBox via the media plugin. Get one mock sender/receiver registered. Run for 24 hours.
**What you'll learn:** whether the Layer 4 plan is actually buildable on this stack, and what custom-resource shapes you actually need.
**Effort:** ~1 day.

**(b) Authentik federation spike in `dmf-central`.**
Stand up one central Authentik. Configure the existing `dmf-infra` Authentik to be a downstream federated IdP. Get passkey login working through the chain.
**What you'll learn:** whether the federation story works as cleanly as the plan claims, and what `dmf-central` actually needs to be.
**Effort:** ~half a day.

**Pick (a).** It's the bigger thesis-killer and the more credible artifact for (i) and (iii). If NMOS doesn't land cleanly, you'd rather discover that before committing dmf-cms release-1 to the routing-matrix story.

### Move 2 — One vertical slice through dmf-cms to a real backend

Pick **one** dmf-cms section — `Workflows` is the obvious choice — and wire it end-to-end to a real AWX job that runs against NetBox-derived inventory and returns a real result to the UI. Yes, this implies finally closing the AWX loop the April reviews flagged. But the framing isn't "harden the loop"; it's "test whether your console's data flow actually works."

**What this falsifies (or confirms):**

- The dmf-cms `app-contract` model survives a real backend
- AWX's job-template API shape is compatible with the operator UX you want
- NetBox's custom-field schema is enough to drive AWX inventory the way you'd commit to
- The runtime auth flow (Authentik OIDC user → AWX RBAC → NetBox token) actually composes

If you do this slice well, dmf-cms release-1 stops being a list of pages and becomes "do the same vertical slice four more times." That's a much better commitment posture than "ship a nav shell and figure out the data model later."

**Effort:** ~2-3 hours. The most de-risking single thing you can do across the whole project.

### Move 3 — Commit the DMF Platform Plan to a canonical repo

`dmf-infra/docs/dmf-platform-plan.md` is the natural home (it's the most public repo, and it's where every cross-reference already points). Sanitise of anything site-specific. Even committing as v0.1 draft is enough — you can iterate. The current state where every README points at a phantom path is bad for (i), (iii), and future-you.

**Effort:** ~30 min.

---

## What to *not* do at this stage

- **Don't add Prometheus alerts yet.** Not until you've decided what "production" looks like. Adding alerts now picks names and SLOs you'll regret.
- **Don't add NetBox PG backup yet.** Lab data loss is acceptable while you're still reshaping the schema. Backup what you've decided to commit to, not what you're still experimenting with.
- **Don't fold `dmf-central` or `dmf-media` back.** I retract the prior mode-C suggestion. Asymmetric cost — keeping them as scaffolds is cheap; re-splitting later is expensive. They earn their existence by being reservations for the thesis tests Move 1 will fill in.
- **Don't reorganise the EBU layering yet.** Find the first playbook that genuinely breaks the taxonomy in practice (likely something cross-cutting in Move 1's NMOS work). *Then* decide whether to evolve the taxonomy.

---

## The thing to add: a commit gate

Experiments without a commit-gate become drift. Pick a marker — date or milestone — that triggers the transition from "experimenting" to "committing." Suggested gate:

> When dmf-cms release-1's first vertical slice is running end-to-end against real backends **AND** one NMOS registry is deployed in `dmf-media`, write `docs/architectural-commitments-v1.md` and stop reshaping the foundations. After that, new work follows the layout instead of reshaping it.

Roughly a 1-2 week scope for one operator with focus. After that point the April P0s (alerts, backups, token rotation) become genuinely the right next work — because by then you'll be hardening *committed* architecture, not still-fluid experiments.

---

## The single sentence

You're in the right phase doing the wrong type of work in it. **Experimentation should produce falsifying evidence, not polished surfaces.** Move 1 (NMOS spike) and Move 2 (dmf-cms vertical slice to real AWX) will teach you more about whether the architecture survives contact with reality than the next month of console-shell polish or playbook reorganisation. Plus Move 3 (commit the plan) because (i) and (iii) require it and it's free.

---

## Appendix — context this review built on

### Repos in scope (state at 2026-04-30)

| Repo | Role | State | Real activity? |
|---|---|---|---|
| dmf-cms | Layer 6 console (FastAPI/HTMX/SSE) | ~7 modules, OIDC, Authentik invitation client, Helm chart | Yes — on `feature/dmf-console-release-0-bootstrap`, last 3 commits Authentik invitation API fixes |
| dmf-infra | Layers 2–3 + 6 (non-media) + verticals, generic public | Working cluster bootstrap, EBU V2.0 reorg landed | Yes — 7 dirty files: Zot OIDC, Authentik blueprints, born-inventory, post-bootstrap-verify |
| dmf-env | Private inventory, Terraform L1, secret shims, Resource Profiles | Hetzner ARM env active | Minor (1 file dirty: hosts.ini) |
| dmf-central | "Deploy-once" central IdP / secrets / registry | 3-commit scaffold, all roles empty | No — placeholder |
| dmf-media | Layer 4–5 (NMOS, EBU LIST 2110, PTP, NetBox media plugin) | 3-commit scaffold, all roles stubs | No — placeholder |

### What the prior April reviews already covered (not relitigated here)

The Claude 2026-04-16 and Qwen 2026-04-17 reviews are accurate and broadly agree. Their joint P0:

- AWX loop never closes — plumbing without flow
- NetBox API token in plaintext in Forgejo SCM
- Zero `PrometheusRule` alerts
- No NetBox PG backup
- `Admin123` universal password in CLAUDE.md

None of those have been addressed in the ~13 days since. In experiment phase that's fine — but Move 2 above incidentally closes the AWX loop as a side effect of doing the right de-risking work.

### Pattern to be aware of

Timeline:

- **2026-04-16/17** — two reviews flag AWX loop / alerts / backup / token leak as P0
- **2026-04-25** — DMF EBU Mapping doc dated; major reorg into V2.0 layout
- **2026-04-26** — DMF Console Initial Implementation Plan dated
- **2026-04-26 to now** — dmf-cms release-0 implementation, Authentik invitation API integration with 3 fix commits, Zot OIDC integration, Authentik blueprint provisioning, born-inventory work
- **The April P0s** — still open

Every individual commit is reasonable. The aggregate signal — "structural elaboration is winning over hardening of unfinished foundations" — is a strategic posture worth choosing explicitly rather than drifting into. In experiment phase, this is acceptable *if* the structural elaboration is producing falsifying evidence (Move 1 / Move 2 do; release-0 nav shell mostly didn't).
