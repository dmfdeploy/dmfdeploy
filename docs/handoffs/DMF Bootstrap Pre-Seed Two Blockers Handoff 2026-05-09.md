# DMF Bootstrap Pre-Seed Rollout — Two Blockers Handoff

**Date:** 2026-05-09
**Audience:** Next session — assume zero prior context
**Scope:** `dmf-infra/k3s-lab-bootstrap/bootstrap-provision-pre-seed.yml` and
`dmf-env/bin/bootstrap-secrets.sh`
**Status:** Analysis complete, no code changes made. Two blockers must be
resolved before the aliyun-frankfurt pre-seed run can be trusted.

## Context

We are testing the pre-seed wrapper roll-out described in
`docs/plans/DMF Bootstrap Provision Configure Split Plan 2026-05-07.md`
(revision 5) against the new `aliyun-frankfurt` environment per
`docs/handoffs/DMF Aliyun Frankfurt Rollout Next Steps Handoff 2026-05-08.md`.

Two issues surfaced before Step 1 of that handoff could run cleanly. Both are
real, both block continuing, and the fixes are inside the plan's intent — no
design questions reopened.

## Blocker 1 — Authentik + Zot OIDC + breakglass-verify must move out of pre-seed

### What's in the wrapper today

`dmf-infra/k3s-lab-bootstrap/bootstrap-provision-pre-seed.yml:58-63`:

```yaml
# ── Vertical: Identity base ──────────────────────────────────────────────────
- import_playbook: playbooks/vertical-security/110-authentik.yml
  tags: [vertical-security, identity, authentik]
- import_playbook: playbooks/vertical-security/190-breakglass-verify.yml
  tags: [vertical-security, identity, verify, breakglass]
- import_playbook: playbooks/vertical-security/191-zot-oidc.yml
  tags: [vertical-security, identity, registry, authentik, oidc]
```

### Why this is wrong per the plan

Plan revision 5 (lines 372-401):
- Pre-seed ends at OpenBao + ESO + (optional) `120-network-policies`.
- "Authentik base install" is listed under **post-seed Layer 6 vanilla app
  installs** (line 397).
- `vertical-security/191-zot-oidc.yml` is explicitly listed under Phase 2
  "Move Existing Whole Playbooks" → **`bootstrap-configure.yml`** (line 593).
- `190-breakglass-verify.yml` is still a stub (Specific Fix #5,
  `vertical-security/190-breakglass-verify.yml:1-17`) — when implemented it
  belongs in `bootstrap-verify.yml`.

### Why this is also mechanically broken (the seed-collision trap)

This is the nastier reason. `app-admin-facts` is the role that 110-authentik
and 191-zot-oidc both call to populate `secret/apps/<app>/admin`:

`dmf-infra/k3s-lab-bootstrap/roles/common/app-admin-facts/tasks/main.yml:125-139`

```yaml
- name: Generate app-admin password when missing
  ansible.builtin.command:
    argv:
      - openssl
      - rand
      - -base64
      - "{{ app_admin_password_bytes | string }}"
  register: _app_admin_generated_password
  changed_when: false
  when:
    - (_app_admin_existing_data.password | default('')) | length == 0
    - app_admin_password_input | length == 0
  delegate_to: localhost
```

If `secret/apps/<app>/admin` is empty, the role generates a fresh random
password locally and writes it back to OpenBao.

Then `seed-bao` writes app-local compatibility copies from
`vault_bootstrap_admin_password` —
`dmf-env/bin/bootstrap-secrets.sh:687-694`:

```python
# Compatibility copies for transition — map app-local admin to shared bootstrap
if 'vault_bootstrap_admin_password' in vars:
    pw = vars['vault_bootstrap_admin_password']
    vars['vault_forgejo_admin_password'] = pw
    vars['vault_netbox_superuser_password'] = pw
    vars['vault_grafana_admin_password'] = pw
    vars['vault_awx_admin_password'] = pw
    vars['vault_zot_admin_password'] = pw
```

Combined with the plan's seed-collision policy (lines 884-890):

> - if a target path is absent, write it from the encrypted bundle
> - if a target path exists with the same value, do nothing
> - if a platform path exists with a different value, fail and require an
>   explicit rotate operation
> - **if an app-local admin path exists with a different value, fail and require
>   an explicit app-account migration play**

