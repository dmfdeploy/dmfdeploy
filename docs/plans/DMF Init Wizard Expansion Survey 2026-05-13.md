---
status: historical
date: 2026-05-13
---
# DMF Init Wizard Expansion — Survey & Discussion

> **Not an implementation plan.** This is a survey of the current wizard and
> surrounding bootstrap tooling, mapped against the operator's intent to widen
> the wizard into the full greenfield orchestration. Code changes deferred —
> design tensions surfaced and decisions taken in §"Decisions taken".

## Context

`dmf-env/bin/init-wizard.sh` exists and works (used to commission `aliyun-123`
end-to-end on 2026-05-12). It stops at *artifact generation*: it writes the
encrypted bundle, tfvars, manifest, and inventory files, then prints a
numbered list of ten next steps for the operator to run manually
(`init-wizard.sh:610-657`).

The operator's intent is to widen it so that:

1. **Initial values** are fully selectable (today many manifest fields are
   hardcoded by provider; e.g. cluster_size=3, replica_count=2).
2. **A profile choice** drives the shape of the deployment — `cloud`,
   `flypack online`, `flypack offline`.
3. The wizard **drives the post-artifact steps too**: `tofu init/plan/apply`,
   the pre-seed playbook, the OpenBao init + unseal ritual, the seed-bao
   step, the post-seed playbook, born-inventory, and verification.

The question is *how much* of that the wizard should own, given the existing
plan (`DMF Deployment Workflow and Manifest Plan.md` §3.1) explicitly
forbids the wizard becoming a second infrastructure engine. The pragmatic
answer is **orchestrator, not engine** — the wizard becomes a state
machine that invokes existing scripts in order, with resume/skip semantics
for already-completed steps. This survey treats that as the working
hypothesis.

## What the wizard does today

`dmf-env/bin/init-wizard.sh` (661 lines, interactive bash TUI)

**Collects (operator-typed):**
- env_name, provider (`hetzner` | `aliyun`)
- operator username, email, display name
- base_domain, Cloudflare DNS token, Cloudflare zone
- workstation paths: SSH pubkey/privkey, OpenBao break-glass dir, USB share base
- provider creds: HCLOUD_TOKEN **or** Alicloud AK/SK
- B2 keyID, applicationKey, region
- optional Tailscale auth key, Headscale host

**Auto-generates:**
- 32-char bootstrap_admin password, 48-char k3s token, 60-char Authentik
  bootstrap token, plus DB passwords for authentik/netbox/awx/forgejo/zot
  (`init-wizard.sh:571-579`)

**Writes seven artifacts (atomic, refuses to overwrite):**
1. `${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>.sops.yaml` (SOPS+age encrypted bundle)
2. `${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>/object-storage.tfvars`
3. `${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>/{hetzner,aliyun}.tfvars`
4. `dmf-env/manifests/<env>.yaml` (ResourceProfile, **hardcoded `lane: cloud`**)
5. `dmf-env/inventories/<env>/group_vars/all/main.yml`
6. `dmf-env/inventories/<env>/group_vars/all/openbao_secrets.yml`
7. Appends a SOPS recipient rule to `dmf-env/.sops.yaml`

Stops there. Prints 10 manual followup commands.

## What lives downstream (and should be wrapped, not reimplemented)

