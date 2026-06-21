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

**Primary bottleneck: CPU / control-plane scheduling latency.** Disk fsync is *not*
the dominant signal, and memory/zram pressure is a secondary amplifier — but neither
is fully exonerated (see counter-evidence below). Independently reproduced by codex on
the live node (see cross-check, §5).

Evidence captured live on the constrained env `<constrained-env>` / node `<lan-ip>`
(concrete env id + IP in operator-local state, not committed here), during a later
`configure` run (so load was only ~5, yet the signatures were already present):

| Signal | Reading | Interpretation |
|---|---|---|
| Load average | `4.96 / 5.10 / 7.87` on 4 cores | sustained ~2x oversubscription; post-seed peaked at 8+ |
| etcd `apply request took too long` | **873/day**, lease grants up to **1.57s** (expected 100ms) | apiserver read/write path stalling |
| etcd `slow fdatasync` | **1/day** | SSD (`sda`, ROTA=0) keeps up on fsync — not the primary bottleneck |
| kubelet `ExecSync ... DeadlineExceeded timeout 3s` | **253/day** (`ak healthcheck`, Authentik `pg_isready` at 5s) | health probes time out under CPU starvation |
| kubelet `Housekeeping took 1.872s` | **22/day** | kubelet itself starved |
| vmstat | little/no IO-wait, no active si/so, MemAvailable ~3.5GiB, no OOM kills | rules out disk-IO-bound and OOM as primary |
| etcd DB size | 14MB | tiny — not an etcd-growth problem |
| k3s flags | plain `server --cluster-init` + audit logging | **no kube/system-reserved, no systemd `CPUWeight`/`IOWeight`** |
| Memory | ~305MB free, ~171MiB–1GB zram in use | tight; zram compression adds CPU tax (amplifier) |

**Counter-evidence to keep in the verification window (disk/IO is a real secondary):**
the 12:00 etcd snapshot took **14.5s to stream 14MB**, and audit logging is non-trivial
(live `audit.log` ~33MiB, rotated dir ~1.1GiB). Not enough to make disk primary, but it
means raising control-plane IO priority and trimming audit are both load-bearing.

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

> **Implementation invariant (load-bearing — codex P1):** all k3s server/kubelet
> args and systemd `[Service]` properties on this node already flow through **one
> owner** — the audit-logging role replaces `ExecStart` wholesale
> (`roles/base/k3s/templates/k3s-audit-logging.conf.j2`) and `300-k3s.yml` (≈L281–318)
> warns that drop-in must preserve `--node-name` and `--cluster-init`. Every change
> below must be **additive through that existing template path** (`k3s_server_args` /
> `k3s_kubelet_args` / the audit drop-in), never an independent last-writer-wins
> drop-in, or the next restart silently loses audit or reservation flags.

### Tier 1a — Protect the control plane (low risk, highest leverage)

Goal: under CPU/IO contention the kernel serves the control plane first.

- **Additive systemd `[Service]` properties on the existing k3s ExecStart owner**
  (cgroup v2 active):
  - `CPUWeight` — raise above the default 100 so the k3s/containerd subtree wins CPU.
    **Make it a tunable, start conservative (e.g. 500–1000), verify before going
    higher.** `CPUWeight=10000` is very aggressive: k3s *and* containerd share
    `/system.slice/k3s.service`, so a huge weight also favours image
    pull/decompression over pods and does **not** isolate etcd/apiserver from
    containerd work inside that subtree (that's what Tier 1b is for).
  - `IOWeight` — same treatment for block IO (the 14.5s snapshot stream says IO
    priority matters here).
- **Kubelet reservations via `k3s_kubelet_args`** so they render as
  `--kubelet-arg=kube-reserved=...` / `--kubelet-arg=system-reserved=...` (the repo
  mapping in `300-k3s.yml` ≈L71–99). **Do not** add raw `--kube-reserved` *server*
  flags unless `k3s server --help` proves that exact flag exists. Starting point
  (fits the live footprint: node requests ≈1755m CPU / 3820Mi under a reduced
  3-CPU / ~7Gi allocatable node):
  - `kube-reserved=cpu=500m,memory=512Mi`
  - `system-reserved=cpu=500m,memory=512Mi`

### Tier 1b — Throttle the image-pull storm (pairs with 1a, same slice)

- **containerd `max_concurrent_downloads` 1–2** via a constrained-node fragment under
  containerd's `config-v3.toml.d/` (the live generated config imports that dir; no
  max-concurrent is set today). Promoted into the first validation slice **because**
  raising `CPUWeight` on the shared cgroup otherwise favours image pulls over pods.

