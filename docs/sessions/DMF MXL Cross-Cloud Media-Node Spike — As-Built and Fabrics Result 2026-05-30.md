# DMF MXL Cross-Cloud Media-Node Spike — As-Built & Fabrics Result (2026-05-30)

**Outcome: SUCCESS / GREEN.** Two cloud-B ARM nodes were joined as MXL media
nodes to the existing live cloud-A (Hetzner) k3s testlab cluster over Tailscale,
and a cross-host MXL grain transfer over the libfabric **tcp** provider was
verified between them.

This is the **preserved-learnings** record, consolidated and sanitized from the
`feat/mxl-single-node-spike` working docs (which were never meant for `main` and
have been removed from the public component repos). Concrete environment
identifiers, tailnet IPs, and operator-local paths are replaced with placeholders;
the technical findings are kept verbatim in substance.

**Design context (umbrella):**
[[DMF MXL Single-Node Media Node Spike Plan 2026-05-17]] (design),
`DMF MXL Single-Node Loopback Execution Plan 2026-05-29.md`,
`DMF MXL On-Demand Media Function Cycle Plan 2026-06-01.md`. The single-node
shared-memory baseline (`mxl-hello`) preceded this cross-host fabrics test.

> Placeholders: `<env>` = the live Hetzner testlab cluster slug; `<ctl-tailnet-ip>`
> = its control-node tailnet IP; `media-01/02` = the two cloud-B media nodes;
> `<aliyun-vpc-cidr>` / `<hetzner-priv-cidr>` = the respective private CIDRs;
> `$DMFDEPLOY_UMBRELLA/mxl` = the local MXL upstream source checkout.

---

## Part 1 — Cross-cloud media-node join (as-built)

**Goal & why cloud-B:** stand up two ARM nodes as MXL media nodes and join them to
the *existing* live cloud-A k3s cluster `<env>` over Tailscale. Cloud-A ARM
capacity for fresh nodes was unavailable, so a second cloud (Frankfurt region)
was the substitute. Entirely additive, feat-branch-only.

**Result:** two Ubuntu 24.04 ARM nodes joined as k3s **agents** over Tailscale —
`Ready`, `v1.30.6+k3s1`, tainted `dmf.io/mxl=true:NoSchedule` + labeled
`dmf.io/role=mxl-processor`, INTERNAL-IP = tailnet IP. Cross-cloud pod networking
verified end-to-end (pod→cloud-A CoreDNS 0% loss; cluster DNS; TLS to apiserver
ClusterIP).

**Rollout (operator-run):** hidden-secret cred entry (cloud-B AccessKey) →
`tf-apply.sh <media-env> apply` → a thin `mxl-media-join.sh` (NOT the OpenBao
`run-playbook.sh` wrapper — the media env has no OpenBao bundle).

### Design principle — mirror vanilla bootstrap; diverge only deliberately
Reuse the existing numbered playbooks unchanged, driven by inventory vars; add the
media nodes as a normal-but-tainted agent group. Keep new code minimal and confined
to new files on the feat branch — no edits to shared roles that would have to land
in `main`. All divergences were expressed as **OS-conditional overrides in
media-group vars / a thin addon task**, not by rewriting shared playbooks.

### Ubuntu / cross-cloud divergences (all parameterized, Debian-preserving defaults)
| Symptom | Fix (shared playbook param ↔ media-group var) |
|---|---|
| SSH host-key verify fail (fresh nodes) | `ANSIBLE_HOST_KEY_CHECKING=False` in the join script |
| `k3s_control_node` undefined (agent-only inventory) | set it to a control hostname (only used in a `when`) |
| `kubernetes` pip vs apt PyYAML (PEP 668) | `200-baseline` `extra_args` → `--break-system-packages --ignore-installed` |
| harden `Restart sshd` (Ubuntu unit is `ssh`) | handler `name` param → `harden_sshd_service: ssh` |
| tailscale role ingress debug needs a domain | `cert_manager_cluster_domain: media.invalid` |
| **Tailscale × cloud-B CGNAT** — `100.100.x` DNS/mirrors inside `100.64/10` dropped by tailscale anti-spoof nft | tailscale up → `tailscale_extra_up_args: --netfilter-mode=off` |

