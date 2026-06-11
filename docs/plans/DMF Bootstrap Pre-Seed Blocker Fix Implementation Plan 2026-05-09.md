---
status: executed
date: 2026-05-09
---
# DMF Bootstrap Pre-Seed Blocker Fix Implementation Plan

**Date:** 2026-05-09
**Status:** Implementation plan
**Scope:** `dmf-env`, `dmf-infra/k3s-lab-bootstrap`

## Goal

Unblock the `aliyun` pre-seed bootstrap run and make the bootstrap
stage boundary match the pre-Bao secrets design.

This plan implements the handoff in
`docs/handoffs/DMF Bootstrap Pre-Seed Two Blockers Handoff 2026-05-09.md`
and includes the live Aliyun CCM DaemonSet selector failure found during the
survey.

The first live rerun after the CCM fix also exposed a private Traefik chart
CRD ownership problem. That is included here because it blocks the same
pre-seed wrapper.

## Changes

### 1. Fix Aliyun CCM DaemonSet scheduling

Live state shows the Aliyun CCM DaemonSet at `DESIRED=0` because the manifest
uses:

```yaml
nodeSelector:
  node-role.kubernetes.io/control-plane: ""
```

The k3s nodes have:

```text
node-role.kubernetes.io/control-plane=true
```

Update `dmf-env/tasks/aliyun/ccm.yml` so the rendered upstream manifest selects
the live k3s label value. Re-running the pre-seed wrapper should then schedule
the CCM pod and let Traefik's `LoadBalancer` service reconcile.

### 2. Make `bootstrap-secrets.sh seed-bao` target the cluster over SSH

`seed-bao` and `seed-awx-control-node-ssh` currently call local bare
`kubectl`, which can hit the wrong context. Add a helper that runs:

```text
ssh <target> sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml ...
```

Target resolution:

1. `DMF_KUBECTL_SSH_TARGET`
2. first host under `[k3s_control]` in `inventories/<env>/hosts.ini`
3. fail closed

The existing stdin secret transport remains intact.

### 3. Restore the pre-seed/post-seed/configure boundary

Move these imports:

| Playbook | Current | Target |
|---|---|---|
| `vertical-security/110-authentik.yml` | pre-seed | post-seed |
| `vertical-security/190-breakglass-verify.yml` | pre-seed | remove until real verify exists |
| `vertical-security/191-zot-oidc.yml` | pre-seed | configure |

Pre-seed should end after OpenBao, network policies, and ESO. No
`app-admin-facts` caller should run before `seed-bao`.

### 4. Add post-seed guard

At the start of `bootstrap-provision-post-seed.yml`, assert that OpenBao has:

```text
secret/platform/bootstrap_admin
secret/platform/k3s/cluster
```

This prevents accidental first-run use of `lifecycle-provision.yml` from
installing Layer 6 apps before the bundle has been seeded.

### 5. Keep private Traefik from installing cluster CRDs

The private Traefik role deploys a second Traefik instance. The bundled k3s
Traefik install already owns the cluster-scoped `traefik.io` CRDs. During the
live rerun, the upstream chart attempted to install newer Gateway API CRDs and
failed on Kubernetes `v1.30.6+k3s1` because those CRDs use a CEL function that
is not available on this cluster.

Set the private Traefik Helm release to skip CRD installation. The role should
only install the second namespaced controller and NodePort service.

### 6. Map Aliyun Tailscale inventory to the role contract

The pre-seed wrapper exports `vault_tailscale_authkey` from the pre-Bao
bootstrap bundle. The Aliyun inventory must map that value into
`tailscale_authkey` and use the role's `tailscale_headscale_url` /
`tailscale_hostname` variables. Otherwise `321-tailscale.yml` still behaves as
if it depends on the old OpenBao export path.

### 7. Add temporary kernel CVE mitigations

Add a host-platform playbook for the May 2026 Linux local privilege escalation
issues:

| Vulnerability | CVE | Mitigation |
|---|---|---|
| Copy Fail | `CVE-2026-31431` | block and unload `algif_aead` |
| Dirty Frag | `CVE-2026-43284`, `CVE-2026-43500` | block and unload `esp4`, `esp6`, `rxrpc` |