All of Tier 1 is gated on a constrained-node fact/profile so it does not penalise the
CAX21 lane.

### Tier 2 — Settle-gate the install (fixes the trigger)

- **Bounded control-plane settle gate between heavy app imports** in post-seed: prior
  app Ready **+** API `/readyz` responsive **+** no active AWX-operator reconcile storm
  (if detectable) **+** a short quiet period after the Zot seed / AWX. This is the real
  lever.
- **Then** lengthen rollout-wait timeouts + add retries so transient slowness doesn't
  needlessly fail/rerun the playbook. Pain relief, **not** the main fix — bigger
  timeouts alone only hide the symptom.

### Tier 3 — Cut per-request cost & flap

- **Trim apiserver audit logging during bootstrap** (currently on — synchronous IO per
  API call, ~1.1GiB rotated), re-enable after, or ship a minimal bootstrap audit policy.
- **Harden exec probes as a class on the constrained profile**, not just one app: the
  live offenders include `ak healthcheck` (3s) and Authentik `pg_isready` (5s). Raise
  `timeoutSeconds`/`failureThreshold`, or switch expensive exec probes to cheaper
  HTTP/TCP where the charts allow.
- **etcd snapshot/compaction tuning only if repeated fresh runs show the default k3s
  snapshot colliding with bootstrap.** No leader churn / DB growth / fsync collapse
  seen, so generic etcd flag tuning stays **out of Tier 1**.

---

## 3. Verification

Re-run a **fresh** constrained-node deploy end-to-end; post-seed completes on the
**first** attempt. Measure against a **bounded post-seed window** (capture a
`journalctl` cursor or absolute start/end timestamps) and report **rate + max**, not
`grep -c` over a whole day (which is not comparable run-to-run):

- apply-took-too-long rate, max lease-grant duration
- slow-fdatasync count, etcd snapshot + compaction durations (baseline: 14.5s snapshot)
- ExecSync timeouts (baseline 253/day), kubelet housekeeping warnings (baseline 22/day)
- pod restart deltas across the install storm
- pressure counters: `vmstat 1 5` (IO-wait, si/so), zram usage, node allocatable vs
  allocated requests/limits, cgroup `cpu.weight` for `k3s.service` vs `kubepods.slice`

Pass = first-attempt post-seed success **and** a clear drop in apply-stall rate /
ExecSync timeouts vs the recorded baseline.

---

## 4. Scope / sequencing

Revised order (per codex cross-check, §5):

- **Tier 1a + 1b together first** — additive `k3s.service` CPU/IO weight + kubelet
  reservations **and** containerd download throttle, because the shared k3s/containerd
  cgroup means the weight change is only safe alongside the throttle. Small, additive
  through the existing template owner, reversible. Validate this slice moves the needle
  before touching playbook orchestration.
- **Tier 2** (settle gates) spans multiple app playbooks; do it second, behind the same
  constrained-node profile gate.
- **Tier 3** is audit/probe/snapshot polish.

The v0.1 reproducibility slice targets Hetzner CAX21, so this is filed `v0.2`. Pull
into `v0.1-polish` if the Pi 4 constrained-node path becomes a committed target.

---

## 5. Cross-check (codex, 2026-06-21)

Independent adversarial review by codex (gpt-5.5) via agent-bridge. Verdict:
**CHANGES-NEEDED, core diagnosis directionally right.** codex re-ran the live read-only
checks and reproduced the counts (873 apply-stalls, 253 ExecSync timeouts, 22 kubelet
housekeeping, 1 slow-fdatasync, 14MB etcd DB, no OOM, no IO-wait). Findings folded into
this revision:

- **P1** scrub committed env id / LAN IP → placeholders (done).
- **P1** reservations must render as `--kubelet-arg=kube-reserved=...`, not raw server
  flags (Tier 1a).
- **P1** changes must be additive through the single audit ExecStart owner, preserving
  `--node-name`/`--cluster-init` (invariant box in §2).
- **P2** soften "not disk, not OOM"; keep 14.5s snapshot + ~1.1GiB audit as secondary
  IO evidence (§1).
- **P2** containerd throttle into the first slice; `CPUWeight=10000` too aggressive →
  tunable, start low (Tier 1a/1b).
- **P2** verification needs a bounded window + pressure counters (§3).
- **P3** probe hardening as a class incl. `pg_isready`; etcd tuning out of Tier 1 (§3).
