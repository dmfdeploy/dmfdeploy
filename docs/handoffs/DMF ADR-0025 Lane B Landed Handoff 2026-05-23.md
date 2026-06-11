# DMF ADR-0025 Lane B Landed Handoff

**Date:** 2026-05-23
**For:** next session picking up Phase 8 hygiene, chart 0.1.1, or Lane C runner-pod work
**Cluster verified:** `g2r6-foa9`

## TL;DR

ADR-0025 Lane B is landed and live-verified. `media-launch-nmos-cpp` now runs
inside an AWX EE pod through the DMF Catalog Container Group, installs the
NMOS-cpp Helm chart from in-cluster Zot, waits with an explicit
`kubernetes.core.k8s_info` readiness gate, then flips the NetBox lifecycle tag
to active. ADR-0016 Path A is fully superseded for `media-*` JTs and remains
canonical for 693-class infrastructure plays only.

The big lesson is not Helm, AWX, or NetBox. It is containerd image-pull DNS:
containerd pulls from the node host network namespace and cannot resolve
`*.svc.cluster.local` through CoreDNS. The working pattern is pinned Zot
ClusterIP + node `/etc/hosts` + containerd `certs.d/hosts.toml` plain-HTTP
override.

## What Shipped

### Phases 1-5 baseline

| Repo | Commit | What |
|---|---|---|
| `dmf-media` | `07d2df7` | Initial `charts/nmos-cpp/` Helm chart |
| `dmf-media` | `b954342` | `bin/publish-chart-to-ghcr.sh` wrapper |
| `dmf-runbooks` | `1630626` | Launcher/role rewrites for in-cluster Helm execution |
| `dmf-infra` | `a374471` | Phase 3 Stage 4b Zot seeding path |
| `dmf-infra` | `c45e14b` | AWX EE registration, Container Group, JT pin |
| `dmf-env` | `3a1bdb0` | g2r6-foa9 pre-flight bundle commit (private repo) |
| `dmfdeploy` | `f7a594f` | Umbrella chart publish helper |
| `dmfdeploy` | `8011f4e` | Lane B implementation plan |
| `dmfdeploy` | `72f9032` | ADR-0027 placeholder |
| `dmfdeploy` | `ec511a2` | Phase 6 amendment: containerd image-pull DNS |

### Phase 6 fix chain

| # | Repo | Commit | Fix |
|---|---|---|---|
| 1 | `dmf-infra` | `cf5ded4` | AWX controller cross-namespace pod-create RBAC |
| 2 | `dmf-infra` | `d0831cb` | k3s containerd `certs.d` for plain-HTTP Zot |
| 3 | `dmf-infra` | `efa9cd3` | awx-integration image defaults to cluster-internal Zot |
| 4 | `dmf-infra` | `eb36581` | Zot Service pinned ClusterIP + node `/etc/hosts` |
| 5 | `dmf-infra` | `b4822ae` | AWX controller `pods/attach` RBAC |
| 6 | `dmf-runbooks` | `c67c955` | Launcher NetBox URL + image overrides |
| 7 | `dmf-runbooks` | `dd1a400` | Explicit `k8s_info` readiness gate replacing broken Helm wait |

### Phase 7 retirement

- ADR-0025 promoted to Accepted.
- ADR-0016 amended: fully superseded for `media-*` JTs.
- Historical Move 1 Gate 2 plans now carry 2026-05-23 supersession banners.
- Parent convergence plan marks Lane B landed and Lane C still in flight.
- `dmf-runbooks` and `dmf-media` CLAUDE banners updated.
- Obsolete `dmf-infra` media runbook duplicates retired:
  `playbooks/runbooks/media-launch-nmos-cpp.yml` and
  `playbooks/runbooks/media-finalise-nmos-cpp.yml`.
- STATUS operator notes now record the landing.

## Verification Evidence

AWX job history:

