---
status: executed
date: 2026-05-04
---
# DMF Forgejo Import + AWX Runbooks Plan

**Date:** 2026-05-04  
**Phase:** Experiment (ADR-0004)  
**Supersedes/extends:** [DMF Forgejo Repo Hosting and Migration Plan.md](./DMF%20Forgejo%20Repo%20Hosting%20and%20Migration%20Plan.md)

---

## Purpose

Two related goals:

1. **Import all dmfdeploy repos into the in-cluster Forgejo** so Forgejo becomes the canonical git host for the DMF platform (completing the migration outlined in the earlier Forgejo plan).

2. **Wire AWX to run the infra playbooks from Forgejo** so that new facilities can be deployed from the cluster itself, not just from the operator's laptop via `bin/run-playbook.sh`.

This document captures the current state, the target architecture, the phased plan, and the open decisions that need to be made before execution.

---

## Current State

### Forgejo (in-cluster)

| Item | Value |
|---|---|
| URL | `https://forgejo.<lan-host>` |
| Version | Forgejo 14.0.2 (Helm chart 16.0.2) |
| Namespace | `forgejo` |
| Storage | 10Gi Longhorn PVC (`forgejo-shared-storage`) |
| Admin user | `dev` (password: `changeme`, stored in `forgejo-admin` secret) |
| Service user | `forgejo-svc` (created by bootstrap role) |
| Existing repos | `awx-automation`, `app-configs` (both under `forgejo-svc`, private, empty/auto-init) |
| OAuth | Authentik OIDC configured, `ops-admin` group → admin |
| SSH | Port 22 mapped via ClusterIP, no external ingress for SSH |
| Public repos | None (API search returns empty) |

### Forgejo (local, `forgejo-<operator>`)

| Item | Value |
|---|---|
| Address | `<lan-ip>:22` (LAN, SSH) |
| SSH config | `~/.ssh/config` → Host `forgejo-<operator>`, key `~/.ssh/forgejo_<operator>` |
| Repos hosted | All 5 component repos under user `<operator>`: |
| | `<operator>/dmf-cms`, `<operator>/dmf-infra`, `<operator>/dmf-env`, `<operator>/dmf-central`, `<operator>/dmf-media` |
| Umbrella | `dmfdeploy` (umbrella docs/decisions/skills) — not a git remote yet |

### AWX (in-cluster)

| Item | Value |
|---|---|
| URL | `https://awx.<lan-host>` |
| Version | AWX 24.6.1 (operator 2.19.1) |
| Admin user | `awx-local-admin` (password in `awx-admin-password` secret) |
| Service user | `awx-svc` (personal token, created by `awx-integration` role) |
| Projects | 1 project: `awx-automation` synced from Forgejo `forgejo-svc/awx-automation` |
| Project content | `collections/requirements.yml`, `inventory/netbox.yml`, `playbooks/runbooks/eso-openbao-health-check.yml` |
| Inventories | `NetBox Inventory` (dynamic, from NetBox API) |
| Job Templates | `eso-openbao-health-check` only |
| SCM Credential | `forgejo-scm` (for git clone from Forgejo) |
| Execution EE | `quay.io/ansible/awx-ee:24.6.1` (default only) |
| SSO | SAML via Authentik, `LOGIN_REDIRECT_OVERRIDE` active |

### Current Playbook Execution Path

```
Operator laptop (macOS)
  └─ bin/run-playbook.sh
       ├─ bin/export-openbao-vars.sh   ← reads ~/.config/*, generates temp vars
       ├─ ansible-playbook -i dmf-env/inventories/hetzner-arm/
       └─ → SSH to k3s control node → kubectl/helm/ansible
```

This path depends on:
- Local config files on the operator's Mac (`~/.config/hcloud/`, `~/.config/cf/`, `~/.config/ts/`)
- `dmf-env` private repo (inventory + secrets)
- `bin/export-openbao-vars.sh` wrapper for secret injection
- SSH to the control node from the Mac

---

