---
status: executed
date: 2026-06-10
executed: 2026-06-10
---

# WP9 — TODOS.md → GitHub Issues Triage Table (2026-06)

**Status:** Active — operator-review gate before WP10 (issue creation). Flip to
`executed` once WP10 has created the issues and WP11 retires TODOS.md.

Target repo for all issues: **`dmfdeploy/dmfdeploy`** (umbrella; cross-repo
backlog lives here, component label routes it). Every issue body must be
**placeholder-clean** (no LAN hostnames, IPs, operator identity, live env ids)
and must link back to its source doc by repo-relative path. Conventions:
labels from the WP8 set; milestones `v0.1-polish` / `v0.2` / (none = icebox).

## A. Keep as issue (24 issues, consolidated from ~45 TODOS items)

| # | Title | Labels | Milestone | Folds in / source |
|---|---|---|---|---|
| 1 | Umbrella public entrance + GitHub working model (WP tracker) | component:cross-repo, workstream:entrance | v0.1-polish | TODOS §Umbrella entrance WP1–17; body links the 2026-06-10 plan; becomes its `tracking_issue` |
| 2 | dmf-init installer UI redesign (pass 1 PR + pass 2) | component:dmf-init | v0.1-polish | Folds "two-click start is non-obvious"; links the 2026-06-10 redesign plan; becomes its `tracking_issue` |
| 3 | Dynamic NetBox-driven monitoring — remaining: launcher stamping + grafana/loki probe tuning | component:cross-repo, workstream:monitoring | v0.1-polish | TODOS §NetBox monitoring (2 open items); links ADR-0038 + 2026-06-04 plan; becomes its `tracking_issue` |
| 4 | Release automation (E2) — tag-driven publish workflows | component:cross-repo, workstream:release | v0.2 | STATUS "E2 NOT started"; umbrella B2 publish is carried by issue 1, not here |
| 5 | dmf-init GitHub Actions build workflows | component:dmf-init, workstream:release | v0.2 | Links the 2026-06-10 exec spec (draft); becomes its `tracking_issue` |
| 6 | Authentik cross-cluster federation with passkey enrollment (FROZEN thesis-killer) | component:dmf-central, workstream:identity-secrets | v0.2 | TODOS §Strategic moves; frozen per architectural-commitments-v1 |
| 7 | EBU V2.0 taxonomy hard case — two-function fabric (PAUSED thesis-killer) | component:cross-repo, workstream:catalog | v0.2 | TODOS §Strategic moves; carried by paused MXL spike |
| 8 | Hetzner leakage audit cleanup (items 1–10) | component:cross-repo, workstream:hardening | v0.2 | TODOS §Infrastructure debts |
| 9 | OpenBao credential hygiene: AppRole secret_id TTL rotation + root-token disposal | component:cross-repo, workstream:identity-secrets | v0.2 | TODOS §Infrastructure debts (2 items folded) |
| 10 | OpenBao lifecycle (trigger-gated): HA raft migration + re-key procedure + DR drill | component:cross-repo, workstream:identity-secrets | v0.2 | TODOS §OpenBao architecture (3 items folded; ADR-0011 revisit triggers in body) |
| 11 | init-wizard cloud-lane gaps (manifest renderer stub, per-env TF scaffold, group_vars 2/6, tfvars wrapper, stale .sops rules, provider-aware defaults) | component:dmf-env, workstream:hardening | v0.2 | TODOS §init-wizard follow-ups (6 items folded into one) |
| 12 | Cosign image signing for dmf-cms releases | component:dmf-cms, workstream:release | v0.2 | TODOS §dmf-cms |
| 13 | Bootstrap-user privilege residue: in-cluster Forgejo OAuth auto-create + cross-app admin audit | component:cross-repo, workstream:identity-secrets | v0.2 | TODOS §dmf-cms (2 items folded; 2026-05-03 handoff) |
| 14 | Verify add_user_to_group crashloop resolved on next live env (likely closed in v0.9.2) | component:dmf-cms, workstream:hygiene | v0.1-polish | TODOS §dmf-cms [verify] item |
| 15 | MXL catalog entries + Flows view absent from Console (compound; needs catalog data + CMS view) | component:cross-repo, workstream:catalog | v0.2 | TODOS §dmf-init #11 + #9-follow-up folded |
| 16 | Sandbox teardown leaves node dirty — add decommission step or document re-image | component:dmf-init, workstream:hardening | v0.2 | TODOS §dmf-init #12 (pairs with SSH-key fix) |
| 17 | Duplicate orphan envs on Create form re-submit (no idempotency) | component:dmf-init | v0.1-polish | TODOS §dmf-init |
| 18 | Audit remove-env cloud-lane steps are true no-ops off-cloud | component:dmf-init, workstream:hygiene | v0.2 | TODOS §dmf-init |
| 19 | Pre-push hygiene hooks missing in all repos — add or relax the gate | component:cross-repo, workstream:release | v0.1-polish | TODOS §Release (reframed from "install agentic hooks" — harness mothballed; STATUS E1 note) |
| 20 | Rotate Forgejo dev credentials (LAN mirror remains live) | component:cross-repo, workstream:compliance | v0.1-polish | TODOS §Release; body placeholder-clean, no host details |
| 21 | Tier A compliance finish (A.1/A.3/A.4/A.5/A.6/A.8/A.9) | component:cross-repo, workstream:compliance | v0.2 | TODOS §Release; links 2026-05-11 readiness plan (draft) |
| 22 | Per-entry catalog lifecycle lock — deploy/finalise cross-action race | component:dmf-cms, workstream:catalog | v0.1-polish | TODOS §Function catalog (observed race, needs CMS image build) |
| 23 | ADR-0034 permanent internal collection source (offline/air-gap catalog path) | component:cross-repo, workstream:catalog | v0.2 | TODOS §Function catalog; links 2026-05-29 plan (draft) |
| 24 | Hygiene sweep: dmf-infra `.qwen/`, dmf-env `hosts.ini` dirty state, dmf-cms mockup reference, stale README paragraphs | component:cross-repo, workstream:hygiene | (none) | TODOS §Hygiene candidates (4 items folded) |

