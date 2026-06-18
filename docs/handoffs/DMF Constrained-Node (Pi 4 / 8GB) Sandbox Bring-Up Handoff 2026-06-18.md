# DMF Constrained-Node (Pi 4 / 8 GB) Sandbox Bring-Up — Handoff 2026-06-18

**Intent:** stand up a *fully functioning* DMF sandbox (full stack **with AWX awake**) on
a bare-metal **Raspberry Pi 4B (4-core Cortex-A72 / 8 GB)** — same resource class as the
CAX21 target — via the `dmf-init` container + `dmf-env` **sandbox provider**.

**Outcome: SUCCESS.** All four bootstrap phases completed green — post-seed, configure
(incl. console→AWX integration + smoke test), and **verify 130/130** — with AWX *awake*,
after right-sizing worker pools. We thought this might be impossible at the start; it isn't.

---

## The one thing that mattered: right-size worker pools to RAM, not CPU

The full stack **with AWX awake** initially thrashed the node to death (load 25–57, k3s API
flapping, `authentik-worker` death-spiralling, swap thrash, eventual reboot). The cause was
**not** AWX being inherently huge — it was **app worker pools auto-sizing to the CPU count
(`2×cores+1`)** with no regard for available RAM. On 4 cores each app spawned 4–9 workers,
each a full Django/uwsgi copy (~100–240 MiB).

Right-sizing three components reclaimed **~1.3 GB** and turned "~0 headroom → swap-thrash
death spiral" into "~2.3 GiB headroom → stable at load ~6":

| Component | Default | Knob | Cut to | Result |
|---|---|---|---|---|
| **NetBox** (NGINX Unit) | 993 MiB | `nginx-unit.json` ConfigMap `processes.max`/`spare` | `max:1, spare:1` | **158 MiB (−835)** |
| **Authentik server** (gunicorn) | 653 MiB | env `AUTHENTIK_WEB__WORKERS` | `2` | **450 MiB (−203)** |
| **AWX web** (uwsgi) | 988 MiB | `/etc/tower/uwsgi.ini` `processes` (`lazy-apps=true`) | `2` | **~480 MiB (−~500)** |

Full accounting + further headroom (AWX rsyslog sidecars 168 MiB ×2, Prometheus 484 MiB,
Authentik worker 504 MiB) and the exact knobs are in **[dmfdeploy/dmfdeploy#93](https://github.com/dmfdeploy/dmfdeploy/issues/93)** (updated this session;
retitled to "right-size worker pools for constrained single-node").

> ⚠️ These were applied as **live cluster patches** for the proof. They persist across a
> reboot (etcd) but are **reverted by a dmf-infra re-run or by the AWX operator reconciling
> `awx-web`**. The durable fix is to bake them into the sandbox release-profile fit-overrides
> (#93). Until then, keep the **AWX operator scaled to 0**.

## Operational tricks used during bring-up (until #93 lands)

- **Scale the AWX *operator* to 0, keep web+task up.** The operator's reconcile loop
  (`awx-manage` + ansible-runner) was a bigger CPU hog than AWX itself; the AWX **API is
  served by the web pod** and needs no operator for API-only work (configure integration).
- **Split `configure` by AWX dependency** when memory is tight: run the Authentik/NetBox
  plays with AWX scaled down (`--skip-tags awx,smoke-test`), then the AWX plays with AWX up
  (`--tags awx,smoke-test`). Both phases idempotent; re-run freely.
- **Phases are idempotent** — a transient (worker flap, API timeout under burst) is cleared
  by re-running the phase, not starting over. `dmf-init` v0.3.0 now resumes a failed phase
  from the UI (#87).

## Host prep that's load-bearing (Pi-specific)

- **`cgroup_enable=memory cgroup_memory=1`** in `/boot/firmware/cmdline.txt` — without the
  memory cgroup, k3s/kubelet won't enforce limits. This is the classic Pi-k3s blocker.
- Headless GPU trim (`gpu_mem=16`, drop `vc4-kms-v3d`), disable BT/WiFi/avahi/cloud-init.
- **8 GB SSD swapfile + 2 GB zram, `vm.swappiness=100`** — cushions exec spikes. Note the
  k3s role runs `swapoff -a` + comments fstab; re-enable the swapfile (kubelet here tolerates
  swap). Disk swap frees real RAM better than zram when pages are idle.
- **OpenBao re-seals on every reboot** — unseal with the 1-of-1 Shamir key from the env
  bundle (`unseal_keys_hex[0]`); it listens on **HTTPS** (`bao ... -tls-skip-verify`).

## Backlog status (from this + the prior session)

- ✅ **#86** (dmf-init default `DMF_REPO_BASE_URL`), **#87** (UI resume) — landed, dmf-init **v0.3.0**
- ✅ **#88** (Authentik `ak shell` worker-flap hardening), **#92** (AWX sync gates on migration) — landed, dmf-infra main
- ⬜ **#93** — the durable worker-pool right-sizing fit-override (this session's key finding). **Now the single gating item** for a *reproducible* constrained-node deploy; suggest `v0.1-polish`.

## Next steps

1. Land **#93** (sandbox-profile fit-overrides: NetBox Unit processes, Authentik workers,
   AWX uwsgi processes; plus the original AWX-operator CPU cap + `authentik-worker` QoS
   requests). Then a fresh `dmf-init` bootstrap on a Pi 4 right-sizes from the start — no
   hand-tuning, no operator-juggling.
2. Optional extra headroom if needed: trim AWX rsyslog queue (336 MiB), Prometheus retention,
   Authentik worker concurrency.
3. Re-validate end-to-end on a *clean* bootstrap once #93 lands to confirm reproducibility.

**Net:** the 8 GB Pi 4 (and CAX21) is a viable, fully-functioning DMF target — the platform
fits; the bootstrap just needs to right-size worker pools to RAM instead of CPU.
