---
status: executed
date: 2026-04-22
---
# DMF Orchestrator and Playbook Renumbering Plan — 2026-04-22

> **Status: Superseded (2026-04-25)** — the orchestrator structure described
> here landed via commit `5c970c4`+`5595a46` in dmf-infra. The canonical
> reference is now `DMF EBU Mapping (2026-04-25).md`. This document is kept
> for the historical analysis and decision rationale; current state lives in
> the repos and the Mapping doc.

> **Vocabulary aligned 2026-04-25** with the EBU *Dynamic Media Facility Reference
> Architecture* White Paper V2.0. See `DMF EBU Mapping (2026-04-25).md` for the
> canonical layer / vertical / lifecycle map.

> **Prior status (2026-04-22):** Implemented in `dmf-infra` @ `d21dde6`
> (`feat(orchestrator): add site.yml + 9 phase wrappers`) plus the 23-file
> mechanical rename. The env wrapper was extended with `a924e34`
> (`fix(runner): give site and phase wrappers longer timeouts`). Kept for
> history. (The 9 "phase" wrappers were later refactored into lifecycle
> wrappers — see EBU Mapping doc.)

**Status:** Planning. Not yet implemented.
**Scope:** `dmf-infra/k3s-lab-bootstrap/playbooks/` (generic), with
inventory flags in `dmf-env/inventories/<env>/group_vars/all/`.
**Related punch-list entries** (from `DMF Pre-Rebuild Critical Review 2026-04-22.md`):
- §1.2 "No orchestrator" (action item #10 in the handoff)
- §1.3 "Collision-numbered playbooks" (`15-ingress`, `15-ingress-private`, `15-metallb`)
- §1.4 "`18-post-bootstrap-verify` is misnamed"

**Driving principle:** The operator authorises each phase (now: each layer /
vertical / lifecycle stage), but within a phase the plays run in a defined,
defensible order — no ambiguity, no shell-glob drift, no "ran the wrong one
out of three 15-*.yml". Single-env and multi-env (Hetzner, flypack, future
RPi) both satisfied by the same scheme. *(Phase vocabulary was later
replaced by EBU Layer / Vertical / Lifecycle terms — see Mapping doc.)*

---

## 1 · Problem statement

### 1.1 No `site.yml`

Today, 28 playbooks under `playbooks/` run manually one at a time. The
rebuild runbook is a plain-text list in `DMF Session Handoff` docs. Failure
modes:

- Operator skips a step (e.g. 18-post-bootstrap-verify) and a later step
  leaves the cluster in a partial state.
- Operator runs a step out of order (e.g. 25-prometheus before
  24-eso) — the role fails in an opaque way because a secret isn't present
  yet.
- Re-runs don't have fail-fast gates between phases: a broken phase 2 can
  silently feed garbage into phase 3.

### 1.2 Collision-numbered 15-*.yml

```
15-ingress.yml          ← cloud-native on Hetzner (or metallb-l2 fallback)
15-ingress-private.yml  ← private Traefik (NodePort 30443)
15-metallb.yml          ← forces metallb-l2; legacy fallback only
```

Shell glob sort puts `15-ingress-private.yml` before `15-ingress.yml`
alphabetically, which is the opposite of the intended intent. On Hetzner
`15-metallb.yml` must never run (see `feedback_dmf_hetzner_ingress_metallb.md`),
but the numeric prefix suggests it's part of the sequence.

### 1.3 `18-post-bootstrap-verify` is a phase-1 smoke test

It runs after k3s + ingress + cert-manager + tailscale, but before longhorn,
openbao, monitoring, apps. The name implies "everything is up" which is
misleading. There is no "phase 2 verify" or "phase 3 verify" today.

### 1.4 Ad-hoc mix of bootstrap, platform, apps, integrations

The current 00/05/10/15/16/17/18/20s/30s/40s layout is roughly "bootstrap /
platform / apps / integrations" but the boundaries aren't explicit and the
gaps (02-04, 06-09, 11-14, 19, 33-34, 36-39, 43-49) aren't load-bearing.
Inserting a new step means picking a number that happens to be free, which
leaks information about ordering constraints that aren't actually there.