The playbook installs persistent `/etc/modprobe.d` rules, regenerates initramfs
when available, unloads currently loaded modules, and fails if any mitigated
module remains loaded. Wire it into pre-seed immediately after hardening so the
node is mitigated before Kubernetes workloads are installed.

### 8. Avoid repeated apt cache refresh hangs during reruns

`200-baseline.yml` already refreshes apt cache with `cache_valid_time: 3600`.
Keep the harden role's package install from forcing another cache refresh during
close reruns. This avoids hanging all three nodes in apt transport processes
after a previous targeted Tailscale install added the Tailscale apt source.

Also bound apt acquire timeouts before the baseline cache refresh and expose
`baseline_update_apt_cache`. First boot still refreshes apt by default; live
reruns after targeted package-source changes can pass
`-e baseline_update_apt_cache=false` to avoid a redundant cache refresh.

### 9. Skip provider-id metadata lookup on installed k3s nodes

After Tailscale is up, the Aliyun metadata endpoint can be unreachable from the
node because the tailnet uses the same CGNAT range family. The provider ID is
only needed while installing k3s. Add a pre-check for `/usr/local/bin/k3s` and
skip the metadata fetch on already-installed nodes; fresh installs still fetch
metadata before Tailscale is installed.

### 10. Cache the Aliyun CCM manifest during reruns

The Aliyun CCM provider task rendered the same upstream manifest every run but
forced a fresh download. During live reruns, node DNS/network conditions can
make that fetch fail even when `/tmp/aliyun-ccm-<version>.yml` already exists.
Explicitly check the cached manifest first, skip `get_url` when present, and
bound any first-run download with a timeout.

### 11. Avoid private Traefik Helm repo access on installed reruns

After Tailscale is installed, Aliyun metadata/DNS addresses in `100.100.0.0/16`
overlap Tailscale's CGNAT space and outbound DNS can time out. The private
Traefik release is already installed on reruns, so check `helm status` first and
skip the network-backed repository/upgrade path when the release exists. The
deployment readiness check remains the source of truth after the skip.

### 12. Avoid cert-manager remote CRD/Helm access on installed reruns

Cert-manager is installed before Tailscale on fresh runs, but live reruns may
already have Tailscale up. Check the existing Helm release and
`certificates.cert-manager.io` CRD first. Skip the remote CRD URL and
network-backed Helm upgrade when cert-manager is already present; downstream
issuer/certificate readiness checks remain active.

### 13. Pin Aliyun host DNS before Tailscale joins

Aliyun nodes receive DHCP DNS servers in `100.100.0.0/16`:

```text
100.100.2.136
100.100.2.138
```

After Tailscale is active, those resolvers time out for normal host lookups,
while direct queries to Cloudflare and Google public DNS succeed. Add an
Aliyun-only Tailscale role option that writes a netplan DNS overlay for `eth0`
with DHCP DNS disabled and these resolvers:

```text
1.1.1.1
1.0.0.1
8.8.8.8
8.8.4.4
```

Apply and verify this before package installs, Helm repository access, or
Headscale registration in `321-tailscale.yml`. Keep the option disabled by
default in the generic role so other environments do not inherit Aliyun-specific
resolver policy.

Also disable the Tailscale role's apt cache refresh for Aliyun. The baseline
playbook owns cache refresh on fresh bootstrap, and forcing another refresh in
`321-tailscale.yml` can hang live reruns after the Tailscale apt source exists.

### 14. Keep nftables reloads idempotent

The Hetzner private-lane fix correctly avoided `flush ruleset` because k3s owns
separate iptables-nft tables. Live Aliyun inspection showed the follow-on
problem: reloading `/etc/nftables.conf` without replacing the DMF-owned table
appends duplicate `inet filter` rules. Update the harden template to destroy
and recreate only `table inet filter`, and remove the Tailscale role's redundant
runtime nftables append/reload tasks. The harden role remains responsible for
the persistent `iifname "tailscale0" accept` rule.

### 15. Bound post-bootstrap verifier Kubernetes writes