## Target Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  In-Cluster Forgejo (forgejo.<lan-host>)                 │
│                                                               │
│  [org or user]                                                │
│  ├── dmfdeploy         (umbrella: docs, decisions, skills)    │
│  ├── dmf-cms           (React + FastAPI operator console)     │
│  ├── dmf-infra     (Ansible playbooks + Helm roles)       │
│  ├── dmf-env       (private: inventory, secrets, tokens)  │
│  ├── dmf-central       (central services scaffold)            │
│  └── dmf-media     (media domain modules, deferred)       │
│                                                               │
│  forgejo-svc (service user)                                   │
│  └── awx-automation    (runbooks, AWX job template defs)      │
│  └── app-configs       (app-level configs)                    │
└──────────────────────┬───────────────────────────────────────┘
                       │ AWX SCM sync (token)
                       ▼
┌──────────────────────────────────────────────────────────────┐
│  AWX (awx.<lan-host>)                                    │
│                                                               │
│  Projects (SCM-synced from Forgejo):                          │
│  ├── dmf-infra-playbooks  ← dmf-infra/k3s-lab-bootstrap  │
│  ├── dmf-inventory        ← dmf-env/inventories/         │
│  └── awx-automation       ← forgejo-svc/awx-automation       │
│                                                               │
│  Inventories:                                                 │
│  ├── hetzner-arm (manual or git-synced from dmf-inventory)   │
│  └── NetBox Inventory (dynamic, from NetBox API)             │
│                                                               │
│  Credentials:                                                 │
│  ├── forgejo-scm      (existing: git clone token)            │
│  ├── k3s-ssh          (SSH key → k3s-admin@control-node)     │
│  ├── openbao-approle  (AppRole for secrets read)             │
│  └── hetzner-cloud    (API token, for layer-1 playbooks)     │
│                                                               │
│  Job Templates (one per infra playbook):                      │
│  ├── Deploy: Baseline      (200-baseline.yml)                │
│  ├── Deploy: k3s           (300-k3s.yml)                     │
│  ├── Deploy: Forgejo       (620-forgejo.yml)                 │
│  ├── Deploy: NetBox        (610-netbox.yml)                  │
│  ├── Deploy: AWX           (640-awx.yml)                     │
│  ├── Deploy: dmf-cms       (650-dmf-cms.yml)                 │
│  ├── Operate: Full         (lifecycle-operate.yml)           │
│  ├── Bootstrap: Forgejo    (692-forgejo-bootstrap.yml)       │
│  └── Health: OpenBao       (eso-openbao-health-check.yml)    │
└──────────────────────────────────────────────────────────────┘
```

---

## Phased Plan

### Phase 1: Import repos to Forgejo

**Goal:** All 6 repos (dmfdeploy umbrella + 5 component repos) exist in the in-cluster Forgejo with full history.

**Mechanism:** Mirror push from local `forgejo-<operator>` → in-cluster Forgejo.

```bash
# For each repo:
# 1. Create empty repo on in-cluster Forgejo via API
# 2. Clone from forgejo-<operator> (or use local copy)
# 3. Add in-cluster Forgejo as remote
# 4. git push --mirror
# 5. Verify branches, tags, history
```

**Sub-steps:**

| Step | Action | Details |
|---|---|---|
| 1.1 | Decide org/user layout | **OPEN QUESTION** — see below |
| 1.2 | Create org (if chosen) or ensure user exists | API call to Forgejo |
| 1.3 | Create target repos (empty, auto-init, private) | 6 repos + existing 2 under `forgejo-svc` |
| 1.4 | Mirror push each repo | From local `forgejo-<operator>` or laptop copies |
| 1.5 | Verify history integrity | `git log --oneline`, tag count, branch list |
| 1.6 | Update `origin` remotes on laptop | Point to in-cluster Forgejo |
| 1.7 | Update docs | This umbrella's CLAUDE.md, QWEN.md, AGENTS.md reference `forgejo-<operator>` |

**Acceptance criteria:**
- All 6 repos exist in Forgejo with full history
- `git clone` from Forgejo works (HTTPS + SSH if configured)
- Laptop remotes updated to point to Forgejo
- No split-brain (old `forgejo-<operator>` is archived or made read-only mirror)

---

### Phase 2: Extend Forgejo bootstrap role

**Goal:** The `forgejo-bootstrap` role auto-creates all repos (not just the 2 stub repos).

**Changes to `roles/stack/operator/forgejo-bootstrap/`:**

| Change | Detail |
|---|---|
| Extend `forgejo_repos` list | Add the 6 new repos to the defaults |
| Add org creation task | If org layout chosen, create `dmf-platform` org via API |
| Add repo ownership logic | Assign repos to org vs `forgejo-svc` user appropriately |
| Generate read-only SCM token | Separate token for AWX git clone (read-only, no write scope) |

**Existing behavior preserved:**
- Admin token creation (`forgejo-admin-automation`)
- Service user creation (`forgejo-svc`)
- Service token with `write:repository` for automation
- Token persistence to OpenBao or Ansible Vault

---

### Phase 3: AWX Project + Inventory setup

**Goal:** AWX can see and sync the playbooks and inventory from Forgejo.

**Projects to create in AWX:**

| Project | Forgejo Source | SCM URL | Branch |
|---|---|---|---|
| `dmf-infra-playbooks` | `dmf-infra` | `https://forgejo.<lan-host>/<org>/dmf-infra` | `main` |
| `dmf-inventory` | `dmf-env` | `https://forgejo.<lan-host>/<org>/dmf-env` | `main` |
| `awx-automation` | `forgejo-svc/awx-automation` | existing | `main` |

