---
status: executed
date: 2026-05-11
---
# DMF Secret Ownership and OpenBao Migration Plan

## Purpose

Move the DMF secret estate out of tracked files and ad hoc local shims into the
right durable secret stores, with OpenBao as the default runtime authority for
cluster and application secrets.

This plan covers both:

- the values that still need to be migrated
- the boundary rules for values that should never be copied into OpenBao

## Core Rule

If a value is needed by a running DMF cluster or one of its apps, and it is not
strictly bootstrap-only, it should live in the cluster’s OpenBao instance.

If a value is only needed before the cluster exists, it may remain in an
operator-local bootstrap shim until the first OpenBao instance is available.

If a value is break-glass material, it belongs in offline escrow, not in the
runtime vault.

## Secret Classes

### 1. Runtime secrets

These should live in in-cluster OpenBao KV v2:

- application admin passwords
- application API tokens
- service account tokens
- NetBox runtime tokens
- Forgejo admin/service tokens
- AWX service credentials
- monitoring app credentials
- cluster-local integration secrets

### 2. Bootstrap-only operator secrets

These may live outside OpenBao until the cluster is up, then should be copied
into OpenBao and the local bootstrap copy retired or treated as cache:

- cloud provider API tokens used to create the first host layer
- DNS provider tokens needed before the cluster exists
- Tailscale/Headscale bootstrap auth material if required during first
  provisioning
- one-time inventory seeding values that are only needed for the first apply

### 3. Offline break-glass material

These must not be moved into OpenBao as ordinary runtime data:

- OpenBao root token
- OpenBao unseal shares
- any recovery bundle that exists specifically for break-glass
- long-lived offline escrow data that is intentionally separated from the
  running cluster

## What Already Belongs in OpenBao

Some DMF values have already been moved or should be treated as already on the
path to OpenBao ownership:

- NetBox admin token in `secret/apps/netbox/runtime`
- NetBox-related API tokens created by the SoT playbook
- app admin secrets that are written by bootstrap playbooks into cluster
  runtime secrets
- cluster runtime secrets that ESO consumes after bootstrap

## Current Migration Status

### Already on the OpenBao path

These roles already know how to persist to in-cluster OpenBao when the
OpenBao metadata is present:

- `roles/stack/operator/netbox-sot`
- `roles/stack/operator/forgejo-bootstrap`
- `roles/stack/operator/awx-integration`

Those roles still have a `vault.yml` fallback path, but the OpenBao path is the
preferred runtime authority and is already wired in.

### Still bootstrap-local or env-vault-backed

These are still produced outside OpenBao during the current bootstrap flow:

- `vault_hcloud_token`
- `vault_cloudflare_dns_token`
- `vault_tailscale_authkey`
- `vault_k3s_token`
- `vault_zot_admin_password`
- `vault_awx_admin_password`

These need individual classification:

- `hcloud` and Cloudflare tokens are provider bootstrap inputs.
- `tailscale_authkey` is a provisioning input that may move into OpenBao if the
  cluster needs to re-use it after bootstrap.
- `k3s_token` is a first-bootstrap join secret and can retire after cluster
  bring-up.
- `zot_admin_password` and `awx_admin_password` are app-admin secrets and
  should ultimately become OpenBao runtime secrets.

### Still represented as repository metadata

These should stay as non-secret metadata or helper lookup values:

- `openbao_role_id` in `inventories/hetzner-arm/group_vars/all/openbao_secrets.yml`
- hostnames, namespaces, and service names
- URLs that do not grant access by themselves

## What Still Needs a Review

The current environment still has bootstrap generation paths that create values
locally before the cluster exists:

- `vault_hcloud_token`
- `vault_cloudflare_dns_token`
- `vault_tailscale_authkey`
- `vault_k3s_token`
- `vault_zot_admin_password`
- `vault_awx_admin_password`
- `vault_alertmanager_ntfy_url`
- `vault_alertmanager_watchdog_url`

Those are not all equally sensitive, and they do not all belong in the same
place permanently. The migration should classify them individually:

- provider tokens used only for first provisioning can remain as operator-side
  bootstrap inputs until the first cluster exists
- once OpenBao is available, values that the cluster or its apps will reuse
  should be copied into OpenBao and fetched from there on later runs
- non-secret URLs or descriptors can stay in git if they do not grant access
- some of the repo bootstrap roles already support OpenBao persistence, but the
  env-vault fallback still exists and must be retired only after the new path is
  proven on rerun

## Source-of-Truth Matrix

| Value class | Bootstrap source | Durable source of truth |
|---|---|---|
| Cloud provider token | local operator shim | OpenBao if reused after first provisioning |
| DNS provider token | local operator shim | OpenBao if reused after first provisioning |
| Tailscale authkey | local operator shim | OpenBao if the cluster needs it post-bootstrap |
| K3s join token | generated locally for first bootstrap | OpenBao or cluster runtime secret after bootstrap |
| App admin passwords | local seed generation only | OpenBao KV v2 |
| App API tokens | local seed generation only | OpenBao KV v2 |
| NetBox runtime token | bootstrap role | OpenBao KV v2 |
| OpenBao root token | init ceremony | offline escrow only |
| OpenBao unseal shares | init ceremony | offline escrow only |

