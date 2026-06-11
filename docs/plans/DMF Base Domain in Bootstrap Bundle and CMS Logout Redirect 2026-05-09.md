---
status: executed
date: 2026-05-09
---
# Plan: Capture Base Domain in Bootstrap Bundle & Wire to CMS Logout Redirect

**Date:** 2026-05-09
**Phase:** Experiment (ADR-0004)
**Related ADRs:** ADR-0002 (generic playbooks + private inventory), ADR-0005 (VERSION as single source of truth), ADR-0007 (no secrets in argv/logs/tmp), ADR-0008 (bootstrap/runtime/break-glass secret tiers), ADR-0010 (run-playbook.sh only entry point)

---

## 1. Problem Statement

After OIDC logout from the DMF Console (dmf-cms), the user is redirected to a hardcoded `https://dmf.example.com/` placeholder URL instead of the live platform's landing page (e.g., `https://<lan-host>/`).

### Root Cause

The domain is defined in **Ansible inventory group_vars** but **never wired through** to the CMS container environment variables. The chain breaks at the Helm values template (`values.yml.j2`), which never emits `oidc.logoutRedirectUrl`. The chart's own `values.yaml` default (`https://dmf.example.com/`) fills the gap.

### Current Data Flow (Broken)

```
Inventory group_vars/all/main.yml
  cert_manager_cluster_domain: <lan-host>     ← defined here
  dmf_cms_host: console.<lan-host>            ← defined here

Ansible CMS role defaults/main.yml
  cms_host: console.{{ cert_manager_cluster_domain | default('dmf.example.com') }}
                                                    ← uses inventory value ✓

Ansible CMS role templates/values.yml.j2
  oidc.logoutRedirectUrl: ???                       ← MISSING ✗

Helm chart values.yaml (dmf-cms)
  oidc.logoutRedirectUrl: "https://dmf.example.com/" ← hardcoded fallback fills gap

Container env var
  DMF_CONSOLE_OIDC_LOGOUT_REDIRECT_URL = "https://dmf.example.com/"

Python settings (main.py:211)
  landing = settings.oidc.logout_redirect_url or "https://dmf.example.com/"
                                                    ← lands on placeholder
```

### Why the Inventory-Only Approach Is Incomplete

The inventory group_vars define the domain per environment (`hetzner-arm`, `aliyun`), and ADR-0002 still makes `dmf-env` inventory/manifests the home for environment design intent. This plan does **not** change that source-of-truth boundary.

The gap is narrower:

1. **Bootstrap replay gap**: The bootstrap bundle (`${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>.sops.yaml`) already captures admin identity, k3s token, provider API tokens, and other pre-Bao bootstrap inputs. A fresh rebuild should not have to infer the base URL from scattered defaults after the bundle exists.
2. **Execution-time gap**: `run-playbook.sh` already exports bundle fields as `vault_*` variables for Ansible. The CMS role can consume the same path instead of reconstructing URLs from chart defaults.
3. **DR clarity gap**: If the inventory and bundle disagree, the operator needs an explicit precedence rule instead of a silent fallback to `dmf.example.com`.

For this change, the encrypted bundle becomes the **bootstrap execution copy** of `base_domain`; inventory/manifests remain the design source. Making the bundle the sole source for environment identity would need a separate ADR and cleanup pass.

---

## 2. Target Architecture

