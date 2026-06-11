# DMF Sandbox v0.1 Gate — Verification + Open Follow-Ups Handoff (2026-05-29)

**For:** a freshly-cleared agent picking up the DMF sandbox / v0.1 release-gate work.
**Author:** Claude (orchestrator session, 2026-05-29).
**Read this after** the boot ritual in `CLAUDE.md` and `STATUS.md`.

---

## 0. TL;DR — where things stand

- The **`sandbox-single-node` v0.1 release gate (ADR-0031) is functionally met** on a
  clean `main` bootstrap. Full cold cycle (k3s → OpenBao/ESO → Authentik/NetBox/
  Forgejo/Zot/AWX/dmf-cms/monitoring → catalog deploy/teardown) was re-verified
  end-to-end on env **`y834-bcwe`** (operator `ron-swanson` / `pawnee.dmf.test`),
  grounded on live `kubectl`/`awx-manage` (not buffered stdout).
- Three fixes shipped + proven on `main` this session: **FIX 1** scoped machine
  identity, **FIX 2** offline/galaxy-free catalog, **double-launch guard** (dmf-cms
  0.9.2). Details in §3.
- **The remaining pre-tag item is a formal fresh-clone-by-a-non-maintainer run.**
  Everything else is follow-up polish (§4).
- ⚠️ **Branch hygiene (read §1 before touching any repo).** Our work is on `main`;
  a parallel agent's `feat/mxl-single-node-spike` must not be mixed in.

---

## 1. ⚠️ Branch hygiene — READ FIRST

The 6 component repos are **shared working copies** (one checkout per repo, used by
every pane/agent). A parallel **MXL agent** keeps `dmf-env` / `dmf-infra` /
`dmf-media` on branch **`feat/mxl-single-node-spike`** with uncommitted work.

- **Before committing or running anything, verify `git -C <repo> rev-parse --abbrev-ref HEAD` is `main`** for every repo you touch. Earlier this session our commits silently
  landed on `feat/mxl` because the shared checkout was on it; recovered via
  `git branch -f main feat/mxl-single-node-spike` (pure ff, our commits only).
- **Do NOT** switch the shared checkout's branch, commit onto `feat/mxl`, merge it
  into `main`, or disturb its dirty files. See memory `feedback_verify_main_branch_before_work`.
- **Isolation pattern (use this):** for a run that needs a clean `main` without
  disturbing the shared checkout, use dedicated **git worktrees**. This session's
  worktrees are live at `~/repos/dmf-main-repro/{dmf-env,dmf-infra,dmf-cms,dmf-media}`
  (all on `main`; `dmf-cms` is `--detach` because its shared checkout already holds `main`).
  **The bootstrap reads cross-repo relative sibling paths** (`dmf-cms/VERSION`+`charts`,
  `dmf-media/catalog`) — so a worktree run needs **all** referenced repos as siblings,
  not just `dmf-env`+`dmf-infra`. (Clean these up with `git -C <repo> worktree remove <path>` when done.)

---

## 2. Boot ritual / orientation (read order)

1. `CLAUDE.md` — workspace map, conventions, cluster target.
2. `STATUS.md` — current state; the `<!-- HUMAN-START -->` block has the 2026-05-29 entries.
3. **This handoff.**
4. `docs/decisions/INDEX.md` — ADRs. Most relevant below (§5).
5. Active gate docs: `docs/plans/DMF OSS v0.1 WP1S Single-Node Sandbox Lane 2026-05-25.md`
   (§8 gate checklist, §8.1 the imc1-cyh4 findings) and
   `docs/plans/DMF OSS v0.1 WP5 Release Verification and Tagging 2026-05-25.md` (§4.1 sandbox-row).

**Verification discipline (hard lesson):** ground every claim on real artifacts —
on-disk playbook logs (`/tmp/dmf-playbook-logs/…`), live `kubectl`, `awx-manage shell`.
A sibling agent's tool channel batched/delayed output and it hallucinated a phantom
"DONE" against a non-existent env id. Never trust an exit code or a recap alone;
confirm against cluster state.

---

## 3. What landed this session (all on `main`, verified)

