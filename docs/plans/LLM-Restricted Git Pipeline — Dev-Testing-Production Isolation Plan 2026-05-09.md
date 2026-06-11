---
status: historical
date: 2026-05-09
---
# LLM-Restricted Git Pipeline — Dev/Testing/Production Isolation

**Status:** Proposed
**Date:** 2026-05-09
**Scope:** dmf-infra, dmf-cms, dmf-env, dmf-media, dmf-runbooks (umbrella) + Forgejo + AWX
**Trigger:** Architecture requirement — LLM-generated code must not reach production without human review, and LLM agents must have no credentials capable of touching production systems

---

## Goal

**Phase 1 (now, experiment phase):** Implement Option A — protected branches + LLM-scoped Forgejo tokens on existing repos. This gives branch-level isolation (LLM agents can only push to `dev` branch) and credential discipline (agents are not given production credentials in their session). Addresses both primary threats: (a) code quality gate and (b) credential capability.

**Phase 2 (post-experiment, deferred):** Migrate to Option B — separate repos per environment (`-dev`, `-testing`, production) with physical credential isolation and promotion workflows. This is the stronger pattern, deferred until experiment phase concludes and governance overhead is justified.

This plan covers both phases. Phase 1 is the immediate implementation target. Phase 2 is documented for future execution.

---

## Concepts

### What "restricted to dev" means

An LLM agent is "restricted to dev" when, **within the git-path and credential scope of its assigned session**, it **cannot** under any normal or accidental misconfiguration:

- Push commits to `-testing` repos or `main` branches of any repo
- Create or merge PRs/MRs targeting `main` or `testing` branches
- Read or write secrets, deploy keys, or credentials scoped to testing or production
- Trigger CI/CD pipelines that deploy to testing or production environments
- Forgejo API calls that modify protected branches or production repo state

