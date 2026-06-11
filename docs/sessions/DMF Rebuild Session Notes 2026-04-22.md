# DMF Rebuild Session Notes — 2026-04-22

> **Vocabulary updated 2026-04-25** — playbook numbers in this session log
> reflect the pre-EBU naming at the time of writing. Canonical layer /
> vertical / lifecycle map is `DMF EBU Mapping (2026-04-25).md`.

**Status:** Rebuild paused at playbook 32-librenms (not yet attempted).
Everything 00–31 is live and verified on the new Hetzner ARM cluster.
**Renumbered 2026-04-22-B:** Playbook numbers updated per orchestrator plan
(see `DMF Improvement Run Plan 2026-04-22.md` Step B). Old → new mapping
in `DMF Orchestrator and Renumbering Plan 2026-04-22.md` §2.

**Operator:** the originating operator. Session ran on a Mac mini at `<lan-ip>`.

**Cluster:**
- `k3s-node-01` <control-node-public-ip> / 10.0.0.2 / tailnet 100.64.0.14
- `k3s-node-02` <node-public-ip> / 10.0.0.3 / tailnet 100.64.0.15
- `k3s-node-03` <node-public-ip> / 10.0.0.4 / tailnet 100.64.0.16
- Hetzner LB `dmf-traefik` healthy at `<lb-public-ip>`
- Wildcard `*.dmf.example.com` → all 3 tailnet IPs
- OpenBao unsealed, ESO AppRole live, Authentik blueprints applied

---

## 1 · Playbooks run and their outcome

| # | Playbook | Outcome | Fix landed this session |
|---|----------|---------|-------------------------|
| 00 | `00-baseline.yml` | clean | — |
| 01 | `01-verify-environment.yml` | **fixed** → clean | `become: false` at play level; `select('string')` on hcloud parser; ssh check uses `ansible_user` + drop `.results` misuse |
| 05 | `05-harden.yml` | **fixed** → clean | nftables rule uses `iifname "tailscale0"` (was `iif`, which refuses to load if interface absent) |
| 10 | `10-k3s.yml` | clean | — |
| 15 | `15-metallb.yml` | **SKIPPED** on Hetzner | memory saved; plan removes it |
| 15 | `15-ingress.yml` | clean | — |
| 15 | `15-ingress-private.yml` | clean | — |
| 16 | `16-cert-manager.yml` | **fixed at CF side** → clean | Cloudflare token needed `Zone.Zone.Read` in addition to `Zone.DNS.Edit`; no code change |
| 17 | `17-tailscale.yml` | **fixed** → clean | `tailscale up --auth-key=file:<path>` (was `--authkey-file=<path>` which current upstream tailscale rejects) |
| 18 | `18-post-bootstrap-verify.yml` | clean | — |
| 20 | `20-longhorn.yml` | clean | — |
| 21 | `21-zot.yml` | clean | — |
| 22 | `22-landing-page.yml` | clean | — |
| 23 | `23-openbao.yml` | clean | — |
| 24 | `24-external-secrets-operator.yml` | clean | — |
| 25 | `25-prometheus.yml` | **fixed** → clean | umbrella chart `prometheus-25.8.0` expects Alertmanager config under `alertmanager.config:`, not the legacy `alertmanagerFiles.alertmanager.yml` top-level |
| 26 | `26-loki.yml` | clean | — |
| 27 | `27-grafana.yml` | clean | — |
| 28 | `28-promtail.yml` | clean | — |
| 29 | `29-authentik.yml` | **fixed** → clean | blueprint `!Find` on scope mappings must use `authentik_core.propertymapping`, not `authentik_providers_oauth2.scopemapping` (subclass resolves via BlueprintLoader but not via apply_blueprint) |
| 30 | `30-netbox.yml` | clean | — |
| 31 | `31-forgejo.yml` | **fixed** → clean | chart's Ingress moved from public `traefik` class to `traefik-private` class — Forgejo is a host-based app, reachable only via tailnet wildcard, not via the public LB |
| 32–42 | not attempted | — | — |

---

## 2 · Cross-cutting infra findings (ops-quality, not per-role)

### 2.1 SSH ControlMaster mux degrades after 30+ playbook invocations
**Symptom:** ansible-playbook hangs on a single task for 10–20 min with no
output. Process tree shows a child ssh against `<home>/.ansible/cp/<hash>`
with 0 cpu time; on the node, no `AnsiballZ` python process is running.
The mux socket file exists but the underlying TCP connection is zombied.

**Fix landed:** `k3s-lab-bootstrap/ansible.cfg` gained an `[ssh_connection]`
block:
```ini
ssh_args = -o ControlMaster=auto -o ControlPersist=600s \
           -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
           -o TCPKeepAlive=yes
pipelining = True
```
- `ServerAliveInterval=15` + `ServerAliveCountMax=3` means the mux kills itself
  within ~45s of a dead connection, letting the next task open a fresh mux
  instead of waiting forever.
- `pipelining = True` cuts per-task sudo+python invocations in half.

**Manual recovery if it happens anyway:**
`pkill -f "ansible-playbook.*NN"; rm -f ~/.ansible/cp/<hash>`, then re-run.

### 2.2 Bash `| tail -N` pipe fully buffers playbook output
**Symptom:** launching `bin/run-playbook.sh ... | tail -80 &` makes the run
appear hung — no output arrives until the process exits. Worse, the user
can't distinguish a real hang from a running job.