| Area | What | Commits / artifacts |
|---|---|---|
| **FIX 1 — scoped identity** | AWX machine tokens minted *as* the svc user (ownership binds to the authenticating principal, not a `description`). `dmf-cms-svc` + `awx-svc` self-own their tokens; `awx-break-glass` owns zero. Least-priv: execute on the catalog JTs + Inventory Use on NetBox. | `dmf-infra 64cd035`; codified **ADR-0028 §C3.1** (umbrella `0a5fb5d`) |
| **FIX 2 — offline catalog** | `netbox.netbox` + `pynetbox` baked into the AWX EE; project `requirements.yml` neutralized; DMF EE pinned on the NetBox **inventory source** (not just JTs). No `galaxy.ansible.com` egress. | `dmf-infra d2800a9` + `38d2db6`; EE `ghcr.io/dmfdeploy/awx-ee:0.1.1` (`sha256:867faa97…`) |
| **AWX single-node fit** | `MAX_FORKS` + lean requests, profile-gated; web/task limits tuned to lab-parity. | `dmf-infra 0cc2cd6` + `3b2b6db` |
| **Double-launch guard** | Console catalog deploy/teardown: backend `find_active_job_for_template` idempotency + frontend in-flight button gate. | `dmf-cms c9deb90` + `2464c0b` (v0.9.2, `ghcr.io/dmfdeploy/dmf-cms:0.9.2` `sha256:ba780f3a…`) |
| **Cold-bootstrap sops fix** | `seed-bao` re-encrypt: `--config` to per-env `.sops.yaml` + temp named to match the creation-rule. | `dmf-env 3ab4e50` |
| **Env-neutral output** | `dmf-env/bin` scripts: no stale-env defaults/examples; `get-passkey-enrollment-url.sh` wired to the dual-path resolver. | `dmf-env 1fe7db1` |
| **Docs** | ADR-0028 §C3.1, **ADR-0034 Accepted**, gate-doc folds (WP1S §8.1, WP5 §4.1). | umbrella `0a5fb5d`, `2438578`, `bdd3984`, `f8a6664`, `1947690` |

---

## 4. OPEN FOLLOW-UPS TO IMPLEMENT (ranked)

### 4.1 Formal fresh-clone-by-a-non-maintainer run (the one pre-tag gate item)
- **Why:** WP1S §8 items 1 & 9 — prove a stranger can bootstrap from public docs+repos
  on a generic ARM64 Debian host with no maintainer creds. This session's runs were
  maintainer-driven.
- **Where:** WP1S §8 / WP5 §4.1. Quickstart must state the **cross-repo siblings**
  requirement (clone *all* component repos as siblings — see §1).
- **Acceptance:** clean cold bootstrap + catalog loop from a fresh clone, documented.

### 4.2 ADR-0034 — internal Ansible collection source (permanent galaxy-free)
- **Why:** v0.1 ships the EE-bake *interim*; the permanent fix is internal collection
  resolution so nothing ever hits public Galaxy (ADR-0030 air-gap).
- **Decision (locked):** **Forgejo-git** mirrors, `type: git` pinned entries in
  `requirements.yml`; Zot-OCI deferred until `ansible-galaxy` OCI matures.
- **Plan:** `docs/plans/DMF Internal Ansible Collection Source Plan 2026-05-29.md`. ADR: `docs/decisions/0034-internal-ansible-collection-source.md`.
- **Acceptance:** full catalog loop offline with `galaxy.ansible.com` egress blocked.

### 4.3 Authentik usernameless login (operator-flagged 2026-05-29)
- **Why:** with resident passkeys enrolled, the Authentik **authentication** flow still
  prompts for username before the WebAuthn challenge — unnecessary friction.
- **Nuance:** `docs/plans/DMF Authentik Bootstrap Enrollment Drop Username Prompt Plan 2026-05-28.md`
  (status: not implemented) covers the **enrollment** flow only. This is a **separate**
  instance on the **authentication/login** flow: the identification stage needs a
  passkey-first / discoverable-credential ("Use a passkey") path. Extend that plan or
  open a sibling. ADR-0015 (passkey-only) governs. Non-blocking UX.

### 4.4 Deploy↔finalise race (catalog cross-action serialization)
- **Why:** the 0.9.2 dedup guard only dedupes the *same* action; deploy (`media-launch`,
  JT) and finalise (`media-finalise`, JT) are *different* templates, so firing them
  near-simultaneously races into pods-up + tag-`active` with a no-op finalise.
- **Fix direction:** per-catalog-entry cross-action lock (reject/queue finalise while a
  deploy for the same entry is in flight, and vice versa). Memory `project_dmf_catalog_deploy_finalise_race`.

### 4.5 Lower priority
- **Sub-second double-launch TOCTOU** — two POSTs in the same window before either job
  is created; optional DB/advisory lock. Memory `project_dmf_cms_catalog_double_launch`.
- **Changes-page CMS bugs** — `forgejo.py::list_repos` dict unwrap + AWX `order_by=-id`;
  batch into a 0.9.3 image. Memory `project_dmf_cms_changes_page_bugs`.
- **AWX EE-tag single source of truth** — `630-zot-seed` fallback is decoupled from the
  role default; hand-sync on bump. Memory `project_awx_ee_pin_gotchas`.

---

## 5. Required ADRs

| ADR | Why it matters here |
|---|---|
| `0015` passkey-only Console | login/MFA posture (§4.3) |
| `0028` Identity & Authority Chain (**§C3.1** added this session) | machine tokens minted *as* the svc identity (§3 FIX 1) |
| `0031` OSS v0.1 release-profile matrix | the sandbox gate contract (§0, §4.1) |
| `0032` / `0033` scoped NetBox writer / `zot-svc` | least-priv machine identities (siblings of FIX 1) |
| `0034` internal collection source (**Accepted**) | §4.2 |
| `0010` `run-playbook.sh` only sanctioned ansible entry · `0007` secrets never in argv/transcript | operating rules |

