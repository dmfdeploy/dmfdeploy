# DMF Console Passkey-First Login — Investigation & Fix

**Date:** 2026-05-04  
**Scope:** dmf-cms OIDC login flow vs Authentik passkey configuration

## Problem statement

User expects passkey-only authentication on DMF Console (dmf-cms). Two symptoms observed:

1. **Username/login window still appears** — user sees a credential form instead of an automatic passkey challenge
2. **Passkey must be entered twice** — the passkey browser prompt appears multiple times per login session

## Investigation methodology

1. Read dmf-cms backend auth code (`main.py`, `security.py`, `authentik.py`, `settings.py`)
2. Read dmf-cms frontend auth flow (`App.tsx`, `auth.ts`)
3. Checked live cluster: `kubectl -n dmf-cms logs deploy/dmf-cms` (300 lines)
4. Checked live Authentik: `kubectl -n authentik logs deploy/authentik-server` (200 lines)
5. Inspected Authentik blueprints ConfigMap (`authentik-blueprints`) — full YAML
6. Ran `ak shell` on authentik-server to trace `default-authentication-flow` stages
7. Reviewed Ansible playbook OIDC provider configuration (`cms/tasks/main.yml`)

## Root cause: `prompt=login` OIDC parameter

**File:** `dmf-cms/src/dmf_cms/main.py`, line ~180, in the `/auth/login` handler.

The `/auth/login` endpoint builds an OIDC authorization URL with `prompt_login=True`, which adds `prompt=login` to the query string sent to Authentik.

### What `prompt=login` does

Per the OIDC spec, `prompt=login` tells the identity provider to **force the user to re-authenticate**, even if they have an existing session. This bypasses Authentik's smart passkey-first behavior:

| With `prompt=login` (current) | Without `prompt=login` (expected) |
|---|---|
| Forces full auth flow from scratch | Respects existing session + passkey state |
| Shows identification → password → MFA stages | Shows identification → passkey challenge (password skipped for passkey users) |
| User: type username → see password field → use passkey | User: type username → passkey challenge → logged in |
| Ignores `webauthn_stage` binding on identification stage | Uses `webauthn_stage` to offer passkey immediately |

### Why the "double passkey" happens

The Authentik logs show 3 separate login cycles within the log window. Each cycle:

1. dmf-cms `/auth/login` → 302 to Authentik with `prompt=login`
2. User authenticates (username + passkey via forced flow)
3. Authentik callbacks to dmf-cms `/auth/callback` → stores session → 302 to `/`
4. Next page load: `/api/me` returns 401 (session not yet propagated or browser cache issue) → triggers another `/auth/login` redirect

The `prompt=login` parameter amplifies this because it forces a full re-auth even when Authentik has a valid session cookie, creating unnecessary round-trips.

## Authentik configuration — verified correct

The blueprints in `authentik-blueprints` ConfigMap are properly configured:

### `default-authentication-flow` stages (order of execution)

| Order | Stage | Purpose |
|---|---|---|
| 10 | `default-authentication-identification` | Username entry + passkey WebAuthn trigger |
| 20 | `default-authentication-password` | Password input (for users without passkeys) |
| 30 | `default-authentication-mfa-validation` | MFA validation |
| 100 | `default-authentication-login` | Session creation |

### Identification stage wiring (the key config)

The blueprint `16-passwordless-bootstrap.yaml` sets on `default-authentication-identification`:

```yaml
webauthn_stage: !KeyOf dmf-passkey-login-validation
passwordless_flow: !KeyOf dmf-passkey-login-flow
enrollment_flow: !Find [authentik_flows.flow, [slug, dmf-bootstrap-passkey-enrollment]]
```

This means: after the user enters their username, Authentik checks if they have a WebAuthn passkey registered. If yes → trigger the `dmf-passkey-login-validation` stage (passkey challenge). If no → fall through to the password stage.

**This is the correct passkey-first configuration.** The `prompt=login` parameter from dmf-cms is the only thing preventing it from working.

### DMF Console OIDC provider

```yaml
authentication_flow: !Find [authentik_flows.flow, [slug, default-authentication-flow]]
```