---

## 2 · Proposed renumbering

> *(Historical: the two-digit numbering below shipped in 2026-04-22. It was
> superseded on 2026-04-25 by a three-digit EBU layer/vertical scheme
> (e.g. `40-openbao.yml` → `vertical-security/100-openbao.yml`,
> `62-librenms.yml` → `vertical-monitoring/140-librenms.yml`,
> `80-stack-verify.yml` → `lifecycle/operate-stack-verify.yml`,
> `90-teardown.yml` → `lifecycle/finalise-teardown.yml`). See
> `DMF EBU Mapping (2026-04-25).md` for the canonical table.)*

The rule: **phase number in the tens digit, ordering within phase in the
units digit, letters reserved for parallel-group siblings that must run in
a defined local order.**

### Phase scheme *(historical — superseded by EBU layer/vertical/lifecycle scheme)*

| Phase (legacy) | EBU mapping | Tens | Meaning | Skippable? |
|----------------|-------------|------|---------|------------|
| 0 | Layer 2 — Host Platform | `0x` | Environment verify, host baseline, hardening | no |
| 1 | Layer 3 — Container Platform | `1x` | k3s control plane + Host layer | no |
| 2 | Layer 3 — Container Platform | `2x` | Ingress + networking + TLS + private lane | no |
| 3 | Layer 3 — Container Platform | `3x` | Storage (Longhorn) + registry (zot) | no |
| 4 | vertical-security / vertical-orchestration / vertical-monitoring | `4x` | Secrets (OpenBao + ESO) + observability | no (ESO); mon skippable per-env |
| 5 | vertical-security | `5x` | Identity (Authentik) | skippable on flypack factory-pack |
| 6 | Layer 6 — Application & UI (LibreNMS → vertical-monitoring) | `6x` | Apps (NetBox, Forgejo, LibreNMS, AWX) | per-app skippable |
| 7 | Layer 6 — App integration glue | `7x` | Integration glue (SoT sync, token bootstrap, AWX wiring) | per-integration |
| 8 | lifecycle-operate | `8x` | Full-stack verification, load-tests, DR drills | yes, on-demand |
| 9 | lifecycle-finalise | `9x` | Teardown / decommission / backup/restore | yes |

### Concrete mapping (old → new)

```
01-verify-environment.yml       →  00-verify-environment.yml
00-baseline.yml                 →  01-baseline.yml
05-harden.yml                   →  02-harden.yml
                                                    # 03-09 reserved (cloud-init extras, os-patch, etc.)

10-k3s.yml                      →  10-k3s.yml              (unchanged)
18-post-bootstrap-verify.yml    →  11-k3s-verify.yml       (scope narrowed to k3s + CNI)

15-ingress.yml                  →  20-ingress-public.yml   (cloud-native / CCM or metallb-l2)
15-ingress-private.yml          →  21-ingress-private.yml  (tailscale-lane Traefik)
15-metallb.yml                  →  DELETE (fold into 20-ingress-public as an opt-in mode;
                                            do not ship a separate playbook that forces metallb-l2).
                                            Rationale: single ingress playbook with
                                            `cluster_ingress_mode` inventory var is less
                                            error-prone than three playbooks that overlap.
16-cert-manager.yml             →  22-cert-manager.yml
17-tailscale.yml                →  23-tailscale.yml        (already multi-node as of 36b8404)
                                →  29-network-verify.yml   (NEW: wait for cluster-tls Ready,
                                                            verify LB healthy, verify CF A record
                                                            set matches tailnet IPs)

20-longhorn.yml                 →  30-longhorn.yml
21-zot.yml                      →  31-registry-zot.yml
22-landing-page.yml             →  32-landing-page.yml

23-openbao.yml                  →  40-openbao.yml
24-external-secrets-operator.yml→  41-eso.yml
25-prometheus.yml               →  45-prometheus.yml
26-loki.yml                     →  46-loki.yml
27-grafana.yml                  →  47-grafana.yml
28-promtail.yml                 →  48-promtail.yml
                                →  49-monitoring-verify.yml (NEW: assert Watchdog fired ntfy +
                                                             healthchecks; Alertmanager receivers ok)

29-authentik.yml                →  50-authentik.yml
                                →  51-authentik-breakglass-verify.yml (NEW: prove OpenBao seeded
                                                                       local admin password works
                                                                       in app login flow BEFORE any
                                                                       downstream OIDC wiring —
                                                                       enforces the break-glass
                                                                       doctrine lesson from 2026-04-19)

30-netbox.yml                   →  60-netbox.yml
31-forgejo.yml                  →  61-forgejo.yml
32-librenms.yml                 →  62-librenms.yml
35-awx.yml                      →  63-awx.yml

40-netbox-sot.yml               →  70-netbox-sot.yml
41-forgejo-bootstrap.yml        →  71-forgejo-bootstrap.yml
42-awx-integration.yml          →  72-awx-integration.yml

                                →  80-stack-verify.yml      (NEW: full end-to-end smoke —
                                                             every app reachable over public + private
                                                             lane, every OIDC login works, every
                                                             backup target reachable)
                                →  90-teardown.yml          (NEW: optional, sketch-only today;
                                                             documents safe order to tear down the
                                                             Hetzner cluster for a cost-saving pause)
```