**Scope note:** LLM agents (Codex, Claude Code, Qwen) run on the operator's Mac with full shell access, kubectl, SSH keys, and `bin/run-playbook.sh`. This plan addresses **git-path control** (Forgejo token scope) and **credential discipline** (the agent is not given production credentials in its session). It does NOT address the broader vector of an agent running arbitrary shell commands on the operator's machine. That vector requires a sandbox or trust model, which is out of scope for this plan (see Open Decision #2).

### Why branches alone are insufficient

Using dev/testing/production branches within a single repo is the weakest isolation pattern because:

- A single CI token or deploy key that can read the repo can typically read all branches
- Repo-level secrets (Forgejo CI variables, Forgejo Actions secrets) are visible to any workflow in that repo
- An LLM agent with `write:repository` scope can force-push, delete branches, or modify branch protection if the token has admin rights
- CI runners executing dev workflows may have access to repo-wide secrets

### Why repo-per-environment is preferred

Three separate repos per component (e.g. `dmf-infra-dev`, `dmf-infra-testing`, `dmf-infra-production`) provide:

- **Credential isolation**: Each repo has its own set of CI variables, deploy keys, and tokens
- **Token scoping**: LLM agents get tokens scoped only to `-dev` repos
- **CI runner isolation**: Each repo can be bound to different runner pools
- **Audit clarity**: It's immediately obvious which environment a change targets
- **Promotion discipline**: Code moves between repos via explicit artifact promotion (tagged release, signed tarball, or reviewed merge into the next repo), not automatic branch merging

### Artifact promotion

The mechanism by which code moves from dev → testing → production:

1. **dev → testing**: Human-reviewed PR/MR. A maintainer reviews the dev work, then merges or copies the validated state into the testing repo. This can be automated as "when PR is approved + merged, push to testing repo" but the human approval is the gate.

2. **testing → production**: Immutable artifact promotion. After testing validates, a signed release manifest, tagged image, or reviewed Helm values file is promoted to production. Production never receives raw LLM-generated code — only reviewed, tested artifacts.

### Current DMF platform architecture (what exists today)

| Component | Where it lives | Role |
|-----------|---------------|------|
| **Umbrella** (dmfdeploy) | `<umbrella-repo>/` | Docs, ADRs, skills, status |
| **dmf-infra** | dmf-infra/ | Ansible playbooks + roles (Layers 1–3 + verticals) |
| **dmf-cms** | dmf-cms/ | React 18 + FastAPI operator console (Layer 6) |
| **dmf-env** | dmf-env/ | Per-env inventory + Layer 1 Terraform + Ansible |
| **dmf-central** | dmf-central/ | Central services scaffold |
| **dmf-media** | dmf-media/ | Layers 4–5, NMOS / EBU LIST |
| **dmf-runbooks** | dmf-runbooks/ | Thin AWX launcher playbooks |
| **Forgejo** | In-cluster k3s, `forgejo.<lan-host>` | Git hosting for AWX SCM-sync |
| **AWX** | In-cluster k3s, `awx.<lan-host>` | Ansible automation platform |
| **OpenBao** | In-cluster k3s | Secrets storage |

Forgejo currently hosts repos under the `forgejo-svc` service account: `awx-automation`, `app-configs`, `dmf-media`, `dmf-infra`, `dmf-runbooks`. Mirror-push to GitHub was removed 2026-05-07.

### Forgejo capabilities relevant to this plan

Forgejo (v3.x, Forgejo Helm chart v16.0.2) supports:

- **Branch protection rules** — require reviews, restrict who can push, prevent force-pushes, require status checks
- **Teams** — group users with per-repo read/write/admin permissions
- **Deploy keys** — read-only or read-write SSH keys per repo
- **Fine-grained access tokens** — scope to specific repos and permissions (read:user, read:repository, write:repository, etc.)
- **Forgejo Actions (Gitea Actions)** — built-in CI/CD runner (Act-compatible workflows) — currently **not enabled** (`.forgejo/workflows/ci.yml` exists but no runner is configured)
- **Webhooks** — notify external systems on push/PR events
- **Environments** — require approval before deploying to protected environments (Forgejo feature, requires Actions runner)

### AWX capabilities relevant to this plan

- **Projects** — SCM-sync from git URLs (currently syncing from Forgejo repos per ADR-0014)
- **Credentials** — scoped per project or job template (SSH, Vault, SCM, cloud)
- **Job Templates** — reference playbooks from projects, with credential bindings
- **Organizations/Teams** — isolate users and credentials (not currently used)
- **Workflow Job Templates** — chain multiple job templates with approval gates
- **Execution Environments** — containerized runner images (EEs) that can be scoped per environment

---

## Actions

### Phase 1: Protected branches + LLM token scoping (NOW — experiment phase)

This is the immediate implementation scope. Option A: protected branches on existing repos, no new repos created.

#### 1.1 Branch protection on `main` for all repos

For each Forgejo repo under `forgejo-svc` (`dmf-infra`, `dmf-cms`, `dmf-media`, `dmf-runbooks`), configure branch protection on `main`:

- **No direct push** — all changes must go through PR
- **Require at least 1 approval** — from `ops-admin` team (the operator)
- **Block on rejected reviews** — cannot merge if review is rejected
- **No force-push** — prevent history rewrite
- **Whitelist**: only `ops-admin` team can push/merge to `main`

This ensures the LLM agent (or anyone without ops-admin team membership) cannot push directly to `main`.

**Implementation via Forgejo API:**
```bash
# For each repo:
curl -X POST "https://forgejo.<lan-host>/api/v1/repos/forgejo-svc/<repo>/branch_protection_rules" \
  -H "Authorization: token $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "branch_name": "main",
    "enable_push": false,
    "enable_whitelist": true,
    "whitelist_user_teams": ["ops-admin"],
    "require_pull_request": true,
    "require_approvals": true,
    "num_required_approvals": 1,
    "dismiss_stale_approvals": true,
    "block_on_rejected_reviews": true,
    "block_official_reviews": false
  }'
```

**Files to modify:**
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo-bootstrap/tasks/main.yml` — add branch protection task after repo creation loop
- Or run as a one-shot script from operator's workstation (acceptable for experiment phase)

#### 1.2 Create `dev` branch on all repos

If not already present, create a `dev` branch on each repo:

```bash
git checkout -b dev
git push origin dev
```

The `dev` branch has NO branch protection — LLM agents can push freely here.

#### 1.3 Create LLM-restricted Forgejo user

Create a new Forgejo user `llm-agent-svc` with:

- Token scoped to: `read:repository`, `write:repository` — on all repos
- **No admin rights**
- **No membership in `ops-admin` team** (so cannot bypass branch protection)
- Token persisted to OpenBao at `secret/apps/llm-agent/forgejo`

Since Forgejo tokens are repo-scoped (not branch-scoped), the `llm-agent-svc` user CAN technically access all repos via API. The **enforcement** is that:
- It cannot push to `main` (branch protection blocks it regardless of write permission)
- It cannot merge PRs to `main` (requires ops-admin team approval)
- It CAN push to `dev` branch freely

This is the core of Option A: the token has broad repo access, but branch protection is the enforcement boundary.

**Implementation:**
```bash
# Create user via admin API
curl -X POST "https://forgejo.<lan-host>/api/v1/admin/users" \
  -H "Authorization: token $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "llm-agent-svc",
    "email": "llm-agent-svc@example.com",
    "password": "<generated-password>",
    "must_change_password": false,
    "send_notify": false,
    "active": true
  }'

