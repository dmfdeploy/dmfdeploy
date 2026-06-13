---
name: dmf-cluster-access
description: Operate against the live DMF lab cluster. The cluster is the truth — local kubectl is not. This skill encodes how to inspect, change, and recover state authoritatively. Env slug rotates; current id in umbrella STATUS.local.md (run bin/generate-status.sh).
---

# DMF Cluster Access

**Scope:** the live Hetzner k3s lab cluster — 3 nodes on Hetzner CAX21 (ARM64), nbg1.
The env slug rotates as we cut new test clusters (run `bin/generate-status.sh`
and read the generated `STATUS.local.md` for the current id). This is currently the only DMF cluster. When `dmf-central`
and flypack profiles stand up, this skill is revised, not generalized prematurely.

**Iron rule:** the local Mac's `kubectl` context can point anywhere. For DMF, the
**only** authoritative source is the control node. `scripts/verify-cluster.sh`
in `dmf-cms/` exists because we got bitten by this. SSH or use the remote-kubectl
pattern below for every read that matters.

---

## 🛑 §0 Secrets Discipline (read first, every time)

Hard rules. Violations leak secrets into transcripts, prompt caches, shell history,
`/tmp`, or telemetry — all hard to scrub once leaked.

1. **Never echo, cat, or pipe a secret to stdout when running through an AI agent.**
   Tool output is captured into the conversation transcript and prompt cache. If a
   command's only purpose is to print a secret, run it in a *separate terminal* — not
   through the agent. The agent should request that work be done, not do it.

2. **Never put a secret in argv.** That covers `curl -d '{"password":"..."}'`,
   `export OPENBAO_TOKEN=xxx` on the command line, `bao operator unseal <share>`,
   any flag with the literal value. Argv is world-readable via `ps`. Use stdin
   (`read -s`, `printf '%s' "$x" |`), files, or shell builtins.

3. **Treat any session that retrieved a secret as compromised for that secret's
   lifetime.** Rotate after the session, even if "nothing went wrong." Telemetry,
   crash dumps, and caches you don't control may still hold a copy.

4. **Never copy `/etc/rancher/k3s/k3s.yaml` off the control node** — except
   for the operator's primary workstation (mac-mini), under the documented
   Tailscale-only pattern in
   `dmfdeploy/docs/architecture/DMF Local kubectl via Tailscale.md`. That
   exception is read-only-intent, tailnet-only, mode-0600 under `~/.kube/`.
   The cluster-admin kubeconfig is **never** copied to CI, containers, other
   workstations, gists, chat, or transcripts. Writes still flow through
   `bin/run-playbook.sh` (§4), not the local kubeconfig.

5. **Never paste OpenBao Shamir share contents into any chat, terminal recording,
   screenshot, or shared note.** Three shares = full master key compromise. Use
   the `dmf-openbao-unseal` skill; never ad-hoc the share values.

6. **`/tmp` hygiene.** `bin/run-playbook.sh` writes secrets to
   `/tmp/openbao-vars-*.XXXXXX` (mktemp + trap cleanup). On crash or Ctrl-C,
   stale files persist. Sweep periodically:

   ```bash
   find /tmp -name 'openbao-vars-*' -mmin +30 -delete
   ```

   Playbook logs at `/tmp/dmf-playbook-logs/` can contain secret values if a task
   forgot `no_log: true`. Audit with:

   ```bash
   grep -iE 'password|token|secret|api_key' /tmp/dmf-playbook-logs/*.log
   ```

   Rotate anything leaked, then delete the offending log.

7. **Right pattern for "the agent needs a secret to do its job":** invoke a tool
   (playbook, script) that retrieves the secret server-side and uses it without
   exposing it to the orchestrator. Playbook 650 doing `docker login` inside an
   isolated docker config is the model. Don't ask the agent to "retrieve and pass
   along" a secret.

---

## 1. Cluster facts (read once)

| Item | Value |
|---|---|
| Environment slug | `<env-name>` (current id in the generated umbrella `STATUS.local.md` — run `bin/generate-status.sh`; env slugs rotate as we cut new test clusters) |
| Provider | Hetzner Cloud, CAX21, ARM64, region `nbg1` |
| Nodes | `k3s-node-01` (<node-public-ip>, priv 10.0.0.4) · `k3s-node-02` (<node-public-ip>, priv 10.0.0.3) · `k3s-node-03` (<control-node-public-ip>, priv 10.0.0.2) |
| Control plane | All 3 (HA etcd) |
| Default control node for SSH | `k3s-admin@<control-node-public-ip>` (k3s-node-03) |
| KUBECONFIG path on node | `/etc/rancher/k3s/k3s.yaml` (root-owned; use `sudo`) |
| External base URL | `https://*.dmf.example.com` (DNS-01 wildcard via Cloudflare) |
| Ingress | Traefik on host-root subdomains: `console`, `awx`, `auth`, `forgejo`, `grafana`, `netbox`, `openbao`, `registry` |
| Storage | Longhorn, 2 replicas (3-node lab) |
| Monitoring | Prometheus 5Gi PVC / 6h retention, Grafana, Loki, Promtail |
| Secrets backend | OpenBao at `https://openbao.dmf.example.com`, pod `openbao-0` in ns `openbao` |
| Identity | Authentik at `https://auth.dmf.example.com`, OIDC for downstream apps |