### Deletions

- `15-metallb.yml` — fold into `20-ingress-public.yml` via inventory mode flag.

### Additions (6 new playbooks)

- `11-k3s-verify.yml` — narrow scope inherits from old `18-post-bootstrap-verify`.
- `29-network-verify.yml` — fail-fast gate before storage/apps land.
- `49-monitoring-verify.yml` — fail-fast gate that the alerting path works
  end-to-end (Watchdog → healthchecks, not just "Alertmanager deployed").
- `51-authentik-breakglass-verify.yml` — gate before any OIDC downstream
  enablement, enforces the local-admin doctrine.
- `80-stack-verify.yml` — end-to-end smoke.
- `90-teardown.yml` — documented safe teardown for pause-and-rebuild.

---

## 3 · Proposed `site.yml` orchestrator

> *(Historical: the 9 `phaseN-*.yml` wrappers below shipped in `d21dde6`, then
> were folded into `lifecycle-provision.yml` / `lifecycle-operate.yml` /
> `lifecycle-finalise.yml` per `DMF EBU Mapping (2026-04-25).md`.)*

### 3.1 Design choice

**Two-tier**: a top-level `site.yml` that imports one `phaseN.yml` per phase,
plus tags at both levels so operators can run `--tags phase2` or
`--tags ingress,tls` etc. The import-based approach (not `include_tasks`)
gives ansible-playbook the full plan before execution, so `--list-tasks` and
`--start-at-task` work across the whole run.

**Fail-fast between phases**: each phaseN.yml ends with a verify-playbook
import. Any verify failure aborts the whole site.yml run. No rescue blocks
at the phase boundary.

**Import, don't include**: `import_playbook:` is statically resolved, which
is what we want — `include_playbook:` isn't a thing, and `include_tasks:` at
the top of a playbook file is subtly different and can mask ordering bugs.

### 3.2 Skeleton

```yaml
# site.yml
---
# Orchestrator for k3s-lab-bootstrap. The operator runs this OR any sub-phase
# file. Within a phase, the order is fixed; between phases, each is idempotent
# when re-run in isolation. See ./docs/orchestrator.md for the full rationale.
- import_playbook: phase0-host.yml      # tags: phase0, host
- import_playbook: phase1-k3s.yml       # tags: phase1, k3s
- import_playbook: phase2-network.yml   # tags: phase2, network, ingress, tls, tailscale
- import_playbook: phase3-storage.yml   # tags: phase3, storage, registry
- import_playbook: phase4-platform.yml  # tags: phase4, platform, secrets, monitoring
- import_playbook: phase5-identity.yml  # tags: phase5, identity, authentik, breakglass
- import_playbook: phase6-apps.yml      # tags: phase6, apps
- import_playbook: phase7-integration.yml  # tags: phase7, integration
- import_playbook: phase8-verify.yml    # tags: phase8, verify
```

