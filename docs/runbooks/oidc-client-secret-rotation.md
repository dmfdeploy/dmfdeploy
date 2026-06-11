# OIDC Client Secret Rotation

**Status:** Operator-facing runbook. Procedure for rotating an OIDC
client_secret in Authentik and propagating the new value through
OpenBao / ESO / the consuming app's K8s Secret.

**When to run this procedure:**

1. **Incident response** — a client_secret value entered an agent
   transcript, screenshot, log file, chat window, or any other surface
   that ADR-0007 names as a leak vector. Per ADR-0007 rule 6, treat the
   secret as compromised for its lifetime and rotate immediately. In
   the experiment phase per [ADR-0004](../decisions/0004-experiment-phase-stance.md),
   the operator may choose to defer rotation on short-lived test envs
   (record the decision in STATUS HUMAN-START); for any environment
   serving real users or carrying Mode-B obligations
   ([ADR-0020](../decisions/0020-deployment-scope-and-regulatory-posture.md)),
   immediate rotation is binding.
2. **Scheduled rotation** — per ADR-0028 D8 operational hardening
   baseline (currently target, not yet automated). Each OIDC client
   should rotate on a fixed cadence to reduce the value of any
   undetected compromise.
3. **Personnel change** — when an operator's session is suspected
   compromised or when an operator leaves the team.

**Intent model:** [ADR-0028 — Identity and Authority Chain](../decisions/0028-identity-and-authority-chain.md);
[ADR-0007 — Secrets never in argv](../decisions/0007-secrets-never-in-argv.md);
[ADR-0015 — DMF Console passkey-only](../decisions/0015-dmf-console-passkey-only.md).

**Scope:** OIDC client_secret for any Authentik-managed provider. The
current canonical case is the **DMF Console** OIDC provider
(`oidc-dmf-console` in the Authentik blueprint), consumed by `dmf-cms`
via the `DMF_CONSOLE_OIDC_CLIENT_SECRET` environment variable. The
same procedure applies to any other Authentik OIDC client (NetBox,
Forgejo, Grafana, Zot, future apps) — substitute the provider name and
the consuming app's Secret path.

> **Secrets discipline (non-negotiable):** every step below pipes
> values via stdin or env-var scoped to the task. **No secret values
> in argv**, no echo to stdout, no scratch files in `/tmp` that
> persist beyond the rotation. ADR-0007 binds; the steps below
> conform.

---

## TL;DR

```bash
# Substitute: <env> with the live env (current: g2r6-foa9)
#             <provider> with the Authentik provider name (e.g. "DMF Console")
#             <secret-path> with the OpenBao path (e.g. secret/apps/dmf-cms/oidc)
#             <namespace>/<secret> with the consuming K8s Secret
#               (e.g. dmf-cms/dmf-cms-runtime)

# 1. Generate new secret (32-char random, never echoed).
NEW_SECRET=$(openssl rand -hex 32)

# 2. Update Authentik (via API; new secret on stdin, never in argv).
#    Requires Authentik admin token from OpenBao.

# 3. Update OpenBao at <secret-path>.client_secret = $NEW_SECRET
#    via bin/run-playbook.sh <env> <rotation playbook> -- or
#    manually with `bao kv patch` piped from stdin.

# 4. Force ESO reconciliation (the ExternalSecret will pick up the
#    new value and rewrite the K8s Secret; the consuming Deployment
#    rolls when the checksum changes).

# 5. Verify: login round-trip through the affected app; check that
#    Authentik returns the new client_id/secret pair when probed via
#    its admin API.
```

Steps below explain each phase in detail.

---

## Prerequisites

- OpenBao unsealed on `<env>`. If sealed, run the `dmf-openbao-unseal`
  skill procedure first.
- Authentik admin password retrievable via
  `dmf-env/bin/get-admin-cred.sh <env> authentik`.
- Operator workstation has `kubectl` access to `<env>` via Tailscale or
  direct (see `dmf-cluster-access` skill §1).
- The consuming app's deploy playbook is known
  (`dmf-infra/k3s-lab-bootstrap/playbooks/650-dmf-cms.yml` for the DMF
  Console case).

---

## §1. Generate the new secret

```bash
# In a fresh shell, never in the agent transcript.
NEW_SECRET="$(openssl rand -hex 32)"

# Verify length only — don't print the value.
[ ${#NEW_SECRET} -eq 64 ] || echo "ERROR: secret generation failed"
```

