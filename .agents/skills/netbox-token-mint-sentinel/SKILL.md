---
name: netbox-token-mint-sentinel
description: Robust stdout capture pattern for NetBox token mints — avoids tail -n 1 fragility when manage.py shell emits banner lines
source: auto-skill
extracted_at: '2026-06-04T15:46:19.829Z'
---

# NetBox Token Mint — Sentinel Capture Pattern

## Problem

When minting NetBox tokens via `manage.py shell < script.py`, the shell
emits banner lines like `NNN objects imported automatically` before or
after the script output. Using `| tail -n 1` to capture the token grabs
the WRONG line when banner output is present, resulting in an empty or
corrupt token being persisted to OpenBao — the adapter pod CrashLoops
because the env var is empty.

**Discovered in:** FIX5 (2026-06-04). The PromSD token mint captured
empty stdout because `tail -n 1` grabbed a blank line after the banner.
The token WAS minted in NetBox (ORM worked), only the capture failed.

## Pattern

### 1. Python script: print with sentinel prefix

```python
print("PROMSD_TOKEN=" + TOKEN_PREFIX + token.key + "." + token.token)
```

The sentinel prefix (`<IDENTIFIER>=`) is a stable marker that will never
appear in banner output. Use a unique identifier per token type (e.g.,
`PROMSD_TOKEN=`, `AWX_TOKEN=`, `ADMIN_TOKEN=`).

### 2. Shell capture: grep + cut, not tail

```bash
/opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py shell < /tmp/nbs-token-promsd.py \
  | grep '^PROMSD_TOKEN=' | tail -n 1 | cut -d'=' -f2-
```

- `grep '^PROMSD_TOKEN='` — filters to only the sentinel line, ignoring all banners
- `tail -n 1` — safety if multiple sentinel lines exist (shouldn't happen, but defensive)
- `cut -d'=' -f2-` — strips the prefix, yields the bare token value

### 3. Why this works

| Output line | tail -n 1 | sentinel grep+cut |
|---|---|---|
| `1 objects imported automatically` | ❌ wrong line | ✓ ignored |
| (blank line) | ❌ wrong line | ✓ ignored |
| `PROMSD_TOKEN=v1_abc123.xyz789` | ❌ may or may not be last | ✓ matched |
| Any future banner variation | ❌ fragile | ✓ robust |

## Application

### In dmf-infra netbox-sot role

The token mints are in `roles/stack/operator/netbox-sot/tasks/main.yml`.
Each mint task sets a `<component>_token_cmd` fact that contains the
heredoc + shell command. Apply the pattern to both:
1. The `print(...)` line in the Python heredoc
2. The shell pipeline after `PY`

### Latent fragility in other token mints

As of 2026-06-04, these mints still use `| tail -n 1` (same latent
fragility, though they've worked in practice because their banner is
conditional):
- Admin token (line ~30)
- AWX token (line ~47)
- LibreNMS token (line ~64)
- Catalog token (line ~82)

Apply the sentinel pattern to these as a follow-up.

## Verification

After fixing, verify the token is captured correctly:
1. The downstream task should set `effective = <register>.stdout | trim`
2. Check that `effective | length > 0` (non-empty)
3. The token should match the format `<prefix><key>.<raw_token>`

## Why not JSON output?

An alternative (used by `698-cms-netbox-forgejo-tokens.yml`) is to print
JSON and parse with `jq`. This also works but is more complex for simple
token capture. The sentinel pattern is simpler and sufficient for single-
value output. Use JSON parsing only when the script emits multiple fields.
