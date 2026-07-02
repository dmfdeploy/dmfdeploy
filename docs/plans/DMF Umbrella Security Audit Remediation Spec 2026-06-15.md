---
status: draft
date: 2026-06-15
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/165
---
> **Public-safety note (2026-07-02).** This spec originally enumerated the real
> leaked literals as before→after mappings. Before committing, every real value
> was replaced by its placeholder form (the concrete values live only in the
> operator-local scrub patterns). Where a mapping table now shows the same
> placeholder in both columns, read the left column as "the real value that was
> scrubbed". Executed slice: Changes 4–7 + 12 landed under #133/#137; the
> script-hardening remainder (Changes 1–3, 8–11, 13–17) is tracked in #165.

> **Post-sweep reconciliation (2026-06-24, umbrella #133).** A live `git grep`
> sweep found this spec's literal lists were **incomplete** (some files were
> already partially scrubbed in an earlier session; new leaks were never
> listed). The topology/identity public-safety slice (Changes 4–7 + the gate
> gap) was executed under #133. The complete set actually scrubbed, beyond
> what Changes 4–7 enumerate:
>
> - **Aliyun public IPs (extra):** `<aliyun-validation-node-1-ip>`, `<aliyun-validation-node-2-ip>`,
>   `<aliyun-validation-node-3-ip>` (validation-env nodes), `<aliyun-validation-slb-ip>` (SLB), `<aliyun-sandbox-node-ip>`
>   (sandbox node) + its dashed `<aliyun-sandbox-node-ip-dashed>.sslip.io` form.
> - **Operator VPS:** `<operator-vps-ip>` → `<operator-vps-ip>`.
> - **Aliyun resource IDs (extra):** SLB id `<aliyun-lb-id>` →
>   `<aliyun-lb-id>`, and **vserver-group ids** `<aliyun-vserver-group-http>` /
>   `<aliyun-vserver-group-https>` → `<aliyun-vserver-group-http|https>` — the `rsp-`
>   form was missed here and caught only by the tightened account-fingerprint
>   gate (`[a-z]{1,4}-<account-fingerprint>…`).
> - **OpenBao token accessor:** `<openbao-accessor>` →
>   `<openbao-accessor>` (identity literal beyond the two role_ids).
> - **Tailscale CGNAT host IPs:** `<tailscale-host-ips> (nine hosts)` and the
>   `.22-24` / `.16/17/18` shorthand forms → placeholders; the `100.64.0.0/10`
>   **range** notation (RFC 6598) preserved.
> - **Gate tightened:** `~/.dmfdeploy/scrub-private-patterns.sh` + a new
>   gitignored `.gitleaks.local.toml` mirror now carry these literals; public
>   `.gitleaks.toml` gained a generic `dmf-cloud-resource-id` rule. Raw sweep
>   + commit-time gitleaks now flag reintroduction.
> - **§4 / §5 — resolved (2026-06-24), no action:** operator confirmed both
>   source envs (`hetzner-arm`, `aliyun-frankfurt`) are **decommissioned** (no
>   local env state / breakglass / inventory for either). The leaked role_ids
>   died with their clusters → rotation moot; the scrubbed literals reference
>   ephemeral torn-down infra → history rewrite not warranted.

# DMF Umbrella Security Audit — Remediation Spec 2026-06-15

> **Goal:** eliminate every finding from the 2026-06-15 adversarial security
> audit of `dmfdeploy/dmfdeploy`. This document is the **sole source of
> truth** for what changes are proposed. Nothing is implemented here — this
> is a change-specification document only.

## Scope

- **Repo:** `dmfdeploy/dmfdeploy` (umbrella)
- **Audit date:** 2026-06-15
- **Methodology:** 4 parallel adversarial streams — shell injection, GitHub
  Actions supply-chain, secrets/information-disclosure, skills + Python code
- **Findings:** 0 CRITICAL, 6 HIGH, 5 MEDIUM, 16 LOW

---

## Change 1 — Fix command injection in `issue-close.sh` (H1)

