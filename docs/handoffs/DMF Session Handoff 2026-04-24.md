# DMF Session Handoff — 2026-04-24

> **Read this first.** Self-contained handoff for a fresh session with
> no prior chat memory. Replaces the 2026-04-22 handoff set.

> **Vocabulary updated 2026-04-25** — playbook numbers and Phase / Layer
> language in this handoff predate the EBU realignment. Canonical layer /
> vertical / lifecycle map is `DMF EBU Mapping (2026-04-25).md`.

> **Architecture note 2026-04-27** — references in this log to the VPS
> OpenBao on Aliyun via wg2 describe historical operator infra, not DMF
> scope. DMF clusters use embedded in-cluster OpenBao only; see
> `project_dmf_no_wg2_openbao.md` and Platform Plan §7b for the canonical
> per-cluster pattern.

## 1. Environment at a glance

- **Operator host:** Mac mini at `<lan-ip>`. Claude Code runs
  here. Never SSH into .117 — you're already on it.
- **Cluster:** 3-node Hetzner ARM (cax21). Bastion/SSH target:
  `k3s-admin@<control-node-public-ip>` (same node as control-plane #1).
- **Live cluster access:** SSH to `k3s-admin@<control-node-public-ip>` and run
  `sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml ...` there.
  Treat the Mac's local `kubectl` context as untrusted until you have
  verified it points at the Hetzner cluster.
- **Public endpoint:** Hetzner LB at `<lb-public-ip>`, apex
  `dmf.example.com`.
- **Apps live on host-root subdomains** of `*.dmf.example.com`:
  `auth` (302 — Authentik), `awx`, `forgejo` (200), `grafana`,
  `librenms`, `netbox`, `registry`. All on DNS-01 wildcard TLS.
  Public `apps.json` advertises them as host cards.
- **Private lane:** Tailscale + socat + secondary Traefik on
  NodePort 30443 (not WireGuard-wg3 as originally planned).
- **JuiceFS:** mounted at `<volumes>/secure` (and elsewhere).
  Survives Mac loss.
- **Memory:** `<home>/.claude/projects/-Volumes-<operator>-<note-store>/memory/`
  — read `MEMORY.md` index at session start.

## 2. Repos and heads

| Repo | Path | Branch | HEAD | Remotes |
|------|------|--------|------|---------|
| `dmf-infra` | `~/repos/dmf-infra` | `main` | `61a4ead` | `origin` (GitHub), `forgejo` (homelab) |
| `dmf-env` | `~/repos/dmf-env` | `main` | `019fb50` | `origin` (homelab Forgejo) |
| `openbao-secret-platform` | `~/repos/openbao-secret-platform` | `main` | `c60904c` | — |
| `dmf-cms` | `~/repos/dmf-cms` | `master` | `963a6c1` — scaffold only | — |

Reorg branches present but NOT merged (see §7 open items):
`reorg/layered-structure` on infra, `reorg/multi-env-docs` on env.

## 3. Orchestrator and playbook layout

Canonical entry points (from `dmf-env`):

```bash
cd ~/repos/dmf-env

# Full build (~45–90 min)
bin/run-playbook.sh ../dmf-infra/k3s-lab-bootstrap/site.yml

# Or a single phase
bin/run-playbook.sh ../dmf-infra/k3s-lab-bootstrap/phase4-platform.yml

# Or a single playbook
bin/run-playbook.sh ../dmf-infra/k3s-lab-bootstrap/playbooks/40-openbao.yml
```

Phase-based numbering (0x–9x, complete in-tree):

```
phase0:  00-verify-environment  01-baseline  02-harden
phase1:  10-k3s  11-k3s-verify
phase2:  20-ingress-public  21-ingress-private  22-cert-manager
         23-tailscale  29-network-verify
phase3:  30-longhorn  31-registry-zot  32-landing-page
phase4:  40-openbao  41-eso  45-prometheus  46-loki  47-grafana
         48-promtail  49-monitoring-verify
phase5:  50-authentik  51-authentik-breakglass-verify
phase6:  60-netbox  61-forgejo  62-librenms  63-awx
phase7:  70-netbox-sot  71-forgejo-bootstrap  72-awx-integration
phase8:  80-stack-verify
phase9:  90-teardown
```

`run-playbook.sh` wraps with `timeout 900` by default; for
`site.yml`/phase wrappers it's already been widened in the script —
no manual override needed.

## 4. OpenBao custody (live as of 2026-04-24)

All break-glass artefacts on JuiceFS at
`<secure-store>/openbao-breakglass/hetzner-lab/`. **Never
`$HOME/secure`.** See saved memory `feedback_dmf_secure_path.md`.

- `share-1.json`, `share-2.json` — JuiceFS
- share 3 — macOS login Keychain (service
  `openbao-breakglass-share-3`) via `osascript`
- `share-4.json`, `share-5.json` — USB `OPENBAO_A`
  (`/Volumes/OPENBAO_A/`)
- `openbao-keys-automation.json` — JuiceFS, holds root token + 3
  unseal shares + ESO AppRole role_id/secret_id + ops-admin userpass
- Unseal threshold: 3 of 5
- DR procedure: `System/Breakglass Runbook 2026-04-22.md`

**ESO AppRole** (`auth/approle/role/external-secrets`):
- Policy `eso-reader` (read-only on `secret/*` + pki issue)
- `secret_id_ttl=720h` (30d) — rotation every ~25 days
- Current accessor: `<openbao-accessor>`,
  expires **2026-05-24T18:15Z**
- Next rotation due: **2026-05-19** (runbook:
  `System/ESO AppRole Rotation Runbook.md`)

## 5. What shipped this session (2026-04-24)

Reconciliation pass + TTL rotation.

**Infra commits on `main` (pushed):**
- `61a4ead` — `fix(openbao): give ESO AppRole secret_id a finite 30d TTL (720h)`
- `aa43af3` — `fix(openbao): write shares 1+2 to JuiceFS path, not $HOME`

**Env commits on `main` (pushed):**
- `019fb50` — `fix(openbao): point break-glass paths at JuiceFS, not $HOME`

**Secbrain docs updated:**
- `Projects/DMF Platform Plan.md` — 2026-04-24 status snapshot header
  (numbering, private lane, host-root exposure, ntfy bridge)
- `Projects/DMF Orchestrator and Renumbering Plan 2026-04-22.md` —
  marked DONE
- `Projects/DMF Improvement Run Plan 2026-04-22.md` — Steps A/B/C/E
  DONE; Step D (DR drill) PARTIAL (paused at Phase 4)
- `Projects/DMF Open Questions 2026-04-20.md` — post-rebuild
  reconciliation section, closing subdomain/private-lane/DNS-01/ntfy
  findings; keeping reorg branches, Hetzner leakage, AppRole TTL,
  Longhorn BackupTarget OPEN
- `System/Breakglass Runbook 2026-04-22.md` — JuiceFS paths
- `System/ESO AppRole Rotation Runbook.md` — NEW
- `System/Todo.md` — trimmed from 4581 → 702 lines; pre-2026-04-19
  archived to `System/Todo Archive pre-2026-04-19.md`
- `System/Lessons.md` — unchanged this session

**Live ops:**
- Migrated shares 1+2 + automation file from `$HOME/secure` to
  `<secure-store>/openbao-breakglass/hetzner-lab/`
- Applied `secret_id_ttl=720h` to running AppRole, minted new
  secret_id, updated automation JSON + K8s Secret
  `external-secrets/openbao-approle`, rollout-restarted ESO
- Destroyed old TTL=0 accessor
- Both ExternalSecrets (`authentik/authentik-breakglass`,
  `authentik/authentik-runtime`) re-synced cleanly

## 6. Canonical docs to read for context

- `Projects/DMF Platform Plan.md` — architecture (read the 2026-04-24
  status snapshot at top)
- `Projects/DMF Pre-Rebuild Critical Review 2026-04-22.md` — reviewer
  punch list; §1.1, §2.1, §2.3, §4.1, §4.2 are still open items
- `Projects/DMF Open Questions 2026-04-20.md` — post-rebuild reconciliation
- `System/Lessons.md` — 80+ lessons; read if hitting a known-gotcha
  category (OpenBao pod no-jq, Tailscale CLI, nftables, etc.)
- `System/Breakglass Runbook 2026-04-22.md` — OpenBao DR
- `System/ESO AppRole Rotation Runbook.md` — credential rotation
- `System/Todo.md` — active work (702 lines; reverse-chron at top)
- `dmf-infra/k3s-lab-bootstrap/docs/flypack-offline-lane.md` —
  canonical flypack spec (supersedes Platform Plan §7b and §254–300)
- `openbao-secret-platform/` — separate Alibaba VPS OpenBao rollout
  (cross-site setup; not the in-cluster OpenBao)

## 7. Open items (prioritised)

Pick one when resuming. Each is scoped to a single session's worth of
work; each has a clean stopping point.

### 7a. Longhorn BackupTarget — no backups configured
- **Impact:** single disk loss = data loss. NetBox, AWX, Authentik,
  Grafana postgres — all at risk.
- **Approach:** decide a target (Hetzner Object Storage S3-compatible?
  JuiceFS-backed S3? separate VPS?), add a `BackupTarget` CR to the
  Longhorn role, add a recurring Snapshot + Backup schedule for PVCs.
- **Reference:** Lessons.md 2026-04-18 "Longhorn BackupTarget Is a CR,
  Not a Setting".

### 7b. DR Drill Step D resumption — prove rebuild is reproducible
- **Paused at:** Phase 4 (Loki PVC cleanup + SSH ControlMaster mux hang).
- **Log:** `Projects/DMF DR Drill Session Log 2026-04-22-B.md` — full
  narrative + 12 in-tree bugfixes landed during the partial run.
- **Risk of resuming:** needs a fresh cluster rebuild, so it's a
  full-session effort. Critical for confidence in the orchestrator.

### 7c. Root token disposal (§2.3 of Critical Review)
- **Goal:** stop keeping a forever-valid root token in the automation
  JSON. Mint a scoped `app-admin-writer` policy + a long-lived token
  with that policy; let the actual root get disposed.
- **Dep:** touches the same `40-openbao.yml` role that shipped the
  TTL fix — low rework risk if done next.

### 7d. Reorg branch rebase/merge
- **State:** `reorg/layered-structure` (infra) and `reorg/multi-env-docs`
  (env) both diverge from `main` because operational work landed after
  branch point. Cannot fast-merge.
- **Options:** rebase onto `main` and resolve conflicts; or
  reapply the structural moves as small commits on `main` and delete
  the branches.

### 7e. Hetzner leakage audit cleanup (10 files)
- List in `Projects/DMF Open Questions 2026-04-20.md` under "Hetzner
  Leakage Audit". Mostly `docs/*.md` + example inventory — generalise
  or move to `dmf-env`.
- Low-risk, doc-only. Good as a "warming up" task.

### 7f. ESO auto-restart handler on Secret change
- Small improvement: when the `openbao-approle` Secret data changes
  (during `41-eso.yml` or manual rotation), automatically trigger
  a Deployment rollout. Removes manual step 5 from the rotation
  runbook.

### 7g. Alerting rules + receivers (§4.1 of Critical Review)
- Partially addressed (ntfy formatter bridge shipped, watchdog via
  healthchecks.io). Still missing meaningful alert conditions
  (cert-expiry warning, node-down, PV 80%+, CrashLoopBackOff, ESO sync
  failing). Live check showed the `PrometheusRule` CRD is not installed,
  so either install the operator CRD path or add rules through the
  deployed Prometheus chart mechanism.

## 8. Non-DMF context the operator carries

- **Local RPi cluster** (`kubectl` default context `default` →
  `rpi-node-01/02/03`). Separate from Hetzner DMF. Had a hard reset
  on 2026-04-24 — see Todo.md "2026-04-24 Local Cluster Post-Reset
  Pod Recovery" for the remaining NFS CSI decision.
- **OpenClaw local LLM** workstream is in `Playbooks/OpenClaw*` and
  is unrelated to DMF. Don't touch unless asked.
- **VPS OpenBao** on Aliyun at `<operator-vps-ip>` with wg2 tunnel — this
  is the cross-site secrets platform, separate from the in-cluster
  OpenBao in the Hetzner DMF lab. See
  `openbao-secret-platform/docs/openbao-secret-platform.md`.

## 9. Known gotchas (frequently hit)

- **OpenBao pod has no `jq`.** Always emit JSON from `bao` and pipe to
  `jq` locally after `ssh → kubectl exec`.
- **zsh on Mac mini** doesn't treat `$VAR "..."` as a command prefix.
  Use `eval` or inline the command.
- **macOS Keychain from Ansible** needs `osascript`, not direct
  `security add-generic-password`. See share-3 write path in
  `roles/stack/operator/openbao/tasks/main.yml`.
- **Tailscale CLI:** use `--auth-key=file:<path>`, not the removed
  `--authkey-file`.
- **nftables `iifname`**, not `iif`, for pre-existing interfaces.
- **Ansible on `localhost`** — must set `become: false` on the play.

## 10. How to verify the system before starting work

Cheap probes (no secrets, no writes):

```bash
# Public endpoints
curl -I https://dmf.example.com/ | head -1              # expect HTTP/2 200
curl -I https://auth.dmf.example.com/ | head -1         # expect HTTP/2 302
curl -I https://forgejo.dmf.example.com/ | head -1      # expect HTTP/2 200
curl -s https://dmf.example.com/apps.json | jq 'length' # expect 7

# OpenBao seal + ESO approle state (read-only)
AUTOMATION=<secure-store>/openbao-breakglass/hetzner-lab/openbao-keys-automation.json
ROOT_TOKEN=$(jq -r .root_token "$AUTOMATION")
ssh k3s-admin@<control-node-public-ip> "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n openbao \
  exec openbao-0 -- sh -c 'BAO_TOKEN=${ROOT_TOKEN} bao status -format=json 2>/dev/null'" \
  | jq -c '{sealed, initialized, version}'

ssh k3s-admin@<control-node-public-ip> "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml \
  get externalsecret -A -o json" \
  | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name) ready=\(.status.conditions[0].status)"'
```

If the probes pass and `secret_id_ttl` reads `2592000` or less, the
state recorded here is still accurate.

## 11. If this handoff is stale

Check `System/Todo.md` — the top entry is always the most recent work.
If new work has landed after this handoff without updating it, produce
a fresh handoff (delete this one and write a new
`DMF Session Handoff YYYY-MM-DD.md`) before picking up new work.