All OIDC providers (Forgejo, NetBox, Grafana, LibreNMS, Zot, DMF Console) use `default-authentication-flow`. This is intentional — the same passkey-first behavior should apply to all apps.

## Files changed

### 1. `dmf-cms/src/dmf_cms/main.py` — remove `prompt_login=True`

The `/auth/login` handler calls `build_authorize_url(..., prompt_login=True)`. Remove this argument.

### 2. `dmf-cms/src/dmf_cms/security.py` — remove `prompt_login` parameter

The `build_authorize_url()` function accepts and processes `prompt_login`. Remove the parameter and the conditional that sets `query_params["prompt"] = "login"`.

### 3. `dmf-infra/.../20-app-providers.yaml.j2` — switch DMF Console to passkey-only flow

The DMF Console OIDC provider's `authentication_flow` is changed from
`default-authentication-flow` to `dmf-passkey-login`. This is the
decisive fix: the identification stage (which renders the username
field) is bypassed entirely. Users go straight to WebAuthn validation.

**Codified as ADR-0015.**

## Expected behavior after fix

| Scenario | Before | After |
|---|---|---|
| User with passkey logs in | Username → password field → passkey | Username → passkey challenge → logged in |
| User with passkey + active Authentik session | Forced re-auth (prompt=login ignores session) | Silent OIDC redirect (no interaction) |
| Break-glass user (no passkey) | Username → password → logged in | Username → password → logged in (unchanged) |
| Logout → re-login | Full re-auth cycle | Fresh identification → passkey challenge |

## Cluster procedure

After deploying the fix:

```bash
# Rebuild and push image
cd ~/repos/dmfdeploy/dmf-cms
scripts/sync-version.sh --check  # confirm VERSION is current
# (build + push happens via playbook 650-dmf-cms.yml)

# Deploy to cluster
cd ~/repos/dmfdeploy/dmf-env
bin/run-playbook.sh hetzner-arm ../dmf-infra/k3s-lab-bootstrap/playbooks/650-dmf-cms.yml

# Verify
cd ~/repos/dmfdeploy/dmf-cms
scripts/verify-cluster.sh

## Trade-offs

- **Risk:** Removing `prompt=login` means users with a valid Authentik session will get a silent login (no interaction). This is the desired behavior for passkey-first UX.
- **Break-glass:** Users without passkeys (`akadmin`, `break-glass`) will still see the password field — the identification stage's `webauthn_stage` only triggers passkey for users who have one registered.
- **Security:** `prompt=login` was a belt-and-suspenders measure to ensure session freshness. The Authentik session cookie expiry and the dmf-cms session middleware (`SessionMiddleware` with `same_site="lax"`) provide sufficient session management without forcing re-auth on every visit.

## Test results

### v0.6.1 (prompt=login removal)

| Check | Result |
|---|---|
| Pod image | `registry.dmf.example.com/dmf-cms:0.6.1` ✓ |
| VERSION match | Local 0.6.1 == cluster 0.6.1 ✓ |
| Healthz | 200 OK, auth_mode=oidc ✓ |
| `prompt=login` in redirect | **Gone** ✓ |

### v0.6.1 + passkey-only flow (dmf-passkey-login)

| Check | Result |
|---|---|
| Provider auth flow | `dmf-passkey-login` ✓ |
| UX (iOS Safari) | "Sign In" button → passkey popup → logged in ✓ |
| Username field | **Gone** ✓ |
| Password field | **Gone** ✓ |

### Rollback plan

If the passkey-only flow causes issues for users without passkeys:

```bash
# Revert provider to default flow
ssh k3s-admin@<control-node-public-ip> "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n authentik exec deploy/authentik-server -- ak shell -c '
from authentik.providers.oauth2.models import OAuth2Provider
provider = OAuth2Provider.objects.get(name=\"DMF Console\")
provider.authentication_flow_id = \"default-authentication-flow\"
provider.save()
'"

# Or re-run the blueprint (will reset to dmf-passkey-login)
cd ~/repos/dmf-env
bin/run-playbook.sh hetzner-arm ../dmf-infra/k3s-lab-bootstrap/playbooks/vertical-security/110-authentik.yml
```