**Severity:** HIGH
**File:** `bin/agentic/issue-close.sh`
**Lines:** 83–86

### Problem

`COMMENT_BODY` (derived from user-supplied `--note`) is interpolated directly
into a Python triple-quoted string. A `--note` containing `"""` terminates the
Python string and enables arbitrary code execution.

### Current code (lines 83–86)

```bash
COMMENT_PAYLOAD=$(python3 -c '
import json, sys
print(json.dumps({"body": """'"$COMMENT_BODY"'"""}))
')
```

### Proposed code

```bash
COMMENT_PAYLOAD=$(printf '%s' "$COMMENT_BODY" | python3 -c '
import json, sys
body = sys.stdin.read()
print(json.dumps({"body": body}))
')
```

### Rationale

The comment body flows through stdin (`sys.stdin.read()`) instead of being
spliced into Python source. No shell metacharacter in `$COMMENT_BODY` can
break out of the stdin channel.

---

## Change 2 — Fix command injection in `issue-open.sh` (H2)

**Severity:** HIGH
**File:** `bin/agentic/issue-open.sh`
**Lines:** 250–255

### Problem

`$BODY_FILE` (user-supplied path) is interpolated into a Python `open()` call,
and `$TITLE` is interpolated into a Python string literal. A `$BODY_FILE` path
containing a single quote breaks the `open()` call and enables arbitrary code
execution. `$TITLE` is incidentally safe due to the upstream regex at line 142
(`^[A-Za-z][A-Za-z0-9 :_/.\\-]{4,80}$`) but that is defense-by-coincidence.

### Current code (lines 240–248)

```bash
LABELS_JSON=$(python3 -c '
import json,sys
labels = ["agent-opened", "type:'"$TYPE"'", "pickup:'"$PICKUP"'", "effort:'"$EFFORT"'"]
for s in "'"${ALL_SCOPES[*]}"'".split():
    labels.append(f"scope:{s}")
print(json.dumps(labels))
')

PAYLOAD=$(python3 -c '
import json, sys
with open("'"$BODY_FILE"'") as f:
    body = f.read()
payload = {"title": "'"$TITLE"'", "body": body, "labels": '"$LABELS_JSON"'}
print(json.dumps(payload))
')
```

### Proposed code

```bash
LABELS_JSON=$(printf '%s\n' "$TYPE" "$PICKUP" "$EFFORT" "${ALL_SCOPES[@]}" | python3 -c '
import json, sys
lines = sys.stdin.read().strip().splitlines()
typ, pickup, effort = lines[0], lines[1], lines[2]
scopes = lines[3:]
labels = ["agent-opened", f"type:{typ}", f"pickup:{pickup}", f"effort:{effort}"]
for s in scopes:
    labels.append(f"scope:{s}")
print(json.dumps(labels))
')

PAYLOAD=$(python3 -c '
import json, sys, os
body_file = os.environ["DMF_BODY_FILE"]
title = os.environ["DMF_TITLE"]
labels = json.loads(os.environ["DMF_LABELS_JSON"])
with open(body_file) as f:
    body = f.read()
print(json.dumps({"title": title, "body": body, "labels": labels}))
' )
```

The `PAYLOAD` invocation requires three environment variables to be exported
immediately before the call:

```bash
DMF_BODY_FILE="$BODY_FILE" DMF_TITLE="$TITLE" DMF_LABELS_JSON="$LABELS_JSON" \
    PAYLOAD=$(python3 -c '
import json, sys, os
body_file = os.environ["DMF_BODY_FILE"]
title = os.environ["DMF_TITLE"]
labels = json.loads(os.environ["DMF_LABELS_JSON"])
with open(body_file) as f:
    body = f.read()
print(json.dumps({"title": title, "body": body, "labels": labels}))
')
```

### Rationale

All user-controlled values flow through environment variables or stdin rather
than being interpolated into Python source. `os.environ[]` is not exploitable
via shell metacharacters.

---

## Change 3 — Fix command injection in `export-scan.sh` (H3)

**Severity:** HIGH
**File:** `bin/export-scan.sh`
**Lines:** 109–110

