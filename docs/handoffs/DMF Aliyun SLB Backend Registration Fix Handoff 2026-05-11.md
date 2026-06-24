# DMF Aliyun — SLB Backend Registration Fix Handoff

**Date:** 2026-05-11
**Audience:** Next session — assume zero prior context.
**Scope:** `dmf-env/tasks/aliyun/`, ADR-0019.
**Status at end of session:** `dmf-traefik-slb` (`<aliyun-slb-ip>`) backend
group now has all 3 ECS nodes registered; public lane serves HTTPS 200
end-to-end. Both root-cause defects fixed in the playbook and live.

## TL;DR

Two distinct defects were causing the Aliyun SLB to have zero backends:

1. **Tailscale's `ts-input` iptables chain drops Aliyun internal-service
   replies.** The chain ends with `DROP all -- !tailscale0 *
   100.64.0.0/10`. Aliyun's IMDS (`100.100.100.200`), internal DNS
   (`100.100.2.136/138`), and OpenAPI VPC endpoints (broader
   `100.100.0.0/16`) all live inside that CGNAT `/10`. Reply packets
   arrive on `eth0`, not `tailscale0`, and get dropped. Manifests as
   Aliyun CCM panicking on STS token refresh (~6h after the initial
   token, obtained pre-Tailscale) and CrashLoopBackOff.

2. **Aliyun CCM v2.14 excludes nodes with the legacy
   `node-role.kubernetes.io/master` label from LB backend selection.**
   k3s auto-applies that label to every server-mode node. DMF runs
   control-plane-only k3s clusters (3 nodes, all server-mode, no
   dedicated workers) → zero eligible backends → empty vserver group.

Both fixes are now in `dmf-env/tasks/aliyun/`. See ADR-0019 for the
Tailscale-CGNAT-vs-cloud-internal-services decision record.

## Root-cause investigation summary

Reproduced live against `aliyun` cluster (3× ECS, `<aliyun-slb-ip>` SLB):

| Probe | Observation | Conclusion |
|---|---|---|
| `kubectl -n traefik get svc` | namespace empty | Traefik actually lives in `kube-system` (k3s default) — no real fault |
| `kubectl -n kube-system get pods -l app=cloud-controller-manager` | 3× `CrashLoopBackOff` (159 restarts) | CCM broken |
| `kubectl logs ds/cloud-controller-manager` | `fail to get next token: Put "http://100.100.100.200/latest/api/token": i/o timeout` then nil-pointer panic | CCM can't reach IMDS |
| `curl --max-time 5 http://100.100.100.200/latest/meta-data/instance-id` from host | `Connection timed out` | IMDS unreachable from the host, not just the pod |
| `ip route get 100.100.100.200` | `via 10.0.0.253 dev eth0` | Routing is correct |
| `sudo iptables -L ts-input -n -v` | `DROP !tailscale0 100.64.0.0/10` | Tailscale's drop covers IMDS |
| `sudo conntrack -L -d 100.100.100.200` | `SYN_RECV` (reply never reaches the socket) | Confirmed drop is on the reply path |
| `sudo iptables -I ts-input -i eth0 -s 100.100.100.200 -j RETURN` then curl IMDS | returns `<aliyun-instance-id>` | Fix concept validated |
| Restart CCM, watch logs | `dial tcp 100.100.0.49:443: i/o timeout` (VPC API) | Scope is the full `100.100.0.0/16`, not just IMDS |
| Widen rule to `100.100.0.0/16`, restart CCM | CCM healthy, but vgroups still `ServerCount: 0` | Second defect lurking |
| Watch CCM logs | repeating `warning: can not find correspond node k3s-node-02 for endpoint 10.42.1.4` | Node exists, but CCM's NodeLister returns nil — points at a filter |
| `kubectl label node k3s-node-02 node-role.kubernetes.io/master-` | backend immediately appears in vgroup | Master-label exclusion confirmed |
| Re-add label + add `service.beta.kubernetes.io/alibaba-cloud-loadbalancer-backend-label` annotation | backend disappears again | Annotation does NOT bypass master exclusion |
| Strip master label from all 3 nodes | 3 backends in both vserver groups | Functional fix |

## Files changed (uncommitted at start of next session if you skipped the commit step)

### `dmf-env/tasks/aliyun/firewall.yml` (was a placeholder)

Now installs and enables:

- `/usr/local/sbin/tailscale-aliyun-internal-allow.sh` — idempotent
  shell helper that waits up to ~15s for the `ts-input` chain to
  exist, then inserts a `RETURN` rule above the CGNAT drop for
  `100.100.0.0/16` (the Aliyun internal service range).