If 110-authentik or 191-zot-oidc runs before `seed-bao`:
1. `app-admin-facts` finds `secret/apps/{authentik,zot}/admin` empty.
2. Generates a random password, writes it back.
3. `seed-bao` later tries to write the bundle's bootstrap admin to the same
   path → collision policy fires → either fail-closed or (worse, depending
   on script branch) silently no-op, leaving Authentik admin and
   `secret/platform/bootstrap_admin` permanently out of sync.

Either outcome means we cannot seed cleanly. There is no benign reading.

### Required moves

| Playbook | From | To | Why |
|---|---|---|---|
| `vertical-security/110-authentik.yml` | pre-seed `:58` | `bootstrap-provision-post-seed.yml` | Layer 6 app install per plan; needs seeded `secret/platform/bootstrap_admin` for app-admin-facts |
| `vertical-security/190-breakglass-verify.yml` | pre-seed `:60` | drop import (stub); when real, → `bootstrap-verify.yml` | Cannot verify break-glass before Authentik exists |
| `vertical-security/191-zot-oidc.yml` | pre-seed `:62` | `bootstrap-configure.yml` | OIDC overlay per Phase 2 of plan; needs seeded admin + Authentik present |

### Required assertion

Per plan lines 705-708, `bootstrap-provision-post-seed.yml` must assert
`secret/platform/bootstrap_admin` and `secret/platform/k3s/cluster` exist in
OpenBao before any Layer 6 app install consumes local admin credentials.
This is the safety net for accidental first-run use of `lifecycle-provision.yml`
(the compatibility wrapper) on a not-yet-seeded cluster.

### Net effect after the fix

Pre-seed ends at: host platform → container platform → registry (htpasswd
only) → OpenBao installed/initialized/unsealed/policy-ready → ESO with
ClusterSecretStore → optional network policies. No `app-admin-facts` call
runs before `seed-bao` returns. Operator then proceeds to manual OpenBao
init+unseal (Step 2 of the aliyun handoff) and `seed-bao` (Step 3).

## Blocker 2 — `seed-bao` uses bare local `kubectl`

### What's there today

`dmf-env/bin/bootstrap-secrets.sh:721` (and 22 sibling call sites in
`cmd_seed_bao` / `cmd_seed_awx_control_node_ssh`):

```bash
bao_pod="$(kubectl get pods -n openbao -l app.kubernetes.io/name=openbao \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)" || { ... }
```

Bare `kubectl`. Resolves against operator-local kube context.

### Why this is broken

Operator's local kubectl currently points at `default` context (RPi homelab,
per `dmfdeploy/CLAUDE.md` "⚠️ Cluster Target" warning). For
`aliyun-frankfurt` there is no local kubeconfig entry by default — the
aliyun handoff papers over this in operator-facing prose by writing
`kubectl --context aliyun-frankfurt ...` in steps 2/3
(`DMF Aliyun Frankfurt Rollout Next Steps Handoff 2026-05-08.md:97,101,121,251`),
but `seed-bao` itself does not honor that, and silently running the script
today would either fail (no context) or execute against the wrong cluster.

### The established pattern

The rest of `dmf-env/bin/` already follows SSH → control-node →
`sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml`:

| Script | Pattern |
|---|---|
| `unseal-openbao.sh:60-63` | `ssh "$SSH_TARGET" sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n openbao exec ...` |
| `cluster-bootstrap-operator-approle.sh:68` | same SSH→sudo kubectl chain |
| `cluster-rotate-approle-secret-id.sh:70` | same |
| `app-admin-facts/tasks/main.yml:43-45,69-70` | `kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml` (Ansible already delegates to control node) |
| **`bootstrap-secrets.sh:721, 731, 757, 778, 794, 800, 823, 826, 836, 840, 852, 855, 865, 868, 878, 886, 902, 923, 992, 999, 1015, 1050`** | **bare `kubectl` against operator-local context** |

`bootstrap-secrets.sh` is the only outlier.

### Recommendation — match `unseal-openbao.sh`

Wrap every `kubectl` call in `cmd_seed_bao` and
`cmd_seed_awx_control_node_ssh` with:

```bash
ssh "$SSH_TARGET" sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml ...
```