## 6. Required skills (`.claude/skills/`)

- **`dmf-cluster-access`** — operate against the live cluster; the cluster is the truth.
- **`dmf-openbao-unseal`** — unseal procedure (sandbox uses Tier-3 1-of-1 local).
- **`dmf-cms-build-and-release`** — the ONLY sanctioned dmf-cms release path (VERSION → GHCR → 630 mirror → 650 deploy). Required for any §4.5 CMS image work. Read its §0 first.
- **`agent-bridge`** — cross-pane delegation (`~/.claude/skills/agent-bridge/bin/agent-bridge`).

## 7. Scripts + the canonical procedure

All in **`dmf-env/bin/`** (resolve envs from `~/.dmfdeploy/envs/<env>/` via `lib/_resolve_env_paths.sh`):

- `init-wizard.sh` — render a fresh sandbox env (interactive; sandbox has **no real
  secrets** except the Lima SSH key path; humorous throwaway identities are fine).
- `recreate-sandbox-vm.sh` — env-agnostic, VM-first→wizard-IP Lima VM (re)create.
- `run-playbook.sh <env> <playbook>` — sanctioned ansible entry (ADR-0010).
- `bootstrap-secrets.sh {doctor,seed-bao,export-vars} <env>`.
- `get-passkey-enrollment-url.sh <env>` — mint the operator passkey enrollment URL (resolver-wired).
- `unseal-openbao.sh <env>`.

**Canonical bootstrap sequence** (from the wizard's printed next-steps; run from the
`dmf-env` dir/worktree, playbooks resolve `../dmf-infra/k3s-lab-bootstrap/…`):
```
bin/bootstrap-secrets.sh doctor <env>
RUNBOOK_TIMEOUT=5400 bin/run-playbook.sh <env> ../dmf-infra/k3s-lab-bootstrap/bootstrap-sandbox-provision-pre-seed.yml
bin/bootstrap-secrets.sh seed-bao <env>
RUNBOOK_TIMEOUT=5400 bin/run-playbook.sh <env> ../dmf-infra/k3s-lab-bootstrap/bootstrap-sandbox-provision-post-seed.yml
RUNBOOK_TIMEOUT=5400 bin/run-playbook.sh <env> ../dmf-infra/k3s-lab-bootstrap/bootstrap-sandbox-configure.yml
RUNBOOK_TIMEOUT=5400 bin/run-playbook.sh <env> ../dmf-infra/k3s-lab-bootstrap/bootstrap-sandbox-verify.yml
```
Expect `bootstrap-sandbox-verify` to fail **only** on the ADR-0028 D8 passkey gate
(≥2 enrolled operator passkeys) until a human enrolls via the browser — that is the
one un-automatable step.

**Catalog loop (machine path, as `dmf-cms-svc`):** the JTs are `media-launch-nmos-cpp`
(deploy) and `media-finalise-nmos-cpp` (finalise). Launch the deploy, wait for it to
**fully complete** (pods Running) before finalise (avoid the §4.4 race). To attribute to
`dmf-cms-svc`, launch via the Console's stored AWX token (read node-side, never echoed —
ADR-0007) or AWX's programmatic path with `created_by=dmf-cms-svc`.

---

## 8. Live state (as of 2026-05-29)

- **Env `y834-bcwe`** bootstrapped on Lima VM `dmf-sandbox` (node IP in
  `~/.dmfdeploy/envs/y834-bcwe/inventory/hosts.ini` — the VM's bridged LAN IP),
  at clean slate (catalog torn down). Operator **`ron-swanson`**, base domain
  **`pawnee.dmf.test`**, apps at `console|auth|netbox|forgejo|awx|grafana|registry.pawnee.dmf.test`.
  Reach from a workstation via `/etc/hosts` entries → node IP + local-CA trust.
- **Worktrees** at `~/repos/dmf-main-repro/{dmf-env,dmf-infra,dmf-cms,dmf-media}` (all `main`).
- **Teardown when done:** `rm -rf ~/.dmfdeploy/envs/y834-bcwe && limactl delete -f dmf-sandbox`
  + `git -C <repo> worktree remove ~/repos/dmf-main-repro/<repo>` for each.
- **`ops-admin`** is the OpenBao automation/break-glass identity — NOT a human login.

## 9. Relevant memories
`feedback_verify_main_branch_before_work` · `project_awx_token_ownership_authenticating_principal` ·
`project_awx_ee_pin_gotchas` · `project_sandbox_sops_config_class_bug` ·
`project_dmf_cms_catalog_double_launch` · `project_dmf_catalog_deploy_finalise_race` ·
`project_dmf_cms_changes_page_bugs` · `project_dmf_sandbox_local_vm`.
