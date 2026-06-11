---
status: executed
date: 2026-06-05
---
# DMF Sandbox E2E Test Harness Plan (2026-06-05)

A thin, script-driven, near-non-interactive from-scratch sandbox validation
pipeline. Purpose: stop re-explaining the dmf-sandbox rollout to agents every
time — encode it once as scripts + fixed values + a deterministic gate, with
captured logs. **Wrap existing `dmf-env`/`dmf-init` tooling; do NOT reimplement.**

## Locked decisions (operator, 2026-06-05)
- **Full thin harness**: reset + bootstrap + verify + one-command e2e + README.
- **Reset model = VM-recreate (pristine)**: each run recreates the Lima VM. The
  VM lifecycle is irreducibly host-side (`limactl` is macOS virtualization — a
  Linux container can't manage the host VM), so a thin **host launcher** owns it.
- **Home = `dmf-init/test/e2e/`** (versioned with the bootstrap code it tests;
  public-safe — values are fictitious, paths use `$HOME`/`/tmp`, VM IP captured
  at runtime, never hardcoded).
- **Reuse the existing verify runbook** `dmf-infra .../bootstrap-sandbox-verify.yml`
  (via `dmf-env/bin/run-playbook.sh`) for cluster/identity/console verification —
  plus the monitoring G1–G5 SSH checks for the NetBox-driven-monitoring path.
- **Passkey enrollment = built-in, default-ON, skippable** (`--no-passkeys`).
  Enroll 2 passkeys via a **CDP virtual authenticator** so `verify-d8-hardening`
  (asserts ≥2 confirmed WebAuthn devices) goes green.

## Review folds (qwen-left, 2026-06-05)
1. **`--no-passkeys` must NOT drop the D8 token-lifetime checks.** `verify-d8-hardening.yml`
   also asserts OAuth2 provider access/refresh lifetimes + invalidation flow — infra-level,
   not passkey-level. **Small dmf-infra edit:** add a distinct tag (e.g. `verify-d8-passkeys`)
   to ONLY the "Assert ... confirmed passkey count" task; `--no-passkeys` ⇒
   `--skip-tags verify-d8-passkeys` (keeps the lifetime/invalidation asserts). If the edit
   is deferred, document the gap loudly.
2. **`lib/preflight.sh` gate at the top of e2e.sh:** limactl present + daemon up; `uv`
   installed; `python -c "import dmf_init.main"` ok; 6 symlink targets exist; Playwright
   browser installed (skip only if `--no-passkeys`). Fail fast with a clear message.
3. (passkey approach revised below — enrollment-URL ×2, console drive dropped.)
4. **Scope the SSH key to the run:** bootstrap.sh runs inside its own agent —
   `eval "$(ssh-agent)"; ssh-add "$LIMA_KEY"; … ; ssh-agent -k` (trap-guarded) so a
   mid-run failure never leaves the key in the operator's host agent.
5. **Cut `--fast`** (no semantics yet). **Don't hardcode 10:** derive expected probe
   count from NetBox (count of `monitoring:probe`-tagged ipam.services), assert
   `/sd/probe` groups == that count AND > 0 AND all `up` — robust to which apps a given
   bootstrap provisions.

## Resource cleanup (MANDATORY — trap-based, runs on success AND failure)
Every script registers a `trap cleanup EXIT INT TERM`; `cleanup()` is idempotent
and frees **all ephemeral resources** so nothing lingers after a run:
- **dmf-init server**: kill the launched PID → frees `:8091`. (Track the PID;
  don't `pkill` broadly.)
- **port-forwards / tunnels**: kill any `kubectl port-forward` / SSH `-L` PIDs the
  harness started.
- **ssh-agent**: the per-run agent is killed (`ssh-agent -k`) — key never lingers
  in the operator's host agent (fold #4).
- **headless browser**: Playwright context/Chromium closed even on exception
  (`try/finally` / context manager).
- **background jobs + temp scratch**: any `&`'d helpers reaped; transient temp
  files removed. **Keep** the run-dir logs and `/tmp/backups` (those are outputs).
- **preflight also pre-cleans**: if `:8091` is already bound or a stale dmf-init
  from a prior aborted run is running, free/kill it before launching (so re-runs
  never collide). Same for a stale ssh-agent env.
- **VM lifecycle**: ephemeral cleanup NEVER touches the VM. VM teardown is an
  explicit `--teardown` flag (stop+delete VM + wipe `$DMF_DATA_ROOT`); default
  leaves the VM up for inspection but everything else freed. `reset.sh` recreating
  the VM is the sanctioned VM churn.
Acceptance includes: after a successful `./e2e.sh`, `lsof -i:8091` is empty, no
orphan `dmf_init.main` / `ssh-agent` / `chromium` / `port-forward` processes from
the run remain.

## Statelessness
All runtime state is ephemeral: `DMF_DATA_ROOT=/tmp/dmf-init-montest`, backups
`/tmp/backups/{a,b}`, logs `/tmp/sandbox-e2e/runs/<ts>/`. Wipe = clean slate.
Only the harness *code* persists (in `dmf-init`). The `reposrc` mirror
(`/tmp/dmf-init-reposrc`, 6 symlinks → local repos) is source, re-seeded by reset.

## Architecture: thin host launcher + reusable stages
```
dmf-init/test/e2e/
  profile.montest.env     # fixed values (single source of truth)
  e2e.sh                  # host entrypoint: reset -> bootstrap -> verify [-> passkeys] -> report
  lib/reset.sh            # recreate VM (wraps dmf-env recreate-sandbox-vm.sh) + wipe data root/backups + reseed reposrc (6)
  lib/bootstrap.sh        # ssh-add lima key; launch dmf-init; drive the API non-interactively
  lib/verify.sh           # run bootstrap-sandbox-verify.yml via run-playbook.sh + G1-G5 monitoring gate; structured PASS/FAIL + exit code
  lib/passkeys.py         # CDP virtual-authenticator: enroll passkey #1 (enrollment URL) + #2 (console); Playwright
  lib/_common.sh          # logging helpers, run-dir, source profile
  README.md               # agent-facing: "run ./e2e.sh"; what each stage does; flags
```
`e2e.sh` flags: `--no-passkeys`, `--keep` (don't teardown),
`--only reset|bootstrap|verify|passkeys`. Every stage tees to the run dir; final
line is a one-screen PASS/FAIL summary + exit code (0 green). First stage is
always `lib/preflight.sh` (see review fold #2).

## Fixed values (`profile.montest.env`)
```
OPERATOR_USERNAME=montest-op
OPERATOR_EMAIL=montest@dmf.test
OPERATOR_DISPLAY="Montest Operator"
PASSPHRASE=montest-test-pass            # backup passphrase (throwaway sandbox)
DMF_DATA_ROOT=/tmp/dmf-init-montest
REPO_BASE_URL=file:///tmp/dmf-init-reposrc
REPOSRC_DIR=/tmp/dmf-init-reposrc
BACKUP_A=/tmp/backups/a
BACKUP_B=/tmp/backups/b
DMF_BIND_PORT=8091
VM_NAME=dmf-sandbox
LIMA_KEY=$HOME/.lima/_config/user       # SSH key for the node; guest user = $USER; iface lima0
REPOS=(dmf-env dmf-infra dmf-runbooks dmf-cms dmf-media dmf-promsd)
SANDBOX_BASE_DOMAIN=montest.dmf.test
# probe-target count is DERIVED at verify time from NetBox (monitoring:probe tag),
# not hardcoded — assert /sd/probe groups == that count, >0, all up.
```
VM IP is discovered at runtime from `recreate-sandbox-vm.sh` stdout — never stored.

## Stage contracts

### reset.sh
1. `dmf-env/bin/recreate-sandbox-vm.sh -y` → capture NEW_IP (stdout).
2. `ssh-keygen -R $NEW_IP`.
3. wipe `$DMF_DATA_ROOT`, `$BACKUP_A`, `$BACKUP_B`; `mkdir -p` backups.
4. rebuild `$REPOSRC_DIR` with 6 symlinks → `$UMBRELLA/<repo>/.git`.
Emits `NEW_IP` for downstream. (This is the only host-bound, sudo/destructive
stage — wrapping it makes it one approvable unit.)

### bootstrap.sh  (drives the non-interactive dmf-init API)
Contract already proven — mirror `docs/plans/DMF Montest Fresh-Bootstrap
Validation Task 2026-06-04.md`:
- `ssh-add $LIMA_KEY` into the agent the dmf-init process uses.
- launch dmf-init (`uv run python -m dmf_init.main`, backgrounded, log captured);
  grab the single-use token from stdout; `GET /?token=` → cookie jar.
- `POST /api/repos/fetch` (6 repos) → `/api/render` (CreateNewRenderRequest:
  operator + sandbox{label montest, node_ip NEW_IP, ansible_user $USER, iface
  lima0, ssh_private_key = PEM CONTENTS of $LIMA_KEY}) → `/api/backup` →
  `/api/bootstrap/start` (exactly 2 remotes = BACKUP_A/B as rclone `local`) →
  stream to completion; resume any pause autonomously (sandbox unseal from
  `$DMF_DATA_ROOT/envs/<env>/openbao-keys.json`). Emits `ENV_ID`.

### verify.sh  (REUSE the runbook + monitoring gate)
- `dmf-env/bin/run-playbook.sh $ENV_ID .../bootstrap-sandbox-verify.yml`
  (with `DMF_DATA_ROOT` set). `--no-passkeys` ⇒ add `--skip-tags verify-d8-hardening`.
- Monitoring gate (SSH to node, ops-admin auth over `https://127.0.0.1:8200`
  `BAO_SKIP_VERIFY`): **G1** `promsd_api_token` non-empty; **G2** ESO
  `monitoring/dmf-promsd-netbox` `netboxToken` non-empty + synced; **G3** adapter
  Running + anon-NetBox 403 vs token 200; **G5** `/sd/probe` == EXPECTED_PROBE_TARGETS
  groups + Prometheus (route-prefix `/prometheus`) `netbox-probe` all up.
  (Query the adapter/prometheus from the prometheus pod — dmf-promsd image has no
  wget/curl.) Structured PASS/FAIL per gate; non-zero exit on any fail.

### passkeys.py  (CDP virtual authenticator — default ON)  [revised per review]
- Headless Chromium with `--host-resolver-rules="MAP *.$SANDBOX_BASE_DOMAIN <NEW_IP>"`
  (no /etc/hosts). Add a virtual WebAuthn authenticator (CDP `WebAuthn.enable` +
  `addVirtualAuthenticator`, internal/resident/UV=true).
- **Enroll BOTH via the enrollment-URL flow — NOT the console.** `verify-d8-hardening`'s
  own fail_msg sanctions this: "re-run to mint the next enrollment URL, enroll another
  device." So: loop ×2 → `get-passkey-enrollment-url.sh $ENV_ID` (mints a fresh itoken
  each call) → open URL → virtual authenticator auto-signs the Authentik ceremony →
  confirmed device. This drops the fragile console "add passkey" UI drive entirely.
- **Fallback** (only if the browser ceremony proves flaky): pre-seed the 2nd confirmed
  WebAuthnDevice via `kubectl exec` into Authentik (`ak` mgmt / ORM). Assertion-only,
  no UI. Keep enrollment-URL as the happy path; fall back on timeout.
- Poll until ≥2 confirmed. Isolated stage — a failure here only fails the passkey
  gate, never corrupts the cluster.

## Acceptance
- `./e2e.sh` from a clean machine → green: VM rebuilt, bootstrap complete,
  `bootstrap-sandbox-verify.yml` passes (incl. D8 via enrolled passkeys), G1–G5
  monitoring green, exit 0, logs under `/tmp/sandbox-e2e/runs/<ts>/`.
- `./e2e.sh --no-passkeys` → green minus D8 (skips browser).
- README lets a fresh agent run it with zero extra context.
- Public-safe: no real IPs/operator-identity hardcoded (gitleaks clean).

## Build orchestration
codex builds (it has full session context: the API contract, the gates, the
unseal autonomy, the born-inventory + token fixes). qwen-left reviews. Claude
verifies by running `./e2e.sh` end-to-end. Land on `main` in `dmf-init`
(+ the verify monitoring-gate helper may need nothing in dmf-infra — reuse only).
```

---

## V2 — agent-ergonomic playbook/stage runner (deferred; build after full-e2e is green)

**Problem it solves (the real one).** The friction isn't "stage vs full deploy" —
it's that **every agent re-derives the SOPS / age-key / `DMF_DATA_ROOT` plumbing
from scratch**. This cost real time on 2026-06-05: codex bypassed `run-playbook.sh`
with raw `ansible-playbook` because it couldn't get SOPS working; Claude had to dig
out that the missing piece was `SOPS_AGE_KEY_FILE=$DMF_DATA_ROOT/runs/<env>/age/keys.txt`.
That knowledge must live in **one command**, not in each agent's head.

**The verb.** A thin runner that targets the **existing live env** (no redeploy):
```
e2e.sh run playbooks/691-netbox-sot.yml     # one playbook against the live cluster
e2e.sh stage configure                       # re-run a whole stage (pre-seed|post-seed|configure|verify)
```
It auto-resolves the current env id, sets `DMF_DATA_ROOT` + `SOPS_AGE_KEY_FILE`, and
runs — the agent never types a key path or env var.

**Two values (both real):**
1. **Fast iteration** — re-run one playbook/stage in ~2 min instead of a ~30-min
   from-scratch rebuild. (Directly the loop we burned on the mxl/693 failures.)
2. **Day-2 coverage** — running "through the container" exercises dmf-init's
   **Manage `rerun-playbook`** action, the operator path the Day-0-only harness
   never tests.

**Execution path — default through the container, with an escape hatch:**
- **`--via-manage` (default):** route through dmf-init's Manage `rerun-playbook`
  (`manage_actions.py`). Bonuses: (a) **guaranteed toolchain** — ansible/sops/kubectl
  baked into the image, so it Just Works regardless of the driving agent's machine;
  (b) exercises the real Day-2 path. Cost: needs a manage session (passphrase +
  restored OpenBao) — wire it non-interactively from the sandbox break-glass keys.
- **`--direct`:** auto-resolved `run-playbook.sh` (host-side). Simpler/faster; still
  kills the keys friction (the whole point). Use when you just want raw speed.

**Bounds / caveats:**
- Frame as "re-run *this* stage/playbook against an **existing bootstrapped env**,"
  NOT arbitrary out-of-order execution on a blank VM. Roles are mostly idempotent,
  but stages have ordering deps (configure assumes pre-seed's cluster + seeded
  OpenBao).
- Reuse the existing env; do not recreate the VM (that's the Day-0 `reset` path).

**Make-or-break: discoverability.** The payoff only lands if agents *reach for it*
instead of hand-rolling (like codex did). MUST ship with a loud line in
`dmf-init/CLAUDE.md` + the harness README: *"To re-run a playbook/stage against the
live sandbox, use `e2e.sh run <playbook>` / `e2e.sh stage <name>` — do NOT hand-roll
SOPS/keys or call ansible-playbook directly."*

**Assessment:** highest-leverage DX piece in the harness — it removes the exact
friction this session burned time on. Slot as a v2 verb once the full from-scratch
`./e2e.sh` is green.