**Project update options:**
- `dmf-infra-playbooks`: Update on launch + periodic (every 1h)
- `dmf-inventory`: Update on launch + periodic (every 1h)
- `awx-automation`: Existing, keep as-is

**Inventory approach — two options:**

| Option | Mechanism | Pros | Cons |
|---|---|---|---|
| A: Manual inventory | Create `hetzner-arm` manually in AWX with 3 hosts + vars | Simple, no custom scripts | Drifts from git source of truth |
| B: Custom inventory script | Script in `dmf-inventory` project parses `dmf-env/inventories/hetzner-arm/hosts.ini` | Single source of truth | Requires script maintenance |
| C: SCM-synced inventory file | AWX Project syncs the repo, inventory source points to the `.ini`/`.yml` file | Best of both | May need custom EE for ansible inventory plugins |

**OPEN QUESTION** — see below.

---

### Phase 4: AWX Credentials

**Goal:** AWX has the credentials needed to run infra playbooks.

| Credential | Type | Source | Purpose |
|---|---|---|---|
| `forgejo-scm` | Source Control | Existing — `forgejo-svc-token-awx` | Git clone from Forgejo |
| `k3s-ssh` | Machine/SSH | **OPEN QUESTION** — see below | SSH to k3s control node for playbook execution |
| `openbao-approle` | HashiVault/Custom | OpenBao AppRole (role_id + secret_id) | Read secrets from OpenBao during playbooks |
| `hetzner-cloud` | Custom/Env Var | Hetzner API token (from OpenBao or operator Mac) | Layer-1 Tofu playbooks |

**Credential sourcing challenge:**

The current `bin/run-playbook.sh` reads secrets from:
- `~/.config/hcloud/cli.toml` — Hetzner Cloud API token
- `~/.config/cf/dns.txt` — Cloudflare DNS token
- `~/.config/ts/authkey.txt` — Tailscale auth key
- `bin/export-openbao-vars.sh` — self-seeded bootstrap secrets

These need to be available to AWX. Two approaches:

| Approach | Mechanism |
|---|---|
| A: Push to OpenBao | Store all tokens in OpenBao at `secret/apps/infra/credentials`, AWX reads via AppRole |
| B: AWX native credentials | Create AWX credentials manually, store values in OpenBao for backup |

**OPEN QUESTION** — see below.

---

### Phase 5: Execution Environment

**Goal:** AWX EE has all Ansible collections needed by the infra playbooks.

**Current EE:** `quay.io/ansible/awx-ee:24.6.1` (default)

**Collections needed (from scanning the playbooks):**

