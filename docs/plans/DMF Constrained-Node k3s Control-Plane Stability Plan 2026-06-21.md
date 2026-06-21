---
status: executed
date: 2026-06-21
executed: 2026-06-21
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/106
---
# DMF Constrained-Node k3s Control-Plane Stability Plan (2026-06-21)

> **EXECUTED 2026-06-21 — Tier 0 + SSH-resilience, live-verified.** The root cause
> (AWX-awake RAM exhaustion → kswapd thrash → k3s cycling → transient
> 6443/Forgejo/SSH refusals) is fixed by two changes in `dmf-infra`
> ([PR #20](https://github.com/dmfdeploy/dmf-infra/pull/20)):
> (1) the **await-asleep gate** — block the non-AWX configure phase until AWX
> Deployments actually reach `replicas=0`; (2) **SSH ConnectionAttempts + retries**
> so a transient refusal during the AWX-wake load can't abort the run.
> A full `bootstrap-sandbox-configure.yml` ran end-to-end on the Pi 4:
> **`ok=770 failed=0 unreachable=0 rc=0`, k3s `NRestarts` unchanged (no cycling).**
> The live run confirmed **Tier 1 (kube/system-reserved, CPU/IO weighting) and Tier 3
> are NOT required** for a clean run — they are optional defense-in-depth and are left
> as follow-ups (the awake consumer window is slow under AWX-awake load but survivable).
> Tiers below are retained for the design record.

**Status:** Executed 2026-06-21 — Tier 0 + SSH-resilience live-verified (see the EXECUTED note above).
**Tracking:** [dmfdeploy/dmfdeploy#106](https://github.com/dmfdeploy/dmfdeploy/issues/106)
**Component:** `dmf-infra` (k3s role + sandbox bootstrap profile).
**Trigger:** Fresh `dmf-init` deploy onto a Pi 4 (4-core / 8GB) flaked during
**post-seed** — the playbook failed twice and only succeeded on re-run.

---

## 1. Root cause (diagnosed against the live node)

> **UPDATED 2026-06-21 after running configure live (attempts 2–4): the dominant
> cause is RAM exhaustion, triggered by AWX being awake through configure.** The
> CPU-stall picture below is real but is the *downstream mechanism*; the upstream
> driver is memory. CPU weighting is therefore **not** the primary lever (you cannot
> `cpu.weight` your way out of `kswapd`). See §1a.

### 1a. Primary cause — AWX stays awake → RAM exhaustion → kswapd thrash → k3s cycling

Captured by driving `bootstrap-sandbox-configure.yml` directly from the dmf-init
container and instrumenting the node. The chain, fully observed:

1. configure's `awx-presence` role patches the AWX CR **asleep (`web/task_replicas:0`)
   then immediately awake (`replicas:desired`)** — back to back, with **no wait for the
   sleep to take effect** (role comment: *"ASLEEP — no waits"*). The AWX operator
   reconciles a sleep over **~6–10 min**, so the quick re-wake coalesces into "stay
   running." Worse: once the node is thrashing, the **operator is itself too starved to
   reconcile** — observed the CR at `replicas=0` while the Deployments were still `1/1`.
2. So AWX runs **awake through the whole memory-heavy second half of configure** (Zot
   OIDC, Forgejo, CMS wiring). Live RAM holders on the 8 GB node:
   `awx-manage 2140MiB + python ~1686MiB + gunicorn 774 + postgres 768 + k3s 587 +
   prometheus 402 + …` → **AWX awake ≈ 4–5 GB**, leaving **~46 MB free**.
3. The kernel falls into reclaim: **`kswapd0` pegged ~39% CPU**, **`%Cpu` ~45% sys /
   0% idle**, zram churning → **load 28–35 on 4 cores** for minutes (memory fine to OOM:
   no kernel OOM-kill; PSI not compiled in, but `top` is unambiguous).
4. Starved, **k3s's main process exits and `Restart=always` cycles it** —
   `NRestarts` 2→3, `ExecMainStatus=0`, `WatchdogUSec=0` (so **not** a systemd
   watchdog, **not** OOM-killer, **not** a panic; a clean exit under starvation).
5. Each k3s restart blips the apiserver + service proxy + ingress → the transient
   `127.0.0.1:6443` refusal (longhorn lookup), the Forgejo-ingress refusal
   (`forgejo.<...>/api/v1/version`), and the earlier SSH refusal — **whichever task
   lands in the restart window fails.** configure aborts → AWX never gets put back to
   sleep → next attempt walks into the same wall. **Load-dependent, not a code bug in
   the failing task.**

**Fix priority follows the chain:** keep AWX *actually* asleep through configure
(Tier 0) and give the node memory headroom (eviction/reserved) **first**; CPU/IO
weighting and per-request trims are secondary polish. Stabilising the live node took
exactly one action — scaling `awx-web`/`awx-task` to 0 freed ~4 GB and `kswapd`
dropped to 0% immediately.

### 1b. Downstream mechanism (the CPU-stall picture)

**Under the thrash, CPU / control-plane scheduling latency is what surfaces in logs.**
Disk fsync is *not* the dominant signal. Independently reproduced by codex on the live
node (see cross-check, §5).

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

### The configure-stage AWX wake is the peak spike (and an SSH-refusal trigger)

A second, sharper failure mode appears during `configure`: a task waiting on the AWX
web Deployment to become ready **after a wake** returned `UNREACHABLE` —
`ssh: connect to host <lan-ip> port 22: Connection refused` (run otherwise 532 ok /
0 failed).

This is the **AWX scale-to-zero wake**, by design. Per
[ADR-0043](../decisions/0043-workload-scale-to-zero-availability.md): the constrained
node "cannot hold AWX (~2 GiB across `awx-web` + `awx-task`) awake alongside everything
else," and the `awx-presence` role drives AWX **1→0→1→0 at phase boundaries** during
bootstrap. So the configure-stage wake is a deliberate **~2 GiB RAM + operator-reconcile
spike** on top of an already-tight node — it pushes memory into zram, taxes CPU, and is
the single heaviest moment of the whole deploy. **Keeping AWX awake through bootstrap is
*not* the fix — that is the 2 GiB RAM hog ADR-0043 exists to avoid (tested, too heavy);
the wake is necessary, it just has to be survivable.**

What actually happened to SSH (evidence, this run):
- **Not** sshd dying (`ssh.service` ActiveEnterTimestamp unchanged), **not** OOM (no
  kernel kills), **not** accept-queue overflow (`ListenOverflows`/`ListenDrops`/
  `SyncookiesSent`/`TCPBacklogDrop` all 0), **not** socket-activation. sshd was
  accepting logins seconds before and after.
- A hard `Connection refused` (RST / ICMP port-unreachable, not a timeout) with all of
  the above ruled out points at the **firewall layer**: the node carries 622 iptables /
  170 nft rules incl. hundreds of kube-proxy `KUBE-POD-FW ... -j REJECT --reject-with
  icmp-port-unreachable`, which kube-proxy rewrites repeatedly as pods churn during the
  wake. `icmp-port-unreachable` surfaces to the client as exactly "Connection refused".
  **Confidence: high** it was not sshd/resource exhaustion; **medium** on the
  kube-proxy-churn specifics (needs a live `conntrack`/`iptables` trace at the failure
  instant to confirm). Either way it is a **single-task transient**, not a node outage.

### Secondary observation (track, don't fix here)

`/proc/uptime` indicated the node booted ~3.5h ago while the journal's first entry
was stamped 3 days earlier — Pi has no RTC, `fake-hwclock` restored a stale time and
chrony later stepped it forward. A clock step mid-deploy can transiently upset TLS
validation against the API. Secondary to the CPU story; note it in case it recurs.

---

## 2. Remediation (tiered)

> **Order matters (updated after the live run): Tier 0 is the primary fix.** It removes
> the upstream RAM-exhaustion driver. Tiers 1–3 harden the node against residual
> pressure but do **not** substitute for Tier 0 — with AWX awake, no amount of CPU
> weighting saves an 8 GB node.

### Tier 0 — Keep AWX *actually* asleep through configure (primary, highest leverage)

The failing loop is: `awx-presence` patches AWX asleep then awake back-to-back with no
wait, AWX never sleeps, ~4–5 GB stays resident, the node thrashes, k3s cycles. Fix the
sequencing, in the `awx-presence` role + the configure orchestration (`dmf-infra`):

- **Gate "asleep" on *observed* termination, not the CR patch.** After patching
  `web/task_replicas:0`, wait until the AWX Deployments report `replicas:0` / pods gone
  before proceeding — the operator's reconcile is async (~6–10 min) and, under load,
  can stall entirely (observed CR=0 while Deployments=1/1). Don't trust the patch.
- **Don't wake AWX for non-AWX work.** Keep AWX asleep through the memory-heavy
  configure middle (Zot OIDC, Forgejo, NetBox, CMS non-AWX wiring). **Wake it last**,
  immediately before the AWX-integration + smoke-test steps that actually need it, and
  put it back to sleep right after.
- **Wake gently / one heavy thing at a time.** When the wake is unavoidable, quiesce
  other heavy churn first (don't overlap the wake with Longhorn/Forgejo/Zot work).
- **Failure leaves AWX asleep, not awake.** If configure aborts, AWX must not be left
  resident eating 4–5 GB into the next attempt (a `block/rescue` or always-sleep
  finaliser). Stabilising the live node was exactly this: scale `awx-web`/`awx-task` to
  0 → ~4 GB freed, `kswapd` to 0% instantly.

> Scope note: this lands in the `awx-presence` role — the #97 scale-to-zero area being
> live-tested. Treat the `ASLEEP — no waits` design as the defect to fix.

### Tier 1 — Memory headroom for the control plane (do alongside Tier 0)

> **Implementation invariant (load-bearing — codex P1):** all k3s server/kubelet
> args and systemd `[Service]` properties on this node already flow through **one
> owner** — the audit-logging role replaces `ExecStart` wholesale
> (`roles/base/k3s/templates/k3s-audit-logging.conf.j2`) and `300-k3s.yml` (≈L281–318)
> warns that drop-in must preserve `--node-name` and `--cluster-init`. Every change
> below must be **additive through that existing template path** (`k3s_server_args` /
> `k3s_kubelet_args` / the audit drop-in), never an independent last-writer-wins
> drop-in, or the next restart silently loses audit or reservation flags.

> **Demoted (live-run correction):** the **memory** levers below — `kube-reserved` /
> `system-reserved` with eviction thresholds — are the load-bearing part of Tier 1,
> because the failure is RAM-driven. The CPU/IO **weighting** (Tier 1a) is **secondary
> polish**: `kswapd`/reclaim CPU is kernel work that cgroup weight cannot deprioritise,
> so weighting helps only the residual non-thrash contention. Reconcile with the
> existing **"constrained-node worker right-sizing (issue #93)"** task already in
> configure — extend it rather than duplicate.

### Tier 1a — Protect the control plane **and sshd** (secondary; CPU/IO weighting)

Goal: under CPU/IO contention the kernel serves the control plane *and the management
plane (sshd)* first — workload pods yield, not the things the deploy needs to reach.

> **cgroup gotcha (load-bearing):** `cpu.weight` is **relative among siblings**. sshd
> lives in `/system.slice/ssh.service` (weight 100), a **sibling** of
> `/system.slice/k3s.service`. Raising **only** `k3s.service` weight rebalances CPU
> *toward k3s and away from sshd* — it would not help (and could hurt) SSH reachability,
> which is the management-plane symptom we just hit. Protect the whole picture:

- **Additive systemd `[Service]` properties** (cgroup v2 active), through the existing
  ExecStart owner for k3s:
  - `CPUWeight` on `k3s.service` — raise above the default 100 so the k3s/containerd
    subtree wins CPU over **workload pods** (`kubepods.slice`). **Tunable, start
    conservative (e.g. 500–1000), verify before going higher.** `CPUWeight=10000` is
    very aggressive: k3s *and* containerd share `/system.slice/k3s.service`, so a huge
    weight also favours image pull/decompression over pods and does **not** isolate
    etcd/apiserver from containerd work (that's Tier 1b).
  - **Also raise `ssh.service` `CPUWeight`** (e.g. match or exceed k3s) so the wake
    spike can't starve the very SSH that ansible/operators use to drive the node. This
    is the direct fix for the `Connection refused` symptom.
  - `IOWeight` — same treatment for block IO on both (the 14.5s snapshot stream says IO
    priority matters here).
  - The durable lever is `kube-reserved`/`system-reserved` (below): it caps
    `kubepods.slice` so the **whole** `system.slice` (k3s **and** sshd) keeps headroom,
    rather than fighting workloads weight-vs-weight.
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

### Tier 2 — Settle-gate the install + survive the AWX wake (fixes the trigger)

- **Bounded control-plane settle gate between heavy app imports** in post-seed: prior
  app Ready **+** API `/readyz` responsive **+** no active AWX-operator reconcile storm
  (if detectable) **+** a short quiet period after the Zot seed / AWX. This is the real
  lever.
- **SSH-transient resilience on the AWX-wake wait task.** The configure-stage AWX wake
  is a known, deliberate spike (ADR-0043, ~2 GiB) and momentarily knocked SSH over with
  a one-off `Connection refused`. Make that single task tolerant of a transient
  unreachable so a one-packet REJECT doesn't abort a 532-task run:
  - wrap the wake/readyReplicas wait in an ansible `retries` + `until` loop with a short
    `delay`, and/or scope a connection-level retry (`ansible_ssh_retries` / a
    `wait_for_connection` pre-step) around the wake boundary only.
  - this is targeted resilience for a predictable spike, **not** a blanket timeout bump.
- **Then** lengthen rollout-wait timeouts + add retries so transient slowness doesn't
  needlessly fail/rerun the playbook. Pain relief, **not** the main fix — bigger
  timeouts alone only hide the symptom.

> **Not a fix:** keeping AWX awake through bootstrap. ADR-0043 is explicit that the
> node cannot hold AWX (~2 GiB) awake alongside everything else (tested); scale-to-zero
> *is* the load-reduction strategy. The wake is necessary to verify presence — the goal
> is to make the wake **survivable**, not to remove it.

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

Wake-specific check: the configure-stage **AWX wake** completes without an
`UNREACHABLE`/`Connection refused` on the wait task. If a refusal still occurs, capture
it live at the instant (`conntrack -L`, `iptables -nvL` deltas, `nstat`) to confirm or
refute the kube-proxy-iptables-churn hypothesis before adding more weight/reservation.

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