Inventory + `hosts.ini` live in `dmf-env/inventories/<env-name>/`. Secrets do
not — see §5.

---

## 2. The "what do I want to do?" decision tree

```
                             ┌───────────────────────────────────────┐
                             │  What kind of operation?              │
                             └───────────────────────────────────────┘
                                 │           │              │
                  ┌──────────────┘           │              └─────────────┐
                  ▼                          ▼                            ▼
         READ — observe state          WRITE — change config       DESTRUCTIVE — recover
         (always safe)                 (idempotent, run via         (humans confirm first)
                                       playbook, never patch
                                       Helm by hand)
            §3                              §4                            §5
```

Markers used below:
- 🟢 **READ-ONLY** — runs without side effects
- 🟡 **WRITE** — changes cluster state via the sanctioned path (Ansible playbook or sanctioned script)
- 🔴 **DESTRUCTIVE** — can lose data or block the cluster; **confirm with the user before executing**

---

## 3. 🟢 READ-ONLY operations

### 3.1 Cluster health (the canonical lens)

Two paths, both valid for reads:

- **SSH to the control node** — canonical, always works, no setup. Use this for
  "is the cluster actually healthy?" questions where you must not be misled by a
  stale local context.
- **Local kubectl via Tailscale** — set up on the operator's mac-mini under the
  exception in §0.4. Lower-latency, doesn't tie up an SSH session, fine for
  routine reads. See
  `dmfdeploy/docs/architecture/DMF Local kubectl via Tailscale.md` for the
  contract (read-only intent, no `apply`/`patch`/`exec`/`port-forward`).

Don't trust an arbitrary local `kubectl get` if you don't know which kubeconfig
is loaded — `kubectl config current-context` first.

```bash
ssh k3s-admin@<control-node-public-ip>

sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get nodes -o wide
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get pods -A -o wide
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get pvc -A
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get volumes.longhorn.io -n longhorn-system
```

One-liner pattern from your laptop (no SSH session needed):

```bash
ssh k3s-admin@<control-node-public-ip> \
  "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n <ns> get pods -o wide"
```

### 3.2 What's actually deployed?

```bash
# In a specific namespace
ssh k3s-admin@<control-node-public-ip> \
  "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n dmf-cms describe deploy dmf-cms | grep Image"

# Helm releases
ssh k3s-admin@<control-node-public-ip> \
  "sudo helm --kubeconfig /etc/rancher/k3s/k3s.yaml -n monitoring list"

# Or for dmf-cms specifically:
cd ~/repos/dmfdeploy/dmf-cms && scripts/verify-cluster.sh
```

### 3.3 Service URLs (from a browser or curl)

| Service | URL | Auth |
|---|---|---|
| Landing page | `https://dmf.example.com/` | — |
| Console (dmf-cms) | `https://console.dmf.example.com/` | OIDC |
| Authentik | `https://auth.dmf.example.com/` | passkey/admin |
| OpenBao | `https://openbao.dmf.example.com/` | userpass/AppRole |
| Registry (Zot) | `https://registry.dmf.example.com/` | userpass |
| AWX | `https://awx.dmf.example.com/` | OIDC + admin |
| Forgejo | `https://forgejo.dmf.example.com/` | OIDC + admin |
| Grafana | `https://grafana.dmf.example.com/` | OIDC + admin |
| NetBox | `https://netbox.dmf.example.com/` | OIDC + admin |
| Prometheus | `https://prometheus.dmf.example.com/` | — |

Healthz: `curl -sk https://console.dmf.example.com/healthz` (and similar per app).

### 3.4 Logs

```bash
ssh k3s-admin@<control-node-public-ip> \
  "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n <ns> logs deploy/<name> --tail=200"

# All containers
ssh k3s-admin@<control-node-public-ip> \
  "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n <ns> logs <pod> --all-containers --tail=200"
```

For app-level logs aggregated, use Grafana/Loki at `https://grafana.dmf.example.com/`.

### 3.5 Storage usage (frequent gotcha)