| Collection | Why |
|---|---|
| `kubernetes.core` | `k8s`, `k8s_info`, `helm`, `k8s_scale` modules |
| `community.general` | `git_config`, `ini_file`, `xfconf`, `proxmox` modules |
| `ansible.posix` | `lineinfile`, `copy`, `file`, `shell` modules |
| `netbox.netbox` | Already requested — NetBox inventory source |
| `community.hashi_vault` | HashiVault/OpenBao lookup plugin (may need custom build) |

**Action:** Update `awx-automation/collections/requirements.yml` and build a custom EE via `ansible-builder` if `community.hashi_vault` isn't available in the default EE.

**Alternative:** If `community.hashi_vault` is problematic, use `ansible.builtin.uri` to call OpenBao API directly from playbooks (more brittle but no custom EE needed).

---

### Phase 6: Job Templates + Surveys

**Goal:** One Job Template per infra playbook, with survey for environment selection.

**Job Templates to create:**

| JT Name | Playbook | Inventory | Survey |
|---|---|---|---|
| `Deploy: Baseline` | `playbooks/200-baseline.yml` | hetzner-arm | `environment` selector |
| `Deploy: k3s` | `playbooks/300-k3s.yml` | hetzner-arm | `environment` selector |
| `Deploy: Forgejo` | `playbooks/620-forgejo.yml` | hetzner-arm | — |
| `Deploy: NetBox` | `playbooks/610-netbox.yml` | hetzner-arm | — |
| `Deploy: AWX` | `playbooks/640-awx.yml` | hetzner-arm | — |
| `Deploy: dmf-cms` | `playbooks/650-dmf-cms.yml` | hetzner-arm | — |
| `Operate: Full` | `lifecycle-operate.yml` | hetzner-arm | — |
| `Bootstrap: Forgejo` | `playbooks/692-forgejo-bootstrap.yml` | hetzner-arm | — |
| `Health: OpenBao` | `playbooks/runbooks/eso-openbao-health-check.yml` | hetzner-arm | Existing |

**Survey for environment selection (replaces `bin/run-playbook.sh` env arg):**

```json
{
  "name": "Target Environment",
  "description": "Which environment to deploy to?",
  "spec": [
    {
      "question_name": "environment",
      "question_description": "Select the target environment",
      "required": true,
      "type": "multiplechoice",
      "choices": ["hetzner-arm", "flypack-01", "flypack-02"],
      "default": "hetzner-arm",
      "variable": "environment",
      "min": 0,
      "max": 1024
    }
  ]
}
```

**Extra vars mapping:**

The survey `environment` variable maps to the inventory path:
```yaml
inventory_path: "inventories/{{ environment }}/"
```

This replicates the `bin/run-playbook.sh` behavior of `inventories/<env>/`.

---

## Open Questions

These decisions are deferred pending user input. A freshly-booted agent should
ask these before starting execution.

### Q1: Forgejo org vs user layout

**Context:** Should repos live under a `dmf-platform` organization or under the existing `dev` admin user?

| Option | Pros | Cons |
|---|---|---|
| **Create `dmf-platform` org** | Clean separation, org-level permissions, supports multiple collaborators | More API calls, need to create org first |
| **Under `dev` user** | Simpler, fewer API calls | Mixes personal and platform repos, no org-level permissions |

**Recommendation:** Create `dmf-platform` org. It's the clean separation the platform architecture implies.

---

### Q2: dmf-env visibility

**Context:** `dmf-env` contains the private inventory, secrets references, and bootstrap vars. Should it be in the same Forgejo?

**Status:** DEFERRED — decision pending.

**Options under consideration:**

| Option | Detail |
|---|---|
| Same Forgejo, private repo | All code in one place, AWX accesses via token. Simpler but secrets-bearing repo is in-cluster |
| Separate — AWX gets read-only mirror of inventory only | Keep `dmf-env` out of the cluster entirely. AWX syncs only the inventory files, not the secrets/vars |

---

### Q3: AWX → k3s access method

**Context:** How does AWX execute playbooks against the k3s cluster?

**Status:** DEFERRED — decision pending.