Each `phaseN-*.yml`:

```yaml
# phase2-network.yml
---
- import_playbook: 20-ingress-public.yml
  tags: [phase2, network, ingress]

- import_playbook: 21-ingress-private.yml
  tags: [phase2, network, ingress, private-lane]

- import_playbook: 22-cert-manager.yml
  tags: [phase2, network, tls]

- import_playbook: 23-tailscale.yml
  tags: [phase2, network, tailscale]

- import_playbook: 29-network-verify.yml
  tags: [phase2, verify, network-verify]
```

### 3.3 Per-env profile skipping

Not every environment runs every playbook:
- **Hetzner lab**: full stack.
- **Flypack (airgapped)**: skip phase7 integrations that reach external
  NetBox/Forgejo; embed everything factory-side.
- **RPi homelab**: no CCM, no Hetzner LB, different ingress (MetalLB
  legitimate here). Skip phase5 if no Authentik.

Two levers:
1. **Inventory toggles** (preferred): `phase5_enabled: false` in
   `group_vars/all/phases.yml`. Each phase file has a `when:` guard at the
   top-level play.
2. **Tag skipping**: `ansible-playbook site.yml --skip-tags phase5`. Simple,
   no inventory change, but easy to forget in a rebuild.

Ship both. Default behavior: inventory toggle wins. Tag skip is the
"operator is running ad-hoc" escape hatch.

### 3.4 Where `site.yml` lives

In `dmf-infra/k3s-lab-bootstrap/` (generic), next to `playbooks/`. The
site-specific wrapper (`dmf-env/bin/run-playbook.sh`) gets a sibling
`bin/run-site.sh` that calls `run-playbook.sh` targeting `site.yml`.
Per the lessons file (2026-04-17): generic orchestration belongs in
`dmf-infra`, env-specific wrappers in `dmf-env`.

---

## 4 · Migration plan (implementable in one PR)

### 4.1 Mechanical renames (git mv, so history follows) — ✅ DONE 2026-04-22

```bash
cd <repos>/dmf-infra/k3s-lab-bootstrap/playbooks
git mv 01-verify-environment.yml    00-verify-environment.yml
git mv 00-baseline.yml              01-baseline.yml
git mv 05-harden.yml                02-harden.yml
git mv 18-post-bootstrap-verify.yml 11-k3s-verify.yml
git mv 15-ingress.yml               20-ingress-public.yml
git mv 15-ingress-private.yml       21-ingress-private.yml
git rm 15-metallb.yml                                      # fold into 20
git mv 16-cert-manager.yml          22-cert-manager.yml
git mv 17-tailscale.yml             23-tailscale.yml
git mv 20-longhorn.yml              30-longhorn.yml
git mv 21-zot.yml                   31-registry-zot.yml
git mv 22-landing-page.yml          32-landing-page.yml
git mv 23-openbao.yml               40-openbao.yml
git mv 24-external-secrets-operator.yml 41-eso.yml
git mv 25-prometheus.yml            45-prometheus.yml
git mv 26-loki.yml                  46-loki.yml
git mv 27-grafana.yml               47-grafana.yml
git mv 28-promtail.yml              48-promtail.yml
git mv 29-authentik.yml             50-authentik.yml
git mv 30-netbox.yml                60-netbox.yml
git mv 31-forgejo.yml               61-forgejo.yml
git mv 32-librenms.yml              62-librenms.yml
git mv 35-awx.yml                   63-awx.yml
git mv 40-netbox-sot.yml            70-netbox-sot.yml
git mv 41-forgejo-bootstrap.yml     71-forgejo-bootstrap.yml
git mv 42-awx-integration.yml       72-awx-integration.yml
```

### 4.2 New files

- `playbooks/29-network-verify.yml`
- `playbooks/49-monitoring-verify.yml`
- `playbooks/51-authentik-breakglass-verify.yml`
- `playbooks/80-stack-verify.yml`
- `playbooks/90-teardown.yml`
- `site.yml`
- `phase0-host.yml` through `phase8-verify.yml` (9 phase wrappers)
- `docs/orchestrator.md` (1-pager explaining the scheme; this plan is the draft)

