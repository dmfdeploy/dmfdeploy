# DMF Agent-Trio Session + #94 `no_log` Audit Handoff — 2026-06-18

**For:** a freshly-cleared orchestrator agent picking up where this session left off.
**Primary in-flight task:** umbrella issue **#94** (dmf-infra admin-credential `no_log`
audit) — *scoped and policy-grounded, NOT yet implemented (no branch, no code).*
**Working mode:** agent trio (Claude orchestrator + qwen implementer + codex adversary)
via the `issues-cruncher` skill + `agent-bridge`.

---

## 0. How to use this handoff

1. Run the umbrella boot ritual (CLAUDE.md): `git fetch && git pull`,
   `bin/generate-status.sh`, read this file, skim `docs/decisions/INDEX.md`.
2. Read **§5 (the trio)** and **§6 (#94)** carefully — they carry the non-obvious
   context. Then jump to **§7 (concrete next steps for #94)**.
3. Verify the trio panes BEFORE dispatching (see §5.1 — the agent-bridge role labels
   were scrambled all session; routing was done by *verified* role, not by name).

---

## 1. What shipped this session (all merged + closed)

A cluster of RPi-4B-sandbox bring-up defects + tooling, all crunched with the trio:

| Issue | Repo | What | PR |
|---|---|---|---|
| #88 | dmf-infra | Harden Authentik `ak shell` OAuth reads vs worker-restart races (shared `common/authentik-oauth-credentials` role: readiness gate → sentinel-gated retried exec → robust parse → no-leak block/rescue; rewired 6 consumers) | dmf-infra#8 |
| #86 | dmf-init | Default `DMF_REPO_BASE_URL` to public org `https://github.com/dmfdeploy` | dmf-init#17 |
| #87 | dmf-init | Resume-from-failed-phase (retry endpoint + run-state `failed_step_id` + redacted `no_log` hint + React retry UI + stream re-attach) | dmf-init#18 |
| #92 | dmf-infra | Gate AWX admin-password sync on **`awx-task` Deployment readiness** (= DB migration done) instead of `awx-web` | dmf-infra#9 |
| #90 | umbrella | **agent-bridge durable-marker rewrite** (see §5) | dmfdeploy#91 |
| #89 | dmf-infra | `no_log` on secret-RENDER tasks across the **6 OAuth consumer roles** (OIDC `client_secret` Secrets + Helm-values files + redact librenms debug + netbox assert) | dmf-infra#10 |

**Follow-ups filed:** #94 (this handoff's task), and #89 was itself a follow-up filed mid-#88.
**Release:** **dmf-init v0.3.0** cut + tagged + published to GHCR (`:latest` + `:0.3.0`,
multi-arch) **and** air-gapped bundle tarballs attached to the v0.3.0 GitHub Release
(amd64 needed one re-run after a transient `get.helm.sh` flake).

---

## 2. ⚠️ Release freshness gotcha (decide if it matters)

The dmf-init **v0.3.0 air-gapped bundle was built ~14:09Z, BEFORE #89 merged (17:21Z)**.
So:
- **Networked image** (`ghcr.io/dmfdeploy/dmf-init:latest`): clones `dmf-infra@main` at
  **runtime** → always has #88/#92/#89. No action needed.
- **Air-gapped bundle** (v0.3.0 tarballs): baked `dmf-infra@main` at build time → has
  #88/#92 but **NOT #89** (and won't get #94 when it lands).
- **If air-gapped parity matters:** cut **dmf-init v0.3.1** after #94 lands (bump
  `VERSION` + `pyproject.toml` + `frontend/package.json` + `package-lock.json` in
  lockstep, PR, then `git tag v0.3.1 && git push origin v0.3.1` → triggers
  `publish-image.yml` + `build-bundle.yml`). Tagging is a **public-publish action — get
  operator approval** (operator authorized the v0.3.0 tag explicitly this session).

---

## 3. Open backlog (besides #94)

- **#93** — dmf-infra resource governance for constrained single-node (cap AWX operator
  CPU + give `authentik-worker`/`-server` QoS requests + relax liveness probe).
  **v0.2**, larger, and **overlaps the in-flight AWX scale-to-zero plan** (branch
  `docs/awx-on-demand-scale-to-zero-plan`, "qwen-right's reviewed plan"). **Do NOT
  trio-crunch in isolation** — reconcile with that plan first.