### Problem

`$SCRATCH` (from `$EXPORT_ROOT`) and `$GL` (from `$TMPDIR`) are single-quoted
inside a `bash -c` argument string. If either path contains a single quote,
the quoting breaks and arbitrary commands execute. Both variables are
user-controllable via environment.

### Current code (lines 109–110)

```bash
run "gitleaks ${GL_VERSION} (no-git tree, relative)" bash -c "cd '$SCRATCH' && '$GL' detect --source . --no-git --config .gitleaks.toml --no-banner --redact"
run "gitleaks ${GL_VERSION} (main scope, 1 commit)"  bash -c "cd '$SCRATCH' && '$GL' detect --log-opts=main --config .gitleaks.toml --no-banner --redact"
```

### Proposed code

Add path validation before the `run` calls (insert after line 101, before
the gates section):

```bash
# Path-safety: reject paths with shell metacharacters that would break
# bash -c quoting (the gitleaks invocations below use bash -c with
# single-quoted paths; a single quote in $SCRATCH or $GL = code injection).
case "$SCRATCH" in *\'*|*\;*|*\|*|*\&*|*\`*|*\$*) die "SCRATCH path contains shell metacharacters: $SCRATCH" ;; esac
case "$GL"      in *\'*|*\;*|*\|*|*\&*|*\`*|*\$*) die "GL path contains shell metacharacters: $GL" ;; esac
```

### Rationale

Exporting `SCRATCH` and `GL` to a temp script file would be more robust but
adds complexity. A fail-fast metacharacter check is simpler and proportionate
— these paths are machine-generated from `$EXPORT_ROOT` and `$TMPDIR`, so
legitimate paths will never contain shell metacharacters. The check converts
a silent injection into a loud, immediate failure.

---

## Change 4 — Replace OpenBao AppRole role_ids with placeholders (H4)

**Severity:** HIGH
**Files affected (4 files, 10 occurrences):**

| File | Line(s) | Value |
|------|---------|-------|
| `docs/reviews/dmf-aliyun-frankfurt-readiness-review-2026-05-08.md` | 180, 189, 255, 327, 438 | `<openbao-role-id-netbox>` |
| `docs/questions/aliyun-frankfurt-rollout-open-2026-05-08.md` | 11, 22, 26 | `<openbao-role-id-netbox> (partial)` (partial) |
| `docs/handoffs/DMF Aliyun Frankfurt Audit + Phase A Handoff 2026-05-08.md` | 55 | `<openbao-role-id-netbox> (partial)` (partial) |
| `docs/plans/DMF App Admin Account Drift Audit and Realignment Plan 2026-05-14.md` | 325 | `<openbao-role-id-app-admin>` |

### Proposed change

In each file, replace the real UUID with a placeholder:

```
<openbao-role-id-netbox>  →  <openbao-role-id-netbox>
<openbao-role-id-app-admin>  →  <openbao-role-id-app-admin>
```

For partial references (e.g., `<openbao-role-id-netbox> (partial)`), replace with the same
placeholder form (`<openbao-role-id-netbox>`).

### Additional action (operational, not a code change)

**Rotate both role_ids** on the live cluster. The role_ids alone are half the
credential pair (the secret_id is the other half), but they have been public
long enough that rotation is prudent. This is an operator action, not a repo
change — coordinate via the `dmf-openbao-unseal` skill.

---

## Change 5 — Replace public cloud IPs with placeholders (H5)

**Severity:** HIGH
**Files affected (7 files, 21 occurrences):**

### IP → placeholder mapping

| Real IP | Placeholder | Context |
|---------|-------------|---------|
| `<aliyun-slb-ip>` | `<aliyun-slb-ip>` | Aliyun SLB frontend |
| `<aliyun-node-1-ip>` | `<aliyun-node-1-ip>` | k3s node 1 |
| `<aliyun-node-2-ip>` | `<aliyun-node-2-ip>` | k3s node 2 |
| `<aliyun-node-3-ip>` | `<aliyun-node-3-ip>` | k3s node 3 |
| `<hetzner-floating-ip>` | `<hetzner-floating-ip>` | Hetzner floating IP |

