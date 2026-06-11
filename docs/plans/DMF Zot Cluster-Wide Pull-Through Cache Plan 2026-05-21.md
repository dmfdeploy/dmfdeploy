---
status: historical
date: 2026-05-21
---
# DMF Zot Cluster-Wide Pull-Through Cache — Plan Stub

**Status:** Idea — not committed. Captured 2026-05-21 from a sizing
discussion during a rollout. Awaiting an owner.

## Context

Today Zot's role in the DMF Platform is **the registry for DMF-built
images** (push-mode): `awx-ee`, `dmf-cms`, `nmos-cpp-{registry,node}`.
Total footprint ~2GB. The test-posture PVC was sized 15Gi
(`init-wizard.sh` POSTURE map, commit `8959f15`); production 20Gi.

The open architectural question — surfaced when sizing Zot for
g2r6-foa9 — is whether to broaden Zot's role to **cache every image
the cluster pulls**, not just DMF-built ones. Concretely:
configure containerd `/etc/rancher/k3s/registries.yaml` to mirror
upstream registries (docker.io, ghcr.io, quay.io, registry.k8s.io)
through Zot, with Zot in pull-through proxy mode.

This is orthogonal to ADR-0025 (cluster-internal Ansible + Catalog
Helm) — that ADR moved the *DMF-built* EE image into Zot as a runtime
mirror; this plan would extend the same pattern to *every* image.

## Why it might matter

1. **Flypack-offline (ADR-0022).** Offline operation strictly requires
   every image to be available locally. Pull-through caching seeded
   ahead of disconnect is the obvious mechanism.
2. **Supply-chain audit.** A single registry to audit (Zot) instead of
   four upstream registries. Image provenance lives in one place.
3. **Bandwidth.** Hetzner/Aliyun → upstream pulls cost time on every
   pod restart; pull-through after first warm-up is fast.
4. **Upstream-availability resilience.** If quay.io has a bad day, the
   cluster keeps working off Zot's cache.

## Open questions (intentionally not answered here)

- **Mechanism.** Zot pull-through proxy (transparent, requires
  containerd config) vs. explicit seed playbook (operator maintains
  the canonical image list). Pull-through wins for breadth; explicit
  seed wins for flypack-offline determinism.
- **Scope.** Every env, or just `flypack-offline`? If every env, the
  per-cluster Zot footprint dominates (40-60Gi); if just offline, the
  online clusters keep the 15Gi test posture.
- **Sizing target.** With history, 50Gi+. Without history, ~12Gi for
  the current Helm stack version set. Need a retention policy (Zot
  has built-in garbage collection).
- **TLS / auth.** Upstream registries vary (GHCR uses tokens,
  docker.io has rate limits, k8s.gcr.io is open). Pull-through needs
  upstream-creds management — likely belongs in OpenBao.
- **Cache invalidation.** Image tag mutations (`latest` etc.) need
  policy. DMF's image discipline (ADR-0005, immutable tagged
  releases) helps but doesn't cover upstream chaos.
- **Storage class.** 50Gi×2 Longhorn replicas on test-class nodes is
  >50% of usable capacity. Production-class nodes or a different
  storage backend (NFS share? object-storage-backed Zot?) needed.

## Sizing reference (compressed image+layers, deduped, ~2026)

| Component | Estimated footprint |
|---|---|
| Authentik (server + worker + postgres + redis) | ~1.2 GB |
| NetBox (netbox + postgres + valkey + housekeeper) | ~1.5 GB |
| AWX (operator + web/task/postgres/receptor) | ~2.5 GB |
| Forgejo (+ postgres) | ~0.5 GB |
| Longhorn (~10 images) | ~2.0 GB |
| cert-manager + ESO + OpenBao + Traefik | ~0.5 GB |
| Prometheus stack + Grafana + Loki | ~1.2 GB |
| DMF-built (awx-ee + dmf-cms + nmos-cpp×2) | ~2.0 GB |
| **One full version set** | **~11 GB** |
| With 3-5 version iterations + GC margin | ~25-40 GB |

## Cross-references

- [ADR-0022 — Flypack-online thin edge agent](../decisions/0022-flypack-online-thin-edge-agent.md) (offline-lane sibling)
- [ADR-0025 — Cluster-internal Ansible + Catalog Helm](../decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md) (DMF-built image runtime mirror)
- [DMF Public Container Registry Publishing Plan](DMF%20Public%20Container%20Registry%20Publishing%20Plan%202026-05-19.md)
  (GHCR = canonical for DMF-built; Zot = runtime mirror)
- `dmf-env/bin/init-wizard.sh` POSTURE_ZOT_STORAGE_SIZE — current
  test=15Gi / production=20Gi. Both posture values move up if/when
  this plan promotes.

## Recommended next step

Spike: configure containerd `registries.yaml` on a throwaway env to
mirror docker.io through Zot in pull-through mode. Measure cache-miss
vs cache-hit pull latency. Decide based on data whether the
operational win justifies the storage cost.

Out of scope for current g2r6-foa9 rollout.
