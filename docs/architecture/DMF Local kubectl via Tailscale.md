# DMF Local kubectl via Tailscale

**Scope:** the `hetzner-arm` k3s cluster only. Operator workstation only (currently a single Mac, on the operator's tailnet).

**Status:** active operational path as of 2026-05-06. Replaces the prior "always SSH to the control node for kubectl" stance for **read-only** convenience use; SSH-then-`sudo kubectl` remains the canonical path for state-of-record reads (see `dmf-cluster-access` SKILL.md §3.1).

---

## TL;DR for a fresh agent

1. The operator's Mac has a kubeconfig at `~/.kube/k3s-hetzner.yaml` — context name `hetzner-arm`.
2. It points at the control node's **Tailscale IP** (`100.64.0.55:6443` at the time of writing), not the public IP. Traffic stays on the tailnet; the API server is **not** publicly exposed.
3. TLS verifies against the cert hostname `k3s-node-01` via `tls-server-name:` in the kubeconfig — the IP target and the cert SAN don't have to match.
4. `kubectl get nodes` from the operator's Mac is fine. **Don't use this from any other workstation, CI runner, or container** — the kubeconfig contains a cluster-admin client cert.

```bash
export KUBECONFIG=~/.kube/k3s-hetzner.yaml
kubectl get nodes
kubectl -n authentik get pods
```

---

## How the setup works (mechanism)

### 1. Tailscale on the cluster

Every node runs `tailscaled` (deployed by `playbooks/321-tailscale.yml` → role `base/tailscale`). Each node registers with an **ephemeral hostname** — a stable prefix (`k3s-node-01`, `k3s-node-02`, `k3s-node-03`) plus a random suffix per registration (e.g. `k3s-node-01-x2ntqe8u`). The IP (`100.64.0.55`) stays put while the node stays up; both name and IP can change on re-register.

Old, offline ephemeral entries pile up in `tailscale status` over time. Don't use them.

### 2. The tailnet shape

| Tailnet IP | Name | Notes |
|---|---|---|
| `100.64.0.3` | `<operator-workstation>` | Operator workstation (operator tailnet account) |
| `100.64.0.55` | `k3s-node-01-<suffix>` | Control plane, current API target |
| `100.64.0.54` | `k3s-node-02-<suffix>` | Control plane (HA etcd) |
| `100.64.0.53` | `k3s-node-03-<suffix>` | Control plane (HA etcd) |

The IPs above were correct as of 2026-05-06. **They change** when the cluster is redeployed (Path Y) or when `tailscaled` re-registers. To re-discover:

```bash
tailscale status | grep -E "k3s-node|^100" | grep -v offline
```

### 3. The cert SAN gap

The k3s API server cert (issued by k3s itself) includes these SANs:

```
DNS: k3s-node-01, k3s-node-02, k3s-node-03,
     kubernetes, kubernetes.default, kubernetes.default.svc, ..., localhost
IP:  10.0.0.2, 10.0.0.3, 10.0.0.4 (private),
     10.43.0.1 (cluster CIDR), 127.0.0.1,
     <control-node-public-ip> (k3s-node-01 public IPv4)
```

The Tailscale IP `100.64.0.55` is **not** in the SAN. Without intervention, `kubectl --server=https://100.64.0.55:6443` fails TLS verification because the cert's SAN list doesn't include that IP.

The role `base/k3s` does **not** currently pass `--tls-san` for the tailnet name or IP. Adding it is a planned hardening pass; until then, see (4).

### 4. The `tls-server-name` workaround

A kubeconfig cluster entry can carry both:

```yaml
clusters:
- cluster:
    server: https://100.64.0.55:6443    # connect to this address
    tls-server-name: k3s-node-01        # but verify the cert against this hostname
    certificate-authority-data: ...
  name: hetzner-arm
```

`tls-server-name` is a standard kubeconfig field. It decouples the TCP target from the cert-verification name, which matches the cert's `DNS:k3s-node-01` SAN. No `/etc/hosts` edit, no SAN regen, no public exposure.

### 5. Bootstrapping the kubeconfig (one-time, current pattern)

```bash
# Pull k3s.yaml from the control node via Tailscale
ssh -i ~/.ssh/id_ed25519_k3s_hetzner k3s-admin@100.64.0.55 \
  'sudo cat /etc/rancher/k3s/k3s.yaml' > /tmp/k3s-hetzner.yaml

# Rewrite cluster/context/user names + add Tailscale IP and tls-server-name
sed -e 's/name: default$/name: hetzner-arm/' \
    -e 's/cluster: default/cluster: hetzner-arm/' \
    -e 's/current-context: default/current-context: hetzner-arm/' \
    -e 's|server: https://127.0.0.1:6443|server: https://100.64.0.55:6443\n    tls-server-name: k3s-node-01|' \
    /tmp/k3s-hetzner.yaml > ~/.kube/k3s-hetzner.yaml

# Then awk-fix the user-block name to "hetzner-arm-admin" (sed above renames clusters too aggressively)
awk '/^users:/{u=1} /^[a-z]/&&!/^users:/{u=0}
     u && /^- name: hetzner-arm$/{print "- name: hetzner-arm-admin"; next}
     {print}' ~/.kube/k3s-hetzner.yaml > ~/.kube/k3s-hetzner.yaml.tmp
mv ~/.kube/k3s-hetzner.yaml.tmp ~/.kube/k3s-hetzner.yaml
chmod 600 ~/.kube/k3s-hetzner.yaml
shred -u /tmp/k3s-hetzner.yaml 2>/dev/null || rm -f /tmp/k3s-hetzner.yaml
```

When the node re-registers and the Tailscale IP changes, only the `server:` line needs updating. The cert-CA and client cert remain valid until k3s rotates them (default: 1 year).

---

## What an agent should and shouldn't do

### Should
- ✅ **Read the cluster** with this kubeconfig when the operator is logged in to the same shell. `kubectl get pods -A`, `kubectl describe`, `kubectl logs`, etc.
- ✅ **Prefer this over `ssh + sudo kubectl`** for routine reads when the goal is to surface state in the conversation. It's lower-latency and doesn't tie up an SSH connection.
- ✅ **Re-discover the Tailscale IP** if the kubeconfig is stale: `tailscale status | grep -E 'k3s-node-01-.* active'` and update `server:` accordingly.
- ✅ **Note in the conversation** when you switched from SSH-based to local-kubectl reads, so the operator can audit.

### Shouldn't
- ❌ **`kubectl apply`, `patch`, `delete`, `exec`, `cp`, `port-forward`** — write/destructive ops still go through `bin/run-playbook.sh`, per `dmf-cluster-access` §4. The kubeconfig has cluster-admin power; treating it as read-only is a discipline choice, not a permission boundary.
- ❌ **`cat`, `echo`, or otherwise print** `~/.kube/k3s-hetzner.yaml` or any field within it. The `client-certificate-data` and `client-key-data` blocks are admin credentials. Leaking them to the transcript means rotating the entire k3s cluster cert chain (re-init, not just a kubectl-only fix).
- ❌ **Copy the kubeconfig anywhere** — not to a CI artefact, not to another Mac, not to a container, not to a gist for "easier sharing." If a second workstation needs access, the operator generates a separate scoped credential (RBAC, not cluster-admin).
- ❌ **Rely on the Tailscale IP being stable** across redeploys. After Path Y (full redeploy), the kubeconfig will need a new `server:` line.
- ❌ **Use this from any environment that isn't the operator's primary workstation.** No CI, no shared workstation, no cloud workspace. The trust model is "this laptop is already a SSH-key holder for the cluster, so adding a kubeconfig is no worse"; that argument doesn't hold for any other host.

---

## Reconciliation with `dmf-cluster-access` SKILL.md §0.4

The skill's §0 rule states:

> 4. Never copy `/etc/rancher/k3s/k3s.yaml` off the control node. It's a cluster-admin certificate. SSH into the node and run `kubectl` there.

This document is the **explicit operator-authorized exception** to that rule, scoped to:
1. The operator's primary workstation (single Mac, operator tailnet account)
2. Tailnet-only network reachability (no public exposure)
3. Local file at mode `0600` under `~/.kube/`
4. Read-only intent (writes still flow through Ansible)

The rule still applies in spirit: don't sprawl admin credentials. The exception is narrow. If a future agent or operator wants to extend access to a second workstation or to grant scoped read-only access to a teammate, that's an RBAC question, not a "copy the kubeconfig" question — generate a `ServiceAccount` with a `ClusterRole`, mint a kubeconfig from its token, and document the scope.

A pending hardening item is to amend `roles/base/k3s/` to pass `--tls-san=100.64.0.55` (or, better, a stable tailnet hostname once that's wired up via MagicDNS) so the `tls-server-name` workaround can be retired. That ADR/work isn't done yet.

---

## Troubleshooting

### `Unable to connect to the server: dial tcp 100.64.0.55:6443: i/o timeout`

Tailscale either isn't up locally or the node has gone offline.

```bash
tailscale status | grep "k3s-node-01"
# Verify the suffix on the row marked "active". If "offline", the node tailscaled died.
```

### `tls: failed to verify certificate: x509: certificate is valid for k3s-node-01, k3s-node-02, ..., not 100.64.0.55`

`tls-server-name` is missing from the kubeconfig. Re-add it:

```yaml
clusters:
- cluster:
    server: https://100.64.0.55:6443
    tls-server-name: k3s-node-01    # ← this line
```

### `error: You must be logged in to the server (Unauthorized)`

The client cert in the kubeconfig has expired (k3s rotates yearly) or the cluster was redeployed and the cert chain was regenerated. Re-bootstrap the kubeconfig from the control node.

### Tailscale name keeps changing

Each `tailscale up` with `--ephemeral` (the role's default) generates a new node ID. The `100.64.0.x` IP follows the registration; on reboot it usually stays, but on any tailscaled restart with re-auth it shifts. If this becomes painful, switch the role to non-ephemeral keys with a stable name — that's a one-line change in `roles/base/tailscale/defaults/main.yml`.

---

## Related files

- `~/.kube/k3s-hetzner.yaml` — the kubeconfig (operator's Mac only)
- `~/.ssh/id_ed25519_k3s_hetzner` — SSH key used to bootstrap the kubeconfig from the node
- `dmf-infra/k3s-lab-bootstrap/roles/base/tailscale/` — Tailscale install role
- `dmf-infra/k3s-lab-bootstrap/roles/base/k3s/` — k3s install role (where `--tls-san` would land in the future)
- `.claude/skills/dmf-cluster-access/SKILL.md` — canonical cluster-access discipline; this doc is the §0.4 exception