### Files and line-level replacements

**`docs/handoffs/DMF Aliyun Pre-Seed to Post-Seed Live Validation Handoff 2026-05-10.md`** (lines 32, 34, 156):
- `<aliyun-slb-ip>` → `<aliyun-slb-ip>`

**`docs/handoffs/DMF Aliyun SLB Backend Registration Fix Handoff 2026-05-11.md`** (lines 6, 34, 98, 102):
- `<aliyun-slb-ip>` → `<aliyun-slb-ip>`

**`STATUS.md`** (line 2295):
- `<aliyun-slb-ip>` → `<aliyun-slb-ip>`

**`docs/decisions/0019-tailscale-cgnat-vs-cloud-internal-services.md`** (line 12):
- `<aliyun-slb-ip>` → `<aliyun-slb-ip>`

**`docs/handoffs/DMF Aliyun Frankfurt Rollout Next Steps Handoff 2026-05-08.md`** (lines 50–52):
- `<aliyun-node-1-ip>` → `<aliyun-node-1-ip>`
- `<aliyun-node-2-ip>` → `<aliyun-node-2-ip>`
- `<aliyun-node-3-ip>` → `<aliyun-node-3-ip>`

**`docs/plans/DMF Staged Release Phase 2-3 Plan 2026-04-29.md`** (lines 32, 118, 134, 440, 455, 496, 517):
- `<hetzner-floating-ip>` → `<hetzner-floating-ip>`

**`docs/handoffs/DMF Layer-1 OpenTofu Phase B Cut-over Handoff 2026-04-27.md`** (lines 75, 375):
- `<hetzner-floating-ip>` → `<hetzner-floating-ip>`

---

## Change 6 — Replace Tailscale CGNAT IPs with placeholders (H5 continued)

**Severity:** HIGH (continuation)
**Files affected (2 files, 15 occurrences):**

### IP → placeholder mapping

| Real IP | Placeholder | Context |
|---------|-------------|---------|
| `<tailscale-api-node>` | `<tailscale-api-node>` | API server Tailscale IP |
| `<tailscale-worker-2>` | `<tailscale-worker-2>` | Worker 2 Tailscale IP |
| `<tailscale-worker-1>` | `<tailscale-worker-1>` | Worker 1 Tailscale IP |
| `<tailscale-hetzner-1>` | `<tailscale-hetzner-1>` | Hetzner node Tailscale IP |
| `<tailscale-hetzner-2>` | `<tailscale-hetzner-2>` | (range reference) |
| `<tailscale-hetzner-3>` | `<tailscale-hetzner-3>` | (range reference) |

### Files and line-level replacements

**`docs/architecture/DMF Local kubectl via Tailscale.md`** (lines 12, 28, 37, 38, 39, 59, 70, 82, 89, 136, 142, 151, 158):
- `<tailscale-api-node>` → `<tailscale-api-node>` (11 occurrences)
- `<tailscale-worker-2>` → `<tailscale-worker-2>` (1 occurrence)
- `<tailscale-worker-1>` → `<tailscale-worker-1>` (1 occurrence)

**`STATUS.md`** (lines 1600, 1976):
- `<tailscale-hetzner-1>` → `<tailscale-hetzner-1>`
- `<tailscale-hetzner-1>-<tailscale-hetzner-3>` → `<tailscale-hetzner-1>` through `<tailscale-hetzner-3>` (expand the range notation)

---

## Change 7 — Replace cloud resource IDs with placeholders (H6)

**Severity:** HIGH
**Files affected (2 files, 4 occurrences):**

### Resource ID → placeholder mapping

| Real ID | Placeholder |
|---------|-------------|
| `<aliyun-vpc-id>` | `<aliyun-vpc-id>` |
| `<aliyun-vsw-id>` | `<aliyun-vsw-id>` |
| `<aliyun-instance-id>` | `<aliyun-instance-id>` |