The 64-char hex format (32 bytes) is Authentik's canonical OIDC client
secret format. Adjust to the provider's documented format if
generalising to non-Authentik IdPs.

---

## §2. Rotate in Authentik

### Option A — Authentik admin UI (single rotation, one-time)

1. Log into Authentik at `https://auth.<cluster-domain>` as the
   operator passkey identity (or `akadmin` if break-glass needed).
2. Navigate to **Applications → Providers → `<provider>`**.
3. Click **Edit** → in the **Client Secret** field, paste the
   `$NEW_SECRET` value.
4. Click **Update**.
5. Verify the provider record shows the new secret's first few characters
   match (Authentik partially masks; full value is no longer retrievable
   via the UI after save).

### Option B — Authentik API (scriptable, ADR-0007 conformant)

```bash
# Read Authentik admin token from OpenBao (stdin-piped, never argv).
# Pattern documented in dmf-cluster-access skill §3.

# Update via PATCH on the provider endpoint.
AUTHENTIK_HOST=auth.<cluster-domain>
PROVIDER_PK=$(curl -fsSk -H "Authorization: Bearer $AUTHENTIK_TOKEN" \
  "https://$AUTHENTIK_HOST/api/v3/providers/oauth2/?name=<provider>" \
  | jq -r '.results[0].pk')

# PATCH with the new secret. The secret value goes in the JSON body via
# stdin (not as a command-line argument).
jq -n --arg s "$NEW_SECRET" '{client_secret: $s}' | \
  curl -fsSk -X PATCH \
    -H "Authorization: Bearer $AUTHENTIK_TOKEN" \
    -H "Content-Type: application/json" \
    --data-binary @- \
    "https://$AUTHENTIK_HOST/api/v3/providers/oauth2/$PROVIDER_PK/"
```

`NEW_SECRET` and `AUTHENTIK_TOKEN` are env vars in the operator's
shell; they never appear in `ps`-visible argv. The JSON body containing
the secret is piped via stdin (`--data-binary @-`).

---

## §3. Propagate to OpenBao

The OIDC client_secret should be stored in OpenBao at a per-app path
(canonical: `secret/apps/<app>/oidc.client_secret` or as documented in
the app's role). For DMF Console: stored under `secret/apps/dmf-cms/oidc`
(or wherever the dmf-cms role's `cms_oidc_client_secret_effective` reads
from — confirm against
`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/cms/tasks/main.yml`).

```bash
# Establish OpenBao operator session (see openbao-session role).
# Then patch the secret path.

bao_pod=$(kubectl -n openbao get pod \
  -l app.kubernetes.io/name=openbao -o jsonpath='{.items[0].metadata.name}')

# Pipe secrets via stdin into the pod. Token + new secret value
# travel via two-line stdin read; neither appears in argv.
printf '%s\n%s\n' "$OPENBAO_TOKEN" "$NEW_SECRET" | \
  kubectl exec -i -n openbao "$bao_pod" -- sh -c '
    IFS= read -r BAO_TOKEN
    IFS= read -r SEC
    export BAO_TOKEN
    bao kv patch secret/apps/dmf-cms/oidc client_secret="$SEC"
  '

# Verify (output is the secret metadata, not the value).
printf '%s\n' "$OPENBAO_TOKEN" | \
  kubectl exec -i -n openbao "$bao_pod" -- sh -c '
    IFS= read -r BAO_TOKEN
    export BAO_TOKEN
    bao kv metadata get secret/apps/dmf-cms/oidc
  '
```

---

## §4. Force propagation to the consuming app

If the consuming app uses ESO (External Secrets Operator), the
ExternalSecret will reconcile on its next refresh interval (typically
1 hour) and rewrite the K8s Secret with the new value. To force
immediate propagation:

```bash
# Force ESO refresh by deleting + recreating the ExternalSecret,
# or by patching its annotation to bump the refresh timestamp.

kubectl -n <namespace> annotate externalsecret <es-name> \
  force-sync="$(date -u +%s)" --overwrite
```

Then trigger a rollout of the consuming Deployment so it picks up the
new env var:

```bash
# For DMF Console: re-run the deploy playbook (canonical path),
# which patches the deployment checksum annotation and waits for the
# new pod to come up.
cd <umbrella>/dmf-env
DMF_BOOTSTRAP_BUNDLE_DIR="$HOME/secure/dmf-bootstrap" \
  bin/run-playbook.sh <env> \
  ../dmf-infra/k3s-lab-bootstrap/playbooks/650-dmf-cms.yml

# Or, for a lighter-weight roll, restart the deployment directly:
kubectl -n dmf-cms rollout restart deploy/dmf-cms
kubectl -n dmf-cms rollout status deploy/dmf-cms --timeout=180s
```

---

## §5. Verify

End-to-end functional check (the only check that proves the rotation
succeeded):

1. **Login round-trip** — open the consuming app's UI in a private
   browser window. Authenticate via OIDC. Confirm the login flow
   completes without error.
2. **Spot-check the consuming pod's env** does NOT carry the old
   secret value. (Don't print the env; just verify the deployment was
   rolled — a fresh `RESTARTS=0` and a recent `Age` on the pod is
   sufficient confirmation that ESO propagated and rolled.)
3. **Check Authentik's audit log** for the secret-rotation event. The
   event should show: actor = the operator's OIDC user (or
   `akadmin` if break-glass), action = `update_provider`, target =
   the provider PK. Authentik's log is at Authentik UI → **Events →
   Logs**.

