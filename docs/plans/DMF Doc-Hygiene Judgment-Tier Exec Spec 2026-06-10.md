---
status: executed
date: 2026-06-10
executed: 2026-06-10
---
# DMF Doc-Hygiene Judgment-Tier — Exec Spec for qwen — 2026-06-10

Companion to `DMF Public Repo Doc-Hygiene Cleanup Plan 2026-06-10.md`. This is the
**tight per-item spec** for the judgment-tier edits. The mechanical tier is already
done (separate pass).

## Hard rules
- **EDITS ONLY.** No `git add`/`commit`/`branch`/`push`. Leave everything unstaged.
- **Apply each OLD→NEW exactly.** OLD strings are verbatim from the current files.
  If an OLD string does not match, STOP that item and report BLOCKED (do not improvise).
- Base dir: `$DMFDEPLOY_UMBRELLA`
- **Do NOT** touch `.forgejo/` workflows or any MXL `feat/mxl` spike/handoff docs —
  those are handled separately. Do NOT touch any file not named below.

---

## Item 1 — `dmf-infra/README.md`: rewrite the "Two-Repo Model" block

OLD (verbatim):
```
## Two-Repo Model

This repo (`dmf-infra`) contains **only generic, environment-agnostic playbooks and roles**.
Site-specific configuration (real IPs, ingress settings, OpenBao metadata) lives in a separate
**private** repo:

```
github: lkirc/dmf-infra    ← public, generic (this repo)
forgejo/gitlab: dmf-env    ← private, site-specific inventory + OpenBao metadata
```
```

NEW:
```
## Part of the DMF Platform

`dmf-infra` is one of the public component repos of the **DMF Platform**
(`github.com/dmfdeploy/`). It contains **only generic, environment-agnostic
playbooks and roles** — never real IPs, hostnames, or secrets. Its companion
[`dmf-env`](https://github.com/dmfdeploy/dmf-env) holds the generic environment
provisioning + bootstrap tooling (wrapper scripts, OpenTofu roots/modules). Per
ADR-0035, **all per-environment state** (inventory, secrets bundle, SSH keys,
OpenTofu state) is **operator-local** under `~/.dmfdeploy/envs/<env>/` and is
never committed to any repo.
```

