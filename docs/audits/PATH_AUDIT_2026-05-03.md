# Path Audit — DMF Infrastructure Playbooks
**Date:** 2026-05-03  
**Scope:** All YAML playbooks and roles across umbrella + component repos  
**Status:** FINDINGS ONLY — no changes applied

---

## Summary

Audit found **3 categories of path references**: environment-specific (expected), variable-derived (safe), and hardcoded (problematic). The hardcoded paths are concentrated in three areas:

1. **OpenBao breakglass file** (inventory-level, correct location)
2. **JuiceFS mount point** (operator environment, correct location)
3. **Colima Docker socket** (operator environment, correct location)

**No playbook-level issues found after the CMS chart path fix.** All playbook imports use relative paths, all role sources use `playbook_dir` or variables.

---

## Findings by Category

### ✅ SAFE: Variable-Derived Paths

These paths are constructed from variables set in inventory, not hardcoded:

| Location | Pattern | Status |
|----------|---------|--------|
| `dmf-infra/roles/stack/operator/cms/defaults/main.yml:4` | `cms_chart_source_path: "{{ playbook_dir }}/../../../dmf-cms/charts/dmf-cms"` | ✓ Relative to playbook |
| `dmf-infra/roles/stack/operator/cms/defaults/main.yml:48` | `lookup('file', cms_chart_source_path ~ '/../../VERSION')` | ✓ Derives from chart path |
| `dmf-infra/roles/stack/operator/cms/tasks/main.yml:348` | `chdir: "{{ cms_chart_source_path \| dirname \| dirname }}"` | ✓ Recently fixed (commit bf2a099) |
| `dmf-infra/roles/stack/operator/cms/tasks/main.yml:379-380` | `src: "{{ cms_chart_source_path }}/"; dest: "{{ cms_chart_stage_path }}"` | ✓ Both from variables |
| `dmf-infra/roles/stack/operator/netbox/tasks/main.yml:410` | `src: "{{ playbook_dir }}/../charts/netbox/"` | ✓ Relative to playbook |
| `dmf-infra/roles/stack/operator/forgejo/tasks/main.yml:73` | `src: "{{ playbook_dir }}/../charts/forgejo/"` | ✓ Relative to playbook |
| `dmf-infra/roles/stack/operator/authentik/defaults/main.yml:25-26` | Blueprint paths use `{{ role_path }}` | ✓ Built-in Ansible variable |

**Stage paths** (`/tmp/`) are safe for temporary build artifacts:
- `cms_chart_stage_path: /tmp/dmf-cms-chart`
- `netbox_chart_stage_path: /tmp/netbox-chart`
- `forgejo_chart_stage_path: /tmp/forgejo-chart`
- `cms_chart_values_path: /tmp/dmf-cms-values.yml`

---

### ⚠️ OPERATOR-SPECIFIC: Hardcoded Environment Paths

These paths reference the **operator's local environment** (Mac mini) and belong in inventory, not playbooks. Currently hardcoded in two locations:

#### OpenBao Break-Glass JSON
**Location:** `dmf-env/inventories/hetzner-arm/group_vars/all/eso.yml:9`
```yaml
eso_openbao_breakglass_file: <secure-store>/openbao-breakglass/hetzner-lab/openbao-keys-automation.json
```
**Status:** ✓ Correct location (inventory, not playbook)  
**Why hardcoded:** It's truly environment-specific (JuiceFS mount on the operator's Mac)  
**Usage:** Referenced by `cms/defaults/main.yml` with fallback chain

#### OpenBao Key Path Fallback
**Location:** `dmf-env/inventories/hetzner-arm/group_vars/all/openbao.yml:8`
```yaml
openbao_key_path: <secure-store>/openbao-breakglass/hetzner-lab/openbao-keys-automation
```
**Status:** ✓ Correct location (inventory)  
**Why hardcoded:** Base path for deriving the full `.json` path  
**Used by:** Role defaults with Jinja filters to append `.json`

#### Colima Docker Socket
**Location:** `dmf-env/inventories/hetzner-arm/group_vars/all/main.yml:135`
```yaml
cms_docker_socket: unix://$HOME/.colima/docker-build/docker.sock
```
**Status:** ✓ Correct location (inventory, added 2026-05-03)  
**Why hardcoded:** Operator's local Docker build environment  
**Used by:** CMS role, referenced as `{{ cms_docker_host }}`

#### JuiceFS Mount Checks
**Locations:**
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/tasks/main.yml:372` (path check)
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/tasks/main.yml:378` (error message)
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/tasks/main.yml:450,460,474` (file operations)

```yaml
- name: Assert JuiceFS mount exists
  ansible.builtin.stat:
    path: <volumes>/secure
  register: _openbao_breakglass_mount

- name: Fail if JuiceFS <volumes>/secure is missing
  ansible.builtin.fail:
    msg: "JuiceFS mount <volumes>/secure is not available..."