# Create token for user
curl -X POST "https://forgejo.<lan-host>/api/v1/users/llm-agent-svc/tokens" \
  -u "llm-agent-svc:<password>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "llm-agent-svc-token-coding",
    "scopes": ["read:repository", "write:repository"]
  }'
```

**Files to modify:**
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo-bootstrap/defaults/main.yml` — add `llm_agent_svc_user`, `llm_agent_svc_token`, token scopes
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo-bootstrap/tasks/main.yml` — add user creation and token generation
- OpenBao persistence for `llm-agent-svc` token at `secret/apps/llm-agent/forgejo`

#### 1.4 Token handoff to LLM agents (gitcredential helper)

The operator retrieves the `llm-agent-svc` token from OpenBao and stores it in the macOS keychain via git credential helper:

```bash
# Operator retrieves token from OpenBao
bao kv get -field=forgejo_svc_token secret/apps/llm-agent/forgejo

# Store in keychain via git credential helper
printf "protocol=https\nhost=forgejo.<lan-host>\nusername=llm-agent-svc\npassword=<TOKEN>\n" | git credential-osxkeychain store

# Verify
git credential-osxkeychain get <<< "protocol=https\nhost=forgejo.<lan-host>"
```

When the LLM agent runs `git clone https://forgejo.<lan-host>/forgejo-svc/dmf-infra.git`, the git credential helper automatically supplies the `llm-agent-svc` token. The agent never sees the token directly in chat (ADR-0007 compliant).

**Important:** The agent's working directory is the operator's local repo clone, which has the credential helper configured. The agent uses `git` commands normally — the credential is injected transparently.

#### 1.5 LLM agent session rules

When an LLM agent is given a task:

- **Can:** Push to `dev` branch, create PRs from `dev` to `main`, run `--check` dry runs
- **Cannot:** Push to `main`, merge PRs to `main`, access production credentials
- **Credential discipline:** The agent's session does NOT include:
  - SSH keys to k3s nodes
  - kubeconfig for the hetzner-arm cluster
  - AWX API credentials
  - OpenBao connection details
  - Cloud CLI credentials (alicloud, hcloud)