### 4.3 Docs + lessons to update

- `DMF Session Handoff 2026-04-22.md` — rewrite §6 table with the new names.
- `docs/cluster-ready.md` — if it references old numbers, update.
- `feedback_dmf_hetzner_ingress_metallb.md` memory — replace references to
  `15-metallb.yml` with "`cluster_ingress_mode: metallb-l2` is off by default;
  don't flip it for Hetzner".
- `System/Lessons.md` — add a lesson: "bootstrap playbook numbers encode the
  phase scheme documented in `site.yml`; don't invent new numbers ad-hoc".

### 4.4 Rollout order

1. Land the renames + metallb fold in one commit (mechanical; passes CI).
2. Land `site.yml` + `phaseN-*.yml` wrappers in a second commit (adds
   orchestration, existing playbook paths already compatible).
3. Land the five new verify playbooks one at a time, each with a
   hand-validated run on Hetzner before merging.
4. Last: update all docs + memory references in one doc-only commit.

**Do NOT do this mid-rebuild.** The current Hetzner rebuild should finish
on the old numbers. This plan ships as a separate pre-PR after the cluster
is green end-to-end, ideally tested first on a second ephemeral Hetzner
project so the diff is provable without touching the production lab.

---

## 5 · Open questions

1. **Should `site.yml` ever be run top-to-bottom unattended in prod?**
   My take: no for now. The DMF CLAUDE.md rule #1 ("plan mode default;
   operator authorises each step") pushes toward phase-at-a-time. `site.yml`
   is mostly valuable as a **self-documenting index** + a thing CI can run
   against a throwaway cluster.
2. **Should the verify playbooks block on healthchecks.io state, or just on
   in-cluster state?** External state is more real but adds a dependency
   on healthchecks.io uptime mid-rebuild. Probably: in-cluster assertions
   + a final `80-stack-verify.yml` that hits the external dead-man's switch.
3. **Do we commit the renumbering to the generic repo or only to DMF/Hetzner?**
   Generic. Other envs (flypack, RPi) benefit from the same scheme. Flypack's
   different-shape playbook set can still follow the tens-digit phase scheme.
4. **How do we handle the lone `metallb-l2` case after folding?** The
   `20-ingress-public.yml` play already branches on `cluster_ingress_mode`
   per the `ingress` role. The `15-metallb.yml` play is purely a forced
   override of that var — which is exactly the anti-pattern. Delete it;
   keep the role logic.

---

## 5b · Additions from the 2026-04-22 rebuild session

Findings from actually running 00–31 end-to-end. Each one is either already
handled in `§4` above or gets a new slot here.

### 5b.1 Deterministic termination guardrails

Two operational issues caused the session to look hung multiple times:

- **Bash pipe to `| tail -N`** on `ansible-playbook` fully buffers stdout
  until the process exits. Invisible progress = indistinguishable from a
  crash. Rule: always write to a log file and stream-tail.
- **SSH ControlMaster mux degradation** after ~30 playbook invocations.
  The mux socket file persists on disk but the TCP connection is zombied;
  ansible waits forever on a dead handle. Without keepalive, the only way
  out is to kill the playbook and remove the socket.

**Landed this session** in `k3s-lab-bootstrap/ansible.cfg`:
```ini
[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=600s \
           -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
           -o TCPKeepAlive=yes
pipelining = True
```

**Proposed additions to this plan:**
- Wrap `bin/run-playbook.sh` with a `timeout 900` (15-minute) hard cap
  per playbook. If a run genuinely needs longer than 15 min (rare —
  looking at you, 25-prometheus), the caller passes `-e max_seconds=...`.
- Standardize the "log to file + streaming tail" pattern as the default
  invocation shape, not a manual workaround per session:
  ```bash
  bin/run-playbook.sh ... > /tmp/dmf-playbook-logs/NN-name.log 2>&1
  # with a sibling bin/monitor-playbook.sh that tails with the right filter
  ```