---

## §6. Update records

After successful rotation:

- **STATUS HUMAN-START** — add a one-line entry to the umbrella STATUS
  marking the rotation timestamp + the provider rotated. Brief is fine.
- **If the rotation was triggered by an incident** (rule 1 of "when to
  run this procedure"), record:
  - The incident details: what surface the secret entered (transcript /
    log / screenshot / etc.) and the session/agent ID if relevant.
  - The decision to rotate (or for short-lived test envs, the
    explicit decision to defer per ADR-0004 — see "Experiment phase
    risk acceptance" below).
  - The rotation completion timestamp.
- **No need to update ADRs or architecture docs** unless the rotation
  surfaces a structural problem (e.g. ESO not propagating cleanly →
  separate investigation; the runbook itself doesn't change).

---

## §7. Experiment phase risk acceptance

Per [ADR-0004](../decisions/0004-experiment-phase-stance.md), the
operator may choose to defer rotation on short-lived experiment-phase
envs. When this happens:

1. **Document the decision** in STATUS HUMAN-START at the time of the
   incident.
2. **Bound the deferral** — only defer if the env will be torn down
   before the deferred risk could plausibly be exercised. Hetzner
   experiment envs (current: `g2r6-foa9`) typically have lifetimes of
   days to weeks; deferring rotation for an OIDC client_secret on such
   an env is bounded by the env teardown.
3. **Track the deferral** — note in STATUS that the rotation was
   deferred, the env, and the reason. When the env is torn down, the
   risk closes; record the closure.
4. **This option is NOT available** for any env serving real users,
   any env under Mode-B obligations
   ([ADR-0020](../decisions/0020-deployment-scope-and-regulatory-posture.md)),
   or any env that's part of a flypack (Mode C). For those, rotation
   is binding.

---

## §8. Roll back if needed

If the rotation breaks login (most common: ESO didn't propagate, or the
deploy didn't roll cleanly):

1. **Stop new logins** — don't propagate the broken state further. The
   OIDC client_secret in Authentik is the new value; downgrading
   Authentik is the rollback path.
2. **Revert in Authentik** — repeat §2 with the *previous* secret
   value. Note: the previous value is no longer recoverable from
   Authentik (it was overwritten in §2). The rollback requires a
   pre-rotation backup of the secret, which is NOT part of this
   procedure today — captured as an enhancement gap.
3. **Alternative: regenerate again** — issue a third value (`openssl
   rand -hex 32`), push to Authentik + OpenBao + force ESO + roll.
   Skips the rollback dependency entirely.

The third-value path is operationally cleaner; the rollback path
requires a backup discipline that this runbook does not yet establish.
Enhancement: add a backup-the-old-secret step before §2 to support
clean rollback. Tracked as a follow-on improvement to this runbook.

---

## Related procedures

- [`dmf-openbao-unseal`](../../.claude/skills/dmf-openbao-unseal/SKILL.md)
  — required if OpenBao is sealed before this procedure can run.
- [`dmf-cluster-access`](../../.claude/skills/dmf-cluster-access/SKILL.md)
  §3 — read-only operations against the live cluster, including the
  stdin-pipe pattern for credential retrieval.
- [`dmf-cms-build-and-release`](../../.claude/skills/dmf-cms-build-and-release/SKILL.md)
  — adjacent procedure for releasing new dmf-cms images.
- [ADR-0028 D8](../decisions/0028-identity-and-authority-chain.md) —
  the operational hardening baseline that makes scheduled rotation
  binding.
