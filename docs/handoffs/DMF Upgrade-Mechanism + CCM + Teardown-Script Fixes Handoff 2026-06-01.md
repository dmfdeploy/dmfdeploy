# DMF Handoff — Upgrade-Mechanism + CCM + Teardown-Script Fixes (2026-06-01)

**Canonical handoff** (most-recent file in `docs/handoffs/` per the boot ritual).
Self-contained. Read this, then `STATUS.md`, then the two plan docs in §5.

This session **implemented** the fixes scoped by the prior handoff
(*DMF g2r6 Teardown + Upgrade-in-Place Mechanism Handoff 2026-06-01.md*) plus the
CCM bump. Orchestrated by Claude (orchestrator pane) with the lifting done by a
Claude worker pane via `agent-bridge`; every commit was reviewed before the next
was dispatched.

---

## 0. One-paragraph summary

Six commits across **dmf-env** (5) and **dmf-infra** (1, now 2 with k3s) landed
on `main` (**unpushed** — operator to review/push): the Hetzner CCM + k3s bump
(Path 3), the `tf-destroy.sh` LB-detach bug fix, the `unseal-openbao.sh`
`use_pty` rewrite (node-local OpenBao API), the `seed-bao`/`bundle_set`
de-masking + instrumentation + CWD-independent `.sops` hardening + a round-trip
test, a new `upgrade-in-place.sh` wrapper, and a fail-fast `seed-bao` hint on
playbook 630. **Everything except the k3s tag check is structurally validated
only — there is NO live cluster.** The remaining work is all live-env-gated:
confirm the actual `bundle_set` abort, validate idempotency on a controlled skew
env, and extend the convergence gate.

---

## 1. What landed (all on `main`, UNPUSHED)

| Repo | Commit | What | Validation |
|---|---|---|---|
| dmf-env | `adabe88` | `tf-destroy.sh` LB-detach resolves network NAME→ID before comparing `.private_net[].network` (was name-vs-ID → never detached → destroy hung). + CCM default `v1.26.0`→**`v1.31.1`** (`tasks/hetzner/ccm.yml:15`). | logic-reviewed |
| dmf-infra | `1b9976a` | k3s `v1.30.6+k3s1`→**`v1.33.12+k3s1`** (`300-k3s.yml:56,153`), Path 3 matrix-aligned with CCM v1.31.1. | tag exists (HTTP 200) |
| dmf-env | `e514bd9` | `unseal-openbao.sh`: share-feed path rewritten to the **node-local OpenBao HTTP API** (`jq -R '{key:.}' \| ssh <node> curl --data-binary @- …/v1/sys/unseal`) — no sudo → use_pty-immune; share never in argv; status path unchanged. `-k` default, `OPENBAO_CACERT` opt-in. | **UNTESTED** (no cluster) |
| dmf-env | `4335d3c` | `bundle_set` **de-masked + instrumented** (per-stage `set +e`/`set -e` fences so failures surface under `set -euo pipefail`; `DMF_BUNDLE_SET_DEBUG=1` exit-codes-only). `bundle_sops_config_file()` now CWD-independent (co-located → `$DMF_ENV_SOPS_CONFIG` → repo-level `$REPO_DIR/.sops.yaml`). New `tests/bundle-set-roundtrip.sh` (5/5 PASS incl. failure-path). | unit test passes; **root cause still UNPROVEN** |
| dmf-env | `d4306a7` | new **`bin/upgrade-in-place.sh <env>`**: OpenBao-unsealed precheck → **seed-bao DE-MASKED (no tee/pipe)** → pre-seed → post-seed → configure → verify-bootstrap-convergence + bootstrap-verify. Idempotent; targets an existing env. | `bash -n` + shellcheck OK; **cannot run e2e without a cluster** |
| dmf-infra | `858fe74` | `630-zot-seed-platform.yml` early assert on `vault_zot_service_password` (ADR-0033) with a "run seed-bao / upgrade-in-place" hint. **191-zot-oidc deliberately NOT guarded** (consumed indirectly via roles; conditional — a blind guard would risk valid runs). | yaml/syntax OK |

**Decisions made this session (operator):**
- **CCM Path 3** (most-current): hccm **v1.31.1** + k3s **v1.33.12+k3s1**.
- **Scope:** all code/script fixes that don't need a live env; defer live
  root-cause confirmation + idempotency validation.

### 1a. Post-review update (operator-reviewed, all folded in)
A dmf-env follow-up commit **`8fc7c05`** addressed the review:
- **Round-trip test now sources the REAL functions** (not inlined copies):
  `bootstrap-secrets.sh` got a `[ "${BASH_SOURCE[0]}" = "${0}" ]` guard so it's
  safely sourceable; the test calls the real `bundle_set`/`bundle_field` and still
  passes **5/5** (incl. failure-path). Direct execution unchanged.
- **`upgrade-in-place.sh`**: added `--dry-run` (`--check --diff` on all stages +
  gates, skips the mutating seed-bao — use this for the controlled-skew dry pass);
  **distinct exit codes** (convergence gate=5, bootstrap-verify=6); section banners
  renumbered to match the 6-step header.
- **`unseal-openbao.sh`**: pod IP **re-resolved per share** (pod could reschedule
  between feeds; old kubectl-exec path was name-based/immune); node-side **curl
  precheck**; the explicit `OPENBAO_API_ADDR` override is **preserved** (when set,
  per-share re-resolve is skipped and the override URL is used).
