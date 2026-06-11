---
name: e2e-harness-design-review
description: Review E2E test harness design plans for host/container boundary correctness, playbook reuse collateral, UI automation fragility, statelessness claims, and pre-flight completeness
source: auto-skill
extracted_at: '2026-06-05T07:37:14Z'
---

# E2E Harness Design Review

A read-only review of a script-driven E2E test harness design plan. Purpose: surface gaps in host/container boundaries, playbook tag-skip collateral damage, fragile UI automation paths, statelessness claims, and pre-flight requirements before implementation.

## When to use

- A plan proposes a thin, script-driven E2E harness (reset → bootstrap → verify → optional stages).
- The harness wraps existing tooling (playbooks, init APIs, cluster operations) rather than reimplementing.
- You want to verify design soundness before an agent builds it.

**Read-only.** Produce a verdict + prioritized findings.

## Procedure

### 1. Ground yourself (read-only)

1. **The harness plan** — read the full document, note locked decisions, stage contracts, fixed values.
2. **The referenced playbook/runbook** — read the verify playbook (`bootstrap-sandbox-verify.yml` or equivalent). Check every imported playbook, its tags, and what assertions it makes.
3. **The referenced bootstrap task** — read the task doc the harness is encoding. Note what was live-validated.
4. **The actual verify playbook code** — read each verifier (e.g., `verify-d8-hardening.yml`) to understand what assertions are dropped when tags are skipped.

### 2. Critique dimensions

#### a. Host vs container boundary
- Is the host-bound surface **minimal and correct**? VM lifecycle (`limactl`, `vfkit`) must be host-side.
- Is anything else accidentally host-bound that should be container-scoped?
- Does the harness wrap host operations in a single approvable unit? (One host launcher, not scattered host commands.)
- **SSH agent scoping**: does the harness add keys to the host agent and leave them behind on failure? Should it use a scoped subshell (`eval $(ssh-agent) && ssh-add ... && run && ssh-agent -k`)?

#### b. Playbook reuse and tag-skip collateral damage
- When the plan uses `--skip-tags` to disable a stage, **what else does that tag control?**
- A verifier like `verify-d8-hardening.yml` may assert both passkey count AND OAuth2 token lifetimes. Skipping it for a `--no-passkeys` fast loop loses the token-lifetime assertions too.
- **Fix options**: split the playbook into separate tags per concern, or document the collateral gap as a known trade-off for the fast loop.
- Verify: does the `--skip-tags` set leave any verifier running that *requires* enrollment or state the skipped stage would have created?

#### c. UI automation fragility
- Identify the highest-failure-probability step — usually CDP/Playwright driving a UI flow (enrollment ceremonies, "add passkey" flows).
- **Fallback path**: is there a simpler, more robust alternative if the UI drive fails? (e.g., pre-seed via `kubectl exec` + database insert / management command instead of driving the console UI.)
- **Isolation**: if this stage fails, does it corrupt the cluster, or just fail the gate? The harness should guarantee the latter.
- **Polling/idempotency**: does the stage poll until its assertion is met, or fail on first attempt?

#### d. Statelessness claim
- "All runtime state in `/tmp`, code in versioned repo" — verify there are no hidden persistent state leaks:
  - SSH known_hosts entries (cleared by `ssh-keygen -R`?)
  - Host agent key additions (scoped?)
  - Docker/container residues
  - Cookie jars, token files, key material in world-readable locations
- The wipe should be a **single clean-slate operation** — verify `$DMF_DATA_ROOT`, backup dirs, and any `/tmp` scratch dirs are all covered.

#### e. Pre-flight completeness
- Does `./e2e.sh` have a gate at the top that checks:
  - Required binaries exist and are running (limactl, uv, docker/colima if needed)
  - dmf-init is built/importable (`dmf_init.main` available)
  - All repos present at symlink targets
  - Playwright browsers installed (if UI automation is used)
  - SSH key exists at the expected path
- Without pre-flight, a fresh agent dies mid-stage with an opaque error.

#### f. Fixed values vs derived values
- Are profile values like `EXPECTED_PROBE_TARGETS=10` hardcoded? They should either be derived from the rendered inventory or validated loosely (`>0` rather than `==10`) since probe target count depends on what the bootstrap actually provisions.
- Reserved/unused flags (e.g., `--fast` with no semantics) — cut until defined.

#### g. Zero-context agent readiness
- Can a fresh agent run `./e2e.sh` with zero extra context?
  - README documents: what each stage does, all flags, expected output, what PASS/FAIL means
  - No hardcoded IPs, real operator identities, or secrets (gitleaks-clean)
  - VM IP discovered at runtime, never stored
  - Exit codes meaningful (0 = green, non-zero = specific failure)

### 3. Prioritize findings

| Priority | Meaning | Example |
|---|---|---|
| **P1** | Correctness or security gap that would cause a broken run or acceptance gate that doesn't prove the stage | Token-lifetime assertions lost via tag skip; SSH key leaked to host agent; verifier requires enrollment that was skipped |
| **P2** | Gap that won't break the run but creates operational friction or ambiguity | No pre-flight checklist; hardcoded probe target count; reserved flag with no semantics |
| **P3** | Nice-to-have or deferred concern | Fallback path not implemented yet but documented; image size of harness scripts |

### 4. Produce the review

Structure the reply as:

```
VERDICT: Sound design / LGTM / CHANGES-NEEDED

Top N improvements:
1. ...
2. ...
3. ...
```

Keep it concise — the recipient needs actionable points, not a full spec rewrite.

## Principles

- **Verify against the actual code**, not just the plan's claims. The plan says "reuse verify playbook" — read the playbook to see what that actually includes.
- **Propose mitigations**, not just problems. "Split into separate tags" or "add pre-flight gate" is better than "this is fragile."
- **Acknowledge correct decisions**. If the host/VM boundary is correct, say so.
- **Distinguish experiment-phase tolerances**. A fragile UI automation step is acceptable in experiment phase if isolated and non-corrupting; it should still have a documented fallback path.