- The umbrella is currently on branch `docs/awx-on-demand-scale-to-zero-plan` (shared
  tree). Don't assume `main`.

---

## 4. The repo / environment facts you need

- **Component repos are siblings of the umbrella**: `../dmf-infra`, `../dmf-init`, etc.
  (not nested). Code edits go in component repos; docs/plans in the umbrella.
- **dmf-infra roles live under `k3s-lab-bootstrap/roles/`** (not `roles/` at repo root).
- **CI gates (dmf-infra)** = `yamllint .`, `ansible-lint playbooks/ -p`,
  `ansible-playbook playbooks/*.yml --syntax-check` (per playbook), `helm-lint`.
  Reproduce locally; they pass clean on `main`. (`yamllint`/`ansible-lint` were installed
  via `brew` this session; `ansible-playbook` is on PATH.)
- **Commit hygiene:** `git commit -s` (DCO sign-off) **REQUIRED**; **no `Co-Authored-By`**,
  no "Generated with" trailer. Conventional-commit subject (commitlint gate).
- **Closing issues cross-repo:** from a component repo use the **fully-qualified**
  `Closes dmfdeploy/dmfdeploy#N`. Bot rebase-merge **severs auto-close**, so issues stay
  OPEN after merge — close manually with a PR-linked comment (operator authorized this
  repeatedly this session) or wait ~24h for the daily reconciler.
- **Install hooks per clone:** `bin/install-hooks.sh` (sets `core.hooksPath`).
- **PR review:** all PRs are `REVIEW_REQUIRED`; the bot author can't self-approve.
  The approving reviewer (per CODEOWNERS) approved + rebase auto-merged each PR.

---

## 5. The agent trio — how to operate it (READ THIS)

Roles: **orchestrator** (you, Claude — ~80% of the value: scope + verify + git/PR),
**implementer** (qwen — precise lifting), **adversary** (codex — completeness/cross-check).
Driven via `~/.claude/skills/agent-bridge/bin/agent-bridge` over tmux panes.

### 5.1 ⚠️ agent-bridge role labels were SCRAMBLED all session — verify, don't trust names