| Step | Existing script / playbook | Notes |
|---|---|---|
| Validate bundle | `bin/bootstrap-secrets.sh doctor <env>` | Idempotent, fast. |
| B2 bucket create | `bin/b2-buckets.sh ensure <env>` | Idempotent. |
| OpenTofu run | `bin/tf-apply.sh <env> {init,plan,apply}` | Reads tokens from operator-local config files (`~/.config/hcloud/cli.toml`, `~/.secure/aliyun/.ay-dmfdeploy`, `~/.config/cf/dns.txt`). Logs to `/tmp/dmf-tofu-logs/`. State-locking disabled for JuiceFS backend. |
| Render inventory from TF | `bin/tf-render-inventory.sh` | Idempotent re-render of `hosts.ini`. |
| Pre-seed playbook | `run-playbook.sh <env> bootstrap-provision-pre-seed.yml` | Layer 2/3 + OpenBao install + ESO. |
| OpenBao operator init | **Manual SSH today** — `bao operator init` on control node, capture 5 Shamir shares. | The most sensitive moment; never automated. |
| Unseal | `bin/unseal-openbao.sh <env>` | Interactive. 3-of-5 Shamir: JuiceFS shares 1+2 + Keychain share 3. |
| Seed bao | `bin/bootstrap-secrets.sh seed-bao <env>` | Decrypts bundle, SSHes, writes to `secret/platform/*`. |
| Export Phase 1 audit vars | `bin/bootstrap-secrets.sh export-vars <env> <json-out>` | Called automatically by `run-playbook.sh`. |
| Post-seed playbook | `run-playbook.sh <env> bootstrap-provision-post-seed.yml` | Monitoring + Layer 6 apps. Asserts seed boundary. |
| Configure | `run-playbook.sh <env> bootstrap-configure.yml` | Cross-app OIDC/SoT wiring. |
| Born inventory | `playbooks/694-born-inventory.yml` | Drives Prometheus SD + NetBox SoT seed from facts. |
| Verify | `bootstrap-verify.yml` (master) + per-vertical gates | Tagged by vertical: resilience, monitoring, security, lifecycle. |

The bones already exist. Every step has an idempotent script. The wizard's
expansion is mostly *sequencing + resume semantics*, not new logic.

## What the operator wants the expanded wizard to also collect

Current manifest hardcodes these by provider (`init-wizard.sh:330-393`); the
expanded wizard should prompt for them:

- `cluster_size` (3 today; flypack-offline implies 1 or 3)
- `per_host.cpu.{kind,cores}`, `memory_gb`, `disk_gb`
- `network.ingress_model` (today: implicit cloud-native; flypack:
  nodeport-only or metallb-l2)
- `storage` default class + replica count (longhorn replica=2 baked in
  `main.yml:469`)
- `apps.<name>.enabled` per-app toggles (NetBox/AWX/Forgejo off by default
  for flypack — `flypack-offline-lane.md:66-76`)
- TLS mode (`factory-acme` vs `customer-provided` — flypack only)
- Backup destination (B2 for cloud; local-only for flypack-offline)
- Cluster-internal DNS, NTP/PTP timing reference (eventual)

## Profile concept — three meanings of "flypack"

The operator named three: `cloud`, `flypack online`, `flypack offline`.
What exists in docs today:

- **`cloud`** — the only operationalised lane. Hetzner CAX21 + Aliyun ECS.
  Cloud-native LBs, public+private ingress, ESO from in-cluster OpenBao,
  B2 backup, optional Tailscale.
- **`flypack` (offline)** — fully specified in
  `dmf-infra/k3s-lab-bootstrap/docs/flypack-offline-lane.md` (canonical, dated
  2026-04-18). Single-node-or-3, embedded OpenBao/Authentik/Zot, all 5
  Shamir shares to client, USB-only update packs, no phone-home. Per-truck
  FQDN under `*.truck.<lan-host>` with factory-renewed wildcard cert.
  **Not yet implemented in code** — spec only.
- **"Flypack online"** — *not* in the canonical spec. The closest reference
  is the `cloud-plus-online-flypacks` lane in
  `docs/plans/DMF Deployment Workflow and Manifest Plan.md` §6.3 and
  the "optional connected flypack" deferral at offline-lane-spec line 472.
  See decision #2 below for the working definition.

The recently-added RPi appliance plan
(`docs/plans/DMF RPi Flypack Appliance Implementation Plan 2026-05-13.md`)
implies a CMS-capable flypack that still includes NetBox/AWX/Forgejo —
which contradicts the offline-lane spec's "default off" stance. There's a
profile-toggle reconciliation pending here.