- **What it DOES get:** The gitcredential helper entry for `llm-agent-svc` (inherited from the operator's git config)

This gives the agent git-level access via its Forgejo token while withholding all infrastructure-level credentials.

#### 1.6 Human review and merge workflow

When the LLM agent completes work:

1. Agent pushes to `dev` branch on the repo
2. Agent creates PR from `dev` → `main` (via Forgejo API or operator assists)
3. Operator reviews the PR in Forgejo UI
4. Operator approves and merges (self-approve — one-operator setup)
5. Merged code is now on `main` and will be picked up by AWX SCM-sync

**Note:** This replaces the multi-tier promotion workflow for now. Code goes `dev` → `main` via operator review. No testing tier exists yet. When aliyun-frankfurt comes online as a second region, this can evolve into a proper dev → testing → production pipeline.

### Phase 1 verification

```bash
# 1. LLM agent token cannot push to main
cd /tmp/test-dmf-infra
git clone https://<forgejo-host>/forgejo-svc/dmf-infra.git
# (auth via gitcredential helper — token not shown in URL)
cd dmf-infra
echo "test" >> test.txt
git add . && git commit -m "test"
git push origin HEAD:main
# Expected: 403 Forbidden or "branch is protected" error

# 2. LLM agent token CAN push to dev
git push origin HEAD:dev
# Expected: succeeds

# 3. Branch protection rules are configured
curl -H "Authorization: token $ADMIN_TOKEN" \
  https://forgejo.<lan-host>/api/v1/repos/forgejo-svc/dmf-infra/branch_protection_rules
# Expected: rules exist for main branch

# 4. llm-agent-svc is NOT in ops-admin team
curl -H "Authorization: token $ADMIN_TOKEN" \
  https://forgejo.<lan-host>/api/v1/users/llm-agent-svc/teams
# Expected: ops-admin team not in list

# 5. Token stored in OpenBao
bao kv get secret/apps/llm-agent/forgejo
# Expected: forgejo_svc_token field present
```

---

### Phase 2: Repo-per-environment + promotion workflows (POST-EXPERIMENT — deferred)

**Trigger:** Experiment phase concludes (thesis-killers resolved), operator is ready for production-grade isolation.

**Scope:** Migrate from Option A (protected branches) to Option B (separate repos per environment) with full credential isolation and promotion workflows.

This phase is documented below for future reference but is NOT in the immediate implementation scope.

#### 2.1 Create dev/testing repos in Forgejo

For each component repo:

```
forgejo-svc/
├── dmf-infra-dev          ← LLM can push here (via llm-agent-svc)
├── dmf-infra-testing      ← LLM cannot touch
├── dmf-cms-dev            ← LLM can push here
├── dmf-cms-testing        ← LLM cannot touch
├── dmf-media-dev          ← LLM can push here
├── dmf-media-testing      ← LLM cannot touch
├── dmf-runbooks-dev       ← LLM can push here
├── dmf-runbooks-testing   ← LLM cannot touch
├── dmf-infra              ← existing (production-equivalent)
├── dmf-cms                ← existing (production-equivalent)
├── dmf-media              ← existing (production-equivalent)
└── dmf-runbooks           ← existing (production-equivalent)
```

**Note:** dmf-env is NOT split. LLM agents lack credentials to it entirely — it's not part of their workflow.

Branch protection on all non-dev repos: `main` requires PR + ops-admin approval.

`llm-agent-svc` token is scoped to `-dev` repos only (via Forgejo team membership or per-repo token scoping).

#### 2.2 AWX project restructuring

Current AWX projects (ADR-0014) expand to include dev/testing variants:

```
AWX projects:
├── dmf-runbooks-dev      → SCM-sync from forgejo-svc/dmf-runbooks-dev
├── dmf-runbooks          → SCM-sync from forgejo-svc/dmf-runbooks (prod, existing)
├── dmf-media-dev         → SCM-sync from forgejo-svc/dmf-media-dev
├── dmf-media             → SCM-sync from forgejo-svc/dmf-media (prod, existing)
├── dmf-infra-dev         → SCM-sync from forgejo-svc/dmf-infra-dev
├── dmf-infra             → SCM-sync from forgejo-svc/dmf-infra (prod, existing)
└── dmf-cms-dev           → SCM-sync from forgejo-svc/dmf-cms-dev
└── dmf-cms               → SCM-sync from forgejo-svc/dmf-cms (prod, existing)
```

Dev job templates deploy to dev namespace; production job templates deploy to production. Credentials are isolated per environment.

#### 2.3 OpenBao secrets (Option B: least-invasive)

Add `dev-*` suffix paths within the existing `secret/apps/<app>/<tier>` scheme:

```
secret/apps/forgejo/dev-runtime     → Dev Forgejo tokens (llm-agent-svc)
secret/apps/forgejo/runtime         → Production Forgejo tokens (existing, unchanged)
secret/apps/awx/dev-runtime         → Dev AWX credentials
secret/apps/awx/runtime             → Production AWX credentials (existing, unchanged)
```

Create `dmf-llm-agent-dev-approle` policy that can read `secret/apps/*/dev-*` only.

#### 2.4 Promotion workflow (tag-based)

1. LLM agent works in `-dev` repo, pushes to `dev` branch
2. Operator reviews, creates tag: `git tag testing-$(date +%Y%m%d-%H%M%S)`
3. Tag is pushed to `-testing` repo via AWX workflow or operator manual step
4. Testing environment validates
5. For production: same pattern, tag-based promotion from testing to production

Each promotion step has a single self-approval gate (one-operator setup).

#### 2.5 Forgejo Actions runners (deferred, net-new)

If CI/CD runners are needed beyond AWX, Forgejo Actions runners would be deployed as a separate effort (new role, new namespaces, new network policies). Currently deferred.



## References

### ChatGPT conversation (one input among several)
- Shared conversation: https://chatgpt.com/share/69fee8dd-04f4-83eb-822b-936b09bc5fd1
- Topic: Git pipeline with LLM restrictions — dev/testing/production isolation
- Framing only — not authoritative. Real requirement from operator's architecture thinking.

### Existing ADRs
- **ADR-0002** — Two-repo model (generic playbooks + private inventory)
- **ADR-0004** — Experiment phase, not hardening — Phase 1 scope is lightweight; Phase 2 deferred
- **ADR-0007** — Secrets never in argv/env/tmp/AI transcripts — token handoff via gitcredential helper
- **ADR-0008** — OpenBao + ESO + AppRole — basis for dev-* path scoping in Phase 2
- **ADR-0010** — `bin/run-playbook.sh` is the only sanctioned ansible entry point
- **ADR-0012** — Configure distinct from Provision — promotion targets Configure, not Provision
- **ADR-0014** — AWX project layout (hybrid launchers + mirrored repos) — extended in Phase 2
- **ADR-0016** — AWX↔control-node SSH via cloud-init + OpenBao
- **ADR-0018** — Self-managed k3s on every cloud — affects runner deployment options

### Code paths
| Path | Purpose |
|------|---------|
| `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo-bootstrap/` | Forgejo repo/user/token/branch-protection creation |
| `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/` | AWX project/JT/credential creation (Phase 2) |
| `dmf-infra/k3s-lab-bootstrap/playbooks/692-forgejo-bootstrap.yml` | Forgejo bootstrap playbook |
| `dmf-infra/k3s-lab-bootstrap/playbooks/693-awx-integration.yml` | AWX integration playbook |
| `dmf-env/inventories/*/group_vars/all/openbao_secrets.yml` | OpenBao secret path mappings per env |
| `dmf-env/bin/run-playbook.sh` | Sanctioned playbook entry point |
| `dmf-cms/.forgejo/workflows/ci.yml` | Forgejo CI placeholder for dmf-cms |
| `dmf-env/.forgejo/workflows/ci.yml` | Forgejo CI for dmf-env |

---

## Relevant context

### Constraints

1. **Forgejo version**: Helm chart v16.0.2, Forgejo v3.x. Verify branch protection API exists before assuming features.

2. **No Forgejo Actions runners deployed**: `.forgejo/workflows/ci.yml` files are placeholders. AWX is the CI execution engine for now.

3. **No production exists yet**: hetzner-arm is the live experiment cluster (ADR-0004). aliyun-frankfurt is geo-redundancy, not testing. Phase 1 uses `main` as the "live" branch, no testing tier yet.

4. **LLM agents have shell/CLI on operator's Mac**: Codex, Claude Code, Qwen run locally with full Bash, kubectl, SSH, and `bin/run-playbook.sh`. Isolation is via gitcredential helper token scope + credential discipline, not sandbox.

5. **OpenBao is the secrets authority**: All new credentials flow through OpenBao.

6. **All repos are on Forgejo**: remotes are `forgejo:ops/<repo>.git`. GitHub mirror-push removed 2026-05-07.

7. **One-operator setup**: The user is the sole operator. Approval gates are ceremonial (self-approve).

8. **dmf-env is NOT split**: LLM agents lack credentials to it entirely.

### Gotchas

- **Branch protection API**: Forgejo's branch protection API may differ from Gitea's — verify with `GET /repos/{owner}/{repo}/branch_protection_rules` on the running instance.
- **Forgejo `ops-admin` team**: May need to be created if it doesn't exist yet. Check `forgejo-svc` user teams before configuring whitelist.
- **AWX SCM-sync cache**: After any repo restructuring (Phase 2), AWX projects need manual "Sync" to pick up new URLs.
- **gitcredential helper scope**: The token is stored for `forgejo.<lan-host>`. If the operator later switches to SSH-based access, the credential helper entry becomes stale.

### Repo layout

```
dmfdeploy/                          # Umbrella (docs, ADRs, scripts)
├── dmf-cms/                        # React + FastAPI (Forgejo, remote: forgejo:ops/dmf-cms.git)
├── dmf-infra/                      # Ansible playbooks + roles
├── dmf-env/                        # Private inventory + Tofu/AppRole configs (NOT split — LLM agents lack credentials)
├── dmf-central/                    # Central services scaffold
├── dmf-media/                      # NMOS / media roles
├── dmf-runbooks/                   # AWX launcher playbooks
├── docs/
│   ├── decisions/                  # ADRs (0001-0018)
│   └── plans/                      # Planning docs (this file)
└── bin/                            # run-playbook.sh, generate-status.sh, etc.
```

---

## Acceptance criteria

### Phase 1 (immediate — do before marking this plan done)

1. **Branch protection on `main` for all 4 repos**: `dmf-infra`, `dmf-cms`, `dmf-media`, `dmf-runbooks` each have branch protection on `main` requiring PR + ops-admin approval.

2. **`llm-agent-svc` user exists** with `read:repository` + `write:repository` token, NOT in `ops-admin` team.

3. **LLM agent token cannot push to `main`**: Verified by `git push origin HEAD:main` with the token — must fail with branch protection error.

4. **LLM agent token CAN push to `dev`**: Verified by `git push origin HEAD:dev` — must succeed.

5. **Token stored in OpenBao** at `secret/apps/llm-agent/forgejo`.

6. **Token available via gitcredential helper**: Agent can `git clone` without seeing the token in its session.

7. **Agent session excludes infrastructure credentials**: No SSH keys, kubeconfig, AWX tokens, OpenBao details, or cloud CLIs in the agent's context.

8. **No secrets leaked**: No credentials, tokens, or keys appear in plaintext in any tracked file, commit, or AI transcript during implementation (per ADR-0007).

### Phase 2 (post-experiment — deferred)

9. **Repo-per-environment created**: `-dev` and `-testing` repos for each component, `llm-agent-svc` scoped to `-dev` only.

10. **AWX projects split** by environment with isolated credentials.

11. **OpenBao `dev-*` paths** created alongside existing `runtime` paths.

12. **Promotion workflow** (tag-based) functional with self-approval gate.

13. **Phase 1 branch protection** remains active on all repos (including production-equivalent).

## Resolved Decisions Log

These decisions were clarified during plan review. They are resolved and baked into the plan above.

| # | Decision | Resolution | Rationale |
|---|----------|-----------|-----------|
| 1 | Phase posture | **Defer Option B to post-experiment. Implement Option A now.** | Option A (protected branches + LLM token scoping) gives both threat mitigations with minimal overhead. Option B (repo-per-env) deferred until governance is justified. |
| 2 | Primary threat | **Both (a) code gate AND (b) credential control** | Option A handles (a) via branch protection + PR review, and (b) by withholding infrastructure credentials from the agent's session. |
| 3 | OpenBao paths | **Option B: least-invasive (`dev-*` suffix)** | No migration required. Existing ESO references unchanged. Phase 2 adds `secret/apps/*/dev-*` alongside existing `secret/apps/*/runtime`. |
| 4 | Token handoff | **gitcredential helper (macOS keychain)** | ADR-0007 compliant — token never appears in chat. Agent inherits credential from git config transparently. |
| 5 | aliyun-frankfurt | **Geo-redundancy / second region** | Not a testing tier. When it comes online, the dev → main workflow can evolve into dev → testing → production using the two-region split. |
| 6 | Repo count | **Option A now (0 new repos). Option B deferred.** | No repo proliferation in Phase 1. Phase 2 creates ~12 new repos when justified. |
| 7 | Promotion | **Tag-based (Phase 2). PR review (Phase 1).** | Phase 1: dev → main via PR + operator review. Phase 2: tag-based promotion across repos. |
| 8 | dmf-env | **Not split.** | LLM agents lack credentials to dmf-env entirely. It's not part of their workflow. |
| 9 | Approval gates | **Single self-approve** | One-operator setup. Gate is ceremonial but documents intent. |
| 10 | ChatGPT provenance | **One input among several** | Useful framing but not authoritative. Real requirement comes from operator's architecture thinking. |