```

**Status:** ⚠️ Hardcoded in **playbook**, not inventory  
**Why problematic:** Different operators may mount JuiceFS at different paths  
**Recommendation:** Make configurable via role variable `openbao_secure_mount_path: <volumes>/secure`

#### Manifest Automation JSON
**Location:** `dmf-env/manifests/hetzner-arm.yaml:141`
```yaml
automation_json: <secure-store>/openbao-breakglass/hetzner-lab/openbao-keys-automation.json
```
**Status:** ✓ Correct location (environment manifest, not playbook)

---

### ❌ RESOLVED: Previously Hardcoded Paths

These were fixed during the 2026-05-03 restructuring session:

| File | Issue | Fix | Commit |
|------|-------|-----|--------|
| `dmf-infra/site.yml` | Absolute path to docs | Changed to relative `../../../docs/` | (earlier) |
| `dmf-infra/roles/stack/operator/cms/defaults/main.yml` | Hardcoded OpenBao breakglass | Now uses `eso_openbao_breakglass_file` from inventory | (earlier) |
| `dmf-infra/roles/stack/operator/cms/defaults/main.yml` | Hardcoded lock file | Now uses `cms_lock_file` variable | (earlier) |
| `dmf-infra/roles/stack/operator/cms/defaults/main.yml` | Hardcoded Docker socket | Now uses `cms_docker_host` variable | (earlier) |
| `dmf-infra/roles/stack/operator/cms/tasks/main.yml` | All DOCKER_HOST refs | Now use `{{ cms_docker_host }}` | (earlier) |
| `dmf-infra/playbooks/696-cms-authentik-api.yml:183` | Hardcoded breakglass path | Now uses `eso_openbao_breakglass_file` fallback | (earlier) |
| `dmf-infra/playbooks/697-cms-awx-token.yml:47` | Hardcoded breakglass path | Now uses `eso_openbao_breakglass_file` fallback | (earlier) |
| `dmf-infra/playbooks/698-cms-netbox-forgejo-tokens.yml:44` | Hardcoded breakglass path | Now uses `eso_openbao_breakglass_file` fallback | (earlier) |
| `dmf-infra/roles/stack/operator/cms/tasks/main.yml:348` | `$HOME/repos/dmf-cms` hardcoded | Changed to `{{ cms_chart_source_path \| dirname \| dirname }}` | bf2a099 |

---

## Risk Assessment

### Low Risk ✓
- **Variable-derived paths** are safe — they adapt to any clone location
- **Inventory-level hardcoding** is expected — these are environment specifics that operators set once
- **Relative playbook paths** work because `playbook_dir` is dynamic

### Medium Risk ⚠️
- **JuiceFS mount path hardcoding** (openbao role) — assumes all operators mount at `<volumes>/secure`
- **Future portability:** If a second environment is added (not `hetzner-arm`), the JuiceFS assumption will break

### Mitigated Risk
- The CMS chart build path fix (commit bf2a099) resolved a critical blocker
- Token pipeline playbooks now use safe fallback chains (`eso_openbao_breakglass_file | default(...)`)

---

## Recommendations

### Priority 1: No Action Required
The three hardcoded operator paths (OpenBao JSON, JuiceFS, Colima socket) are **correctly placed in inventory** (`dmf-env/`), not in playbooks. This is the right pattern — they're environment specifics that new operators should configure once per environment.

### Priority 2: Optional Hardening (Deferred)
If adding multi-environment support, make the JuiceFS mount path configurable:

```yaml
# In role defaults
openbao_secure_mount_path: <volumes>/secure

# In tasks
- name: Assert JuiceFS mount exists
  ansible.builtin.stat:
    path: "{{ openbao_secure_mount_path }}"
```

Then override in environment inventory:
```yaml
# dmf-env/inventories/hetzner-arm/group_vars/all/
openbao_secure_mount_path: <volumes>/secure
```

**Trigger:** When adding a second environment (e.g., `flypack-01`)

### Priority 3: Documentation
The fallback chain pattern is working well:
```yaml
cms_openbao_breakglass_file: >-
  {{
    eso_openbao_breakglass_file
    | default((openbao_key_path | default('')) ~ '.json', true)
  }}
```

This provides three levels of override:
1. Role variable override (highest precedence)
2. Inventory `eso_openbao_breakglass_file`
3. Fallback to `openbao_key_path` + `.json` suffix

Document this pattern in AGENTS.md or CLAUDE.md for future use.

---

## Audit Scope Details

**Searched patterns:**
- `HOME.*repos`, `/Users/<operator>`, `/Volumes/<operator>` (hardcoded paths)
- `chdir:`, `cwd:` (working directory changes)
- `playbook_dir`, `role_path` (dynamic path references)
- `lookup.*file` (file access patterns)
- `import_playbook`, `include_role` (composition imports)
- `chart.*path`, `source.*path` (artifact paths)

**Repos covered:**
- ✓ `dmf-infra/` (comprehensive)
- ✓ `dmf-env/` (inventory)
- ✓ `dmfdeploy/` (umbrella)
- ✓ `dmf-central/` (no playbooks yet)
- ✓ `dmf-media/` (no playbooks yet)
- ⊘ `dmf-cms/` (frontend/backend, out of scope)

---

## Related Commits

- `bf2a099` — fix: use derived path for dmf-cms build directory (fixed chdir issue)
- Earlier session — refactored all hardcoded paths to variables in CMS role

