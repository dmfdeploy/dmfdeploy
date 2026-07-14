---
name: sandbox-harness-render-verify
description: Verification discipline for DMF sandbox harness changes — render-level checks replace live cluster rollout for render-path-only modifications
source: auto-skill
extracted_at: '2026-06-05T15:42:00Z'
type: durable-pattern
scope: dmf-env
owner: operator
review_by: '2027-01-14'
---

# Sandbox Harness Render-Level Verification

When implementing changes to the DMF sandbox e2e harness that only affect the **render path** (init-wizard inputs/outputs, createnew.py model, answers file schema, bootstrap payload), acceptance is satisfied by a **render-level check** — do NOT attempt a live cluster rollout or playbook run unless the change modifies cluster-facing behavior.

## When to use

- Changes to `init-wizard.sh` non-interactive input loading or variable derivation
- Changes to `dmf-init` createnew.py model fields or answers file generation
- Changes to `dmf-init/test/e2e/lib/bootstrap.sh` render payload
- Changes to `dmf-init/test/e2e/profile.*.env` fixed values
- Any harness change where the acceptance criteria explicitly mention "render-level check is enough"

## Procedure

### 1. Verify the render path

```bash
# Create a temporary test answers file
mkdir -p /tmp/dmf-init-test-render
age-keygen -o /tmp/dmf-init-test-render/test-age-key
ssh-keygen -t ed25519 -N "" -C "test-key" -f /tmp/dmf-init-test-render/test-key

cat > /tmp/dmf-init-test-render/answers.yaml <<'EOF'
schema_version: 1
provider: sandbox
operator:
  username: test-op
  email: test-op@dmf.test
  display: Test Operator
sandbox:
  node_ip: 127.0.0.1
  ansible_user: <your-user>
  iface: eth0
  ssh_private_key_path: /tmp/dmf-init-test-render/test-key
EOF

# Run non-interactive render
cd dmf-env
DMF_DATA_ROOT=/tmp/dmf-init-test-render \
SOPS_AGE_KEY_FILE=/tmp/dmf-init-test-render/test-age-key \
bash bin/init-wizard.sh --non-interactive /tmp/dmf-init-test-render/answers.yaml 2>&1
```

### 2. Assert the output

```bash
# Extract the env_id from the summary output
ENV_ID=<from-summary>

# Verify the key variable in group_vars
grep 'dmf_sandbox_base_domain' \
  /tmp/dmf-init-test-render/envs/$ENV_ID/inventory/group_vars/all/main.yml

# Verify derived variables
grep -E 'env_label|cert_manager_cluster_domain' \
  /tmp/dmf-init-test-render/envs/$ENV_ID/inventory/group_vars/all/main.yml
```

### 3. Verify interactive path unchanged

Read the interactive code path (L542-553 in init-wizard.sh) to confirm:
- `prompt_required` or `prompt_default` still fires for sandbox label
- No fallback to env_id in the interactive branch
- The non-interactive-only change is gated to `load_inputs_noninteractive()`

### 4. Verify Python model accepts the new input

```bash
cd dmf-init && uv run python -c "
from dmf_init.createnew import SandboxInputs
# Test the new input variant (empty, missing, etc.)
s = SandboxInputs(...)
assert s.label == <expected>
"
```

### 5. Clean up

```bash
rm -rf /tmp/dmf-init-test-render
```

## What NOT to do

- **Do NOT** run a live playbook against the sandbox VM — env access routes through dmf-init container and requires operator coordination
- **Do NOT** run the full e2e harness (`reset → bootstrap → verify`) — this destroys the live sandbox environment
- **Do NOT** push commits — operator decides when to push

## Commit discipline

When multiple repos are touched:
- Commit each repo separately with related messages
- Check `git status` first — there may be pre-existing dirty files from other sessions
- Only `git add` the specific files your task changed
- Do NOT bundle unrelated dirty state into your commit

## Cleanup

```bash
rm -rf /tmp/dmf-init-test-render
```