Prometheus has a 5Gi PVC and 6h retention. WAL needs ~300MB headroom. Out-of-space
puts the pod into CrashLoopBackOff and Grafana shows "No data".

```bash
ssh k3s-admin@<control-node-public-ip> \
  "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n monitoring exec deploy/prometheus-server -- df -h /data"
```

---

## 4. 🟡 WRITE operations (sanctioned config changes only)

### 4.1 The golden rule

**Run a playbook, don't `kubectl apply`.** All cluster config is owned by Ansible
roles in `dmf-infra/k3s-lab-bootstrap/`. The wrapper in `dmf-env/bin/run-playbook.sh`
exports OpenBao secrets, runs ansible with the right inventory, and logs to a
timestamped file under `/tmp/dmf-playbook-logs/`.

```bash
cd ~/repos/dmfdeploy/dmf-env

# Single layer or vertical
bin/run-playbook.sh ../dmf-infra/k3s-lab-bootstrap/playbooks/650-dmf-cms.yml

# Lifecycle stage (provision/operate/finalise)
bin/run-playbook.sh ../dmf-infra/k3s-lab-bootstrap/lifecycle-operate.yml

# Full build (watch for ~90 min)
bin/run-playbook.sh ../dmf-infra/k3s-lab-bootstrap/site.yml
```

The wrapper takes the env name as its first arg:
`bin/run-playbook.sh <env-name> <playbook>` — look up the current env id in the
umbrella's generated `STATUS.local.md` (run `bin/generate-status.sh`).

### 4.2 Watch a long run

The wrapper prints a log path on start. In a second terminal:

```bash
bin/monitor-playbook.sh /tmp/dmf-playbook-logs/site-20260503-204000.log
```

Filters to `PLAY/TASK/fatal/FAILED/PLAY RECAP` only.

### 4.3 Tag-based selection

Layer N, vertical, lifecycle, or functional tags work:

```bash
ansible-playbook ... --tags layer3
ansible-playbook ... --tags vertical-monitoring
ansible-playbook ... --tags openbao,eso
```

Use `--check --diff` first to preview without applying.

### 4.4 Deploy dmf-cms specifically

After a release tag is built and pushed (see `dmf-cms-build-and-release` skill):

```bash
cd ~/repos/dmfdeploy/dmf-env
bin/run-playbook.sh ../dmf-infra/k3s-lab-bootstrap/playbooks/650-dmf-cms.yml

# Then verify
cd ~/repos/dmfdeploy/dmf-cms
scripts/verify-cluster.sh
```

### 4.5 Layer-1 (Hetzner provisioning) — separate path

Provisioning the nodes themselves uses OpenTofu, not Ansible:

```bash
cd ~/repos/dmfdeploy/dmf-env
bin/tf-apply.sh plan
bin/tf-apply.sh apply
bin/tf-render-inventory.sh    # regenerates hosts.ini from tofu state
```

State lives at `<secure-store>/terraform-states/<env-name>/terraform.tfstate`.

---

## 5. 🔴 DESTRUCTIVE / RECOVERY operations

**Confirm with the user before running anything in this section.** These can lose data,
block the cluster, or expose secrets.

### 5.1 Read app admin credentials from OpenBao (break-glass path)

When the AppRole shim in `bin/export-openbao-vars.sh` can't help — usually because
you need an admin password to log into a UI directly.

🛑 **The output of `get-admin-cred.sh` is a secret value.** Do **not** invoke it
through an AI agent — the password lands in the conversation transcript. Run it in
a separate terminal. The pattern below is shown for reference, not for an agent
to execute on the user's behalf.

```bash
cd ~/repos/dmfdeploy/dmf-env
bin/get-admin-cred.sh <app> | jq '.data.data'
# apps: authentik, awx, netbox, forgejo, grafana, librenms, zot
```

Mechanism: SSH to control node → `kubectl exec` into `openbao-0` → `bao login` with
ops_admin user from `<secure-store>/openbao-breakglass/<env-name>/openbao-keys-automation.json`
→ `bao kv get secret/apps/<app>/admin`. The password is never in argv on the bastion
(piped via stdin into the kubectl exec heredoc); but it **is** in the script's stdout
to the operator's terminal — which is exactly what makes it sensitive.

### 5.2 OpenBao sealed — see the `dmf-openbao-unseal` skill

A sealed OpenBao blocks ESO, secrets reads, runtime auth — almost everything. The
canonical procedure is the `dmf-openbao-unseal` skill, which drives
`dmf-env/bin/unseal-openbao.sh` to feed the 3-share Shamir quorum (JuiceFS
shares 1+2, macOS Keychain share 3) via stdin only — share values never appear in
argv, environment, `/tmp`, or stdout on this side of the boundary.