### Files and line-level replacements

**`docs/handoffs/DMF Aliyun Frankfurt Rollout Next Steps Handoff 2026-05-08.md`** (lines 38–39):
- `<aliyun-vpc-id>` → `<aliyun-vpc-id>`
- `<aliyun-vsw-id>` → `<aliyun-vsw-id>`

**`docs/handoffs/DMF Aliyun SLB Backend Registration Fix Handoff 2026-05-11.md`** (lines 45, 100):
- `<aliyun-instance-id>` → `<aliyun-instance-id>`

---

## Change 8 — Fix token-in-argv in agentic curl calls (M1)

**Severity:** MEDIUM (ADR-0007 violation)
**Files affected (5 files):**

| File | Lines | curl invocation |
|------|-------|-----------------|
| `bin/agentic/issue-close.sh` | 102, 110 | `-H "Authorization: token ${TOKEN}"` |
| `bin/agentic/issue-list.sh` | 55 | `-H "Authorization: token ${TOKEN}"` |
| `bin/agentic/issue-open.sh` | 187, 232 | `-H "Authorization: token ${TOKEN}"` |
| `bin/agentic/issue-promote.sh` | 85, 137 | `-H "Authorization: token ${TOKEN}"` |
| `bin/agentic/issue-migrate-to-github.sh` | 93 | `-H "Authorization: token ${TOKEN}"` |

### Proposed pattern (applied to all 5 files)

Introduce a shared helper function at the top of each file (after the existing
`forgejo_validate_config` call) or factor into a common library sourced by all:

```bash
# forgejo_curl — pass auth token via --config file (never argv).
# Usage: forgejo_curl <url> [additional-curl-args...]
# The config file is created with 0600 perms and cleaned on EXIT.
_FORGEJO_CURL_CONFIG=""
_forgejo_curl_cleanup() { [ -n "$_FORGEJO_CURL_CONFIG" ] && rm -f "$_FORGEJO_CURL_CONFIG"; }
trap _forgejo_curl_cleanup EXIT

forgejo_curl() {
    local url="$1"; shift
    local token; token="$(cat "$FORGEJO_TOKEN_PATH")"
    _FORGEJO_CURL_CONFIG="$(mktemp)"
    chmod 0600 "$_FORGEJO_CURL_CONFIG"
    printf 'header = "Authorization: token %s"\n' "$token" > "$_FORGEJO_CURL_CONFIG"
    unset token
    curl -fsS --config "$_FORGEJO_CURL_CONFIG" "$@" "$url"
}
```

Then replace every:
```bash
TOKEN="$(cat "$FORGEJO_TOKEN_PATH")"
...
curl -fsS -H "Authorization: token ${TOKEN}" "$api" ...
```
with:
```bash
forgejo_curl "$api" ...
```

And remove the `TOKEN="$(cat ...)"` / `unset TOKEN` pairs.

### Rationale

The token is written to a file with `0600` permissions, read by curl via
`--config`, and immediately cleaned. It never appears in `ps aux`,
`/proc/*/cmdline`, or shell history. The trap ensures cleanup on abnormal
exit.

---

## Change 9 — Add `dependabot.yml` (M4)

**Severity:** MEDIUM
**File:** `.github/dependabot.yml` (new file)

### Proposed content

```yaml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    labels:
      - "deps"
      - "ci"
    commit-message:
      prefix: "ci(deps)"
```

### Rationale

Provides automated tracking of GitHub Actions version updates. The SHA-pinned
`actions/checkout` will receive update PRs when new versions are released,
enabling deliberate pin advancement rather than silent staleness. Does not
cover the binary hashes in `guard.yml` (gitleaks, trivy, actionlint) — those
require a separate mechanism (follow-on consideration).

---

## Change 10 — Fix `shell=True` in skills documentation (M5)

**Severity:** MEDIUM
**File:** `.agents/skills/github-operations-via-gh-cli/SKILL.md`
**Line:** 52–55

### Current code

```python
def graphql(query_str):
    result = subprocess.run(
        'gh api graphql -F query=@-',
        input=query_str, shell=True, capture_output=True, text=True
    )
```

