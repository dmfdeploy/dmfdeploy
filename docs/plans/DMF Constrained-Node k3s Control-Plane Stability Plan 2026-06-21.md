---
status: draft
date: 2026-06-21
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/106
---
# DMF Constrained-Node k3s Control-Plane Stability Plan (2026-06-21)

**Status:** Draft (proposed, not started).
**Tracking:** [dmfdeploy/dmfdeploy#106](https://github.com/dmfdeploy/dmfdeploy/issues/106)
**Component:** `dmf-infra` (k3s role + sandbox bootstrap profile).
**Trigger:** Fresh `dmf-init` deploy onto a Pi 4 (4-core / 8GB) flaked during
**post-seed** — the playbook failed twice and only succeeded on re-run.

---

## 1. Root cause (diagnosed against the live node)

**CPU starvation of the k3s control plane — not disk, not OOM.**

Evidence captured live on env `35vv-m48a`, node `192.168.178.134`, during a later
`configure` run (so load was only ~5, yet the signatures were already present):

| Signal | Reading | Interpretation |
|---|---|---|
| Load average | `4.96 / 5.10 / 7.87` on 4 cores | sustained ~2x oversubscription; post-seed peaked at 8+ |
| etcd `apply request took too long` | **873 today**, lease grants up to **1.57s** (expected 100ms) | apiserver read/write path stalling |
| etcd `slow fdatasync` | **1 today** | SSD (`sda`, ROTA=0) keeps up — disk is *not* the bottleneck |
| kubelet `ExecSync ... DeadlineExceeded timeout 3s` (`ak healthcheck`) | recurring | health probes time out under CPU starvation |
| kubelet `Housekeeping took 1.872s` | recurring | kubelet itself starved |
| k3s flags | plain `server --cluster-init` + audit logging | **no `--kube-reserved`, no `--system-reserved`, no systemd `CPUWeight`/`IOWeight`** |
| Memory | ~305MB free, ~1GB in zram swap at peak | tight; zram compression adds CPU tax |

### Failure mechanism (why it is flaky, not deterministic)

1. post-seed (`bootstrap-sandbox-provision-post-seed.yml`) imports ~11 app
   playbooks back-to-back: authentik → landing → netbox → forgejo → **zot
   platform-image seed** → AWX → dmf-cms → prometheus/blackbox/loki/promtail/grafana.
   Each does apply + image pull + **rollout-wait**.
2. Concurrent image decompression + many pods scheduling + the AWX operator
   reconciling peg all 4 cores.
3. CPU-starved etcd/apiserver go latent (the 873 stalls). CPU-starved container
   exec blows the 3s probe deadline → kubelet restarts pods → they flap and never
   reach Ready inside the wait window.
4. Ansible rollout/Ready waits have finite timeouts → on the loaded run they expire
   before the app settles → the post-seed task fails.
5. Re-running succeeds because earlier apps are already settled, so the load storm
   is smaller. **Load-dependent timeout failure, not a code bug.**

### Secondary observation (track, don't fix here)

`/proc/uptime` indicated the node booted ~3.5h ago while the journal's first entry
was stamped 3 days earlier — Pi has no RTC, `fake-hwclock` restored a stale time and
chrony later stepped it forward. A clock step mid-deploy can transiently upset TLS
validation against the API. Secondary to the CPU story; note it in case it recurs.

---

## 2. Remediation (tiered)

### Tier 1 — Protect the control plane (low risk, highest leverage)

Goal: under CPU/IO contention the kernel serves the control plane first.

- **systemd drop-in on `k3s.service`** (cgroup v2 is active on the node):
  - `CPUWeight=10000` (default 100) — control plane wins CPU under contention.
  - `IOWeight=10000` — same for block IO.
- **`--kube-reserved` / `--system-reserved`** on the k3s server args so the
  scheduler keeps headroom for kubelet + etcd instead of packing the node to
  starvation. Starting point for a 4-core / 8GB node (tune with evidence):
  - `--kube-reserved=cpu=500m,memory=512Mi`
  - `--system-reserved=cpu=500m,memory=512Mi`

Lands in the dmf-infra k3s role (`300-k3s.yml` / role templates) gated on a
constrained-node fact/profile so it does not penalise the CAX21 lane.

### Tier 2 — Defuse the install thundering-herd (fixes the trigger)

- **Throttle containerd `max_concurrent_downloads` to 1–2** during seed (image
  pulls are the dominant IO/CPU spike). containerd config under the k3s role.
- **Settle-gate heavy app imports** in post-seed: don't start an app's neighbours
  while a prior operator (AWX especially) is still reconciling. Gate on prior-app
  Ready + a brief control-plane-latency check.
- **Generous rollout-wait timeouts + retries** on the k8s wait tasks so transient
  slowness doesn't fail the playbook (band-aid that removes re-run pain).

### Tier 3 — Cut per-request control-plane cost

- **Trim apiserver audit logging during bootstrap** (currently on — synchronous IO
  per API call), re-enable after, or ship a minimal bootstrap audit policy.
- **Harden probe budgets** on Authentik / AWX / dmf-cms: raise `timeoutSeconds`,
  `failureThreshold`, `initialDelaySeconds` so a 3s exec stall under load doesn't
  trigger a restart cascade.

---

## 3. Verification

- Re-run a **fresh** constrained-node deploy end-to-end; post-seed completes on the
  **first** attempt.
- During post-seed, `journalctl -u k3s | grep -c "apply request took too long"`
  drops sharply vs the baseline (873 in this run's window).
- No `ExecSync ... DeadlineExceeded` on health probes during the install storm.
- Load average stays bounded enough that etcd lease grants stay sub-second.

---

## 4. Scope / sequencing

- **Tier 1 first** — small, isolated, reversible (a systemd drop-in + two server
  flags). Validate it alone moves the needle before touching playbook orchestration.
- Tier 2 is the proper fix for the herd but spans multiple app playbooks; do it
  second, behind the same constrained-node profile gate.
- Tier 3 is opportunistic polish.

The v0.1 reproducibility slice targets Hetzner CAX21, so this is filed `v0.2`. Pull
into `v0.1-polish` if the Pi 4 constrained-node path becomes a committed target.