### 5b.2 Forgejo is private-only from this session forward

Previously: Forgejo shipped with the chart's stock Ingress on the public
`traefik` class. That worked when the wildcard DNS resolved to the public
LB. After the 17-tailscale reconcile, `*.dmf.example.com` resolves to
tailnet IPs only, so the chart's Ingress became unreachable and the
verify task looped indefinitely.

**Landed:** chart Ingress switched to `ingressClassName: traefik-private`.
Forgejo is now consistent with Grafana/NetBox/AWX: host-based access via
tailnet, no public exposure.

**Plan update:** `§2` old→new table — no renaming needed for 31-forgejo,
but an inventory note should document that Forgejo joins the "host apps,
private-lane-only" set. Update this also in:
- `roles/stack/operator/forgejo/defaults/main.yml` (already landed)
- `dmf-env/inventories/hetzner-arm/group_vars/all/main.yml` inline
  comment near `forgejo_host`

### 5b.3 Authentik blueprint preflight

`authentik_core.propertymapping` vs `authentik_providers_oauth2.scopemapping`
subclass mismatch cost ~15 min of debugging. The symptom was cryptic:
the literal string `"None"` appearing in the `property_mappings` list.

**Proposed addition:** a pre-check task in the authentik role that
exercises the key `!Find` references via `ak shell` and asserts they
resolve to non-null UUIDs BEFORE applying the main blueprint. A handful of
one-liners per reference; saves the operator from reading the full
blueprint-import serializer error dump.

### 5b.4 `cert-manager` Certificate wait

The `letsencrypt-dns` ClusterIssuer's DNS-01 challenge fails with a
misleading `valid` state on the challenge but a `pending` order if the
Cloudflare token lacks `Zone.Zone.Read`. The role's `fail_msg` currently
only asserts token presence, not scope sufficiency.

**Proposed addition:** in the cert-manager role, add a token-scope probe
(hit `/user/tokens/verify` + `/zones?name=<apex>`) and fail fast with a
message telling the operator to add `Zone.Zone.Read` to the token if the
zones list is empty.

### 5b.5 Session Notes file is the new fresh-start read

The canonical "how to resume" reading order becomes:
1. `<note-store>/System/Lessons.md` (baseline gotchas)
2. `docs/sessions/DMF Rebuild Session Notes 2026-04-22.md` (state today)
3. `docs/handoffs/DMF Session Handoff 2026-04-22.md` (pre-rebuild context)
4. This plan (orchestration future)

When the next rebuild finishes, a fresh session-notes file should be
written, and the Handoff updated to point at the new one.

---

## 6 · Not in scope for this plan

- CI for re-run idempotency (separate action item #5 in the critical review).
- Dependency metadata / dry-run graph (could be added later via Ansible
  Collections or AWX workflow templates).
- Per-app skippable sub-tags inside each phase (phase5 would benefit, but
  this plan keeps grain at "phase" level for clarity).
- Teardown playbook contents — this plan reserves the slot; the contents
  are a later decision point (hcloud destroy is 3 lines; doing it safely
  wrt OpenBao seal state + Longhorn backups is the real work).

---

## 7 · Decision points for the operator (before implementing)

- [ ] Approve the phase-digit scheme (§2) or counter-propose.
- [ ] Approve the 6 new playbook slots (§2.2) or trim.
- [ ] Approve deleting `15-metallb.yml` vs keeping it as a standalone
      "metallb-only rebuild" path for some future env.
- [ ] Approve that `site.yml` lives in `dmf-infra` (generic) with only
      the wrapper in `dmf-env`.
- [ ] Timing: pre-rebuild-finish or post-rebuild? (Recommendation above:
      post-rebuild, on a second ephemeral project.)
- [ ] Approve the `bin/run-playbook.sh` `timeout 900` hard cap + the
      "log-to-file + streaming tail" invocation pattern as the default
      (§5b.1).
- [ ] Approve the Authentik blueprint preflight `!Find` probe (§5b.3).
- [ ] Approve the cert-manager CF-token scope preflight (§5b.4).