The tmux session (`work`) had mislabeled panes. **agent-bridge was rewritten this
session (#90)** to use **durable tmux pane markers** (`@ab_role` / `@ab_agent`), and the
live panes were re-registered to the *correct* mapping:
- **qwen (implementer)** → role **`qwen-left`** (pane %0)
- **codex (adversary)** → role **`qwen-right`** (pane %4) — *yes, the role label says
  "qwen-right" but it is the real codex; confirmed by self-report `agent=codex model=gpt-5`*
- **claude (orchestrator, you)** → pane %1 (was mis-registered as role "codex")
- `claude-bottom` (%2) = a **separate Claude doing the live RPi sandbox bring-up** (the
  source of these issues). Don't disturb it.

**Before dispatching:** run `agent-bridge doctor` (new command) and/or
`agent-bridge verify`. The new agent-bridge **fails closed** (refuses) if a role is
down/ambiguous/repurposed — it no longer silently mis-routes. If panes changed, re-`register`
(`agent-bridge register <role> %pane`). Routing was validated live: `ping codex`-equivalent
reaches the real codex.

### 5.2 Dispatch / reply protocol

- Multi-line briefs: `agent-bridge send <role> - <<'EOF' … EOF`.
- Every send auto-stamps a reply address; the recipient replies via
  `agent-bridge send <addr> -- "…"`, which **arrives in your input as a turn** (you get
  re-invoked). The reply header tells them the exact address — they should use it verbatim.
- Write long briefs to `/tmp/<issue>-brief.md` and point the implementer at it (keeps the
  send small); paste inline diffs to codex when the repo is outside its trust root.
- codex's spinner is unreadable in capture — judge by disk results, ask it to signal done.

### 5.3 The cruncher loop (per `issues-cruncher` skill)

Phase 0 preflight → **1 scope (orchestrator only — never delegate)** → 2 branch → 3
dispatch qwen → 4 codex cross-check (conditional on risk) → **5 verify on disk** → 6
commit (orchestrator commits, `-s`, no co-author) → 7 push → fresh-checkout verify → PR
(`Closes …`) → CI → land → close → cleanup branch (local + remote).

---

## 6. Key learnings this session (hard-won — apply them)

1. **VERIFY ON DISK, never the agent's report.** Re-read every diff, re-run every gate
   yourself. This caught: qwen's repeated "ansible-lint/syntax-check show only pre-existing
   errors" claims — **these were mis-scoped lint runs**; the authoritative
   `ansible-lint playbooks/ -p` was **0 failures/0 warnings** every time. Also caught a
   fake-build test gap (#87) and a self-broke-then-recovered false alarm.
2. **codex's completeness passes are the highest-value gate on secret/auth work.** On #87
   it caught two *blockers* (missing retry passphrase; a post-checkpoint-2 redaction gap
   that would have **streamed OpenBao secrets unredacted**) and a UI race. On #89 it found
   the **Helm-values-file leaks** (the biggest ones) after my own regex sweeps came back
   "clean," then a debug-print leak, then an assert `fail_msg` leak — three different leak
   *classes* across three passes.
3. **Run an automated completeness sweep, and widen the regex each round.** My #89 sweeps
   missed leaks my regex didn't model (htpasswd, gen-password, fail_msg). Don't trust a
   single sweep; widen it and have codex sweep independently.
4. **Discrimination tests must FAIL on old code.** For each fix, neutralize it and confirm
   the test/sweep flags it (done for #87/#89). Fix-author ≠ test-author where possible.
5. **`ansible.builtin.uri`/`get_url` auto-redact `url_password`** (`no_log=True` in the arg
   spec) → those are NOT leaks. **`headers:` (Authorization Bearer/token), `body`, `msg`,
   `stringData`, registered command stdout are NOT auto-redacted** → those ARE leaks. This
   is the crux of #94 (see §6 below). (codex confirmed, with the nuance that a secret also
   interpolated into `url`/`body` would still leak.)
6. **Match ceremony to risk tier.** Tier 3 (auth-flow / subprocess / concurrency / public
   contract) ⇒ full trio + expect an external review round. #88/#87/#92 were Tier 3.
7. **Scope-freeze:** discoveries → follow-up issues (that's how #89 and #94 were born),
   not unbounded expansion of the current PR.
8. **`no_log` hides diagnostics** — a documented, accepted project tension (see §6 policy).
   Mitigate with sanitized post-task debugs, never with committed `no_log: false`.

---

## 7. IN-FLIGHT TASK: #94 — admin-cred `no_log` audit (SCOPED, NOT STARTED)

**State:** Phase 1 (scope) complete + **policy-grounded plan decided**. No branch, no
code yet. dmf-infra is on `main` (clean). qwen/codex are warm on the topic.

### 7.1 The corrected problem statement

#94 was filed (during #89) citing `forgejo-bootstrap` `url_password` tasks as leaks.
**That premise is partly WRONG:** `url_password` is auto-redacted by the `uri` module
(§6.5). The **real** leak surface across the non-OAuth-consumer roles is:

| Leak | Where | Count | Real? |
|---|---|---|---|
| `Authorization: Bearer {{ admin_token }}` in `headers:` | `netbox-sot/tasks/main.yml` | **~48** | ✅ not auto-redacted |
| `Authorization: token {{ forgejo_token }}` in `headers:` | `awx-integration/tasks/main.yml` | **~11** | ✅ (but some may ALREADY have `no_log` — see §7.4) |
| `stringData: password: {{ awx_admin_password }}` | `awx/tasks/main.yml` "Create AWX admin password secret" (~L39) | 1 | ✅ clear-cut |
| `openssl rand -base64 24` registered | `forgejo-bootstrap/tasks/main.yml` "Generate Forgejo service password" (~L71) | 1 | ✅ clear-cut |
| kubectl-exec ORM token reads (register a token) | `netbox-sot` "Check NetBox for an existing … token" | a few | ⚠️ verify they output a token |
| `url_password: {{ … }}` everywhere (awx-integration, forgejo-bootstrap) | many (~40) | — | ❌ **auto-redacted, NOT leaks — leave them** |
| `*_vault_password_file_effective` path refs | several | — | ❌ a file PATH, not a secret |
| `include_role` passing password to `common/app-admin-facts` | forgejo-bootstrap "Resolve admin identity" | — | ❌ app-admin-facts is `no_log` internally |
| Zot StatefulSet `… | hash('sha256')` rollout annotation | zot (already in #89) | — | ❌ a digest, not a value |

### 7.2 The design question that was raised, and the policy answer

The ~59 Authorization-header tasks are mostly read-only API lookups, so blunt `no_log`
blinds the entire netbox-sot + awx-integration phases from operator-visible logs
(dmf-init streams logs; #87's hint surfaces tails). The operator asked to ground the call
in the docs. **The docs settle it — `no_log` is the policy:**

- **ADR-0007 (`docs/decisions/0007-secrets-never-in-argv.md`)** — secrets must not land in
  argv/env/tmp/transcripts; rule 5 explicitly: *"grep `dmf-playbook-logs/` for
  accidentally-logged secrets"* ⇒ a token in a task's logged invocation IS an
  ADR-0007-class leak.
- **Prior practice** (`docs/plans/Move 1 Gate 2 — Trials and Tribulations 2026-05-05.md`):
  the **awx-integration role already had `no_log: true` added to its Forgejo API tasks**,
  *and* the same doc records *"the `no_log: true` … hides failures"* — the project already
  chose `no_log` despite the cost.
- **`docs/plans/DMF OpenBao AppRole-Reconciler Implementation Brief 2026-05-13.md`**:
  secrets to tasks must be `no_log: true`; **"Do not commit diagnostic `no_log: false`
  tasks."**
- **`docs/plans/DMF In-Cluster Ansible Runner Pod Implementation Plan 2026-05-14.md §8.6`**
  *"`no_log: true` censors USEFUL diagnostic too"* — the tradeoff is documented; mitigation
  = sanitized diagnostics, not skipping `no_log`.
- The recent **Security Audit Remediation Spec (2026-06-15)** (6H/5M/16L) fixed
  `Authorization: token` only in **shell/curl argv** (Change 8). It did **not** cover the
  Ansible `uri`-header case → #94 closes a real gap consistent with the audit's direction.

**Decision (operator-aligned, policy-backed): proceed with codex option (b).**

### 7.3 The agreed plan for #94

1. **Clear-cut leaks (no tradeoff)** → add `no_log: true`:
   - awx `tasks/main.yml` "Create AWX admin password secret" (stringData).
   - forgejo-bootstrap "Generate Forgejo service password" (`openssl rand`, registered).
   - any netbox-sot kubectl-exec ORM task that **registers/outputs a token** (verify first).
2. **The ~59 Authorization-header tasks** → use **block-level `no_log: true`** wrapping the
   netbox-sot and awx-integration API phases (1 annotation per coherent block, not ~59 edits)
   — registers still work; only display is suppressed. Add **sanitized post-task diagnostics**
   (a `debug`/`assert` printing status/id/count/error-class, no secret) only where a failure
   point genuinely needs visibility (per §8.6 / reconciler-brief practice — don't add 59 of them).
3. **Do NOT** touch the `url_password` tasks (auto-redacted), vault-password-file-path refs,
   or the app-admin-facts include.
4. Verify: `yamllint .`, `ansible-lint playbooks/ -p` (0/0), all playbooks `--syntax-check`,
   and a completeness sweep (widen regex to headers/body/msg/stringData/register) → no
   token-bearing task left displaying a secret.
5. Risk tier: **Tier 3** (auth tokens, broad blast radius across the SoT/integration phases)
   ⇒ full trio + codex cross-check + expect a review round.

### 7.4 Reconciliation TODO before/while implementing

- **De-dupe:** Move-1-Gate-2 says some awx-integration API tasks *already* have `no_log`.
  My sweep counted current-state tasks *without* it; confirm which awx-integration tasks
  already carry `no_log` (or a block) so you don't double-wrap.
- **Verify** the netbox-sot kubectl-exec ORM "Check … existing token" tasks actually emit
  the token in registered stdout (the `netbox-token-mint-sentinel` skill is relevant).
- **Block grouping:** netbox-sot has 116 tasks, ~49 `uri` calls — confirm the
  Authorization-header tasks are groupable into one or a few contiguous blocks; if they're
  interleaved with non-secret tasks, per-task `no_log` (or small blocks) may be cleaner.
- **Out of scope for #94** (already excluded): the 6 OAuth consumer roles (done in #89).

---

## 8. Concrete next steps (do these in order)

1. Boot ritual; `agent-bridge doctor` → confirm qwen=`qwen-left`(%0), codex=`qwen-right`(%4);
   re-`register` if changed.
2. `cd ../dmf-infra && git checkout -b fix/admin-cred-no-log-94` (off `main`).
3. Re-run the completeness sweep (widen regex: `headers`/Authorization, `stringData`,
   `slurp`, `rand -base64`, registered exec stdout) to regenerate the exact current task
   list; de-dupe against existing `no_log`/blocks (§7.4).
4. Write the implementer brief to `/tmp/issue94-brief.md` (clear-cut first; then block-level
   `no_log` for the header phases + targeted sanitized diagnostics). Dispatch `qwen-left`.
5. Verify on disk; dispatch `qwen-right` (codex) for the completeness cross-check
   ("any token-bearing task still displaying a secret? any `no_log` over-hiding a needed
   diagnostic? confirm `url_password` correctly left alone").
6. Re-verify after fixes; commit (`-s`, no co-author, `Closes dmfdeploy/dmfdeploy#94`);
   push; fresh-checkout verify; PR with the evidence bundle + the ADR-0007/policy rationale;
   watch CI; on merge close #94 manually + prune branch.
7. Decide on **dmf-init v0.3.1** (§2) if air-gapped parity for #89/#94 is wanted.

---

## 9. Pointers

- Skill: `issues-cruncher` (`.claude/skills/issues-cruncher/`) — the trio playbook + tier
  rules + dmf-profile.
- Policy: ADR-0007; `docs/plans/DMF OpenBao AppRole-Reconciler Implementation Brief …`;
  `… In-Cluster Ansible Runner Pod … §8.6`; `… Move 1 Gate 2 …`; Security Audit Remediation
  Spec 2026-06-15.
- agent-bridge: `~/.claude/skills/agent-bridge/` (SKILL.md documents the new marker model);
  canonical tracked copy `.agents/skills/agent-bridge/` (merged via #90/#91).
- Live sandbox env id rotates — `bin/generate-status.sh` → `STATUS.local.md`. The issues
  came from envs `av12-zk1v` / `oq9y-mnj8` (RPi 4B). Don't touch the local RPi homelab.
