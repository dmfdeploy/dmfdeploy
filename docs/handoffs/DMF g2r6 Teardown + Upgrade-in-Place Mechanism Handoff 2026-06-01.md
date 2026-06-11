# DMF Handoff — g2r6 Teardown + Upgrade-in-Place Mechanism (2026-06-01)

**Canonical handoff** (most-recent file in `docs/handoffs/` per the boot ritual).
Self-contained for any agent — Claude, Qwen, or Codex. Read this, then the two
linked plan docs, then `STATUS.md`.

---

## 0. One-paragraph summary

A failing catalog **teardown** on the Hetzner env `g2r6-foa9` was root-caused to
**ADR-0032 token skew** and fixed at the AWX-JT level — but attempting to *exercise*
the fix exposed that **upgrade-in-place ("re-run pre/post/configure to reach current
`main`") does not work on cloud-lane envs**: a cascade of pre-ADR drift gated behind a
**`seed-bao` cloud-lane write-back bug**, and the fact that **`seed-bao` is not even
invoked by the bootstrap plays**. We assessed, documented, and (operator-decided)
**tore down `g2r6-foa9` + the two Aliyun MXL-spike media nodes**. The upgrade-mechanism
fix and a clean rebuild (with a mandatory Hetzner CCM bump) are the open work.

---

## 1. Current state (verified)

- **`g2r6-foa9` (Hetzner): DESTROYED.** 3× CAX21 nodes, firewall, private
  network+subnet, Cloudflare records, Traefik LB — all gone. Tofu state holds no
  managed resources. Verified: no g2r6 servers/networks/LBs in `k3s-infra-lab`.
- **Aliyun MXL media nodes `aliyun-media-01/02`: DESTROYED** (env `aliyun-media`
  in the `dmf-mxl-spike` worktree) — 14 resources (ECS×2 + VPC/vswitch/SG/keypair).
- **Shared SSH key `k3s-hetzner`: PRESERVED** (it's `prevent_destroy`'d shared lab
  infra — must survive env teardowns).
- **Upgrade-in-place mechanism: STILL BLOCKED** (see §3). The original goal.
- Nothing running. No live DMF cluster currently.

---

## 2. What happened, in order (the narrative)

1. **Teardown 502 → ADR-0032 root cause.** Catalog `media-finalise-nmos-cpp` failed
   at the NetBox `ipam/services/{id}` PATCH (403). ADR-0032 (`dmf-runbooks bf332bb`,
   2026-05-27) dropped the NetBox admin token; the role now writes with
   `vault_netbox_catalog_token`, falling back to the read-only token on pre-0032
   envs. g2r6 (2026-05-21) predates it. **Fixed** by re-running `691-netbox-sot` +
   `693-awx-integration` — the JT now injects `vault_netbox_catalog_token`.
2. **OpenBao unseal detour.** g2r6's bao was sealed; `bin/unseal-openbao.sh` *fails on
   hardened envs* — `Defaults use_pty` in sudoers makes `sudo` drop piped stdin, so the
   share never reaches `bao operator unseal` (NOT an SSH-key issue). Workaround: re-run
   `playbooks/vertical-security/100-openbao.yml` (auto-unseals via Ansible `become` +
   argv, `use_pty`-immune). OpenBao is correctly **not** ingress-exposed — keep it that way.
3. **Cascade of pre-ADR drift** surfaced trying to exercise the fix: missing EE image
   (tag skew — Zot has `awx-ee:0.1.0`, current main wants `0.1.1`), missing ADR-0033
   `zot_service_password`, and the **`seed-bao` `bundle_set` write-back bug** that
   blocks backfilling those secrets.
4. **Assessment + recommendation:** wipe g2r6 (contaminated fixture), fix the mechanism
   bugs (not g2r6-specific), validate idempotency on a controlled `main~N → main` skew
   env. Documented as a plan; **Codex ran a read-only review** and corrected two
   over-optimistic claims (folded in — see §3).
5. **Teardown executed** (operator-decided). Hit two recurring Hetzner-teardown
   gotchas (§4).

---

## 3. Open work (priority order)

### 3.1 Fix the upgrade-in-place mechanism — **keystone**
Plan: [`docs/plans/DMF Idempotent Upgrade-in-Place Mechanism — Findings and Plan 2026-06-01.md`](../plans/DMF%20Idempotent%20Upgrade-in-Place%20Mechanism%20%E2%80%94%20Findings%20and%20Plan%202026-06-01.md)
- **`seed-bao` `bundle_set` aborts (exit 1) on the cloud lane** — root cause UNPROVEN
  (failure precedes the `sops --encrypt` step; the repo-level-`.sops` theory is likely
  a red herring). Instrument first (per-step exit markers on a throwaway bundle; **no
  `set -x`** — leaks secrets).
- **`seed-bao` is NOT invoked by the bootstrap plays** (comments only). Upgrade needs a
  seed step *added* to the sequence (an `upgrade` wrapper, or have the flow run+verify it).
- **De-mask failures:** never pipe `seed-bao` through `tee`/non-`pipefail` wrappers
  (it masked exit-1 as 0 this session).
- **Validate** on a controlled skew env, not on organic drift.

### 3.2 Rebuild — **mandatory CCM bump first**
Plan: [`docs/plans/DMF Hetzner CCM Upgrade Plan 2026-06-01.md`](../plans/DMF%20Hetzner%20CCM%20Upgrade%20Plan%202026-06-01.md)
- Bump `hcloud_ccm_version` ≥ **v1.30.1** in `dmf-env/tasks/hetzner/ccm.yml:15` before
  standing up *any* new Hetzner env — v1.26.0 **crashes after 30 Jun 2026** (datacenter
  API removal). Version path (1/2/3) is an open operator decision (§4 of that plan).

### 3.3 Script bug fixes (surfaced this session)
- **`dmf-env/bin/tf-destroy.sh` LB-detach is broken** — compares network *name* vs the
  LB's network *ID* → always skips detach → subnet/network destroy hangs ~20min then
  times out. (§4 has the manual workaround.)
- **`dmf-env/bin/unseal-openbao.sh`** — `use_pty` stdin bug; proper fix is a node-local
  internal OpenBao API `PUT /v1/sys/unseal` (no sudo, no public ingress).

---

## 4. Hetzner env teardown — the procedure (two gotchas)

`bin/tf-destroy.sh <env>` is **Hetzner-only**; Aliyun uses
`bin/tf-apply.sh <env> destroy -auto-approve`.

1. **Shared SSH-key `prevent_destroy`** (`terraform/modules/hetzner/cluster/main.tf:41`)
   aborts the destroy plan. Drop the key from the env's state (it stays in Hetzner):
   ```
   bin/tf-apply.sh <env> state rm -lock=false module.cluster.hcloud_ssh_key.k3s
   ```
   (`-lock=false` = the JuiceFS backend's normal single-operator mode; the auto-mode
   classifier may block it — operator runs it.)
2. **Detach the CCM LB from the private network before destroy** (the script's auto-detach
   is buggy):
   ```
   hcloud --context <ctx> load-balancer detach-from-network <env>-traefik --network <env>-private
   ```
   The Traefik LB is **data-sourced** in TF — detach, don't delete, until `tofu destroy`
   completes; then `hcloud ... load-balancer delete <env>-traefik`.
3. Re-run `bin/tf-destroy.sh <env>`; sweep with `hcloud --context <ctx> server/network/load-balancer list`.

> Memory pointer (Claude): `project_hetzner_env_teardown_gotchas`,
> `project_unseal_openbao_use_pty_bug`, `project_seedbao_bundle_set_bug`,
> `project_adr0032_catalog_teardown_skew`.

---

## 5. Reference index

### Plans / decisions
- [Idempotent Upgrade-in-Place — Findings & Plan](../plans/DMF%20Idempotent%20Upgrade-in-Place%20Mechanism%20%E2%80%94%20Findings%20and%20Plan%202026-06-01.md) (Codex-reviewed)
- [Hetzner CCM Upgrade Plan](../plans/DMF%20Hetzner%20CCM%20Upgrade%20Plan%202026-06-01.md)
- [`STATUS.md`](../../STATUS.md) — operator notes (🟢 teardown) at top
- ADRs: [`docs/decisions/INDEX.md`](../decisions/INDEX.md) — **0032** (scoped NetBox
  writer), **0033** (zot-svc machine-write), **0028** (identity & authority chain),
  **0024** (two-identity admin)

### Skills / procedures (`.claude/skills/`)
- `dmf-cluster-access/SKILL.md` — SSH-to-control-node reads, write-via-playbook, §0 secrets discipline, §5 destructive ops
- `dmf-openbao-unseal/SKILL.md` — 3-of-5 Shamir unseal (note the `use_pty` caveat above)
- `dmf-cms-build-and-release` — VERSION-driven console build → GHCR → Zot (630) → deploy (650)
- `agent-bridge` — multi-agent tmux messaging (§6)

### Scripts (`dmf-env/bin/`)
- `tf-apply.sh` / `tf-destroy.sh` / `tf-render-inventory.sh` — Layer-1 OpenTofu (Hetzner/Aliyun/AWS)
- `bootstrap-secrets.sh` — `init`, **`seed-bao`** (seeds OpenBao + bundle write-back), **`export-vars`** (sops-decrypts bundle → Ansible vars), `bundle_set`/`bundle_field`
- `run-playbook.sh` — wraps `ansible-playbook`; exports bundle secrets to a temp vars file
- `unseal-openbao.sh` — manual Shamir unseal (`--status` is read-only)
- `dmf-cms/scripts/` — `build-image.sh`, `publish-to-ghcr.sh`, `verify-cluster.sh` (canonical cluster-image-vs-VERSION lens)
- MXL spike (`~/repos/dmf-mxl-spike/dmf-env/bin/`): `mxl-media-init-creds.sh`, `mxl-media-join.sh`, `tf-apply.sh`/`tf-destroy.sh` (env `aliyun-media`)

### Workflows / playbooks (`dmf-infra/k3s-lab-bootstrap/`)
- Upgrade/build sequence: `bootstrap-provision-pre-seed.yml` → *(operator: `seed-bao`)* →
  `bootstrap-provision-post-seed.yml` → `bootstrap-configure.yml`; `lifecycle-provision.yml` / `site.yml` chain these
- Key plays: `playbooks/vertical-security/100-openbao.yml` (auto-unseal),
  `…/191-zot-oidc.yml`, `playbooks/630-zot-seed-platform.yml` (EE/image mirror to Zot),
  `playbooks/691-netbox-sot.yml`, `playbooks/693-awx-integration.yml`,
  `playbooks/650-dmf-cms.yml`, `playbooks/699-cms-smoke-test.yml`,
  `playbooks/verify-bootstrap-convergence.yml`
- Catalog launchers (`dmf-runbooks/playbooks/`): `launch-nmos-cpp.yml`, `teardown-nmos-cpp.yml`
- MXL spike override (NOT for main): `~/repos/dmf-mxl-spike/dmf-infra/.../playbooks/915-mxl-cms-override.yml`

---

## 6. Agent-bridge / multi-agent harness setup

The platform is driven by a supervised multi-agent tmux session wired via the
**`agent-bridge`** skill (send a prompt to another agent's pane, read its reply, keep
the conversation visible to the operator).

**Pane topology (operator's layout):**

```
┌────────────┬────────────┬────────────┐
│  qwen-left │  CLAUDE    │ qwen-right │
│ (dispatch  │ (middle-   │ (often     │
│  worker)   │  LEFT —    │  operator  │
│            │  ORCHESTR.)│  parallel) │
├────────────┴────────────┴────────────┤
│  codex  (independent review / 2nd opinion)│
└───────────────────────────────────────────┘
```

- **Claude = middle-left pane = orchestrator.** Plans, verifies, edits docs/state,
  drives cluster ops. (This handoff was written here.)
- **`qwen-left`** = preferred target for delegated implementation lifts (multi-file
  edits). Always `/clear` it and send **self-contained** context before dispatch.
- **`qwen-right`** = often busy with the operator's parallel work outside the harness;
  don't assume it's free.
- **`codex`** = independent critical review / second opinion (it ran the read-only
  review of the upgrade plan this session and corrected two claims). **Not** used for
  delegated implementation lifts.

**Protocol (from prior operator feedback):**
- Dispatch via `agent-bridge`; instruct the recipient to **reply via `agent-bridge`**
  so replies arrive as notifications (bidirectional), not poll-and-read.
- Harness-dispatched tasks must **report DONE / HALTED / BLOCKED** back via `agent-bridge`.
- After a `/clear` or context reset, re-send **full self-contained context** (the
  recipient starts cold) + the agent-bridge reply protocol.
- Claude orchestrates + verifies; it does the cluster/state-mutating work itself rather
  than delegating those.

> Memory pointers (Claude-local): `feedback_qwen_left_preferred`,
> `feedback_agent_bridge_reply_back`, `feedback_agent_bridge_report_on_finish`,
> `feedback_codex_dispatch_fresh_context`, `feedback_delegate_lifting_work`,
> `feedback_qwen_review_plans_before_exit`.
> Broader harness design: [`docs/agentic/CONSTITUTION.md`](../agentic/CONSTITUTION.md),
> [`docs/plans/DMF Agentic Harness Plan 2026-05-11.md`](../plans/DMF%20Agentic%20Harness%20Plan%202026-05-11.md).

---

## 7. Memories written/updated this session (Claude-local recall)

- `project_adr0032_catalog_teardown_skew` — pre-2026-05-27 envs: catalog PATCH 403; fix = 691+693
- `project_unseal_openbao_use_pty_bug` — hardened-env unseal failure + node-local API fix
- `project_seedbao_bundle_set_bug` — the upgrade-in-place keystone (root cause UNPROVEN)
- `project_hetzner_env_teardown_gotchas` — prevent_destroy key + LB-detach bug
- (refs) `project_awx_ee_pin_gotchas`, `project_sandbox_sops_config_class_bug`,
  `project_691_kv_put_wipes_siblings`, `project_identity_two_layers`

---

## 8. Suggested next action

1. Decide CCM version path (CCM plan §4).
2. Instrument + fix `seed-bao bundle_set` (upgrade plan §6.1); add the seed step to an
   upgrade wrapper; de-mask failures.
3. Stand up a **controlled skew env** (deploy at a pre-ADR `main`/tag → upgrade to
   `main`) to validate idempotent upgrade — plus a fresh current-`main` env for the
   re-run-is-a-no-op half.
4. Fix `tf-destroy.sh` LB-detach + `unseal-openbao.sh` (internal API) as cleanup.