> Note: the `## Two-Repo Model` heading line and the github/forgejo code block are
> replaced; the following paragraph ("Playbooks are typically run through the
> environment wrapper…") and its ```bash``` block stay as-is.

---

## Item 2 — `dmf-infra/README.md`: Loki services-table row

OLD (verbatim):
```
| Loki | `<external_base_url>/loki` | — |
```
NEW:
```
| Loki | `<external_base_url>/loki` (log API — no web UI) | — |
```

---

## Item 3 — `dmf-infra/README.md`: fix the "Project Structure" tree

Replace the entire fenced code block under `## Project Structure` (the block that
begins with the line `k3s-lab-bootstrap/` and ends at its closing ```).

OLD (verbatim) — the block currently containing `├── vertical-control/` etc.
NEW:
```
k3s-lab-bootstrap/
├── ansible.cfg                      # Ansible configuration (no default inventory)
├── requirements.yml                 # Galaxy collection/role requirements
├── site.yml                         # Top-level entry — calls lifecycle-provision
├── lifecycle-provision.yml          # EBU Provision (full build)
├── lifecycle-configure.yml          # EBU Configure stage
├── lifecycle-operate.yml            # EBU Operate stage (verify, drills)
├── lifecycle-finalise.yml           # EBU Finalise & Review (teardown)
├── bootstrap-*.yml                  # From-scratch bootstrap chain (pre-/post-seed,
│                                    #   configure, verify) — driven by dmf-env / dmf-init
├── inventories/
│   └── example/                     # Template inventory; real envs are operator-local
├── playbooks/
│   ├── 200-baseline.yml … 219-*     # Layer 2 — Host Platform: baseline, harden, verify
│   ├── 300-k3s.yml … 339-*          # Layer 3 — Container Platform (k3s, ingress, TLS, storage, registry)
│   ├── 600-landing-page.yml … 699-* # Layer 6 — Application & UI (NetBox, Forgejo, AWX, dmf-cms, integration glue)
│   ├── vertical-security/           # OpenBao, Authentik, breakglass-verify
│   ├── vertical-monitoring/         # Prometheus, Loki, Grafana, Promtail, LibreNMS
│   ├── vertical-orchestration/      # ESO (External Secrets Operator)
│   ├── vertical-resilience/         # Resilience drills / recovery runbooks
│   └── lifecycle/                   # Stack verify + teardown bodies
├── roles/
│   ├── base/                        # Layers 2/3 + verticals (k3s, harden, ingress, longhorn, prometheus base, …)
│   ├── stack/operator/              # Layer 6 + verticals (NetBox, Forgejo, AWX, OpenBao, Authentik, …)
│   ├── stack/standalone/            # Layer 6 alternate (Flypack profile)
│   ├── modules/infra-monitoring/    # Vertical-monitoring extension (LibreNMS, …)
│   ├── modules/advanced/            # Vertical-orchestration extension (ArgoCD, federation)
│   └── common/                      # Utilities used across layers
├── charts/                          # Helm charts vendored/used by playbooks
├── ee/                              # AWX Execution Environment build (ansible-builder)
├── providers/                       # Per-provider helpers
├── tests/                           # Test scaffolding
└── docs/                            # Additional documentation
```

(Key changes: drop the non-existent `vertical-control/`; add real `vertical-resilience/`;
playbook range to `699`; add the `bootstrap-*` chain, `lifecycle-configure.yml`,
`charts/`, `ee/`, `providers/`, `tests/`.)

---

## Item 4 — `dmf-infra/CLAUDE.md`: ADR-0025 block → past tense (it landed)

OLD (verbatim):
```
> **2026-05-19 — incoming additions per ADR-0025:**
> A custom AWX Execution Environment build pipeline lands at
> `k3s-lab-bootstrap/ee/` (ansible-builder config) with `playbooks/630-zot-seed-platform.yml`
> building the EE image and pushing to cluster-internal Zot. The same EE
> image is consumed by the in-cluster ansible runner pod (foundation already
> at `roles/stack/operator/ansible-runner/`, role landed in `ff36ee8`) and
> by AWX-spawned media catalog launchers. See
> `dmfdeploy/docs/plans/DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md`
> and ADR-0025.
```
NEW:
```
> **ADR-0025 (landed 2026-05-19):**
> A custom AWX Execution Environment build pipeline lives at
> `k3s-lab-bootstrap/ee/` (ansible-builder config); `playbooks/630-zot-seed-platform.yml`
> builds the EE image and pushes it to cluster-internal Zot. The same EE
> image is consumed by the in-cluster ansible runner pod
> (`roles/stack/operator/ansible-runner/`) and by AWX-spawned media catalog
> launchers. See
> `dmfdeploy/docs/plans/DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md`
> and ADR-0025.
```

---

## Item 5 — Superseded banner on two pre-migration planning docs

Insert this banner **immediately after the first `# ` H1 title line** (a blank line
above and below it) in BOTH files:
- `dmf-infra/k3s-lab-bootstrap/docs/repo-strategy.md`
- `dmf-infra/k3s-lab-bootstrap/docs/dmf-platform-plan.md`

Banner text:
```
> **⚠️ HISTORICAL / SUPERSEDED.** Pre-migration planning document kept for
> provenance. The repository model and release/contribution process described
> here are **superseded by ADR-0041 (DMF Release and Contribution Model)** and
> the executed GitHub-canonical publish — the DMF Platform's public repos now
> live under `github.com/dmfdeploy/`. Do not treat the workflow below as current.
```

---

## Item 6 — Historical-numbering banner on stale `k3s-lab-bootstrap/docs/` docs

Insert this banner **immediately after the first `# ` H1 title line** (blank line
above and below) in EACH:
- `dmf-infra/k3s-lab-bootstrap/docs/forgejo.md`
- `dmf-infra/k3s-lab-bootstrap/docs/integration-sot.md`
- `dmf-infra/k3s-lab-bootstrap/docs/cluster-ready.md`
- `dmf-infra/k3s-lab-bootstrap/docs/awx-integration-plan.md`
- `dmf-infra/k3s-lab-bootstrap/docs/ci-cd-proposal.md`
- `dmf-infra/k3s-lab-bootstrap/docs/hardening.md`

Banner text:
```
> **⚠️ Numbering/commands may be historical.** Parts of this document reference an
> earlier playbook-numbering scheme (e.g. `31-forgejo`, `40-netbox-sot`, `05-harden`)
> and the pre-OpenBao `--vault-password-file` workflow. The current tree uses the
> `200/300/600` + `vertical-*` layout and the `dmf-env/bin/run-playbook.sh` OpenBao
> wrapper. Cross-check against the live `k3s-lab-bootstrap/playbooks/` tree before running.
```

---

## Item 7 — Neutralize hardcoded operator paths (MARKDOWN DOCS ONLY)

In the following **markdown files only**, replace operator-local paths:
- `~/repos/dmfdeploy/` → `$DMFDEPLOY_UMBRELLA/`
- `~/repos/dmf-env`, `~/repos/dmf-media`, `~/repos/dmf-cms` (bare, not under dmfdeploy/)
  → `$DMFDEPLOY_UMBRELLA/dmf-env`, `$DMFDEPLOY_UMBRELLA/dmf-media`, `$DMFDEPLOY_UMBRELLA/dmf-cms`

Files:
- `dmf-infra/docs/SECURITY-REMEDIATION-GUIDE.md`
- `dmf-infra/roles/README.md`
- `dmf-infra/ee/README.md`
- `dmf-cms/QWEN.md`
- `dmf-cms/docs/DEVELOPMENT-AND-BUILD-RULES.md`
- `dmf-cms/docs/IMPLEMENTATION-STRATEGY.md`

> **Do NOT** edit any `.sh`, `.yaml`, `.yml`, or `Dockerfile` for paths — those may be
> functional and are handled separately by Claude. Markdown only.

---

## Reporting
When done, reply to claude (`%3`) via agent-bridge with `DONE` (or `BLOCKED <item> <why>`)
and this proof (run from `$DMFDEPLOY_UMBRELLA`):
- `grep -n "Two-Repo Model\|lkirc" dmf-infra/README.md` → expect 0
- `grep -n "vertical-control\|693-\*" dmf-infra/README.md` → expect 0; `grep -n "vertical-resilience\|699-\*" dmf-infra/README.md` → present
- `grep -n "incoming additions per ADR-0025" dmf-infra/CLAUDE.md` → expect 0
- `grep -rln "HISTORICAL / SUPERSEDED" dmf-infra/k3s-lab-bootstrap/docs/` → 2 files; `grep -rln "Numbering/commands may be historical" dmf-infra/k3s-lab-bootstrap/docs/` → 6 files
- `grep -rn "~/repos/" dmf-infra/docs/SECURITY-REMEDIATION-GUIDE.md dmf-infra/roles/README.md dmf-infra/ee/README.md dmf-cms/QWEN.md dmf-cms/docs/DEVELOPMENT-AND-BUILD-RULES.md dmf-cms/docs/IMPLEMENTATION-STRATEGY.md` → expect 0
- `git -C dmf-infra status --short` and `git -C dmf-cms status --short` → modified, NOT committed