### Cross-cloud reachability — the `10.0.0.x` problem (key finding)
Cloud-A nodes advertise their flannel VXLAN endpoint as their *private* `10.0.0.x`,
unreachable from cloud-B. **Solved by per-node `/32` Tailscale routes** — NOT
subnet-router forwarding (the live cluster's stacked nftables —
kube-router + kube-proxy + tailscale + harden — blocked forwarding). Each cloud-A
node advertises only its own `10.0.0.x/32` (`tailscale set --advertise-routes`) +
`headscale nodes approve-routes`; traffic then goes direct to each node, local
delivery, no forwarding. Persisted via `tailscale_advertise_routes:
["{{ k3s_node_ip }}/32"]` in `<env>` group_vars. Return path needs nothing —
cloud-B flannel endpoints are already tailnet IPs.

### NetworkUnavailable taint
Set by cloud-A's Hetzner CCM route controller, which won't clear it for non-cloud-A
nodes. The media nodes don't need CCM routing (flannel-over-tailscale suffices), so
**pods just tolerate `node.kubernetes.io/network-unavailable`** (baked into the
chart). Clearing it wouldn't stick — the CCM owns it.

### MTU (the #1 risk) — VERIFIED
Cloud-B `flannel.1=1230` (auto-derived from `tailscale0`, correct), cloud-A
`flannel.1=1400`. **Validation passed:** DF ping from a cloud-B pod caps at 1230
(1300 fails, as expected); a 166 KB cross-cloud bulk fetch completed clean at full
speed — MSS clamps to 1230, so cross-cloud **TCP is fine**. Only large cross-cloud
UDP could fragment. Key gotcha: **there is no `--flannel-mtu` k3s flag** — the 1230
is auto-derived by k3s from `--flannel-iface=tailscale0`. (A review suggestion of
`--flannel-mtu`/`--flannel-kube-subnet-mode=ipvs` was a **fictional flag** — verify
empirically, don't ship invented flags. Real options: rely on the derived 1230 and
test; lower the `tailscale0` MTU; or drop a custom flannel `net-conf.json`.)

### Firewall
No changes needed — cloud-A harden INPUT `policy accept` + `iifname tailscale0
accept`; cloud-B `netfilter-mode=off` + SG allows tailscale UDP 41641 + intra-VSwitch.

### The one unavoidable divergence — cross-cloud k3s join → **Approach B**
`300-k3s.yml` assumes the control plane is built in the same run (join token read
off the fresh control node; `k3s_server_url` hard-coded from the control node's
*private* `10.0.0.x`). Both are wrong here: the control plane already exists and is
reachable from cloud-B **only at its Tailscale IP** `<ctl-tailnet-ip>`.

**Decided: Approach B** — a separate `<media-env>` inventory + a thin ~15-line join
play that sources the existing cluster's node-token out-of-band (reusing
`bootstrap-secrets.sh`'s `inventory_control_host()` / `inventory_host_var()` SSH-read
helpers) and runs the agent install with `K3S_URL=https://<ctl-tailnet-ip>:6443`.
Rejected **Approach A** (add the nodes to the live `<env>` inventory) — concrete
footguns: `300-k3s.yml`'s second play targets `k3s:!k3s_control` (would hit existing
cloud-A agents + re-run audit drop-ins on live control nodes); `200-baseline.yml` is
`hosts: all` (would re-baseline cloud-A); `tf-render-inventory.sh` regenerates
`hosts.ini` from tofu state and would **silently wipe** the manually-added cloud-B
entries; and mixing clouds makes group-wide plays hang if a cloud-B node is
unreachable. B is self-contained and tear-out-able.

### Other decisions
- **OS = Ubuntu 24.04** — faithful to the upstream MXL host environment; PEP 668 pip
  handling carries over from Debian; no baseline blocker.
- **Storage = none (no Longhorn)** — MXL is tmpfs/shared-memory, so pods use
  `emptyDir{medium: Memory}`/hostPath. The `NoSchedule` taint also keeps the Longhorn
  manager DaemonSet off.
- **Monitoring = existing cloud-A Prometheus** scrapes them via k8s SD over the
  tailnet (kubelet + cAdvisor auto; node-exporter must tolerate the media taint).
- **NetBox born-inventory = SKIP for now** — the role is add/update-only (no prune);
  core metrics come via k8s SD regardless. Re-runnable later via `694-born-inventory.yml`.

---

## Part 2 — MXL Fabrics cross-host demo (GREEN)

**What it proves:** a `target` (receiver) and an `initiator` (sender) from one
consolidated `mxl-fabrics-demo` image, running on **two different MXL media nodes**,
transferring grains across hosts over the node's VPC NIC via `hostNetwork`. The
initiator also runs the demo media functions (test-pattern producer + reader + info)
so there are real grains to move. First cross-host fabrics test (vs the single-node
shared-mem `mxl-hello` baseline).

