# DMF dmf-init Bootstrap-Pause UX Tasks — Handoff (2026-06-03)

**What:** make the three dmf-init bootstrap **pauses** (`ca-cert`, `hosts-map`,
`passkey`) fully self-service in the web UI. The live sandbox exercise (env
`g830-j8ou` on `<sandbox-node-ip>`) validated dmf-init end-to-end but surfaced that
**all three pauses ship empty payloads** — the operator could only complete them
because the orchestrator pulled the data from the host (CA via `kubectl`, enroll URL
via the helper script, hosts from the cluster). The UI must do this itself.

**Companion docs:** `docs/handoffs/DMF dmf-init Live-Sandbox Exercise Findings
2026-06-03.md` (the fix batch + live validation) and STATUS.md (operator notes).

**Scope: dmf-init only** — backend `dmf-init/src/dmf_init/`, frontend
`dmf-init/frontend/src/BootstrapView.tsx`.

---

## ✅ STATUS: DELIVERED + E2E-VALIDATED (2026-06-03)
All tasks implemented (codex), live-verified (Claude) and reviewed (qwen); pushed to
LAN `dmf-init main` (`5b41950..7456014`):
- `139b0cf`→`120703f` — **T1** live-fetch payloads + render metadata (3 live-caught bug
  fixes: order-dependent hosts.ini parse, base_domain wrong dir, CA jsonpath fragility →
  `-o json`+decode; + helper timeouts + `yaml_utils` dedup).
- `962fc6f` — **T2** pause UI (per-OS CA cmds + download, hosts block + `tee` + DNS note,
  clickable enroll link, per-pause **Verify & Continue**) + **T3** `GET
  /api/bootstrap/passkey/{run_id}`.
- `7456014` — T3 error-path tests (404/409/502).

**Full from-scratch E2E (env `fl21-cbq0`, fresh blank VM, operator-driven in the browser):**
all 11 steps DONE → **"Bootstrap verified. #2 and #3 sealed."** The three pauses were
completed *through the new UI* (ca-cert download+cmds, hosts block, clickable enroll link),
the passkey **Verify & Continue** gated on the live T3 poll, verify `failed=0`.
**Bonus:** ran `@main` with **no sidesteps** and configure passed `ok=694 failed=0` —
confirming the dmf-runbooks merge (`7d9e8b9`) **resolved #9** (mxl JTs now create cleanly).

### Follow-up findings from the E2E (dmf-init backlog)
- **Backup returns a raw 500 on a bad rclone remote.** A rejected remote config →
  `rclone copyto` exit 1 bubbled up as an unhandled 500 + traceback. `run_backup_create_new`
  should catch `subprocess.CalledProcessError` from `_validate_remote`/`_run_rclone` and
  return a clean 4xx ("remote validation failed — check remote config").
- **Re-submitting the create-new form silently creates duplicate orphan envs.** Warn/guard
  or reuse the prior render.
- **Two-click start is non-obvious:** "Continue → Run bootstrap" (mounts the panel) then a
  separate "Run bootstrap" (actually starts). Consider collapsing/clarifying.
- (Deferred, NOT dmf-init) the **dmf-cms `0.9.2` crashloop persists** — masked again by the
  fallback pod + the weak `699` smoke test; ships with the dmf-cms version bump.

### Manage teardown action — validated, with a fix (2026-06-03)
Drove the **Manage teardown action** through the new UI on `fl21-cbq0`: lock held →
**re-backup-before-destroy sealed checkpoint #4** → invoked `remove-env.sh --yes`. It
errored at "Removing environment directory": `remove-env.sh`'s rm-rf safety guards (and
fallback/message) hardcoded `${HOME}/.dmfdeploy/envs/`, refusing the stateless
`DMF_DATA_ROOT` path (same family as #1). **FIXED + pushed:** dmf-env
`feat/wizard-non-interactive` `c43401b` — derives a `DMF_DATA_ROOT`-honoring base, keeps the
must-be-under-`<data_root>/envs/` safety (still rejects outside paths), updates all 4 sites,
+ `tests/remove-env-data-root.sh`. Re-ran live → "Environment removed", env dir gone. So the
dmf-init teardown action now works end-to-end under a stateless root. **Secondary oddity:**
`remove-env.sh` runs the cloud-lane "Deleting Hetzner SSH key" step unconditionally even on a
sandbox env — confirm it's a true no-op off-cloud (don't touch a shared hcloud key).
**Still open: #12** — sandbox/bare-metal teardown removes local+cloud state but does NOT
decommission the node (k3s + platform stay running on the VM).