## Concrete Path Checklist

### Already wired in the environment manifest

- `secret/k3s-hetzner/credentials#hcloud_token`
  - owner: provider bootstrap
  - status: already consumed by the layer-1 / CCM path
- `secret/k3s-hetzner/credentials#cloudflare_dns_token`
  - owner: provider bootstrap
  - status: already consumed by cert-manager and DNS record workflows
- `secret/k3s-hetzner/credentials#alertmanager_ntfy_url`
  - owner: monitoring config
  - status: already consumed by Prometheus/Alertmanager
- `secret/k3s-hetzner/credentials#alertmanager_watchdog_url`
  - owner: monitoring config
  - status: already consumed by Prometheus/Alertmanager

### OpenBao-backed app paths already in use

- `secret/apps/netbox/runtime`
  - owner: NetBox runtime
  - status: already used by born-inventory and NetBox SoT
- `secret/apps/authentik/runtime`
  - owner: Authentik runtime
  - status: already used by the Authentik role
- `secret/apps/authentik/admin`
  - owner: Authentik admin bootstrap
  - status: app-admin role target
- `secret/apps/authentik/breakglass`
  - owner: Authentik break-glass
  - status: offline/exceptional access path
- `secret/apps/authentik/bootstrap-passkey`
  - owner: Authentik bootstrap enrollment
  - status: bootstrap-only operator path

### Still to migrate or prove

- `secret/k3s-hetzner/credentials#tailscale_authkey`
  - owner: cluster provisioning
  - target: OpenBao-backed provider secret path if we keep reusing it after bootstrap
- `secret/k3s-hetzner/credentials#k3s_token`
  - owner: first-cluster bootstrap
  - target: OpenBao-backed bootstrap secret if we want reruns to avoid local regeneration
- `secret/apps/forgejo/admin`
  - owner: Forgejo admin bootstrap
  - target: OpenBao when the fallback is retired
- `secret/apps/forgejo/runtime`
  - owner: Forgejo service integration
  - target: OpenBao when the fallback is retired
- `secret/apps/awx/admin`
  - owner: AWX admin bootstrap
  - target: OpenBao when the fallback is retired
- `secret/apps/awx/runtime`
  - owner: AWX service integration
  - target: OpenBao when the fallback is retired
- `secret/apps/zot/admin`
  - owner: Zot admin bootstrap
  - target: OpenBao when the fallback is retired

## Migration Sequence

### 1. Inventory the current secret surface

- list all `vault_*` variables and where they are written
- list all local config files and keychain entries used by wrappers
- list all runtime secrets already persisted in OpenBao
- identify every repo file that still contains a hardcoded credential or token
- verify the environment manifest references each OpenBao-backed path that is
  intended to be consumed by the bootstrap and runtime roles

### 2. Classify each value

- decide whether the value is bootstrap-only, runtime, or break-glass
- decide whether the durable home is OpenBao, operator keystore, or offline
  escrow
- remove any value from git if it is a live secret and not just metadata

### 3. Migrate runtime values into OpenBao

- write the value into the right KV path
- update the consuming playbook to read from OpenBao
- keep the old source only long enough to verify the new path
- prefer the existing `secret/apps/<app>/...` and
  `secret/k3s-hetzner/credentials` conventions instead of inventing new
  one-off mounts

### 4. Retire plaintext copies

- remove plaintext exports from tracked docs and repo files
- replace them with path references and wrapper instructions
- keep only non-secret identifiers in git

### 5. Verify reruns

- rerun bootstrap and app playbooks from a clean shell
- confirm the playbooks resolve from OpenBao rather than local plaintext
- confirm that a new cluster can still bootstrap from the documented seed path

## Boundary Rules

1. Do not store live DMF credentials in tracked markdown, YAML, or shell
   scripts.
2. Do not move break-glass root material into ordinary OpenBao KV paths.
3. Do not keep two independent long-lived secret stores for the same value.
4. If a value exists only for provisioning, document it as bootstrap-only and
   keep its lifetime short.
5. If a value belongs to the running cluster, OpenBao should own it.

## Expected Outcomes

- DMF repos remain usable without secret leakage in git
- bootstrap playbooks read runtime secrets from OpenBao where possible
- only bootstrap-specific inputs remain in local operator shims
- break-glass material stays isolated from runtime secret traffic

## Next Steps

1. Build a concrete inventory of every DMF secret-bearing input.
2. Map each input to its target store.
3. Move the runtime secrets into OpenBao-backed paths.
4. Delete or redact any tracked plaintext secret remnants.
5. Update the repo migration plan to require the secret migration cutover
   before repo hosting is considered complete.
