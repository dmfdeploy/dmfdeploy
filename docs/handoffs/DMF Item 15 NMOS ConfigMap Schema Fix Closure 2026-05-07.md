# DMF Item #15 — nmos-cpp ConfigMap Schema Fix — Closure

**Date:** 2026-05-07
**Author:** session following Gate 2 Open Followups Handoff (2026-05-06)
**Status:** DONE

---

## TL;DR

Item #15 (handoff 2026-05-06) closed. The nmos-cpp registry and mock node
pods now start cleanly, register with each other, and serve the NMOS
Query API at HTTP 200. Two root-cause bugs were found beyond the
placeholder schema; three fixes total.

---

## What was wrong

Three separate bugs prevented the pods from starting:

1. **Placeholder ConfigMap keys:** `host`, `port`, `logging` — these aren't
   recognized by the nmos-cpp binary. Upstream source (Sony nmos-cpp,
   `Development/nmos/settings.h`) defines real keys: `http_port`,
   `server_address`, `logging_level`, `registry_address`, etc.

2. **`--config=` prefix in Dockerfile CMD:** The nmos-cpp binary treats
   argv[1] as either inline JSON or a raw file path. It does NOT
   understand `--config=` flags. The Dockerfiles had
   `CMD ["--config=/config/registry.json"]` which caused the binary to
   look for a file at path `--config=/config/registry.json`.

3. **Missing `registration_port` in node config:** The node defaults to
   port 3210 for registration (compile-time default). The registry
   listens on port 80 (driven by `http_port: 80`). Without explicit
   `registration_port: 80`, the node tries to register at 3210 and
   times out.

---

## Changes made (dmf-runbooks repo)

### Commits (4)

| Commit | Files | What |
|---|---|---|
| `c4d7882` | `roles/nmos-cpp/defaults/main.yml`, `tasks/provision.yml` | Replace placeholder ConfigMap keys with real nmos-cpp schema (`http_port`, `server_address`, `logging_level`, `registry_address`, `label`, `description`). Add per-node ConfigMaps (`nmos-node-config-1`, `nmos-node-config-2`). |
| `2cb41aa` | `files/Dockerfile.registry`, `files/Dockerfile.node` | Remove `--config=` prefix from CMD. |
| `48a767a` | `tasks/provision.yml` | Add `registration_port: 80` to node config. |
| `a4ac4ed` | `tasks/configure.yml` | Set `imagePullPolicy: Always` on registry and node containers to prevent stale k3s cache. |

### Build/push script (new)

`roles/nmos-cpp/scripts/push-nmos-images.sh` — end-to-end build + Zot
push following the documented procedure in the README (isolated
DOCKER_CONFIG, OpenBao credential retrieval via `get-admin-cred.sh`,
cleaned up on exit).

---

## Verification

After final fix (AWX job 310 + manual image pull for registry):

```
NAME                               READY   STATUS
nmos-cpp-registry-0                1/1     Running
nmos-cpp-node-1-6f88db9db7-67r4d   1/1     Running
nmos-cpp-node-2-54fb94cc6-6nzqq    1/1     Running
```

- Query API: `GET /x-nmos/query/v1.3/nodes/` → 200, 3 nodes registered
- Devices: 2 devices, each with 8 senders + 8 receivers
- Health probe: `GET /x-nmos/query/v1.3/nodes/` → HTTP 200

Teardown (AWX `media-finalise-nmos-cpp`): workloads removed, namespace +
ConfigMaps + PVC preserved as designed.

---

## What's left in flight

**Item #12 (NetBox inventory CIDR fix)** — the `Set ansible_host to node
private IP` workaround is still in the launcher playbooks. It's harmless
and functional. The durable fix (NetBox custom field + inventory
`compose:` rule) should be done when a second catalog function joins
that also needs SSH to k3s nodes.

---

## Where this work lives

- `dmf-runbooks/roles/nmos-cpp/` — defaults, provision, configure,
  Dockerfiles, push script
- This handoff: `docs/handoffs/DMF Item 15 NMOS ConfigMap Schema Fix Closure 2026-05-07.md`