**Result (GREEN):** test-pattern grains produced on `media-02` are forwarded over the
libfabric **tcp** provider across the cloud-B VPC into the receiver's domain on
`media-01`; the received flow is `Active` with its head index advancing
(~2-grain / ~50 ms latency). Both pods stable, 0 restarts.

### Key technical findings
- **NIC = `eth0`.** The chosen instance family (`g8y.large`, Yitian-710 Arm) has a
  **single** VPC NIC — there is no `eth1`. `fabrics.interface: eth0` in the chart.
  (Earlier design docs assumed `eth1`; the as-built corrected this.)
- **The tcp provider does NOT bypass the kernel.** Grains traverse the kernel TCP/IP
  stack on both hosts (libfabric RMA semantics emulated by the tcp provider). This
  proves the *plumbing*; the zero-copy path is `verbs`/eRDMA (deferred).
- **`hostNetwork` on the VPC NIC** (full 1500 MTU, same-VPC) → unaffected by the
  cross-cloud flannel/MTU caveats from Part 1.
- **`Recreate` deploy strategy** on both Deployments: the pods are `hostNetwork` and
  bind host port `1234`; RollingUpdate would clash two pods on that port on one node.
- **target-info handshake is manual / two-phase**, and the target **regenerates** its
  target-info blob on (re)start — if the target pod restarts, re-run the deploy steps
  with the new blob.
- **Reinstall caveat:** the chart creates the `mxl` Namespace, so `helm uninstall`
  deletes it; wait for full namespace termination before reinstalling.

### Consolidated image
One image carries **every** demo function — the `mxl` base stage `COPY`s all
`/usr/bin/mxl-*`, so entrypoints differ per chart container (`mxl-fabrics-demo`,
`mxl-gst-testsrc`/`-sink`/`-looping-filesrc`, `mxl-info`, `fake-reader.sh`). The
fabrics Dockerfile adds, over the stock example: `libfabric` +
`-DMXL_ENABLE_FABRICS_OFI=ON`, and GStreamer (so `tools/mxl-gst` builds);
`-DBUILD_UTILS=OFF -DBUILD_TESTS=OFF -DBUILD_DOCS=OFF` to trim build time. Build
context = the MXL source root (`$DMFDEPLOY_UMBRELLA/mxl`). Nodes are ARM64 → **build
natively on a media node** (no qemu); it's a real C++/vcpkg compile — budget time on
a 2-core node. Published public at `ghcr.io/dmfdeploy/mxl-fabrics-demo` (anonymous
pull cross-cloud, no imagePullSecret/Zot). Alternative for a 2-node spike:
`podman save | k3s ctr images import` on both nodes + `image.pullPolicy=Never`.

### Two-phase deploy + verify (as-built shape)
1. **Target (receiver):** `helm install mxl-fabrics <chart> --set
   target.nodeName=media-01`; read the opaque target-info blob the target prints.
2. **Initiator (sender + producer stack):** `helm upgrade … --reuse-values --set
   initiator.enabled=true --set initiator.nodeName=media-02 --set
   initiator.targetInfo='<blob>'`. Initiator pod = `writer` (gst test pattern →
   creates the flow + grains) → `initiator` (forwards grains over the fabric) →
   `reader` → `info`.
3. **Verify:** initiator log shows "Endpoint is now connected"; **success = the
   target flow is `Active: true` with `Head index` climbing over time.**

**Teardown:** `helm uninstall mxl-fabrics`; the cloud-B nodes themselves via
`tf-apply.sh <media-env> destroy`.

---

## Deferred / open
- **verbs/eRDMA (kernel-bypass path):** flip `fabrics.provider`, use an eRDMA-capable
  instance family + RDMA device access in the pod (privileged / SR-IOV). **Open:**
  whether the chosen Arm family even exposes eRDMA is unverified — if not, verbs would
  force a non-Arm family.
- **Cluster-wide flannel MTU 1230** as an optional clean fix (vs the auto-derived
  value) — deferred.
- **Dockerfile arch:** the final `COPY` uses the `aarch64-linux-gnu` triplet; swap to
  `x86_64-linux-gnu` if ever building x86.

## Provenance
Consolidated 2026-06-10 from the (now-removed-from-public) feat-branch docs
`dmf-media/docs/mxl-fabrics-runbook.md`, `dmf-media/docs/mxl-fabrics-workstream-c-handoff.md`,
and `dmf-infra/docs/mxl-media-nodes-plan.md`, plus the `910/915-mxl-*` spike playbooks.
Per the [[DMF Public Repo Doc-Hygiene Cleanup Plan 2026-06-10]] (decision D1), the raw
"NOT for main" operational artifacts were removed from the public component repos and
their learnings preserved here with sanitized topology.