**Fix used this session:**
```bash
bin/run-playbook.sh .../NN-foo.yml > /tmp/dmf-playbook-logs/NN-foo.log 2>&1
```
Then a Monitor tail watches the log file and streams TASK/PLAY/fatal/FAILED
lines as notifications.

**Lesson saved** (`feedback_ansible_output_visibility.md` — see Lessons).

### 2.3 Idempotent "wait" tasks look like failures
Every `until:` block emits `FAILED - RETRYING: [...] (NN retries left).`
before it eventually succeeds. Across 28 playbooks this was confusingly
noisy during the session. Not broken — just worth knowing.

---

## 3 · Open follow-ups from this session

### 3.1 Architectural — belongs in the orchestrator/renumbering plan

1. **Drop `15-metallb.yml`** from the Hetzner path entirely. Fold the mode
   switch into `20-ingress-public.yml` via `cluster_ingress_mode` inventory.
2. **Forgejo now ships as private-only**, matching Grafana/NetBox/AWX
   pattern. Public-lane IngressRoute removed by intent (user decision this
   session). No public URL for forgejo anymore; all access via tailnet.
   Record in role defaults + inventory note.
3. **Cert-manager `Certificate` wait** has a hard 5-minute cap
   (`retries: 30, delay: 10`). That was enough for this run, but only
   because Cloudflare ACME responded fast. Consider bumping to 10 min or
   adding a `fail_msg` that instructs the operator to widen the CF token
   scope if it times out — the most common cause.
4. **Ansible `ansible.cfg`** now has ServerAlive settings. Worth adding a
   short doc note in `docs/` or CLAUDE.md equivalent so a future session
   knows this isn't load-bearing on every env (flypack, RPi) but is a good
   default.
5. **Authentik blueprint lesson for `!Find` on property mappings** is now
   a Lesson. But the failure was cryptic enough (string `"None"` in list)
   that a per-env preflight check that runs `!Find` for the expected
   scope mappings BEFORE applying the main blueprint would save future
   debugging time.

### 3.2 Planning-doc updates pending

- `DMF Session Handoff 2026-04-22.md` — needs a "state as of end of
  2026-04-22 session" update that reflects playbooks 00–31 done, 32+ still
  to run, and the role/config changes that landed.
- `DMF Orchestrator and Renumbering Plan 2026-04-22.md` — additions:
  - New §3.5: "Deterministic termination guardrails" covering the
    SSH ControlMaster keepalive pattern, the `> file.log 2>&1` output
    discipline, and the proposed `timeout 900` wrapper cap.
  - New §4.5: "Forgejo private-only" — remove the public-lane assumption
    from the renumbering plan; role already matches the other host apps.
  - New §5: "Add a fail-fast preflight that exercises the expected
    Authentik `!Find` references for scope mappings before applying
    `20-app-providers.yaml`."
- `DMF Pre-Rebuild Critical Review 2026-04-22.md` — mark items #1 ("single
  node SPOF"), and the hardening items for 17-tailscale / CF reconcile /
  Alertmanager as landed; carry forward items #5 (idempotency CI), #6
  (Longhorn BackupTarget), #7 (DR drill), #8 (AppRole secret_id rotation),
  #9 (token migration to in-cluster OpenBao), plus the new #11/#12/#13
  for the three ops-quality findings above.

### 3.3 New lessons to save (done in Lessons.md during this session)

- `authentik_core.propertymapping` parent polymorphic class for `!Find`
- Ansible playbook output visibility: never pipe through `| tail`
- helm module can silently stall on broken SSH ControlMaster
- Tailscale CLI dropped `--authkey-file`, use `--auth-key=file:<path>`
- Prometheus umbrella chart 25.x → `alertmanager.config:` schema
- nftables: `iifname` not `iif` for not-yet-existing interfaces
- `hosts: localhost` playbooks need `become: false` when `become=True` is
  global in ansible.cfg

---

## 4 · State of the cluster right now

- All 3 nodes `Ready`, untainted by CCM.
- Ingress stack: Hetzner LB + public Traefik (class `traefik`), private
  Traefik on NodePort 30443 (class `traefik-private`).
- cert-manager `Certificate cluster-tls` Ready; wildcard cert in TLSStore.
- Tailscale up on all 3 nodes (100.64.0.14/15/16), socat forwarders live.
- Longhorn default StorageClass, 2-replica.
- Zot registry up.
- Landing page serving `/` on both lanes.
- OpenBao Shamir 3-of-5 initialized, ESO AppRole operational,
  ops-admin userpass seeded.
- Prometheus + Alertmanager with **verified** ntfy + healthchecks
  receivers in the ConfigMap (`alertmanager.config:` path).
- Loki + Grafana + Promtail up.
- Authentik deployed, blueprints applied including
  `20-app-providers.yaml` (Forgejo/AWX/NetBox/Grafana OIDC).
- Break-glass local admin + runtime secret ExternalSecrets materialized.
- NetBox + Forgejo deployed. Forgejo is private-lane-only by design as of
  this session.

---

## 5 · What a fresh session should do next

1. Read `Lessons.md` for the seven new entries.
2. Read this doc.
3. Read the updated Session Handoff (once §3.2 is applied).
4. Run `32-librenms.yml` first — smallest remaining bootstrap step.
5. Then `35-awx.yml`, `40-netbox-sot.yml`, `41-forgejo-bootstrap.yml`,
   `42-awx-integration.yml` in that order.
6. Verify Watchdog ping on healthchecks.io is landing every minute (the
   cluster has been up for a while by the time the fresh session starts —
   prior pings should be visible in the healthchecks web UI).
7. Run the orchestrator plan's decision points with the operator (§7 of
   that doc).