**Options under consideration:**

| Option | Detail |
|---|---|
| **SSH to control node (recommended)** | AWX EE SSHes into `k3s-admin@<node-public-ip>`, runs `kubectl`/`helm`/`ansible-playbook` locally. Matches current `run-playbook.sh` model. Adheres to ADR-0006 (cluster is truth). |
| In-cluster kubeconfig | Mount `/etc/rancher/k3s/k3s.yaml` into AWX EE as a secret. More direct but breaks the "don't copy kubeconfig off node" rule from the cluster access skill. |
| Custom EE with k3s tools | Build a custom EE with `kubectl`, `helm`, `ansible`, SSH keys for all nodes. Most flexible but most complex to maintain. |

---

### Q4: Credential sourcing for AWX

**Context:** Where do Hetzner, Cloudflare, Tailscale, and other API tokens live for AWX to use?

**Status:** DEFERRED — decision pending.

**Options under consideration:**

| Option | Detail |
|---|---|
| Push to OpenBao | Store all tokens in OpenBao at `secret/apps/infra/credentials`. AWX reads via AppRole. Consistent with ADR-0007 (secrets in OpenBao). Requires setting up the AppRole credential type in AWX. |
| AWX native credentials | Create AWX credentials manually. Store copies in OpenBao for backup. Simpler but creates a second source of truth for secrets. |

---

### Q5: Inventory sync method

**Context:** How does AWX get the `hetzner-arm` inventory (hosts, groups, vars)?

**Status:** DEFERRED — decision pending.

**Options under consideration:**

| Option | Detail |
|---|---|
| Manual AWX inventory | Create hosts manually in AWX. Simple but drifts from git source of truth. |
| Custom inventory script | Script parses `hosts.ini` from `dmf-env`. Single source of truth, requires script maintenance. |
| SCM-synced inventory file | AWX Project syncs the repo, inventory source points to the `.ini` file directly. Best of both, may need custom EE for ansible inventory plugins. |

---

## Execution Order (once questions are resolved)

1. **Resolve Q1** → Create org/user layout in Forgejo
2. **Phase 1** → Import all repos to Forgejo
3. **Phase 2** → Extend forgejo-bootstrap role
4. **Resolve Q2–Q5** → Finalize AWX integration design
5. **Phase 3** → Create AWX Projects + Inventory
6. **Phase 4** → Create AWX Credentials
7. **Phase 5** → Build/update Execution Environment
8. **Phase 6** → Create Job Templates + Surveys
9. **Test** → Run `eso-openbao-health-check` from AWX, then a simple deploy JT
10. **Document** → Update this plan with resolved decisions, update ADRs if needed

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| dmf-env push exposes secrets | High | Repo is private, audit git history before push, rotate any exposed tokens |
| AWX EE missing a collection | Medium | Test EE with a dry-run playbook before creating JTs |
| OpenBao AppRole not working from AWX | Medium | Test AppRole auth from AWX EE before building JTs |
| Forgejo SSH not accessible from laptop | Low | Use HTTPS + PAT for push, SSH is optional |
| Inventory drift between git and AWX | Medium | Prefer SCM-synced inventory, or set periodic sync |
| Bootstrap playbook creates circular dependency | High | Forgejo bootstrap runs BEFORE AWX integration; order matters |

---

## References

- [DMF Forgejo Repo Hosting and Migration Plan.md](./DMF%20Forgejo%20Repo%20Hosting%20and%20Migration%20Plan.md) — original Forgejo migration plan
- [CLAUDE.md](../../CLAUDE.md) — umbrella boot ritual, secrets discipline
- [QWEN.md](../../QWEN.md) — Qwen-specific working rules
- [ADR-0006](../decisions/INDEX.md) — cluster is the truth, not local kubectl
- [ADR-0007](../decisions/INDEX.md) — secrets never in argv/env/tmp/AI transcripts
- [dmf-cluster-access skill](../../.claude/skills/dmf-cluster-access/SKILL.md) — cluster operations
- [Forgejo bootstrap role](../../dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo-bootstrap/tasks/main.yml)
