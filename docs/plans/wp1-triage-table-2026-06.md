---
status: executed
date: 2026-06-10
executed: 2026-06-10
---

# WP1 — Plan-Status Triage Table (2026-06)

**Status:** Active — this table is the **single input** to the WP2 frontmatter sweep
(see `DMF Umbrella Public Entrance and GitHub Working Model Plan 2026-06-10.md` §WP1/WP2).
Flip to `executed` once WP2 has been applied and grep-verified.

Rules (binding for sweep agents):

- **Sweep agents must never infer status from a doc's prose.** This table is the
  only source. If a file is missing here, stop and report — do not guess.
- Allowed `status` values: `active | draft | executed | superseded | historical`.
- `date` = plan date (from filename; for the 7 undated files, assigned below —
  4 use the 2026-05-11 umbrella-consolidation import date, 3 Move-1 gate docs are
  assigned from narrative cross-references).
- `executed:` only where the column has a value. `superseded_by:` only where the
  column has a value (exact filename, quoted).
- Per WP2: superseded docs also get a one-line banner under the title pointing at
  the successor (reciprocal link in the successor where sensible).
- `DMF Umbrella Public Entrance and GitHub Working Model Plan 2026-06-10.md` and
  **this file** already carry frontmatter — WP2 must not touch them (114 files to edit).

Semantics: **active** = guiding work right now; **draft** = proposed/approved but
not started, still intended; **executed** = the work landed (terminal);
**superseded** = replaced by a named successor; **historical** = point-in-time /
frozen / shelved, kept for provenance. Default for anything not allowlisted
active/draft is executed-or-historical (codex finding: allowlist-first).

## Active (9)

| File | date | note |
|---|---|---|
| DMF Umbrella Public Entrance and GitHub Working Model Plan 2026-06-10.md | 2026-06-10 | this programme; frontmatter already present |
| DMF v0.1 Commitment & 30-Day Focus-Cut Plan 2026-06-06.md | 2026-06-06 | canonical commitment frame |
| DMF First Public Release Plan 2026-06-09.md | 2026-06-09 | components shipped; umbrella B2 + E2 remain |
| DMF Init Installer UI Redesign Plan 2026-06-10.md | 2026-06-10 | pass 1 PR pending; pass 2 specced |
| DMF Dynamic NetBox-Driven Monitoring Plan 2026-06-04.md | 2026-06-04 | validated green; launcher stamping + probe tuning open |
| DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md | 2026-05-19 | ⚠ Lane C closure unconfirmed; CLAUDE.md still names it the active task |
| DMF OSS v0.1 WP0 Release Contract and Profile Matrix 2026-05-25.md | 2026-05-25 | ⚠ confirm still binding alongside the 2026-06-06 commitment plan |
| DMF OSS v0.1 WP1S Single-Node Sandbox Lane 2026-05-25.md | 2026-05-25 | remaining replicability run = v0.1 Phase 1 gate |
| DMF OSS v0.1 WP5 Release Verification and Tagging 2026-05-25.md | 2026-05-25 | sandbox verification row still gates the v0.1 claim |

## Draft (8)

| File | date | note |
|---|---|---|
| DMF AWX Catalog Credential Type Migration Plan 2026-05-23.md | 2026-05-23 | deferred staged follow-up to Lane B |
| DMF Authentik Bootstrap Enrollment Drop Username Prompt Plan 2026-05-28.md | 2026-05-28 | ⚠ may have landed with later enrollment work — downgrade to executed if so |
| DMF Facility Console — Born-Inventoried Env Surfacing Plan 2026-06-04.md | 2026-06-04 | ⚠ console-side surfacing status unclear (infra side landed) |
| DMF Internal Ansible Collection Source Plan 2026-05-29.md | 2026-05-29 | ADR-0034 follow-up, open in TODOS |
| DMF Pre-Release Compliance Readiness Plan 2026-05-11.md | 2026-05-11 | Tier A finish open in TODOS |
| DMF Tier A Phase Execution Plan 2026-05-11.md | 2026-05-11 | living doc; Tier A remainder open |
| DMF Zot Machine-Identity Service Account Plan 2026-05-27.md | 2026-05-27 | ⚠ "ready for implementation" — confirm not already landed |
| DMF dmf-init GitHub Build Workflows — Exec Spec 2026-06-10.md | 2026-06-10 | specced 2026-06-10, not started (E2-adjacent) |

## Executed (64)