The full pre-seed rerun hung at the `kubernetes.core.k8s` namespace-create task
inside `base/post-bootstrap-verify`, even though read-only `k8s_info` calls and
plain `kubectl` calls remained healthy. Convert the verifier's write/delete
operations to `k3s kubectl apply/delete` with stdin manifests, and keep
`k8s_info` for bounded read/wait checks. Targeted `301-k3s-verify.yml` then
passes pod-to-pod, Service DNS, Traefik ingress, LoadBalancer, and cleanup
checks.

### 16. Put SSH reliability settings in the active Ansible section

The repo already intended to disable SSH ControlPersist, but `ssh_args` lived
under `[defaults]`; Ansible's ssh connection plugin reads that key from
`[ssh_connection]`. Full pre-seed reruns still used `ControlMaster=auto` and
forced `-tt`, which left local SSH sessions open after remote modules exited.
Move `ssh_args` into `[ssh_connection]` and set `usetty = False` so long
bootstrap runs use fresh non-PTY SSH sessions with keepalives.

### 17. Make OpenBao break-glass paths environment-scoped

Aliyun's inventory set `openbao_key_path` with a `.json` suffix even though the
OpenBao role appends `.json` itself, and the role still wrote JuiceFS shares to
a hardcoded `openbao-breakglass/hetzner-lab` directory. Normalize the Aliyun
path to a suffixless basename, create the parent directory before saving init
output, and write share 1/2 to `openbao_breakglass_dir` derived from
`openbao_key_path`. Because the first Aliyun init reached `bao operator init`
before failing to save the keys, the live OpenBao PVC must be reset before the
next pre-seed attempt.

### 18. Use the shared lab wildcard domain

Aliyun app hostnames must use the shared `*.<lan-host>` domain, not the
environment-scoped `*.aliyun.<lan-host>` suffix. Set
`cert_manager_cluster_domain` to `<lan-host>`, update all app host vars to
that wildcard, and register Tailscale nodes as
`<inventory_hostname>.<lan-host>`. The next `321-tailscale.yml` run will
reconcile Cloudflare `*.<lan-host>` A records to the Aliyun tailnet IPs.

### 19. Env-scope share 3 Keychain service and the unseal script

Two follow-ups from §17. With env-scoped JuiceFS dirs in place, the remaining
collisions live on the OS Keychain and inside `bin/unseal-openbao.sh`:

- **Keychain service.** The openbao role wrote share 3 to a global
  `openbao-breakglass-share-3` service. Initializing aliyun would
  silently overwrite hetzner-arm's share 3. Introduce
  `openbao_keychain_share3_service` (default preserves the historical
  hetzner-arm name) and override per env. Aliyun:
  `openbao-breakglass-share-3-aliyun`. The role's preflight write
  test, share-3 write, share-1 `_notes` blurb, and assertion messages all
  reference the variable.
- **`bin/unseal-openbao.sh`.** Originally hardcoded `SHARE_DIR`,
  `SHARE_KEYCHAIN_NAME`, and `SSH_TARGET` to hetzner-lab. Accept an optional
  `[ENV_NAME]` first positional arg (mirrors `bin/run-playbook.sh`). When
  supplied, derive defaults from `inventories/<env>/`: `SHARE_DIR` from
  `openbao_key_path | dirname`, `SHARE_KEYCHAIN_NAME` from
  `openbao_keychain_share3_service` (fallback to the historical default), and
  `SSH_TARGET` from the first `[k3s_control]` host in `hosts.ini` (lookup
  `ansible_host` + `ansible_user` in `[k3s]`). Existing env-var overrides
  still take precedence; no-arg invocation preserves the hetzner-arm default
  for backward compatibility.

### 20. Env-scope USB shares 4+5

Same collision pattern as §19 but on the OPENBAO_A USB stick. The role
hardcoded `/Volumes/OPENBAO_A/share-{4,5}.json`; multi-env init would
overwrite. Introduce `openbao_usb_dir` (default `/Volumes/OPENBAO_A` —
preserves the historical flat hetzner-arm layout at the USB root) and let
each new env override to a per-env subdirectory. The role creates
`openbao_usb_dir` as `state: directory` before writing. Aliyun:
`/Volumes/OPENBAO_A/aliyun`. USB shares 4+5 are off the routine path
(re-init/rekey only), so this only matters when a fresh init runs against
a USB that already holds another env's recovery material.