The base domain is captured during `bootstrap-secrets.sh init` (the operator's init wizard), stored in the encrypted SOPS bundle as bootstrap metadata, and flows through the stack:

```
bootstrap-secrets.sh init <env>
  → prompts operator for base_domain (e.g., <lan-host>)
  → stores bootstrap execution copy in bundle metadata.base_domain

bootstrap-secrets.sh export-vars <env> <json-out>
  → exports vault_base_domain to Ansible vars JSON

Ansible CMS role (650-dmf-cms.yml)
  → reads vault_base_domain from exported vars
  → derives cms_logout_redirect_url = https://{{ base_domain }}/

Helm values template (values.yml.j2)
  → emits oidc.logoutRedirectUrl from cms_logout_redirect_url

Container env var
  → DMF_CONSOLE_OIDC_LOGOUT_REDIRECT_URL = https://<lan-host>/

Python /auth/logout
  → redirects to https://<lan-host>/ (landing page apex)
```

### Execution Source Chain

| Layer | Source | Variable |
|---|---|---|
| **Environment design** (design source) | `dmf-env/inventories/<env>/` and future manifest codegen | `cert_manager_cluster_domain` / equivalent |
| **Bootstrap bundle** (execution copy) | `${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>.sops.yaml` | `metadata.base_domain` |
| **Ansible vars** (derived) | `bootstrap-secrets.sh export-vars` output JSON | `vault_base_domain` |
| **Ansible CMS role** (derived) | `roles/stack/operator/cms/defaults/main.yml` | `base_domain` (from vault var) |
| **Helm values** (derived) | `templates/values.yml.j2` | `oidc.logoutRedirectUrl` |
| **Container** (derived) | Deployment env | `DMF_CONSOLE_OIDC_LOGOUT_REDIRECT_URL` |
| **Python** (derived) | `settings.py` | `oidc.logout_redirect_url` |

---

## 3. Implementation Details

### 3.1 File: `dmf-env/bin/bootstrap-secrets.sh`

**Six changes required:**

#### A. Add `base_domain` prompt in `cmd_init()`

**Location:** After the admin identity section, before provider tokens (around line 480)

**Insert:**

```bash
  # Base domain (used for all platform URLs)
  echo "" >&2
  echo "--- Platform domain ---" >&2

  # Suggest domain from env name if no local config exists
  local suggested_domain=""
  case "${env_name}" in
    hetzner-arm) suggested_domain="<lan-host>" ;;
    aliyun|aliyun-*) suggested_domain="<lan-host>" ;;
    *) suggested_domain="${env_name}.<lan-host>" ;;
  esac

  # Check if we have an existing bundle or inventory to infer from
  local existing_domain=""
  local group_vars="${REPO_DIR}/inventories/${env_name}/group_vars/all/main.yml"
  if [ -f "${group_vars}" ]; then
    existing_domain="$(awk '/cert_manager_cluster_domain:/ { gsub(/[" ]/, "", $2); print $2 }' "${group_vars}")"
  fi

  local default_domain="${existing_domain:-${suggested_domain}}"
  read -r -p "Base domain [${default_domain}]: " base_domain
  base_domain="${base_domain:-${default_domain}}"
  while [ -z "${base_domain:-}" ]; do
    echo "  Base domain is required" >&2
    read -r -p "Base domain: " base_domain
  done
  # Strip leading/trailing whitespace and protocol
  base_domain="$(echo "${base_domain}" | sed 's|^https\?://||; s|/.*||; s|^[[:space:]]*||; s|[[:space:]]*$||')"
```

#### B. Include `base_domain` in the bundle YAML

**Location:** In the `cat > "${tmp_yaml}"` heredoc, add under `metadata:`

```yaml
metadata:
  environment: ${env_name}
  base_domain: ${base_domain}          # ← NEW
  created_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ...
```

#### C. Validate `base_domain` in `validate_bundle_schema()`

**Location:** In the `validate_bundle_schema` Python block, import `re`, add `metadata.base_domain` to required fields, then validate domain shape:

```python
# Add near the existing imports:
import re

# Add to required_fields:
required_fields = {
    'bootstrap_admin.username': str,
    'bootstrap_admin.email': str,
    'bootstrap_admin.password': str,
    'cluster.k3s_token': str,
    'metadata.base_domain': str,
}

# Then validate shape after required_fields has passed.
metadata = data.get('metadata', {})
base_domain = metadata['base_domain']
if not re.match(r'^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$', base_domain):
    print(f'ERROR: metadata.base_domain is not a valid domain: {base_domain}', file=sys.stderr)
    sys.exit(1)
```

#### D. Export `base_domain` in `cmd_export_vars()`

**Location:** In the `cmd_export_vars` Python block, after the bootstrap admin section:

```python
# Base domain (for constructing platform URLs)
metadata = data.get('metadata', {})
if metadata.get('base_domain'):
    vars['vault_base_domain'] = metadata['base_domain']
```

#### E. Add `base_domain` check in `cmd_doctor()`

**Location:** In the doctor schema validation section, add:

```bash
    # Check base_domain is set
    local base_domain
    base_domain="$(bundle_field "${env_name}" metadata.base_domain 2>/dev/null)" || base_domain=""
    check "metadata.base_domain is set" [ -n "${base_domain}" ]
```

#### F. Add safe migration support for existing bundles

Current `cmd_init()` does **not** rewrite existing bundles; it decrypts, reports missing fields, and exits. Add an explicit migration path before making `metadata.base_domain` mandatory for existing environments.

Recommended subcommand:

```bash
bin/bootstrap-secrets.sh set-base-domain <env> <domain>
```

Requirements:

- Validate the domain with the same normalization and regex as `cmd_init()`.
- Update only `metadata.base_domain`.
- Prefer the SOPS `set` subcommand; do not write decrypted bundle contents to `/tmp`.
- Print only non-secret metadata and never dump the decrypted bundle.

Example implementation shape:

```bash
sops set "${bundle}" '["metadata"]["base_domain"]' "\"${base_domain}\""
```

If `sops set` is unavailable on the installed SOPS version, use a secure editor workflow explicitly configured away from `/tmp`, or defer and add a small wrapper that edits through SOPS without exposing full bundle plaintext in agent-visible output.

---

### 3.2 File: `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/cms/defaults/main.yml`

**Add the logout redirect URL variable:**

```yaml
# CMS base domain — prefer bootstrap bundle execution copy, then inventory.
# vault_base_domain is set by bootstrap-secrets.sh export-vars.
base_domain: "{{ vault_base_domain | default(cert_manager_cluster_domain | default('dmf.example.com')) }}"

# Logout redirect URL — where users land after OIDC sign-out
# Points to the platform apex (landing page)
cms_logout_redirect_url: "https://{{ base_domain }}/"
```

**Rationale:** The precedence chain is:
1. `vault_base_domain` from bootstrap bundle (bootstrap execution copy)
2. `cert_manager_cluster_domain` from inventory (design source / migration fallback)
3. `dmf.example.com` (last-resort fallback — should never be reached in practice)

---

### 3.3 File: `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/cms/templates/values.yml.j2`

**Add `logoutRedirectUrl` under the `oidc:` block.** Find the existing `oidc:` section and add:

```yaml
oidc:
  enabled: {{ cms_oidc_enabled | default(true) | to_json }}
  issuerUrl: {{ cms_oidc_issuer_url | default('https://' ~ authentik_host ~ '/application/o/dmf-console/') | to_json }}
  clientId: {{ dmf_cms_oidc_provider_credentials_parsed.client_id | default('') | to_json }}
  clientSecret:
    existingSecretName: dmf-cms-oidc
    key: clientSecret
  logoutRedirectUrl: {{ cms_logout_redirect_url | default('https://' ~ (base_domain | default(cert_manager_cluster_domain | default('dmf.example.com'))) ~ '/') | to_json }}
```

---

### 3.4 File: `dmf-cms/charts/dmf-cms/values.yaml`

**Change the hardcoded default to empty string:**

```yaml
oidc:
  enabled: true
  issuerUrl: ""
  clientId: ""
  clientSecret:
    existingSecretName: dmf-cms-oidc
    key: clientSecret
  logoutRedirectUrl: ""   # ← was: "https://dmf.example.com/" — now deferred to Ansible/Helm template
```

**Rationale:** An empty value in the chart means the Deployment template's `{{- if .Values.oidc.logoutRedirectUrl }}` guard skips the env var, letting Python's own default (see §3.5) take effect. In cluster mode, Ansible always overrides this via the Helm values template, so the chart default is only relevant for local/dev runs.

---

### 3.5 File: `dmf-cms/src/dmf_cms/main.py`

**Change the fallback from hardcoded domain to relative root:**

**Before (line ~211):**
```python
landing = settings.oidc.logout_redirect_url or "https://dmf.example.com/"
```

**After:**
```python
# Logout redirect target: configured URL, or root of current origin.
# Using a relative "/" ensures we never redirect to a hardcoded domain
# that may be stale (e.g., dmf.example.com placeholder).
landing = settings.oidc.logout_redirect_url or "/"
```

**Rationale:** If `DMF_CONSOLE_OIDC_LOGOUT_REDIRECT_URL` is empty (local dev mode, or misconfigured deploy), redirecting to `/` sends the user back to the CMS root — which is at least a valid page on the current host, unlike a hardcoded `dmf.example.com` that doesn't exist. This is a **defensive fallback**, not a replacement for proper configuration.

---

### 3.6 File: `dmf-cms/charts/dmf-cms/templates/deployment.yaml`

**No change needed.** The existing template already conditionally sets the env var:

```yaml
{{- if .Values.oidc.logoutRedirectUrl }}
- name: DMF_CONSOLE_OIDC_LOGOUT_REDIRECT_URL
  value: {{ .Values.oidc.logoutRedirectUrl | quote }}
{{- end }}
```

When `logoutRedirectUrl` is populated by the Helm values template (§3.3), this block renders the env var. When it's empty (local dev), the block is skipped.

---

## 4. Migration Path for Existing Environments

### Hetzner ARM (live)

The existing bundle at `${DMF_BOOTSTRAP_BUNDLE_DIR}/hetzner-arm.sops.yaml` may not have `metadata.base_domain`. Two safe options:

**Option A (recommended):** Use the new migration subcommand:
```bash
cd dmf-env
bin/bootstrap-secrets.sh set-base-domain hetzner-arm <lan-host>
```

**Option B:** Use an interactive SOPS edit workflow configured to avoid `/tmp`, then add the field under `metadata:`:

```yaml
metadata:
  base_domain: <lan-host>
```

Do **not** decrypt the bundle to `/tmp` or any transcript-visible path. The bundle contains bootstrap secrets even though `base_domain` itself is not secret.

Re-running `bootstrap-secrets.sh init hetzner-arm` is not enough unless §3.1F is implemented; current `cmd_init()` only reports missing fields for existing bundles.

### Aliyun (live)

Same process. Current environment name is `aliyun` (renamed from historical `aliyun-frankfurt` on 2026-05-10). Fresh bundles get prompted during `init`; existing bundles use `set-base-domain` or `sops edit`.

### Inventory Group Vars

The inventory group_vars still have `cert_manager_cluster_domain: <lan-host>`. This stays for now as the **environment design source / migration fallback**. A future cleanup can remove duplication only after an ADR decides whether bootstrap bundle metadata replaces inventory/manifest-derived environment identity.

---

## 5. Verification Checklist

### 5.1 Build verification

```bash
# dmf-cms builds cleanly
cd dmf-cms
scripts/sync-version.sh --check
cd frontend && npm ci && npm run build   # no TypeScript errors
```

### 5.2 Bundle schema validation

```bash
# New bundle has base_domain
cd dmf-env
bin/bootstrap-secrets.sh doctor hetzner-arm
# Should show: PASS: metadata.base_domain is set
```

### 5.3 Export verification

```bash
# export-vars includes vault_base_domain
cd dmf-env
out="$(mktemp "${DMF_BOOTSTRAP_BUNDLE_DIR}/export-vars.XXXXXX.json")"
chmod 0600 "${out}"
trap 'rm -f "${out}"' EXIT
bin/bootstrap-secrets.sh export-vars hetzner-arm "${out}"
python3 -c "import json, sys; d=json.load(open(sys.argv[1])); print(d.get('vault_base_domain'))" "${out}"
rm -f "${out}"
# Should print: <lan-host>
```

The exported vars file contains secrets. Keep it outside `/tmp`, keep mode `0600`, and remove it immediately.

### 5.4 Ansible dry-run

```bash
# Check that the CMS role picks up vault_base_domain
cd dmf-env
bin/run-playbook.sh hetzner-arm ../dmf-infra/k3s-lab-bootstrap/playbooks/650-dmf-cms.yml --check --diff
# Should succeed, with cms_logout_redirect_url resolved to https://<lan-host>/
```

### 5.5 Helm template verification

```bash
# Render Helm values and check logoutRedirectUrl
# After a playbook run, check the generated values file on the control node:
# Use the environment's existing SSH target/helper; do not hardcode node names.
# The staged values file should contain:
# Should show: logoutRedirectUrl: "https://<lan-host>/"
```

### 5.6 End-to-end (after deploy)

1. Log in to DMF Console via OIDC
2. Click Logout
3. Browser should redirect to `https://<lan-host>/` (landing page apex)

---

## 6. Files to Modify

| # | File | Change Summary |
|---|---|---|
| 1 | `dmf-env/bin/bootstrap-secrets.sh` | Add `base_domain` prompt in `cmd_init`, validation in `validate_bundle_schema`, export in `cmd_export_vars`, doctor check in `cmd_doctor`, and safe `set-base-domain` migration support |
| 2 | `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/cms/defaults/main.yml` | Add `base_domain` var with vault→inventory→fallback precedence; add `cms_logout_redirect_url` |
| 3 | `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/cms/templates/values.yml.j2` | Add `logoutRedirectUrl` under `oidc:` block |
| 4 | `dmf-cms/charts/dmf-cms/values.yaml` | Change `logoutRedirectUrl: "https://dmf.example.com/"` → `""` |
| 5 | `dmf-cms/src/dmf_cms/main.py` | Change fallback from `"https://dmf.example.com/"` → `"/"` |

---

## 7. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Existing bundle lacks `base_domain` → `doctor` fails | High (certain for older bundles) | Medium (blocks export-vars if schema becomes mandatory) | Implement `set-base-domain`/`sops edit` migration before requiring the field |
| Vault var name collision | Low | Medium | `vault_base_domain` is new; grep confirms no existing usage |
| Helm template syntax error | Low | Medium | `to_json` filter handles quoting; `--check` mode catches errors |
| Local dev mode broken (empty logoutRedirectUrl) | Low | Low | `main.py` fallback to `/` handles this gracefully |
| `dmf.example.com` hardcoded elsewhere in chart | N/A (out of scope) | Low | These are always overridden by Ansible; separate cleanup item |
| Bundle/inventory domain drift | Medium | Medium | Prefer `vault_base_domain` at execution time; add doctor warning if it differs from `cert_manager_cluster_domain` |
| Plaintext bundle leakage during migration | Medium if manually edited | High | Use `sops set` or a controlled SOPS edit workflow; never decrypt the full bundle to `/tmp` or agent-visible output |

---

## 8. Out of Scope

These are **not** part of this change but are related:

1. **Deduplicating inventory group_vars** — removing `cert_manager_cluster_domain` from inventory and making the bundle the sole source. This is a separate cleanup and likely needs an ADR because it changes the ADR-0002 environment-design boundary.
2. **Fixing other `dmf.example.com` defaults in `charts/dmf-cms/values.yaml`** — image repository, ingress host, authentik/awx/netbox/forgejo API URLs. These are always overridden by Ansible in cluster mode.
3. **Authentik OIDC post-logout redirect URI** — this is a separate concern (the Authentik provider blueprint doesn't configure post-logout URIs; the CMS handles it client-side).
4. **Adding or renaming Aliyun inventory fields** — current environment name is `aliyun`; historical `aliyun-frankfurt` references stay only in old handoffs/reviews.

---

## 9. Agent Workflow

When a future agent picks up this plan:

1. Read this document top to bottom.
2. Check `git status` in each touched component repo (`dmf-env`, `dmf-infra`, `dmf-cms`) — ask before modifying dirty state.
3. Implement changes in order (§3.1F migration support before making `metadata.base_domain` required, then §3.1A–E, then §3.2–§3.5).
4. Run verification steps (§5.1–§5.4).
5. If `--check` mode passes, run the actual playbook (`bin/run-playbook.sh hetzner-arm .../650-dmf-cms.yml`) — only if the user approves.
6. End-to-end test (§5.6) requires a live cluster — flag if cluster is unavailable.
7. Commit each repo separately with related messages (ADR-0001: independent component git repos).