| File | date | executed |
|---|---|---|
| AWX NetBox Inventory Sync Fix 2026-05-04.md | 2026-05-04 | 2026-05-04 |
| DMF ADR-0025 Lane B Implementation Plan 2026-05-22.md | 2026-05-22 | 2026-05-23 |
| DMF AWX Authentik SAML Plan 2026-04-27.md | 2026-04-27 | |
| DMF App Admin Account Drift Audit and Realignment Plan 2026-05-14.md | 2026-05-14 | 2026-05-23 |
| DMF Authentik Brand-Wide Passkey-First Login Plan 2026-05-29.md | 2026-05-29 | ⚠ passkey-first proven live on later sandbox envs |
| DMF Base Domain in Bootstrap Bundle and CMS Logout Redirect 2026-05-09.md | 2026-05-09 | |
| DMF Bootstrap Pre-Seed Blocker Fix Implementation Plan 2026-05-09.md | 2026-05-09 | |
| DMF Bootstrap Provision Configure Split Plan 2026-05-07.md | 2026-05-07 | |
| DMF Catalog NetBox Scoped Writer Plan 2026-05-27.md | 2026-05-27 | 2026-05-27 |
| DMF Console Authentik Internal Back-Channel Split Plan 2026-05-27.md | 2026-05-27 | |
| DMF Console Initial Implementation Plan 2026-04-26.md | 2026-04-26 | |
| DMF Doc-Hygiene Judgment-Tier Exec Spec 2026-06-10.md | 2026-06-10 | 2026-06-10 |
| DMF Doc-Hygiene PR-Submission Spec 2026-06-10.md | 2026-06-10 | 2026-06-10 |
| DMF Env Lifecycle Refactor Plan 2026-06-01.md | 2026-06-01 | 2026-06-01 |
| DMF Forgejo Import + AWX Runbooks Plan 2026-05-04.md | 2026-05-04 | |
| DMF Hardcoded Environment Literals Cleanup Plan 2026-05-19.md | 2026-05-19 | |
| DMF Hetzner CCM Upgrade Plan 2026-06-01.md | 2026-06-01 | 2026-06-01 — ⚠ landed in dmf-env, not live-validated |
| DMF Improvement Run Plan 2026-04-22.md | 2026-04-22 | |
| DMF Init Bootstrap Container Plan 2026-06-02.md | 2026-06-02 | 2026-06-08 — remains the dmf-init architectural reference |
| DMF Init Phase 1 Implementation Plan 2026-06-02.md | 2026-06-02 | |
| DMF Init Phase 1b Orchestration Design 2026-06-02.md | 2026-06-02 | |
| DMF Init Phase 1c Manage Mode Design 2026-06-02.md | 2026-06-02 | |
| DMF Init Wizard env_id Provider Architecture Split Plan 2026-05-19.md | 2026-05-19 | |
| DMF Internal Service DNS Migration Survey 2026-05-14.md | 2026-05-14 | |
| DMF LAN Forgejo Archive and GitHub-Mirror Plan 2026-06-10.md | 2026-06-10 | 2026-06-10 |
| DMF Layer-1 OpenTofu Bootstrap Plan 2026-04-26.md | 2026-04-26 | |
| DMF Lifecycle-Configure Bootstrap Completion Plan 2026-05-15.md | 2026-05-15 | |
| DMF MXL M1.1 Catalog Launch Design 2026-06-01.md | 2026-06-01 | 2026-06-05 — ⚠ code-complete; live verify paused |
| DMF MXL-Hello Single-Node Catalog Control-Chain Validation Plan 2026-06-05.md | 2026-06-05 | 2026-06-05 — ⚠ code-complete on main; live verify PAUSED |
| DMF Montest Fresh-Bootstrap Validation Task 2026-06-04.md | 2026-06-04 | 2026-06-05 |
| DMF Move 1 Path A Reset 2026-05-12.md | 2026-05-12 | |
| DMF NetBox-SoT Token-Mint Hardening Task 2026-06-04.md | 2026-06-04 | 2026-06-04 |
| DMF OSS v0.1 Contributor Replicability Premise Pass 2026-05-25.md | 2026-05-25 | promoted into ADR-0031 |
| DMF OSS v0.1 WP2 Bootstrap Independence 2026-05-25.md | 2026-05-25 | ⚠ delivered via dmf-init |
| DMF OSS v0.1 WP3 In-Cluster Platform Services 2026-05-25.md | 2026-05-25 | ⚠ sandbox-trim profile delivered |
| DMF OSS v0.1 WP4 CMS User Administration 2026-05-25.md | 2026-05-25 | 2026-06-08 |
| DMF OpenBao AppRole-Reconciler Implementation Brief 2026-05-13.md | 2026-05-13 | 2026-05-13 |
| DMF OpenBao AppRole-Write Reconciler Plan 2026-05-13.md | 2026-05-13 | 2026-05-13 |
| DMF Orchestrator and Renumbering Plan 2026-04-22.md | 2026-04-22 | |
| DMF Per-App Identity Feasibility Survey 2026-05-24.md | 2026-05-24 | seeded ADR-0028 |
| DMF Pre-Bao Bootstrap Secrets Design 2026-05-08.md | 2026-05-08 | |
| DMF Public Container Registry Publishing Plan 2026-05-19.md | 2026-05-19 | |
| DMF Public Repo Doc-Hygiene Cleanup Plan 2026-06-10.md | 2026-06-10 | 2026-06-10 — wording-scrub follow-ups tracked in STATUS |
| DMF Public Repo Identity Leak Sweep 2026-05-11.md | 2026-05-11 | |
| DMF Sandbox Artifact Consolidation Plan 2026-05-28.md | 2026-05-28 | ⚠ confirm landed |
| DMF Sandbox E2E Test Harness Plan 2026-06-05.md | 2026-06-05 | |
| DMF Sandbox Harness Followups — Env-Domain, QR, Passkey-Flow 2026-06-05.md | 2026-06-05 | 2026-06-08 — ⚠ confirm QR item |
| DMF Sandbox Monitoring Vertical Integration Plan 2026-05-27.md | 2026-05-27 | |
| DMF Sandbox Zero-Setup Addressing (sslip.io) Plan 2026-06-07.md | 2026-06-07 | 2026-06-08 |
| DMF Secret Ownership and OpenBao Migration Plan.md | 2026-05-11 | date = consolidation import |
| DMF Unified App-Admin Helper Plan 2026-05-23.md | 2026-05-23 | |
| DMF Workstream A — CI Recovery Fix Spec 2026-06-09.md | 2026-06-09 | 2026-06-10 |
| DMF Workstream A — Clean-History Import and Canonical Flip Execution Spec 2026-06-09.md | 2026-06-09 | 2026-06-10 |
| DMF Workstream A — Pre-A Tooling Implementation Spec 2026-06-09.md | 2026-06-09 | 2026-06-09 |
| DMF Workstream B — dmf-env Public-Surface Scrub Spec 2026-06-09.md | 2026-06-09 | 2026-06-09 |
| DMF Workstream C — ADR Digest Execution Spec 2026-06-09.md | 2026-06-09 | 2026-06-09 |
| DMF Workstream D — GitHub-First Governance Execution Spec 2026-06-09.md | 2026-06-09 | 2026-06-09 |
| DMF Workstream E1 — PR-Gate CI Execution Spec 2026-06-09.md | 2026-06-09 | 2026-06-09 |
| DMF dmf-init Container Productization Plan 2026-06-07.md | 2026-06-07 | 2026-06-08 |
| DMF dmf-init Live-Sandbox Fix Batch Plan 2026-06-03.md | 2026-06-03 | 2026-06-03 — #11/#12 residue in TODOS |
| Move 1 Gate 1 — Build NMOS + Run Provision.md | 2026-05-04 | date assigned from move-1 narrative |
| dmf-platform-codex-cleanup-task-2026-04-30.md | 2026-04-30 | |
| dmf-platform-move-1-task-2026-05-04.md | 2026-05-04 | 2026-06-04 |
| dmf-platform-move-2-task-2026-04-30.md | 2026-04-30 | 2026-05-04 |