---

## Decisions (locked by operator 2026-06-03)
- **Payload data source = LIVE-FETCH at pause time.** The pauses run *after*
  `configure`, so the cluster is up; builders fetch fresh (no new bootstrap steps,
  reuses the existing SSH/script infra). On failure → `present:false` + an error note
  so the operator can fall back to the host (today's behavior).
- **CA OS coverage = macOS + Debian/Ubuntu.**

## Root causes (confirmed live)
- `hosts-map` empty: `render.json` never stores `node_ip`/`base_domain`
  (`createnew._write_render_metadata` omits them → `BootstrapContext.render_meta` is
  `None`).
- `ca-cert` empty: nothing exports the CA to `env_dir/ca/ca.crt`, and there is **no**
  dmf-env CA helper (only `get-passkey-enrollment-url.sh`). CA lives in the cluster
  secret `cert-manager/dmf-local-ca` (`tls.crt`).
- `passkey` empty: `build_passkey_payload` returns a "run the script on the host" hint
  instead of running it.

---

## Tasks

### T1 — Backend: populate the pause payloads (live-fetch)
File: `src/dmf_init/bootstrap_steps.py` (payload builders) + `src/dmf_init/createnew.py`
(render metadata). Reuse the inventory-derived SSH **target + key** pattern from
`dmf-env/bin/unseal-openbao.sh` (the #5 fix) — never bare `ssh`.
- **render metadata:** `createnew._write_render_metadata` must persist `node_ip`
  (from `request.sandbox.node_ip`) and `base_domain` (from the wizard output /
  rendered inventory) into `render.json`.
- **`build_hosts_map_payload`:** with `node_ip`+`base_domain` present, emit
  `<node_ip> <host>` entries for the **real ingress hosts** — live query
  `kubectl get ingress,ingressroute -A` via the env SSH target; fall back to
  `base_domain` + the standard sandbox subdomains (`console`, `auth`, `forgejo`,
  `awx`, `grafana`, `netbox`, `registry`). Include a `dns_note`.
- **`build_ca_cert_payload`:** live-fetch the CA over SSH:
  `kubectl get secret -n cert-manager dmf-local-ca -o jsonpath='{.data.tls\.crt}' | base64 -d`,
  populate `pem`/`filename`/`present:true`. On failure → `present:false` + note.
- **`build_passkey_payload`:** run `get-passkey-enrollment-url.sh <env_id>`
  (`DMF_DATA_ROOT` set), parse the `enrollment_url:` line and the
  `confirmed passkeys: N/M` line; populate `enrollment_url`, `confirmed`, `required`.
  Keep the host hint as fallback.
- **Secrets:** redact the CA PEM and the enrollment `itoken` from logs.

### T2 — Frontend: render actionable pause UI (`BootstrapView.tsx`)
- **`ca-cert`:** keep the existing **Download** button (wire to the populated `pem`),
  plus per-OS **copy-paste command blocks** with copy buttons:
  - macOS: `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Downloads/<filename>`
  - Debian/Ubuntu: `sudo cp <filename> /usr/local/share/ca-certificates/ && sudo update-ca-certificates`
  - Note: restart the browser after import (required for WebAuthn).
- **`hosts-map`:** copy-pasteable block of `<node_ip> <host>` lines + a convenience
  `sudo tee -a /etc/hosts` one-liner + the `dns_note` (WebAuthn RP ID is bound to the
  domain, so resolution is mandatory).
- **`passkey`:** render `enrollment_url` as a **clickable link**
  (`target="_blank" rel="noopener"`); show the two-authenticator steps (A via the
  link, B via Console → *Create new device invitation*); username hint = `operator`.
- **Per-pause "Verify & Continue" button** (replaces the bare resume):
  - `passkey`: the button runs a **live verify** of the confirmed count and only
    resumes when `confirmed >= required` (2/2); show `N/M`.
  - `ca-cert` / `hosts-map`: confirm-style ("I've completed these steps → Continue") —
    the operator's machine trust/hosts can't be verified from the container; resume on
    confirm. (Optional best-effort hint only.)

### T3 — (enabler for T2 passkey verify)
Expose a small endpoint (or extend the existing one) the frontend can call to return
`{confirmed, required}` passkeys live, so the `passkey` "Verify & Continue" can gate.

## Acceptance
- Every pause renders non-empty, actionable content from live data on a real bootstrap.
- `ca-cert`: download works + macOS & Debian/Ubuntu commands with copy buttons.
- `hosts-map`: real entries + DNS note.
- `passkey`: clickable URL + live 2/2 verify gating resume.
- `uv run ruff check src/dmf_init/` clean; `uv run pytest tests/` green (add unit tests
  for the 3 builders with SSH/script/cluster mocked); frontend typecheck + build green.
- No secrets in logs.

---

## Orchestration — lift / review / verify roles
This work runs on the regimented multi-agent harness (agent-bridge:
`~/.claude/skills/agent-bridge/bin/agent-bridge`; reply address auto-stamped).
- **Claude (`claude-bottom`, `%2`) — orchestrate + verify.** Owns this handoff and the
  acceptance gates; writes/derives the work order; verifies every diff
  (`ruff` + `pytest` + frontend build) and re-runs the live pause check against a
  sandbox env; accepts/rejects.
- **codex (`%1`) — implementation lifting.** Implements T1→T2→T3 from this handoff;
  starts cold, so the dispatch must be self-contained + point here. Reports
  `DONE/BLOCKED Task <n>` to `claude-bottom` via agent-bridge after each task. Stays in
  scope; no unrequested refactors; runs `ruff` every time (a regression last batch was
  pytest-invisible because a test was skip-gated — `ruff` caught it).
- **qwen-left (`%0`) — review.** Reviews each diff against the acceptance criteria
  before Claude accepts; replies `APPROVE` / `CHANGES-NEEDED:<bullets>`.

## Out of scope (deferred platform items, linked — NOT dmf-init)
- **dmf-cms `add_user_to_group` int-vs-dict bug** (`authentik.py:180`): Authentik
  returns group `users` as int PKs; code does `m["pk"]` → `TypeError` → Console
  CrashLoopBackOff on the current rollout (masked by an older fallback pod). Ship in
  the dmf-cms fix + version bump (`0.9.2` → next, with mxl-view + this fix, GHCR).
- **`699-cms-smoke-test.yml` gap** (dmf-infra): asserts only `status.phase=='Running'`
  + `/healthz` — both satisfied by a stale fallback pod, so it can't see a failed
  rollout. Harden to check container readiness / rollout status.
- (dmf-runbooks MXL launcher playbooks were merged to `main` this session — `7d9e8b9`.)

## Live state reference
- Env `g830-j8ou` is up + fully bootstrapped on the `dmf-sandbox` Lima VM
  (`<sandbox-node-ip>`, base domain `*.dmf.test`); dual-remote backups at the two
  local rclone aliases; CA in `cert-manager/dmf-local-ca`.
- Run-local sidesteps in effect (main-only): dmf-media `tmp/no-mxl-*` branch + a
  fetched-copy drop of the 4 mxl AWX-JT entries in `dmf-infra` awx-integration
  defaults. The dmf-init pause payloads can be re-exercised against this live env.
</content>