## Functions the wizard should cover (operator's list)

Mapping the operator's brief against current scripts:

1. **Customize initial values** → expand prompts; add lane-aware sections;
   render manifest from collected values (today: hardcoded constants).
2. **Profile selection** → first prompt after env_name. Drives every
   subsequent prompt (skip cloud-creds for offline flypack; ask for TLS mode
   only for flypack; ask for image-lockfile path for offline).
3. **OpenTofu init + execution** → `tf-apply.sh init` + `plan` + `apply`,
   with confirm-before-apply gate. Capture output IPs into the inventory
   via existing `tf-render-inventory.sh`. **Skipped entirely for
   flypack-offline** (no Layer-1 cloud step).
4. **OpenBao pre-seed** → invoke
   `run-playbook.sh <env> bootstrap-provision-pre-seed.yml`. Wizard then
   drives `bao operator init` over SSH (see decision #3).
5. **OpenBao post-seed** → invoke `seed-bao` then post-seed playbook then
   `bootstrap-configure.yml`.
6. **Born inventory** → run `694-born-inventory.yml` and capture the
   inventory diff for operator review.
7. **Verification** → run `bootstrap-verify.yml` per vertical, summarize
   pass/fail.

## Design tensions

### T1 — wizard-as-engine vs wizard-as-orchestrator

`DMF Deployment Workflow and Manifest Plan.md` §3.1 says the wizard "must
not own provider-specific imperative rollout logic, application install
logic, infrastructure mutation logic beyond invoking the deployment
engine." The expansion the operator described *does* invoke imperative
rollout — but only by calling existing wrapper scripts. That stays
consistent if and only if every long-running action stays in
`tf-apply.sh` / `run-playbook.sh` / `unseal-openbao.sh` and the wizard is
just a top-level state machine + UI. Worth confirming this is the
boundary.

### T2 — handling Shamir shares

The unseal ritual is the one moment that *cannot* be fully automated:
- `bao operator init` runs over SSH and prints 5 Shamir shares + root token
  exactly once. The operator must capture and distribute them
  (2→JuiceFS, 1→Keychain, 2→USB).
- `unseal-openbao.sh` then reads shares 1+2 from JuiceFS and share 3 from
  Keychain and pipes them in without ever putting them in argv/env (ADR-0007).

For the wizard to drive this, it has to either (a) prompt the operator
to paste each share into per-target storage manually mid-flow, or (b)
run `bao operator init` with `-key-shares=5 -key-threshold=3
-format=json`, capture JSON, and *automatically* split shares into
JuiceFS/Keychain/USB without them ever crossing the wizard's stdout. See
decision #3.

### T3 — resume / idempotency

The current wizard is one-shot: it refuses to run if the bundle already
exists (`init-wizard.sh:518`). An expanded wizard has 10+ steps; partial
failures will happen (tofu timeout, playbook flake, network blip). It
needs state — see decision #4.

### T4 — flypack-online definition

Cannot prompt for a profile that isn't designed — see decision #2.

### T5 — manifest schema lock-in

`ResourceProfile` schema is `v1alpha1` and currently rendered by a bash
heredoc (`init-wizard.sh:342-393`). Adding lane-conditional sections will
make the heredoc unwieldy; the rewrite (decision #6) is the right moment
to switch the renderer to a typed-object emitter.

### T6 — interactive choices vs `--config <file>` mode

CI / agentic operation will want the wizard to consume a YAML config and
run non-interactively. See decision #5.

## Decisions taken (2026-05-13 discussion)

1. **Scope of v2** — **`cloud` and `flypack offline`**. The third profile
   (online flypack) is defined here but its implementation can come after
   the first two ship.
2. **Flypack online** = **a flypack appliance with a connection to a
   linked online "hub" instance.** The hub is a cloud-deployed DMF cluster;
   the flypack is sovereign for identity/secrets/runtime, but has a
   declared trust + sync relationship with the hub for telemetry,
   inventory reporting, and (operator-pushed) updates. Practical
   implication: the wizard, when run in `flypack-online` mode, must
   collect (or be told to auto-discover) the hub's URL, the hub's
   trust anchor (cert/JWKS), and the per-flypack join token.
   Reconciliation against the offline-lane canonical spec needs an ADR
   (the offline spec currently says "no central reach" as a hard rule).
3. **`bao operator init`** — **interactive prompt for share locations.**
   The wizard runs `bao operator init -key-shares=5 -key-threshold=3
   -format=json` over SSH and captures the JSON, then walks the operator
   through "where should share 1 go?", "where should share 2 go?", etc.,
   with the default routing being the same as
   `inventories/<env>/group_vars/all/openbao_secrets.yml`
   (JuiceFS×2 + Keychain×1 + USB×2). Shares never appear in the
   wizard's stdout, argv, env, or any log (ADR-0007).
4. **Resume / idempotency** — **state file** at
   `${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>/wizard-state.json` recording per-step
   completion + checksums of inputs. Re-running the wizard prompts
   "resume from step N or restart?" and refuses to re-do destructive
   steps without explicit confirmation.
5. **Non-interactive mode** — **TBD.** The plan is to surface the *same*
   wizard inside `dmf-cms` (so the CMS becomes a second front-end over the
   same orchestration core). That implies the orchestration core must be
   library-shaped (callable from a UI, not bash-only), and that
   non-interactive consumption falls out for free. Concrete shape
   deferred.
6. **Language / rewrite** — **rewrite as required.** The wizard should be
   runnable by **"normal" GitHub users**: minimal prerequisites, no
   exotic toolchain assumptions. Likely Python (already a dependency for
   Ansible) or Go (single static binary, easiest distribution).
   Prerequisites to keep low: a working `git`, `ssh`, a recent enough
   Python or pre-built binary, and the operator's own age/SSH keys.
   Heavy deps (`tofu`, `ansible`, `sops`, `age`, `bao`) should either be
   bundled or be one-line installs the wizard itself can offer to run.
7. **Distribution** — **eventually an online installer link**, in the
   Homebrew style:

   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/<dmf-org>/<repo>/HEAD/install.sh)"
   ```

   The installer should: clone or update the umbrella + needed component
   repos to a sane location, set `$DMFDEPLOY_UMBRELLA`, check/install
   the heavy deps (`tofu`, `ansible`, `sops`, `age`, `bao` CLI),
   generate the operator's age key if missing, set
   `$DMF_BOOTSTRAP_BUNDLE_DIR`, then launch the wizard. The GitHub
   org/repo name is gated on the public-publish work (ADR pending,
   `docs/agentic/decisions-open.md` has `github-org-name` open).
   This unblocks "fresh GitHub user can deploy DMF in one command" —
   the long-term north star.

## Round 2 clarifications and decisions (2026-05-13)

Outputs of the implementation-sequence walkthrough, taken step by step.
Each subsection records the decision that closed that step plus the
artefacts/follow-ups it produced. Supersedes specific decisions in the
prior round where noted.

### Step 1 — profile model (supersedes round-1 decisions #1 and #2)

#### Canonical profile definitions

1. **`cloud`** — full DMF stack deployed to cloud infra (Hetzner CAX21 ARM
   today, Aliyun ECS pending). Already operational.

2. **`flypack-offline`** — full DMF stack on one or more **local** nodes,
   self-contained, no cloud dependency. The offline-lane spec's "no central
   reach" rule applies here and only here. Sizing is named-tier:
   - `rpi-minimal` — 1 node, local-path, RWO, slim retention. RPi5/16GB
     target. The most minimalist variant; matches the
     *DMF RPi Flypack Appliance Implementation Plan*.
   - `lab-3node` — 3 nodes, Longhorn, normal retention. Existing dev-lab
     shape.
   - `site-ha` — 3+ nodes, Longhorn, full retention. Production-ish on-prem.

   All tiers run the **full** DMF role set (openbao, authentik, zot, netbox,
   awx, forgejo, cms, monitoring). The offline-lane spec's decision-log
   entry *"No NetBox/AWX/Forgejo on flypack by default"* is superseded —
   that was scoped to a thin-slice flypack that this version no longer
   matches.

3. **`flypack-online`** — **thin local edge agent** paired to a cloud DMF
   hub. Deliberately *not* sovereign (this supersedes round-1 decision #2,
   which described flypack-online as "sovereign with hub link"). Runs only
   services that have to be local:
   - **Ship-now** (Ansible roles exist today): AWX execution node, local
     Zot (pull-through cache), Prometheus agent (`remote_write` to hub).
   - **Deferred-implementation** (no role yet): iSCSI target, NMOS registry
     at the edge (separate from the dmf-runbooks/nmos-cpp role), Kea DHCP,
     ZTP, VLAN control, DNS-SD/mDNS responder, remote-controllable
     tcpdump, other Layer-2 broadcast tooling.

   The wizard can name this profile and collect hub-pairing material in
   v2, but only enables the ship-now role subset until the deferred roles
   land. The deferred set is a separate multi-month implementation track.

#### Variable taxonomy

**Hybrid**: `profile` + `tier` + flat `dmf_*` keys + `roles:` toggle map.

```yaml
profile: flypack-offline
tier: rpi-minimal
dmf_node_count: 1
dmf_storage_class: local-path
dmf_ingress_mode: nodeport-only
dmf_observability_profile: slim
roles:
  netbox: true
  awx: true
  forgejo: true
```

The `(profile, tier)` pair selects role defaults from `dmf-infra`; flat
`dmf_*` keys override individual values; `roles:` overrides individual
on/off toggles.

#### Upgrade path

Two-stage. Stage 1 ships with wizard v2 territory; stage 2 deferred.

- **Stage 1 — expand cluster.** Add worker nodes to an existing
  flypack-offline cluster via dmf-cms. Stateful apps stay pinned to the
  primary node; new nodes run stateless workloads only. Achievable on top
  of existing k3s join; the load-bearing primitive for any future scaling
  story.
- **Stage 2 — promote to HA.** Migrate primary-only cluster to distributed
  storage + Raft-expanded OpenBao + RWX-capable pods. Per-app
  backup/restore design needed for OpenBao Raft, Authentik Postgres,
  NetBox, AWX, Forgejo, Zot, Prometheus, Loki. Own ADR + own plan.
  Deferred.

Building wizard v2 with the library shape (per round-1 decision #5) is
what makes stage 1 possible later — dmf-cms calls the same orchestrator
core the wizard uses, so "add a node" is a method on the same library.

#### Step 1 follow-ups (not done in this round)

- `dmf-infra/k3s-lab-bootstrap/docs/flypack-offline-lane.md`:
  - Decision-log entry *"No NetBox/AWX/Forgejo on flypack by default"*
    softens to *"off in any thin-slice preset; on for the full DMF
    flypack-offline profile defined here."*
  - §Profile role-toggle defaults table updates to reflect that the full
    DMF stack is the default for this lane.
- A canonical preset-definitions file in `dmf-infra` defaults that the
  wizard reads to render manifests (target shape: a YAML table keyed by
  `(profile, tier)` producing role defaults + flat `dmf_*` values).
- The flypack-online ADR (step 3 of the implementation sequence) records
  the not-sovereign framing and the ship-now-vs-deferred role split.
  → **Closed by [ADR-0022](../decisions/0022-flypack-online-thin-edge-agent.md)
  (Proposed, 2026-05-13).**

### Step 2 — language choice (supersedes round-1 decision #6)

**Python, distributed via `uv`.**

The wizard rewrite is Python. The orchestration core is shaped as a
Python package importable by `dmf-cms` (FastAPI/Python BFF) directly, so
the same `expand_cluster`, `run_step`, `seal_shamir` calls drive both the
operator-facing TUI and the dmf-cms web UI. No subprocess+JSON-lines
bridge needed for cross-component reuse.

Distribution model: an `install.sh` (per round-1 decision #7) bootstraps
`uv` if missing (its own one-line installer), then runs
`uv tool install dmf-wizard`. The operator never types `pip`, `venv`, or
`python3`. From the operator's perspective, this is functionally
indistinguishable from a Go single-binary install.

Rationale (short form):
- Already a platform prerequisite (Ansible runtime, dmf-cms BFF). Zero
  net-new language commitment.
- pydantic + ruamel.yaml is the cleanest typed-emitter path for T5
  (manifest schema lock-in).
- `subprocess.run(env=clean_env, input=share_bytes, ...)` is ADR-0007
  compliant for the Shamir handling in round-1 decision #3.
- The "single static binary" advantage Go would offer is closed by
  modern `uv`; the cross-language friction Go would introduce with
  dmf-cms is not closed by anything.

Hedge documented: if a future field-side CLI (a successor to
`truckctl` on flypack-offline appliances, or a dedicated node-join
binary for stage-1 expand-cluster on remote agents) needs to ship
*without* a Python runtime on the target, **that** tool may be Go.
This is per-tool, not platform-wide. The wizard + orchestration core
is Python.

#### Step 2 follow-ups (not done in this round)

- New ADR under `docs/decisions/` recording the Python+uv choice with
  the Go counterfactual preserved (next ADR number — current head is
  0022 after step 3).
- Decide repo location for the Python package: likely a new top-level
  component repo `dmf-wizard/` (orchestration core + TUI) or as part
  of `dmf-env/` if private-only. Component-repo discussion deferred —
  the step-4 spike landed in the umbrella as `wizard-spike/` to avoid
  premature repo commitment.

### Step 4 — orchestrator spike

Landed at `wizard-spike/` in the umbrella (intentionally spike-shaped,
not the canonical home). Validates three patterns: (1) library-shaped
orchestration core, (2) state-persistent resume semantics with input
checksums, (3) Shamir-safe subprocess wrapping per
[ADR-0007](../decisions/0007-secrets-never-in-argv.md).

Package layout: `pydantic` types, `state.py` (atomic save +
sha256 input checksum), `runner.py` (clean-env subprocess with stdin
piping; ADR-0007 callout in module docstring), `orchestrator.py`
(declarative Step list + status/run_step/resume), minimal argparse
CLI. 23 unit tests pass against fixture shell scripts; no live
infrastructure touched.

The spike is a validation, not the production wizard. When promoted,
the code lands in a `dmf-wizard/` component repo (subject to step-2
follow-up).

#### Step 4 spec gaps surfaced (inputs to step 5)

The spike implementation exposed six design questions that need
answers before the typed-emitter + lane-conditional-prompts work in
step 5:

1. **SKIPPED checksum semantics.** Current spike re-evaluates
   `can_run` on every call (no cache on SKIPPED). Step 5 question:
   should a step that was SKIPPED at checksum X stay SKIPPED on
   re-run when inputs are unchanged, or always re-evaluate the gate?
2. **`resume` does not re-attempt SKIPPED steps.** Current behaviour
   walks `PENDING | FAILED` only. Step 5 question: should resume
   re-evaluate `can_run` on SKIPPED steps in case an upstream step
   flipped the gate?
3. **Timeout exit_code convention.** Spike returns `exit_code=-1` for
   timeouts, which collides with the POSIX signal convention
   (negative = killed by signal N). Production wizard probably wants
   `exit_code: int | None = None` with `timed_out: bool = True` as
   the discriminator.
4. **Secret leak through stdout/stderr is structural-only.**
   `RunResult` has no `stdin_secret` field, so the secret cannot leak
   *structurally*. But if a wrapped script echoes its stdin to stdout
   (e.g. a misbehaving `bao operator init`), the secret would land in
   `stdout_tail`. Step 5 question: should the runner scrub
   `stdout_tail`/`stderr_tail` against the known `stdin_secret`
   before returning?
5. **`Orchestrator.__init__` profile type.** Spike takes
   `profile: str` and uses `# type: ignore` to fit it into
   `WizardState.profile: Literal[...]`. Production version should
   accept the `Profile` Literal directly (or a Profile enum), and
   tier should be a typed field too.
6. **Atomic save fsyncs file, not parent directory.** macOS APFS and
   most modern Linux filesystems journal rename, so this is mostly
   moot. The production wizard on Linux should `os.fsync` the parent
   directory after `os.replace` for power-loss durability.

#### Step 4 acceptance evidence

```
$ cd wizard-spike && uv sync && uv run pytest -v
...
23 passed in 0.32s
```

23 tests covering state persistence, subprocess runner (clean env,
stdin secret pipe, timeout, missing binary), and orchestrator state
machine (run/resume/skip/cache/force).

### Step 5a — typed schema + emitter + spec-gap fixes

Scope was deliberately bounded to the schema/emitter chunk (not the
full prompts + script bindings). Lane-conditional prompts and real
bash-script step bindings become **step 6** and **step 7** in a
follow-up session.

**Added to `wizard-spike/`:**

- `src/dmf_wizard/profiles.py` — `Profile` enum (cloud /
  flypack-offline / flypack-online), `Tier` enum (rpi-minimal /
  lab-3node / site-ha), `PRESET_DEFAULTS` table keyed by
  `(Profile, Tier | None)` with the canonical hybrid taxonomy from
  Step 1 (flat `dmf_*` keys + `roles:` toggle map). `get_defaults`
  returns a deep copy and validates the `(profile, tier)` pair.
  `VALID_TIERS_FOR_PROFILE` enforces tier-applicability per profile.
- `src/dmf_wizard/manifest.py` — discriminated-union pydantic body
  (`CloudManifest` / `FlypackOfflineManifest` / `FlypackOnlineManifest`)
  with `schema_version: Literal[1]` envelope. `build_manifest` merges
  preset defaults with operator overrides (deep-merge on `roles`,
  shallow elsewhere). `dump_yaml` / `load_yaml` round-trip via
  `ruamel.yaml(typ="safe", pure=True)` with deterministic key order
  (declared-field order, not alphabetic).

**Six step-4 spec gaps closed:**

1. **Timeout exit_code convention.** `RunResult.exit_code: int | None`.
   On timeout: `exit_code=None, timed_out=True`. Orchestrator surfaces
   `error="timed out"` (vs `error="exit N"` for non-zero exits).
2. **Stdin secret echo scrubbing.** `RunSpec.scrub_secret: bool = True`
   (default on). Runner replaces stdin-secret byte sequences in
   stdout/stderr tails with `b"[REDACTED]"` before decoding.
   Defence-in-depth on top of the structural guarantee that
   `RunResult` has no `stdin_secret` field.
3. **Parent-dir fsync.** Factored `atomic_write_text` helper in
   `state.py` (used by both state.py and manifest.py). After
   `os.replace`, opens the parent directory and `os.fsync`s the dir
   fd, wrapped in try/except for platforms without dir-fsync (Windows).
4. **`Orchestrator.__init__` profile/tier types.** Takes `Profile`
   and `Tier | None` directly. No more `# type: ignore`. Stored on
   the WizardState.
5. **`resume()` SKIPPED handling.** `resume()` walks PENDING /
   FAILED / SKIPPED. For SKIPPED steps, re-evaluates `can_run` — if
   it now returns True the step runs; if still False the SKIPPED
   result is preserved but NOT added to the returned `executed`
   list (nothing actually ran).
6. **SKIPPED checksum cache.** Retained "re-evaluate every time"
   semantics; the gate is cheap to call and gate predicates often
   depend on other steps' state. Cache would be a footgun.

**Acceptance:**

```
$ cd wizard-spike && uv run pytest -v
...
53 passed in 0.40s
```

23 original + 30 new tests. Public API additions exported from
`__init__.py` (`Profile`, `Tier`, `PRESET_DEFAULTS`, `get_defaults`,
`Manifest`, body classes, `HubReference`, `build_manifest`,
`dump_yaml`, `load_yaml`).

**Smoke-tested end-to-end:** `build_manifest` → `dump_yaml` produces
deterministic YAML for all three profiles (cloud + all 3
flypack-offline tiers + flypack-online with hub reference). Output
preserves field-declaration order, serialises enums as their string
values, and respects ADR-0022 ship-now role toggles for
flypack-online (zot/awx_execution_node/prometheus_agent on; all
others off).

#### Step 5a follow-ups (deferred to later sessions)

> **2026-05-20 convergence note.** Steps 6 + 7 below and the
> `PRESET_DEFAULTS`-to-`dmf-infra` migration are absorbed by
> [ADR-0026 (Provider Descriptors)](../decisions/0026-provider-descriptors.md).
> The descriptor schema is the canonical form the Step 6 prompts and
> Step 7 bindings read from, and Provider Descriptors are a sibling
> consolidation to the `PRESET_DEFAULTS` migration (both targeting
> `dmf-infra` as the single source of truth, both loaded via the same
> pydantic layer in the Python wizard).

- **Step 6** — lane-conditional interactive prompts. Reads
  `orch.state.profile` + `tier` to choose which questions to ask;
  flat `dmf_*` toggles surface as individual prompts; `roles:` map
  surfaces as a per-role toggle list pre-filled from
  `PRESET_DEFAULTS`. Should also support `--config <yaml>` mode for
  non-interactive consumption (groundwork for dmf-cms reuse).
- **Step 7** — real bash-script step bindings. `Step` definitions
  for `bootstrap-secrets.sh doctor`, `b2-buckets.sh ensure`,
  `tf-apply.sh init/plan/apply`, `run-playbook.sh` (pre-seed +
  post-seed + configure), `unseal-openbao.sh` (Shamir prompt walk),
  `694-born-inventory.yml`, `bootstrap-verify.yml`. Closes the
  end-to-end orchestration loop.
- **Migrate `PRESET_DEFAULTS` to `dmf-infra`.** Spike module
  docstring flags this. Source-of-truth split between wizard and
  Ansible role defaults must converge to one canonical location.
  Cross-references Step 1 follow-up.
- **`HubReference` schema.** Currently three fields (`url`,
  `trust_anchor_sha256`, `edge_id`). ADR-0022 should drive the
  final shape (mTLS material, pairing token, hub-URL TLS pin) when
  flypack-online implementation starts.
- **Promote `wizard-spike/` to `dmf-wizard/` component repo.** Once
  steps 6 and 7 land and the wizard reaches feature parity with
  the bash version, move out of umbrella into its own public repo
  (per round-1 decision #7 distribution model).

## Reference: files to read for further discussion

- `dmf-env/bin/init-wizard.sh` — current entrypoint
- `dmf-env/bin/{tf-apply,run-playbook,unseal-openbao,bootstrap-secrets,b2-buckets}.sh`
  — the scripts the wizard would orchestrate
- `dmf-env/manifests/hetzner-arm.yaml` — current manifest shape
- `docs/plans/DMF Deployment Workflow and Manifest Plan.md` — the
  prescriptive design (§3.1 wizard-not-engine boundary)
- `dmf-infra/k3s-lab-bootstrap/docs/flypack-offline-lane.md` — canonical
  flypack spec
- `docs/plans/DMF RPi Flypack Appliance Implementation Plan 2026-05-13.md`
  — recent appliance work, points to the online-flypack ambiguity
- `docs/processes/dmf-bootstrap.md` + `.bpmn` — the BPMN intent model for
  the bootstrap sequence the wizard would automate