- **k3s 1.30→1.33 is NOT an in-place jump (resolved a review concern):**
  `playbooks/300-k3s.yml` installs k3s **only `when: not k3s_binary.stat.exists`**,
  and pre-seed imports it — so re-running pre-seed on an EXISTING env leaves k3s at
  its current version (no minor-skip, no drain/uncordon). The k3s bump applies to
  **fresh builds only**. Consequence: an upgraded existing env runs the new
  CCM/platform on its OLD k3s — a documented, acceptable skew; a true k3s migration
  needs a separate sequential plan.

---

## 2. Open work (all LIVE-ENV-GATED)

1. **Confirm the real `bundle_set` failing command.** Root cause is still
   **UNPROVEN** — the de-masking + `DMF_BUNDLE_SET_DEBUG=1` instrumentation now
   exist to pin it on a live cloud env. Run `seed-bao` against a real cloud env
   and read the per-step exit codes. The repo-level-`.sops` hardening is in place
   but the failure is observed *before* the encrypt step, so it's likely not the
   cause. **Still NO `set -x`** (leaks decrypted bundle + generated secret).
2. **Validate idempotency on a controlled skew env** (the real proof): provision
   a fresh env at `main~N`/a tag, run `bin/upgrade-in-place.sh <env>`, assert it
   converges with no manual steps and a second run is a clean no-op.
3. **Validate `unseal-openbao.sh` rewrite** on a live hardened env: confirm
   node→podIP:8200 reachability + TLS (`-k` vs `OPENBAO_CACERT`).
4. **Extend `verify-bootstrap-convergence.yml`** (plan §6.4 — **deferred**): assert
   all expected `vault_*` present, EE image resolvable in Zot (tag matches JT +
   inventory source), catalog JT carries `vault_netbox_catalog_token`. Deferred
   because that verifier is OpenBao-custody-focused and these need
   live-confirmable paths + Zot/AWX API patterns it doesn't have — adding blind
   risks a spuriously-failing gate. `upgrade-in-place.sh` already *invokes* the
   existing gate as its convergence step.
5. **EE-tag skew** (orthogonal, from prior handoff): current main wants
   `dmf/awx-ee:0.1.1`; ensure 630 re-mirrors it on the next build.

---

## 3. Known minor lints (non-blocking, recorded not fixed)

- `unseal-openbao.sh`: `$TLS_OPT` intentionally unquoted (SC2086) to word-split
  `--cacert <path>`; `REPO_DIR` unused (SC2034, pre-existing pattern); status
  line A&&B||C (SC2015, pre-existing, behaves correctly since `info` always
  succeeds).
- `upgrade-in-place.sh`: `REPO_DIR` unused (SC2034) — boilerplate consistency.
- `upgrade-in-place.sh`: `$EXTRA_ARGS` intentionally unquoted (SC2086) to
  word-split `--check --diff` in dry-run.

None affect behavior. A future cleanup pass could convert `$TLS_OPT` / `$EXTRA_ARGS`
to arrays. (The earlier "round-trip test inlines copies" concern is **resolved** —
`8fc7c05` makes the test source the real functions.)

---

## 4. Git state

**Pushed to the private LAN Forgejo origin:**
- **dmf-infra** ✅ pushed — `1b9976a` (k3s), `858fe74` (zot guard).
- **dmf-env** ✅ pushed — `adabe88`, `e514bd9`, `4335d3c`, `d4306a7`, `8fc7c05`
  (review fixes).
- **umbrella (dmf-platform)** ✅ pushed — STATUS notes + this handoff + CCM plan.

All on `main`, pushed to the LAN Forgejo (NOT any public GitHub mirror — the
public-publish path is separate and gated). Verify `HEAD == main` before further
work (shared checkouts — [[feedback_verify_main_branch_before_work]]).

---

## 5. Reference index

### Plans (the source-of-truth for this work)
- [Idempotent Upgrade-in-Place — Findings & Plan](../plans/DMF%20Idempotent%20Upgrade-in-Place%20Mechanism%20%E2%80%94%20Findings%20and%20Plan%202026-06-01.md) (§6 = the plan we executed)
- [Hetzner CCM Upgrade Plan](../plans/DMF%20Hetzner%20CCM%20Upgrade%20Plan%202026-06-01.md) (Path 3 chosen)
- Prior handoff: *DMF g2r6 Teardown + Upgrade-in-Place Mechanism Handoff 2026-06-01.md*

### Key artifacts touched
- `dmf-env/bin/{tf-destroy,unseal-openbao,bootstrap-secrets,upgrade-in-place}.sh`,
  `dmf-env/tests/bundle-set-roundtrip.sh`, `dmf-env/tasks/hetzner/ccm.yml`
- `dmf-infra/k3s-lab-bootstrap/playbooks/{300-k3s,630-zot-seed-platform}.yml`,
  `…/verify-bootstrap-convergence.yml` (invoked, not modified)

### How to exercise the new wrapper (on a live env)
```
dmf-env/bin/upgrade-in-place.sh <env>            # full: precheck→seed-bao→stages→gates
dmf-env/bin/upgrade-in-place.sh <env> --yes      # non-interactive
DMF_BUNDLE_SET_DEBUG=1 dmf-env/bin/bootstrap-secrets.sh seed-bao <env>   # pin bundle_set failure
```

### Agent memories updated this session (Claude-local)
- [[project_seedbao_bundle_set_bug]] — mitigations landed; root cause still open
- [[project_unseal_openbao_use_pty_bug]] — internal-API fix landed (untested)
- [[project_hetzner_env_teardown_gotchas]] — tf-destroy fixed; CCM bumped