### 21. Rename `aliyun-frankfurt` env to `aliyun`

`hetzner-arm` carries `arm` only because architecture matters for the
inventory; `frankfurt` is a region label and carries no operator-visible
distinction. Rename the env paths and content references to align with
the convention:

- `dmf-env/inventories/aliyun-frankfurt/` → `inventories/aliyun/`
- `dmf-env/manifests/aliyun-frankfurt.yaml` → `manifests/aliyun.yaml`
- `dmf-env/terraform/aliyun-frankfurt/` → `terraform/aliyun/`
- Cloud resource names (RAM role `dmf-infra-ccm-aliyun-frankfurt` →
  `dmf-infra-ccm-aliyun`, etc.) and the `openbao_keychain_share3_service`
  follow.

Historical handoff/review/question/session docs keep their original
filenames as a record of when the env was named `aliyun-frankfurt`.

### 22. seed-bao: temp-root via Shamir quorum for `secret/platform/*` writes

`bin/bootstrap-secrets.sh seed-bao` writes the pre-Bao bundle into OpenBao
at `secret/platform/*` and `secret/apps/*/admin`. The first end-to-end live
run on aliyun exposed three layered defects in the script and one
architectural gap:

- **`expand_local_path` tilde quoting bug.** The function used
  `${1#~/}` to strip a `~/` prefix; bash performs tilde expansion on the
  pattern itself, so the substitution silently no-ops and the
  `~/.ssh/id_ed25519_k3s_aliyun` key from the inventory expanded to
  `<home>/~/.ssh/id_ed25519_k3s_aliyun`. SSH then fell through to the
  default identity, which the Aliyun nodes don't authorise → the script's
  pod-finding `kubectl` returned non-zero with a misleading "no OpenBao
  pod found" error. Fix: quote the tilde — `${1#"~/"}`.