```text
131 | media-launch-nmos-cpp | successful | 2026-05-23 11:48:16.649122+00:00 | 22.442
119 | media-launch-nmos-cpp | failed     | 2026-05-23 11:07:28.504054+00:00 | 316.377
114 | media-launch-nmos-cpp | failed     | 2026-05-23 10:39:44.445137+00:00 | 316.108
108 | media-launch-nmos-cpp | failed     | 2026-05-23 10:22:16.309337+00:00 | 315.900
```

Helm release:

```text
NAME      NAMESPACE  REVISION  UPDATED                                  STATUS    CHART           APP VERSION
nmos-cpp  nmos       4         2026-05-23 11:48:09.219543444 +0000 UTC  deployed  nmos-cpp-0.1.0  0.1.0
```

Workloads:

```text
pod/nmos-cpp-node-1-65f8d78646-xbk29   1/1  Running  0  125m
pod/nmos-cpp-node-2-585f7887bb-2k6kt   1/1  Running  0  125m
pod/nmos-cpp-registry-0                1/1  Running  0  116m

deployment.apps/nmos-cpp-node-1        1/1  image zot.zot.svc.cluster.local:5000/dmf/nmos-cpp-node:0.1.0
deployment.apps/nmos-cpp-node-2        1/1  image zot.zot.svc.cluster.local:5000/dmf/nmos-cpp-node:0.1.0
statefulset.apps/nmos-cpp-registry     1/1  image zot.zot.svc.cluster.local:5000/dmf/nmos-cpp-registry:0.1.0
```

NMOS Query API from an in-cluster pod:

```text
GET http://nmos-cpp-registry.nmos.svc.cluster.local/x-nmos/query/v1.3/nodes
200 bytes=1769
3 records returned; `nmos-mock-node-1` and `nmos-mock-node-2` present.
```

AWX controller target-namespace RBAC:

```text
role/awx-job-pod-manager in nmos:
pods: create, get, list, watch, delete
pods/log: get, list, watch
pods/exec: create
pods/attach: create
```

Zot image-pull plumbing:

```text
service/zot ClusterIP 10.43.165.105 port 5000

All three nodes:
10.43.165.105   zot.zot.svc.cluster.local # DMF-managed ADR-0025 Lane B node-side image pulls

hosts.toml:
server = "http://zot.zot.svc.cluster.local:5000"
[host."http://zot.zot.svc.cluster.local:5000"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
```

## Architectural Finding: Containerd Image-Pull DNS

This is the meta-lesson to carry forward.

ADR-0023 remains correct for pod-to-pod HTTP wiring: in-cluster clients should
use cluster-internal Service DNS instead of public ingress URLs. But container
image pulls are different. containerd resolves the image registry name on the
node before the pod exists, in the node host network namespace, using the
node's resolver. CoreDNS is not in that path. A ref such as
`zot.zot.svc.cluster.local:5000/dmf/awx-ee:0.1.0` fails on an otherwise
healthy cluster unless the node can resolve `zot.zot.svc.cluster.local`.

The durable fix now lives in base roles:

1. Pin the Zot Service `clusterIP`.
2. Write that ClusterIP into `/etc/hosts` on every node.
3. Write containerd `certs.d/<host>/hosts.toml` so the plain-HTTP Zot endpoint
   is allowed for pull/resolve.

This is robust to Zot pod movement because kube-proxy routes the ClusterIP on
each node. No node-local dependency and no MetalLB dependency.

## Systematic URL-Fix Pattern

Lane B also exposed a broader caller-location debt: any role default that used
to point at public ingress because Ansible was running outside the cluster may
need to become a cluster-internal Service URL when consumed by an in-cluster
EE pod.

Examples fixed in this lane:

- `netbox_api_url` for the launcher now uses the in-cluster NetBox Service URL.
- EE, NMOS registry, NMOS node, and chart defaults now point at in-cluster Zot.

Cross-reference:
`docs/plans/DMF Hardcoded Environment Literals Cleanup Plan 2026-05-19.md`.
Same class of debt; different vector. That plan tracks environment literals.
Lane B adds caller-location sensitivity: public URL for workstation/browser,
Service DNS for in-cluster pods, and node `/etc/hosts` for containerd pulls.

## Phase 7 Audit Outputs

Commands run with `.git` internals excluded:

```text
grep -rn 'launch-nmos-cpp' dmf-runbooks/ dmf-infra/ dmf-media/
```

Remaining matches are current catalog/JT/chart wiring or historical disabled
comments. The stale dmf-infra runbook duplicate files were deleted.

```text
grep -rn 'Path A' dmf-runbooks/ dmf-infra/ dmf-media/
```

Remaining matches are either 693-class-qualified or historical comment/banner
references.

```text
grep -rn 'ansible_host' dmf-runbooks/playbooks/
```

No matches.

## Open Items Rolled Forward

1. **Chart bump to 0.1.1.** `dmf-media/charts/nmos-cpp/values.yaml` still has
   placeholder image URLs (`registry.dmf.example.com/...`). The deployed
   launcher overrides them via `release_values`, so the live cluster works,
   but external chart consumers would get wrong defaults. Next steps: update
   values defaults to `zot.zot.svc.cluster.local:5000/...`, bump
   `Chart.yaml` to 0.1.1, republish to GHCR, re-seed Stage 4b, and bump
   `nmos_cpp_chart_version` in awx-integration defaults to `"0.1.1"`.

2. **`dmf-env/bin/run-playbook.sh` default bundle path bug.** The default
   `DMF_BOOTSTRAP_BUNDLE_DIR` still points at a `/Volumes/...` path that does
   not exist on this workstation. Operator workaround: set
   `DMF_BOOTSTRAP_BUNDLE_DIR` to the real workstation-local secure bootstrap
   bundle path before invoking the wrapper. Do not modify `dmf-env` from Codex
   without explicit operator direction.

3. **In-cluster Forgejo mirror posture.** Per ADR-0014 hybrid layout, the
   in-cluster Forgejo repo should be documented with `mirror=false` semantics
   where applicable and a manual refresh mechanism. Spell out whether the
   cluster repo is an AWX SCM source, a mirror target, or both for each repo.

4. **Broken `cronjob.batch/zot-mirror`.** `dmf-infra/roles/base/zot-mirror/`
   uses `--dst`, which is not valid for the pinned skopeo version. Verified
   current cluster residue: 7 failed `prewarm-zot-mirror-*` pods in `zot`.
   Fix the flag or pin a skopeo version that supports the intended syntax.

5. **Operator SSH config has stale Hetzner IPs.** Operator-managed file; Codex
   should not modify it. Flag only.

6. **`dmf-runbooks` `origin` remote still points at stale NXDOMAIN Forgejo.**
   It should be repointed to the operator's LAN Forgejo SSH alias form
   (`git@<lan-forgejo-ssh-alias>:<operator-user>/dmf-runbooks.git`) for
   consistency. This was out of credential-scrub scope.

7. **Credential scrub follow-up.** Credential-bearing URL slots were removed
   across the public-scope repos and `local` remotes now use the SSH alias.
   The obsolete credential-bearing `forgejo-lab` remotes were removed.
   Operator should rotate the affected LAN Forgejo password. `dmf-infra` still
   has 8 in-tree gitleaks hits (`flypack-offline-lane.md`,
   `netbox-deployment-notes.md`, `zot/tasks/main.yml`) that need triage before
   that repo can go public in Move 7.

## Lane C Status

Lane C, the runner-pod Phases 2-4 from
`docs/plans/DMF In-Cluster Ansible Runner Pod Implementation Plan 2026-05-14.md`,
is still in flight under the convergence parent plan. Lane B closure does not
block Lane C. It does prove the shared in-cluster execution pattern and gives
Lane C the image-pull DNS constraints it must inherit.

## Next-Session Pickup Signal

Pick up with Phase 8 hygiene, in this order:

1. Bump and republish `nmos-cpp` chart 0.1.1, re-seed Zot, then run
   `media-launch-nmos-cpp` once more.
2. Fix or explicitly park `zot-mirror` skopeo syntax.
3. Repoint `dmf-runbooks` `origin`.
4. Continue Lane C runner-pod work with the ADR-0025 containerd DNS lesson
   treated as a hard requirement, not an implementation detail.