The existing stdin chain
(`printf '%s' "$pw" | kubectl exec -i ... sh -c 'IFS= read -r P; bao kv put ...'`)
survives intact — `unseal-openbao.sh:84-88` already proves the pattern
works through SSH for stdin-fed secrets:

```bash
status="$(
    ssh -o LogLevel=ERROR "$SSH_TARGET" \
        sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml \
        -n "$OPENBAO_NAMESPACE" exec -i "$OPENBAO_POD" -- \
        sh -c 'IFS= read -r SHARE; bao operator unseal -format=json "$SHARE" 2>&1'
)" || { ... }
```

### SSH target resolution

Priority order (mirroring `unseal-openbao.sh:42`'s `OPENBAO_SSH_TARGET`):

1. `DMF_KUBECTL_SSH_TARGET` env override.
2. First `k3s_control` host from `inventories/<env>/hosts.ini`, parsed once
   per script invocation.
3. Hard fail with a message — **never** fall back to local `kubectl`.

A small helper in `bootstrap-secrets.sh` is fine for this iteration; longer
term it's a candidate for extraction since four scripts now do the same
dance.

### Scope note

This is the smaller scope change to unblock today. Don't widen into a
"refactor all four scripts onto a shared SSH helper" — that's a follow-up.

## Suggested order

1. **Fix Blocker 2 first** — mechanical, no design implications, can't
   `seed-bao` against Aliyun without it.
2. **Fix Blocker 1** — move the three imports, add the post-seed
   `bootstrap_admin` / `k3s/cluster` existence assertion per plan
   lines 705-708.
3. **Re-run pre-seed against `aliyun-frankfurt`** per Step 1 of
   `DMF Aliyun Frankfurt Rollout Next Steps Handoff 2026-05-08.md`. It
   should stop at OpenBao + ESO ready and exit cleanly.
4. **Continue with Step 2** (manual `bao operator init` + unseal — Q2
   parametrization is Phase B per N3).
5. **Continue with Step 3** (`bootstrap-secrets.sh seed-bao
   aliyun-frankfurt`). With Blocker 2 fixed, the script now talks to the
   right cluster via SSH.
6. **Continue with Step 4** (`bootstrap-provision-post-seed.yml` — now
   includes Authentik install).
7. **Continue with Step 6** (`bootstrap-configure.yml` — now includes
   Zot OIDC overlay).

## Files referenced

- `docs/plans/DMF Bootstrap Provision Configure Split Plan 2026-05-07.md`
  (revision 5)
- `docs/plans/DMF Pre-Bao Bootstrap Secrets Design 2026-05-08.md`
- `docs/handoffs/DMF Aliyun Frankfurt Rollout Next Steps Handoff 2026-05-08.md`
- `dmf-infra/k3s-lab-bootstrap/bootstrap-provision-pre-seed.yml`
- `dmf-infra/k3s-lab-bootstrap/playbooks/vertical-security/110-authentik.yml`
- `dmf-infra/k3s-lab-bootstrap/playbooks/vertical-security/190-breakglass-verify.yml`
- `dmf-infra/k3s-lab-bootstrap/playbooks/vertical-security/191-zot-oidc.yml`
- `dmf-infra/k3s-lab-bootstrap/roles/common/app-admin-facts/tasks/main.yml`
- `dmf-env/bin/bootstrap-secrets.sh` (lines 687-694, 721, plus 22 kubectl
  call sites in `cmd_seed_bao` and `cmd_seed_awx_control_node_ssh`)
- `dmf-env/bin/unseal-openbao.sh` (canonical SSH→sudo kubectl pattern,
  lines 42, 60-63, 84-88)
- `dmf-env/bin/cluster-bootstrap-operator-approle.sh:68`
- `dmf-env/bin/cluster-rotate-approle-secret-id.sh:70`

## Non-goals for this fix

- Do not redesign `app-admin-facts`. Its post-seed semantics (read existing,
  fall through to bundle, no random generation) is the target — but only
  after every caller runs post-seed.
- Do not extract a shared SSH-kubectl helper across all four `dmf-env/bin/`
  scripts. Worth doing eventually; not blocking.
- Do not parametrize `bin/unseal-openbao.sh` here — that's Phase B (N3 in
  the aliyun handoff).
- Do not touch `lifecycle-provision.yml` semantics — it remains the
  compatibility wrapper; the plan's required existence assertion covers
  the misuse case.