- `/etc/systemd/system/tailscale-aliyun-internal-allow.service` —
  oneshot, `After=tailscaled.service`, `PartOf=tailscaled.service`,
  `WantedBy=tailscaled.service`. Re-arms on every Tailscale
  start/restart/reboot. Best-effort started inline by the playbook
  when `tailscaled` is already up.

Runs on all 3 k3s nodes via the existing `harden_cloud_firewall_tasks`
hook in `roles/base/harden`.

### `dmf-env/tasks/aliyun/ccm.yml` (extended)

Added a post-CCM-install step that lists nodes carrying the legacy
`node-role.kubernetes.io/master` label and strips it. Idempotent
(`when: ... | length > 0`).

**Caveat:** k3s re-applies the master label on every server-process
restart. If the cluster gets restarted at the node level for any
reason, re-run `bin/run-playbook.sh aliyun
../dmf-infra/k3s-lab-bootstrap/playbooks/310-ingress-public.yml -e
baseline_update_apt_cache=false` to restore SLB backends. This is the
right place for a follow-up if it becomes annoying — see "Open
follow-ups" below.

### `docs/decisions/0019-tailscale-cgnat-vs-cloud-internal-services.md` (new) + INDEX entry

Captures the structural Tailscale-CGNAT-vs-Aliyun conflict, options
considered and rejected, the per-host systemd-unit approach we took,
and triggers for revisiting (new cloud env, Tailscale release change,
apps wanting IPs in `100.100.0.0/16`).

## Live cluster state — end of session

- `tailscale-aliyun-internal-allow.service` `active` + `enabled` on all
  3 nodes. Confirmed re-arms after `systemctl restart tailscaled`.
- `node-role.kubernetes.io/master` label removed from all 3 nodes.
- `dmf-traefik-slb` `<aliyun-slb-ip>`:
  - vserver group `<aliyun-vserver-group-http>` (HTTP/30162) — 3 backends
    (`<aliyun-instance-id>/.91/.92`)
  - vserver group `<aliyun-vserver-group-https>` (HTTPS/30705) — 3 backends
- End-to-end: `curl -k --resolve <lan-host>:443:<aliyun-slb-ip>
  https://<lan-host>/` → HTTP 200 (landing page).

## What's next

1. **Configure stage** (still not run on aliyun — was the previous
   handoff's next step too):
   ```bash
   cd <umbrella-path>/dmf-env
   DMF_BOOTSTRAP_BUNDLE_DIR=<secure-store>/dmf-bootstrap \
       RUNBOOK_TIMEOUT=5400 bin/run-playbook.sh aliyun \
       ../dmf-infra/k3s-lab-bootstrap/bootstrap-configure.yml \
       -e baseline_update_apt_cache=false
   ```
2. **Pick a strategy for the master-label re-apply problem** — see
   below.

## Open follow-ups

- **Persistent master-label suppression.** Today's fix re-strips the
  label every time `310-ingress-public.yml` runs, but k3s re-applies
  it on every server restart. Three reasonable next moves:
  - Convert the strip step into a small `systemd timer + kubectl`
    script on the control node (runs every N minutes; idempotent).
  - Patch k3s `kubelet-arg=node-labels=...` to set the label to a
    non-`true` value (untested; k3s server label application may
    override).
  - File / track upstream issue with Aliyun CCM to migrate from
    `node-role.kubernetes.io/master` to the standard
    `node.kubernetes.io/exclude-from-external-load-balancers` check.
- **Generic Tailscale post-install hook.** The CGNAT allow currently
  lives in `harden_cloud_firewall_tasks` for ergonomic reasons (it
  already runs on every node). The conceptual home is "post-Tailscale,
  per-cloud" — when DMF gets a third cloud, add a
  `tailscale_post_install_tasks` indirection to the generic Tailscale
  role and move the install there.
- **Validate on the next fresh aliyun bring-up.** First-run sequencing
  is: harden → … → tailscaled → … → CCM. Our systemd unit installs
  during harden but only *fires* when tailscaled later starts. CCM
  comes up *after* tailscaled, so by the time CCM tries IMDS, the
  RETURN rule is already in place. The 30-second timing window
  between tailscaled starting and the oneshot firing should not
  matter — but worth confirming end-to-end on the next teardown +
  rebuild.

## File pointers

- Updated playbook tasks: `dmf-env/tasks/aliyun/firewall.yml`,
  `dmf-env/tasks/aliyun/ccm.yml`
- ADR: `docs/decisions/0019-tailscale-cgnat-vs-cloud-internal-services.md`
- Previous handoff (still load-bearing for everything else):
  `docs/handoffs/DMF Aliyun Pre-Seed to Post-Seed Live Validation Handoff 2026-05-10.md`
- Tailscale operational context:
  `docs/architecture/DMF Local kubectl via Tailscale.md`