> Row math: 9 active + 8 draft + 64 executed + 9 superseded + 25 historical
> = 115 tracked plan files (machine-verified against `git ls-files`).
> This table itself (file 116) already carries frontmatter and is not a
> WP2 sweep input.

## Superseded (9)

| File | date | superseded_by |
|---|---|---|
| DMF Day-0 Inventory and Monitoring Plan.md | 2026-05-11 (import) | "DMF Dynamic NetBox-Driven Monitoring Plan 2026-06-04.md" |
| DMF In-Cluster Ansible Runner Pod Implementation Plan 2026-05-14.md | 2026-05-14 | "DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md" |
| DMF MXL Single-Node Media Node Spike Plan 2026-05-17.md | 2026-05-17 | "DMF MXL Single-Node Loopback Execution Plan 2026-05-29.md" |
| DMF NMOS Registry + Crosspoint Demo Plan 2026-05-04.md | 2026-05-04 | "dmf-platform-move-1-task-2026-05-04.md" |
| DMF OSS v0.1 Release Mission 2026-05-25.md | 2026-05-25 | "DMF OSS v0.1 WP0 Release Contract and Profile Matrix 2026-05-25.md" |
| DMF Release and Contribution Model Implementation Plan 2026-05-11.md | 2026-05-11 | "DMF Workstream D — GitHub-First Governance Execution Spec 2026-06-09.md" |
| Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md | 2026-05-06 | "DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md" |
| Move 1 Gate 2 Fix - AWX EE Pod Service Account Mount.md | 2026-05-05 (assigned) | "Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md" |
| Move 1 Gate 2 — AWX Integration + Launch NMOS.md | 2026-05-04 (assigned) | "Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md" |