### Proposed code

```python
def graphql(query_str):
    result = subprocess.run(
        ["gh", "api", "graphql", "-F", "query=@-"],
        input=query_str, capture_output=True, text=True
    )
```

### Rationale

List-argv form is the safe default for `subprocess.run`. It eliminates the
shell interpretation layer entirely — no metacharacter in any argument can
trigger shell expansion. The `gh` CLI receives its arguments directly, which
is what the example intends.

---

## Change 11 — Add `.gitignore` patterns (L11)

**Severity:** LOW
**File:** `.gitignore`

### Proposed addition

Append to the `# === Secrets-prevention baseline ===` block:

```gitignore
# Terraform variable files (may contain secrets)
*.tfvars
*.tfvars.json

# SSH private keys
id_*
!id_*.pub.example
```

### Rationale

`*.tfvars` files can contain provider credentials and are a common leak vector
in Terraform/OpenTofu projects. `id_*` catches SSH private keys that might
otherwise be committed; the `!id_*.pub.example` exception preserves any
example public keys used in documentation (none currently exist, but this
prevents future friction).

---

## Change 12 — Add gitleaks rules for UUID role_ids and cloud resource IDs (L9, L10)

**Severity:** LOW
**File:** `.gitleaks.toml`

### Proposed addition

Append after the `dmf-macos-metadata` rule:

```toml
# Catch cloud-provider resource IDs (Aliyun VPC, VSwitch, ECS instance) that
# fingerprint the exact cloud account. These should appear only in placeholder
# form (<aliyun-vpc-id>, etc.) in public docs.
[[rules]]
id = "dmf-cloud-resource-id"
description = "Aliyun/Hetzner cloud resource ID in tracked tree"
regex = '''(vpc-[a-z0-9]{20,}|vsw-[a-z0-9]{20,}|i-[a-z0-9]{20,})'''
tags = ["infrastructure-fingerprint", "dmf"]
[[rules.allowlists]]
description = "files that intentionally discuss the scrub pattern itself"
paths = [
    '''^\.gitleaks\.toml$''',
    '''^bin/scrub-public-repos\.sh$''',
    '''^bin/dmf-env-public-surface-gate\.sh$''',
    '''^bin/export-scan\.sh$''',
]
```

### Rationale

The `generic-api-key` rule's `docs/` blanket allowlist means a real API key
pasted into a doc goes undetected. This narrower rule targets the specific
resource-ID shapes that have already leaked, providing a safety net against
recurrence. UUID-shaped role_ids are not added as a rule because a UUID regex
would produce excessive false positives on legitimate UUIDs in code (commit
hashes are hex, not UUID, but other UUIDs exist in YAML configs). The role_id
scrub in Change 4 plus operational rotation is the correct control.

---

## Change 13 — Add trap handlers to `mktemp` calls missing them (M3, L2, L5, L6)

**Severity:** LOW / MEDIUM
**Files affected (4 files):**

### 13a. `bin/agentic/issue-migrate-to-github.sh` (line 107)

**Current:**
```bash
body_tmp=$(mktemp -t migrate.XXXXXX)
```

**Proposed:** Add immediately after the mktemp call:
```bash
trap 'rm -f "$body_tmp"' EXIT
```

Or better — move the `rm -f "$body_tmp"` that currently exists at the end of
the loop body into the trap handler, and add a loop-level cleanup:

```bash
body_tmp=""
_cleanup_migrate() { [ -n "$body_tmp" ] && rm -f "$body_tmp"; }
trap _cleanup_migrate EXIT
```

Then assign `body_tmp=$(mktemp -t migrate.XXXXXX)` inside the loop.

### 13b. `bin/generate-status.sh` (line 193, inside `collect_activity()`)

**Current:**
```bash
local tmp
tmp="$(mktemp)"
# ... usage ...
rm -f "$tmp"  # at function end
```

**Proposed:** The `rm -f "$tmp"` at function end is sufficient for the happy
path. Add a trap at function entry:

```bash
local tmp
tmp="$(mktemp)"
# shellcheck disable=SC2064
trap "rm -f '$tmp'" RETURN
```

Note: `RETURN` traps fire when the function returns (bash 4.4+). On macOS bash
3.2, this is unavailable — use an explicit `return` wrapper or accept the
leak on abnormal termination (the file is in `$TMPDIR` and cleaned by the OS).
**Recommendation:** Document this as a known macOS limitation; no code change
required beyond the existing `rm -f "$tmp"`.

### 13c. `bin/check-working-model-sync.sh` (line 64, inside `apply_block()`)

**Current:**
```bash
tmp="$(mktemp)" || return 1
# ... awk writes to $tmp ...
mv "$tmp" "$file"
```

**Proposed:** Add a cleanup trap at function entry:
```bash
apply_block() {
    local file="$1" tmp
    tmp="$(mktemp)" || return 1
    # shellcheck disable=SC2064
    trap "rm -f '$tmp'" RETURN
    # ... existing awk + mv ...
}
```

Same macOS bash 3.2 caveat as 13b. **Recommendation:** Same — document, no
code change required.

### 13d. `bin/agentic/agent-status.sh` (line ~110)

**Current:**
```bash
local tmp="${file}.tmp.$$"
```

**Proposed:** Replace with:
```bash
local tmp; tmp="$(mktemp "${file}.tmp.XXXXXX")"
```

---

## Change 14 — Fix TMPDIR shadowing in `publish-chart-to-ghcr.sh` (L4)

**Severity:** LOW
**File:** `bin/publish-chart-to-ghcr.sh`
**Line:** 72

### Current code

```bash
TMPDIR="$(mktemp -d)"
```

### Proposed code

```bash
_CHART_TMPDIR="$(mktemp -d)"
```

And update all subsequent references from `TMPDIR` to `_CHART_TMPDIR` within
the function (the cleanup trap at line 75 already uses the variable):

```bash
cleanup() {
  rm -rf "${_CHART_TMPDIR}"
  unset HELM_REGISTRY_CONFIG
  unset _CHART_TMPDIR
  unset GHCR_TOKEN
}
trap cleanup EXIT
```

### Rationale