## B. Drop as done / overtaken by events

| TODOS item | Why |
|---|---|
| Moves 1/2/3 (✓ rows) | closed in TODOS already |
| Longhorn BackupTarget | landed (dmf-infra `c62b923`/`61c9895`) |
| dmf-cms `.forgejo/workflows/ci.yml` placeholder | OBE — GitHub per-stack `ci.yml` landed via Workstream E1 (2026-06-09) |
| backup raw 500 on bad rclone remote | OBE — dual-remote rclone model removed 2026-06-08 |
| dmf-init CONTAINER productization section ([x] ×4) | closed 2026-06-08 |
| sslip.io + CA-trust UX + ADR-0040 section ([x] ×3) | closed 2026-06-08 |
| GitHub org + repo setup | done — org + 8 public repos + umbrella created 2026-06-10 |
| Dry-run sync-to-github.sh | OBE — sync-to-github.sh retired (export-scan.sh replaced it) |
| NetBox monitoring [x] rows (ESO validation, born-inventory id-loss, GHCR publish, 4-mint sentinels) | closed 2026-06-04/05 |
| Function catalog [x] rows (Pieces 1/3/7/8, lifecycle-configure obviation) | Move 1 closed 2026-06-04 |

## C. Not migrated (deliberate — documented elsewhere instead)

| TODOS section | Disposition |
|---|---|
| Scaffold roles awaiting implementation (dmf-central / dmf-infra / dmf-media reservations) | NOT issues — intentional reservations per strategic review; carried by docs/OPEN-QUESTIONS.md (WP14) + the FREEZE list |
| Function-catalog v2/v3 deferred rows | frozen scope; OPEN-QUESTIONS (WP14) |
| Meta-harness parking lot (options A–G) | parking lot, not work; partially OBE — WP4/WP6 check-docs gate implements the spirit of option B; remains in TODOS history |

Project #1's 5 existing draft items are converted to real issues in WP10 and
deduped against table A at creation time (if a draft item matches a row above,
the row's issue absorbs it).