- **`remote_kubectl` lost arg quoting through SSH.** OpenSSH joins
  trailing args with single spaces and lets the remote shell re-parse the
  result; naive `ssh host cmd "$@"` corrupts any arg containing shell
  metacharacters. seed-bao's multi-line `sh -c '…'` script bodies (used
  to read stdin-fed secrets into local vars) were therefore split at
  newlines, with the lines after the first executing on the *control
  node* rather than inside the pod ("bash: line 5: bao: command not
  found"). Fix: shell-quote each arg via `printf '%q'` before joining
  into a single command string for ssh.
- **No auth on bao calls.** `bao kv put` ran with no `BAO_TOKEN` set,
  every write hitting 403. Inspecting the role's policies confirmed
  ops-admin (`app-admin-writer`) covers `secret/data/apps/*` only; no
  policy grants `secret/data/platform/*`. The role *did* already use the
  right pattern for elevated writes — see `120-ops-admin-rotation.yml`,
  which submits the 3 Shamir shares from the breakglass JSON to
  `bao operator generate-root`, captures a one-shot root token, performs
  the write, and revokes the token via `bao token revoke -self`.
  Mirroring that pattern in `cmd_seed_bao` and `cmd_seed_awx_ssh`:
  - `acquire_temp_root` reads the breakglass file path from inventory
    (`eso_openbao_breakglass_file` with fallback to
    `openbao_key_path + ".json"`), pulls the first 3 `unseal_keys_hex`,
    runs the cancel/OTP/init/submit/decode dance, and exposes the token
    in `BAO_ROOT_TOKEN`.
  - Every `bao kv put` and `bao kv get` is now invoked through a sh -c
    body that consumes `BAO_TOKEN` as the first stdin line and exports
    `BAO_ADDR=https://127.0.0.1:8200` + `BAO_TOKEN` before running bao.
  - `revoke_temp_root` runs `bao token revoke -self` with that token.
    Wired into a `trap … EXIT INT TERM` so an interrupted run still
    revokes.
- **Metadata-stamp step expected JSON, sops returned YAML.** Final
  cleanup pass that writes `metadata.last_seeded_to_bao_at` ran
  `sops --decrypt | python3 json.load`. The bundle is a `.sops.yaml`,
  so sops emitted YAML by default — Python choked on first character.
  Fix: decrypt with `--output-type json` and re-encrypt with
  `--input-type json --output-type yaml`.

Architectural rationale (option A from §22 design discussion): the
temp-root pattern keeps ops-admin scoped to apps, leaves a clean audit
trail (each seed event is a discrete generate-root + revoke pair), and
matches a pattern already proven and exercised in the role. Alternatives
considered:

- *Add a `bootstrap-seeder` policy granting `secret/data/platform/*` to
  ops-admin* — permanent privilege escalation on a long-lived identity;
  rejected on least-privilege grounds.
- *Skip root-token revocation during init* — leaves a long-lived root
  token in the breakglass JSON; regresses ADR-0011's mitigation; rejected.

### 23. Post-seed guard: narrow metadata-read capability for ops-admin

`bootstrap-provision-post-seed.yml` opens with a "seed boundary guard"
that reads `secret/platform/bootstrap_admin` and `secret/platform/k3s/cluster`
to fail closed if the operator hasn't run seed-bao yet. The first
post-seed run after the seed-bao fix surfaced the read counterpart of
the §22 gap: ops-admin's `app-admin-writer` policy has zero capability
on `secret/data/platform/*`, so the guard's `bao kv get` returned 403.

This is a different shape than seed-bao's writes — it's an
existence-only check that should fail closed, not a privileged write.
The narrowest fix is to switch the guard to `bao kv metadata get` and
extend `app-admin-writer` with `read` on exactly the two metadata paths
the guard inspects:

```hcl
path "secret/metadata/platform/bootstrap_admin" { capabilities = ["read"] }
path "secret/metadata/platform/k3s/cluster"     { capabilities = ["read"] }
```

`bao kv metadata get` returns version + created/updated timestamps only;
the secret data stays inaccessible to ops-admin. The grant is strictly
smaller than ops-admin's existing data-read on `secret/data/apps/*`.

Alternatives considered:

- *Temp-root via Shamir, mirroring seed-bao* — consistent but adds a
  generate-root + revoke ceremony to every post-seed run. Dilutes the
  audit-log signal that "elevated privilege was used here for a reason".
  Worth the cost for one-shot writes; not worth it for an existence
  check that runs on every invocation.
- *Operator-side timestamp check (`bundle.metadata.last_seeded_to_bao_at`)* —
  loses in-cluster verification: a stale bundle timestamp from a seed
  against a different cluster would let the guard pass. Rejected.

The role's `policy-reconciler` reapplies all policies on every openbao
role run, so the live cluster picks up the expanded policy on the next
pre-seed invocation — no manual `bao policy write` needed.

### 24. Post-seed ordering: Authentik before its OIDC consumers

§3 moved `vertical-security/110-authentik.yml` from pre-seed into
post-seed (to fix the seed-collision trap with `app-admin-facts`), but
landed it *after* the monitoring stack. The first end-to-end post-seed
run failed at `base/grafana : Read Grafana OAuth client credentials
from Authentik` — Grafana's role queries
`OAuth2Provider.objects.get(name="Grafana")` from Authentik at install
time, and Authentik wasn't running yet.

Authentik provisions OAuth2Providers via its blueprints
(`templates/blueprints/20-app-providers.yaml.j2`, applied by the role's
"Apply mounted Authentik blueprints via worker CLI" task). Every Layer 6
app that integrates with the identity graph (Grafana, Forgejo, NetBox,
AWX, …) therefore depends on Authentik having completed first.

Reorder post-seed so the identity base runs before the monitoring stack
and any other OIDC consumer:

1. `vertical-security/110-authentik.yml` (identity base + blueprints)
2. `vertical-monitoring/{100,110,120,130,190}*.yml` (monitoring incl. Grafana)
3. `playbooks/{600,610,620,640,650}*.yml` (Layer 6 apps)

No new code beyond the playbook reorder. Authentik's prerequisites
(ESO + bootstrap_admin in OpenBao + k3s ready) are all satisfied at the
top of post-seed, so promoting it to first place is safe.

### 25. seed-bao: per-app conventional username for `secret/apps/*/admin`

After §24 unblocked Authentik's install order, the next failure was
inside Authentik's own `common/app-admin-facts` call:

> Secret secret/apps/authentik/admin resolved username <operator>, expected akadmin.

The previous seed-bao app-local admin loop wrote
`username=${bootstrap_admin.username}` into every
`secret/apps/<app>/admin` path. Most app roles read whatever's there
and accept it, but two paths enforce a hardcoded convention:

- `vertical-security/110-authentik.yml` → `app_admin_expected_username: akadmin`
- `vertical-security/191-zot-oidc.yml` → `app_admin_expected_username: admin`

Update the per-app loop to use the conventional username while keeping
the shared bootstrap_admin password:

| App | Username written | Source of convention |
|---|---|---|
| `authentik` | `akadmin` | role hardcoded |
| `zot` | `admin` | 191-zot-oidc.yml expectation |
| `forgejo` / `netbox` / `awx` / `grafana` | `${bootstrap_admin.username}` | role default of `vault_bootstrap_admin_username` |

Both the write *and* the existence-collision check now compare against
the per-app expected username. When existing data has a different
username the script fails closed with a remediation hint pointing at
the `bao kv metadata delete` cleanup command — needed when an earlier
seed-bao left behind wrong data.

For the aliyun env, the wrong-username entries at
`secret/apps/{authentik,zot}/admin` were purged out-of-band before
re-running seed-bao.

### 26. Per-app admin username audit: install-role vs seed-bao vs consumers

§25 fixed the *seed-bao* side of the per-app convention but a follow-on
audit during the cms-push 401 made the asymmetry visible: each app has
*three* places where the local-admin username appears, and they have
to agree:

1. What the **install role** writes into the app's own auth backend
   (htpasswd / Django superuser / `awx-manage update_password` / etc.)
2. What **seed-bao** writes to `secret/apps/<app>/admin` in OpenBao
3. What **downstream consumers** expect when they read OpenBao to log
   in to the app (cms pushing to Zot, configure-stage OIDC overlays,
   `app_admin_expected_username` assertions in
   `common/app-admin-facts`)

| App | Install creates | seed-bao writes (§25 → §26) | Severity |
|---|---|---|---|
| `authentik` | `akadmin` (role hardcoded) | `akadmin` | already consistent |
| `awx` | `${vault_bootstrap_admin_username}` | `${admin_username}` | already consistent |
| `forgejo` | `${vault_bootstrap_admin_username}` | `${admin_username}` | already consistent |
| `netbox` | `admin` (Helm `superuser.name`) | was `${admin_username}` → now `admin` | data drift, fixed |
| `grafana` | `admin` (Helm chart default) | was `${admin_username}` → now `admin` | data drift, fixed |
| `zot` | was `${vault_bootstrap_admin_username}` → now `admin` | `admin` (§25) | functional bug, fixed |

The Zot mismatch was the actual blocker: cms's image push and
`191-zot-oidc.yml` both authenticate to Zot with the OpenBao-recorded
`admin/<password>`, but Zot's htpasswd was provisioned with
`<operator>:<password>`, so every push hit 401. Fix:

- **Zot install role**: hardcode `zot_admin_user: admin` (matches the
  convention; Zot is an internal registry without an
  operator-meaningful identity). Plus a sha256 of the htpasswd line as
  a pod template annotation, so any future credential rotation rolls
  the StatefulSet (Zot reads htpasswd at process start; mounted-Secret
  refreshes don't help).
- **seed-bao**: extend the per-app table — `zot|netbox|grafana → admin`,
  `authentik → akadmin`, others → `${admin_username}`.

NetBox + Grafana are documented as data-drift fixes only (their
consumers don't authenticate via username/password — NetBox uses an
API token, Grafana uses OIDC — so the wrong recorded value didn't
break anything). They're fixed for clarity and to avoid future
`expected_username` assertions tripping.

### 27. Zot htpasswd: replace passlib bcrypt with the htpasswd CLI

After §26 made the username consistent across install / OpenBao /
consumers, post-seed still failed at the cms image push with a 401.
Live diagnosis showed:

- htpasswd auth was correctly resolving the claimed username (`admin`).
- accessControl's `defaultPolicy: ["read","create","update","delete"]`
  was correctly authorising authenticated pushes.
- The actual problem: the **bcrypt hash in the `zot-htpasswd` Secret
  did not match the bundle's bootstrap_admin password**. Verifying with
  `htpasswd -v` showed every plausible candidate — bundle password,
  OpenBao-stored password, common defaults — failed.

Root cause: the role's `Generate bcrypt hash for admin password` task
used the Jinja `password_hash('bcrypt', rounds=10)` filter. That filter
goes through passlib, whose bcrypt backend raises `AttributeError` on
`bcrypt.__about__.__version__` against bcrypt 5.x (the controller's
pip-installed bcrypt is recent enough to have moved that attribute).
passlib traps the error and silently falls through to a different
backend; in observed runs the resulting hash did not verify against
the input password. The pre-seed log carries the symptom as
`(trapped) error reading bcrypt version` followed by a stacktrace, but
the task itself still reports `ok` so the silent corruption only
surfaces at the first authenticated push attempt.

Fix: shell out to `htpasswd -inB -C 10 <user>` instead of using
passlib's filter. `htpasswd` is part of apache2-utils on Linux, ships
with macOS, and produces a stable bcrypt hash. The password is fed via
stdin so it stays out of argv. The task delegates to localhost (where
the operator's `htpasswd` binary lives) and uses `no_log: true`.

For the live aliyun env, the htpasswd Secret was regenerated
out-of-band from the current bundle password (`htpasswd -nbB admin
$BUNDLE_PW`, base64-encoded into the Secret data, StatefulSet
rolled). The role-level fix prevents this from recurring on future
pre-seed reruns.

A speculative `adminPolicy` block added during diagnosis (suspecting an
authz issue rather than a bcrypt mismatch) was reverted once the real
cause was confirmed by toggling that block in/out of the live config
and observing push behaviour was unchanged.

## Reset checklist

Before the next aliyun pre-seed attempt the live cluster must be torn
down so the broken-init breakglass state cannot be reused:

1. Delete the LoadBalancer Services (`kube-system/traefik`,
   `traefik-private/traefik-private`) so the CCM deprovisions the
   Aliyun SLBs. With CCM degraded the SLBs may need to be deleted
   directly via `aliyun slb DeleteLoadBalancer` after disabling
   `DeleteProtection`.
2. `bin/tf-apply.sh aliyun destroy -auto-approve`.
3. Delete any `*.<lan-host>` Cloudflare A records pointing at the
   Aliyun tailnet IPs (100.64.0.13, .14, .15).
4. Delete the matching Headscale node entries
   (`headscale nodes delete --identifier <id> --force`).
5. Confirm no operator-side state remains:
   - `<secure-store>/openbao-breakglass/aliyun/` should not exist;
   - macOS Keychain should not hold an
     `openbao-breakglass-share-3-aliyun` entry;
   - the USB at `/Volumes/OPENBAO_A/aliyun/` should not exist;
   - hetzner-arm's USB shares at `/Volumes/OPENBAO_A/share-{4,5}.json`
     remain untouched.

## Verification

Static checks:

```bash
cd dmf-infra/k3s-lab-bootstrap
ANSIBLE_LOCAL_TEMP=/private/tmp/.ansible ansible-playbook --syntax-check bootstrap-provision-pre-seed.yml -i inventories/example/hosts.ini
ANSIBLE_LOCAL_TEMP=/private/tmp/.ansible ansible-playbook --syntax-check bootstrap-provision-post-seed.yml -i inventories/example/hosts.ini
ANSIBLE_LOCAL_TEMP=/private/tmp/.ansible ansible-playbook --syntax-check bootstrap-configure.yml -i inventories/example/hosts.ini
```

Secret-boundary checks:

```bash
cd dmf-env
env DMF_BOOTSTRAP_BUNDLE_DIR=<secure-store>/dmf-bootstrap bin/bootstrap-secrets.sh doctor aliyun
```

Live rerun:

```bash
cd dmf-env
export DMF_BOOTSTRAP_BUNDLE_DIR=<secure-store>/dmf-bootstrap
bin/run-playbook.sh aliyun ../dmf-infra/k3s-lab-bootstrap/bootstrap-provision-pre-seed.yml
```

The live rerun remains a deliberate operator action; this implementation pass
only prepares the code and runs static checks unless explicitly directed.