Shadowing `TMPDIR` affects every subprocess spawned after the assignment
(including `mktemp` itself, Python's `tempfile`, etc.). Using a
distinctly-named variable avoids this side effect.

---

## Change 15 — Lock down retired `sync-to-github.sh` escape hatch (L7)

**Severity:** LOW
**File:** `bin/sync-to-github.sh`
**Line:** 15

### Current code

```bash
if [ "${ALLOW_RETIRED_SYNC_TO_GITHUB:-}" != "I_KNOW_THIS_IS_RETIRED" ]; then
```

### Proposed code

```bash
# RETIRED 2026-06-09. No override — use bin/export-scan.sh instead.
echo "sync-to-github.sh is RETIRED (2026-06-09) and PERMANENTLY DISABLED." >&2
echo "  Use bin/export-scan.sh for clean-history public imports." >&2
exit 1
```

Remove the `if` block entirely. The retired implementation below the exit
remains for reference but is now unreachable regardless of environment
variables.

### Rationale

The escape hatch allows any process that can set environment variables to
re-enable a script that pushes full git history (including pre-publish
credentials) to GitHub. Since the tool is retired and `export-scan.sh` is
the replacement, the escape hatch serves no legitimate purpose.

---

## Change 16 — Pin `npx` package in `render-bpmn.sh` (L8)

**Severity:** LOW
**File:** `bin/render-bpmn.sh`
**Line:** 26

### Current code

```bash
npx --yes bpmn-to-image --no-footer "$input:$output"
```

### Proposed code

```bash
npx --yes bpmn-to-image@0.6.0 --no-footer "$input:$output"
```

(Replace `0.6.0` with the current latest version verified via
`npm view bpmn-to-image version`.)

### Rationale

Pinning to a specific version prevents silent upgrades when npm resolves the
latest tag. A compromised future release would not auto-install. The version
pin should be reviewed and bumped deliberately.

---

## Change 17 — Add upper bounds to wizard-spike dependencies (L14)

**Severity:** LOW
**File:** `wizard-spike/pyproject.toml`

### Current

```toml
dependencies = [
    "pydantic>=2.0",
    "ruamel.yaml>=0.18",
]
```

### Proposed

```toml
dependencies = [
    "pydantic>=2.0,<3",
    "ruamel.yaml>=0.18,<0.19",
]
```

### Rationale

Open-ended lower bounds mean a future breaking release (pydantic 3.x,
ruamel.yaml 0.19) could silently install and cause runtime failures. Upper
bounds ensure only compatible minor/patch versions are installed. This is
especially important for pydantic which has had major-version breaking changes.

---

## Summary — Changes by priority

| Priority | Change | Severity | Effort | Files |
|----------|--------|----------|--------|-------|
| 1 | Fix Python interpolation injection in `issue-close.sh` | HIGH | Low | 1 |
| 2 | Fix Python interpolation injection in `issue-open.sh` | HIGH | Low | 1 |
| 3 | Fix `bash -c` injection in `export-scan.sh` | HIGH | Trivial | 1 |
| 4 | Replace OpenBao role_ids with placeholders | HIGH | Medium | 4 + rotate |
| 5 | Replace public cloud IPs with placeholders | HIGH | Medium | 7 |
| 6 | Replace Tailscale CGNAT IPs with placeholders | HIGH | Low | 2 |
| 7 | Replace cloud resource IDs with placeholders | HIGH | Trivial | 2 |
| 8 | Fix token-in-argv in agentic curl calls | MEDIUM | Medium | 5 |
| 9 | Add `dependabot.yml` | MEDIUM | Trivial | 1 (new) |
| 10 | Fix `shell=True` in skills docs | MEDIUM | Trivial | 1 |
| 11 | Add `.gitignore` patterns | LOW | Trivial | 1 |
| 12 | Add gitleaks rules for cloud resource IDs | LOW | Low | 1 |
| 13 | Add trap handlers to mktemp calls | LOW | Low | 4 |
| 14 | Fix TMPDIR shadowing | LOW | Trivial | 1 |
| 15 | Lock down retired script escape hatch | LOW | Trivial | 1 |
| 16 | Pin npx package version | LOW | Trivial | 1 |
| 17 | Add dependency upper bounds | LOW | Trivial | 1 |

**Total: 17 proposed changes across 28 unique files (including 1 new file).**

---

## Items deliberately NOT changed

| Finding | Reason for no change |
|---------|---------------------|
| L1: Missing `set -e` in 9 scripts | Deliberate design — scripts use manual exit-code checking; adding `-e` would break intended behavior |
| L12: Infrastructure topology in skills | These files are in the umbrella which has access controls; the information is needed for agent-assisted operations |
| L13: Test passphrase `montest-test-pass` | Sandbox-only, explicitly acknowledged as test fixture in the skill doc |
| L15/L16: Pre-commit/pre-push hook bypasses | Documented by design — CI is the enforceable backstop; hooks are advisory |
| M2: Sourcing operator-local files | Documented design — security depends on filesystem permissions, which is the correct trust boundary for operator-local tooling |
| INFO findings (I1–I5) | All documented, intentional design decisions |

---

## Estimated blast radius

- **Docs-only changes** (Changes 4–7): ~12 files, zero runtime impact,
  placeholder substitution is mechanical
- **Script changes** (Changes 1–3, 8, 13–15): ~12 files, all in `bin/agentic/`
  (mothballed, requires `DMF_AGENTIC_OVERRIDE=1` to run) plus 3 infra scripts
- **CI changes** (Change 9): 1 new file, additive only
- **Config changes** (Changes 11, 12): 2 files, additive rules/patterns
- **Python changes** (Change 17): 1 file, dependency constraint tightening
- **Doc-only skill change** (Change 10): 1 file, example code in prose

No change modifies the public API surface, cluster state, or cross-repo
contracts.