🛑 **Do not improvise an unseal.** Improvising means typing share values
into a terminal you don't control or running ad-hoc `bao operator unseal <key>`
commands — both leak the share into shell history, argv, and (if running through
an agent) the conversation transcript. Use the script.

```bash
cd ~/repos/dmfdeploy/dmf-env
bin/unseal-openbao.sh --status        # check seal state (no secrets touched)
bin/unseal-openbao.sh                 # interactive 3-share unseal
```

USB shares 4+5 (OPENBAO_A) are reserved for re-init / rekey disasters and are not
part of the routine unseal path.

### 5.3 PVC stuck in Terminating

```bash
ssh k3s-admin@<control-node-public-ip> \
  "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n <ns> patch pvc <name> -p '{\"metadata\":{\"finalizers\":null}}'"
```

### 5.4 Helm release stuck in pending-upgrade

```bash
ssh k3s-admin@<control-node-public-ip> \
  "sudo helm --kubeconfig /etc/rancher/k3s/k3s.yaml -n <ns> rollback <release> <revision>"
```

### 5.5 Prometheus storage full → CrashLoopBackOff

WAL fills the 1Gi default; bumped to 5Gi but still possible if retention misconfigured.

```bash
# Drop the PVC and let the playbook recreate (loses metrics history!)
ssh k3s-admin@<control-node-public-ip> <<'EOF'
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n monitoring delete pvc prometheus-server --wait=false
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n monitoring patch pvc prometheus-server -p '{"metadata":{"finalizers":null}}'
EOF

cd ~/repos/dmfdeploy/dmf-env
bin/run-playbook.sh ../dmf-infra/k3s-lab-bootstrap/playbooks/vertical-monitoring/100-prometheus.yml
```

### 5.6 AWX PostgreSQL "Permission denied" on Longhorn

PostgreSQL runs as UID 26; Longhorn volumes are root-owned. Add to the AWX CR:

```yaml
postgres_data_volume_init: true
```

Then re-run the AWX playbook.

### 5.7 RWX vs RWO Multi-Attach error on reschedule

Workloads that may move nodes (NetBox media, AWX projects) need
`accessMode: ReadWriteMany` + `storageClass: longhorn` — RWO blocks reschedule.
Fix the role's PVC template, then redeploy.

### 5.8 Force pod restart (last resort)

Almost always wrong — re-running the playbook is idempotent and cleaner.

```bash
ssh k3s-admin@<control-node-public-ip> \
  "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n <ns> rollout restart deploy/<name>"
```

---

## 6. Common pitfalls (named so you can avoid them)

| Symptom | Likely cause | Where to look |
|---|---|---|
| `kubectl` shows fine but real cluster is sick | Wrong context (Mac local kubeconfig) | SSH to control node |
| Pod still on old image after `helm upgrade` | Helm chart `image.tag` not bumped | dmf-cms `scripts/sync-version.sh --check` |
| Re-running playbook downgrades image | Hardcoded `cms_image_tag` in role | Use the `lookup('file', ...)` reading `dmf-cms/VERSION` |
| Logo URL broken on landing page | IngressRoute didn't add `PathPrefix(/assets)` | `roles/landing-page/templates/...` |
| ConfigMap change didn't take effect | Pod doesn't auto-rollout | `rollout restart deploy/<name>` (explicit) |
| LibreNMS `lnms` command says permission denied | Don't run `lnms` as root | `su -s /bin/sh librenms -c '/opt/librenms/lnms <cmd>'` |
| `community.hashi_vault` not found in playbook | Wrapper exports vars instead — playbook should use `vault_*` vars from `-e @file` | `bin/run-playbook.sh` already handles this |

---

## 7. References

- `dmfdeploy/docs/architecture/DMF Platform Plan.md` — system overview, status snapshot at top
- `dmfdeploy/docs/architecture/DMF EBU Mapping (2026-04-25).md` — playbook layer/vertical map
- `dmfdeploy/docs/plans/DMF Improvement Run Plan 2026-04-22.md` — Shamir unseal sequence
- `dmfdeploy/docs/plans/DMF Secret Ownership and OpenBao Migration Plan.md` — secret tier classification
- `dmf-infra/CLAUDE.md` — kubectl quick refs and Longhorn / Prometheus troubleshooting
- `dmf-env/CLAUDE.md` — OpenBao AppRole shim, secret-injection model
- `dmf-env/README.md` — wrapper invocations + secrets table
- `dmf-cms/scripts/verify-cluster.sh` — canonical cluster-image-vs-VERSION check

---

**When in doubt:** SSH to the control node and read state directly. If the read disagrees
with what a playbook reports, the cluster is right and the playbook is the next thing to
fix — don't hand-patch Helm releases.