## Historical (25)

| File | date | note |
|---|---|---|
| DMF Agentic Harness Plan 2026-05-11.md | 2026-05-11 | harness mothballed 2026-06-04 |
| DMF Aliyun-123 Lifecycle-Configure Follow-Ups Plan 2026-05-17.md | 2026-05-17 | env long gone; follow-ups absorbed |
| DMF Convergence Next Steps Queue 2026-05-23.md | 2026-05-23 | queue superseded in spirit by TODOS.md |
| DMF Deployment Workflow and Manifest Plan.md | 2026-05-11 (import) | early design; evolved beyond (ADR-0035 era) |
| DMF Dynamic Catalog & Deployable-Workflow Mechanism — Discussion Notes 2026-06-05.md | 2026-06-05 | discussion notes; direction shelved for v0.1 |
| DMF Dynamic Media Facility & Dynamic Catalog — Initial Release Plan 2026-06-05.md | 2026-06-05 | SHELVED by architectural-commitments-v1; future direction only |
| DMF Elastic Media Nodes and Cloud Cost Controller Plan 2026-06-01.md | 2026-06-01 | frozen by v0.1 commitment |
| DMF Forgejo Repo Hosting and Migration Plan.md | 2026-05-11 (import) | Forgejo retired to archive 2026-06-10 |
| DMF g2r6-foa9 Configure-Verify Follow-Ups Plan 2026-05-22.md | 2026-05-22 | ⚠ env long gone; open items absorbed/stale |
| DMF Idempotent Upgrade-in-Place Mechanism — Findings and Plan 2026-06-01.md | 2026-06-01 | FROZEN (commitments); mitigations landed, root cause unproven |
| DMF Init Wizard Expansion Survey 2026-05-13.md | 2026-05-13 | point-in-time survey |
| DMF MXL On-Demand Media Function Cycle Plan 2026-06-01.md | 2026-06-01 | MXL spike paused by commitment gate |
| DMF MXL Single-Node Loopback Execution Plan 2026-05-29.md | 2026-05-29 | partial execution; paused; as-built in docs/sessions/ |
| DMF Media Workloads — NetBox-Driven Media Function Inventory Plan 2026-06-03.md | 2026-06-03 | ⚠ approved model but shelved with dynamic-catalog freeze |
| DMF OSS v0.1 WP-LAB g2r6-foa9 Reference Delta 2026-05-25.md | 2026-05-25 | reference env long gone |
| DMF OSS v0.1 WP1 AWS Provider Profile 2026-05-25.md | 2026-05-25 | multi-provider frozen for v0.1 |
| DMF OpenBao Policy-Writer Session Separation Plan 2026-05-13.md | 2026-05-13 | ⚠ proposed, never picked up |
| DMF RPi Flypack Appliance Implementation Plan 2026-05-13.md | 2026-05-13 | flypack profile deferred (scaffolds reserved) |
| DMF Staged Release Phase 2-3 Plan 2026-04-29.md | 2026-04-29 | Forgejo-era release framing |
| DMF Unseal Posture Tiered Framework Plan 2026-05-24.md | 2026-05-24 | ⚠ pre-ADR, postponed |
| DMF Vendor Multi-Tenancy Vision 2026-05-29.md | 2026-05-29 | vision / north star, not a build target |
| DMF Zot Cluster-Wide Pull-Through Cache Plan 2026-05-21.md | 2026-05-21 | idea, never committed |
| LLM-Restricted Git Pipeline — Dev-Testing-Production Isolation Plan 2026-05-09.md | 2026-05-09 | proposed, never picked up |
| Move 1 Gate 2 — Trials and Tribulations 2026-05-05.md | 2026-05-05 | war story; learnings absorbed into Move-1 learnings |
| dmf-multi-provider-resource-selection-future-direction-2026-05-08.md | 2026-05-08 | capture-only; long-term direction |

## ⚠ Uncertain calls for operator eyes (any bucket)

Rows marked ⚠ above. Biggest judgment calls: (1) Cluster-Internal pivot plan
kept **active** because CLAUDE.md still names it the active task and Lane C
closure is unconfirmed; (2) MXL M1.1 + MXL-Hello marked **executed** on
code-complete despite paused live verification; (3) OSS v0.1 WP0/WP1S/WP5 kept
**active** as the still-binding release contract alongside the 2026-06-06
commitment plan, while WP2/WP3/WP4 are **executed**; (4) Brand-Wide
Passkey-First Login marked **executed** from later live passkey evidence;
(5) Media Workloads inventory plan **historical** (shelved with the
dynamic-catalog freeze) despite "approved model" prose.
