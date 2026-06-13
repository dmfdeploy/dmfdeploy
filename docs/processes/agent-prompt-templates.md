# Agent Prompt Templates

**Status:** Living. Used by Claude (and any other orchestrator) when dispatching tasks to subagents or to Qwen panes via agent-bridge.

This file holds reusable safety-rail blocks for agent dispatch briefs.
Briefs that lift work to a subagent / Qwen pane should reference the
relevant profile here so the dispatched agent reads the rails as part
of its task, not from out-of-band lore.

## Why these exist

A dispatched agent reads only what's in the prompt. The orchestrator's
ADR knowledge, prior-incident memory, and conversation history are NOT
visible. Without explicit safety rails in every brief, the dispatched
agent will, with depressingly high probability, do one of:

- `cat ~/.config/<provider>/<token>.txt` and pipe the result into stdout
  — putting the token in its own transcript AND in the orchestrator's
  conversation transcript via the agent-bridge readback. **Cloudflare
  DNS token leak, 2026-05-11.**
- Embed `/Users/<operator-name>/...` absolute paths in committed files —
  gitleaks `dmf-operator-identity` rule trips. **Several incidents during
  Tier A Phase 1.**
- Use `--no-verify` to bypass gitleaks rather than scrub the input.
- Run `tofu apply` without `-target`, causing drift on unrelated
  resources.
- Forget to `unset AWS_ACCESS_KEY_ID` after a verify step, leaving the
  credentials in their shell history.
- Commit + push their own work, bypassing the orchestrator's
  integration step.

Each rail block below addresses one of these failure modes.

## How to use

In a dispatch brief, choose the **profile** that fits the task and copy
its rail block verbatim into the brief. For task-specific scope
additions, append to the SCOPE rail.

Per the operator's 2026-05-11 direction: every dispatch brief MUST
include the rails appropriate to its profile. The orchestrator is the
last line of defence — there is no per-phase external review gate as of
that date.

---

## Profiles

| Profile | When | Rails included |
|---|---|---|
| **READ_ONLY_RESEARCH** | Subagent doing web research, file exploration, or design lookup — no edits | SECRETS, IDENTITY, REPORTING |
| **CODE_EDIT** | Multi-file edit task within the repo tree, no cluster touch | SECRETS, SCOPE, GIT, IDENTITY, REPORTING |
| **LIVE_INFRA_MUTATION** | `tofu apply`, `kubectl` writes, cloud-resource creation, anything that costs money or touches third-party state | All rails, including LIVE_INFRA + CLUSTER |
| **CLUSTER_OPS** | Ansible playbook runs against the live cluster (not just dry-run) | SECRETS, SCOPE, IDENTITY, CLUSTER, REPORTING |
| **DOCS_ONLY** | Writing or editing documentation, no code or infra | SECRETS (lite), IDENTITY, REPORTING |

When in doubt, use the more restrictive profile.

---

## Rail blocks

Each block below is designed to be copied directly into a brief, under a
section heading like "Safety rails (apply for the rest of this dispatch)".

### RAIL: SECRETS

```
SECRETS (ADR-0007):
  - Never `cat`, echo, print, or pipe-into-stdout the contents of any
    secret-bearing file: ~/.config/<provider>/*.txt, ~/.secure/*, the
    encrypted bundle under $DMF_BOOTSTRAP_BUNDLE_DIR, or anything under
    /root/.aws/. If you can read it, that means its contents land in
    your transcript — which lands in the orchestrator's transcript via
    agent-bridge readback.
  - Use the operator-provided wrapper scripts (bin/tf-apply.sh,
    bin/run-playbook.sh, bin/bootstrap-secrets.sh) which read secrets
    from local config files and inject them as env vars without ever
    printing them.
  - For per-verify use of credentials that *must* live in your shell
    env briefly: source them from the right file via shell parameter
    expansion (not `cat`), use them, then `unset` immediately after.
  - When you echo command output back to the orchestrator, redact any
    credential-shaped value as `<redacted>`.
  - Never put a secret in argv: `bao operator unseal <share>`,
    `aws --secret-key <SECRET> ...`, `curl -d '{"password":"..."}'`
    are all forbidden. Use stdin (`printf '%s' "$x" | tool`),
    `--password-stdin` flags, or wrapper scripts.
```

### RAIL: SCOPE

```
SCOPE (this dispatch only):
  - Touch ONLY the files listed in the brief's "Files to create" /
    "Files to amend" sections.
  - Do NOT touch:
      * dmf-infra/** unless explicitly in scope
      * dmf-cms/**, dmf-runbooks/**, dmf-media/**, dmf-central/**
        unless explicitly in scope
      * docs/** unless explicitly in scope (orchestrator owns docs)
      * .claude/**, .qwen/**, STATUS.md, .githooks/**
      * Any sibling actor's slice (other Qwen pane / other subagent)
  - If you discover you need to touch an out-of-scope file, STOP and
    report — do not silently expand scope.
```

### RAIL: GIT

```
GIT:
  - Do NOT commit. The orchestrator integrates + commits across repos.
  - If you find yourself needing to run `git add`, `git commit`, or
    `git push`, STOP and report — your output is the orchestrator's
    input, and you'll create a merge mess if you commit ahead.
  - NEVER use --no-verify on any git command. The pre-commit hook
    (gitleaks + deterministic generated-doc refresh/checks) is the canonical gate; bypassing it
    silently lands secret-leaking content in history.
  - If gitleaks blocks a commit (orchestrator's commit, not yours),
    the orchestrator will read the finding and scrub. You don't need
    to anticipate; just don't commit.
```

### RAIL: IDENTITY

```
IDENTITY (operator-identity scrub):
  - Never write absolute paths containing the operator username into any
    tracked file (e.g. anything starting with /Users/<that-name>/...).
    The umbrella gitleaks ruleset has a `dmf-operator-identity` rule
    that catches these and refuses commit.
  - Use environment-variable forms instead: $HOME, $DMF_BOOTSTRAP_BUNDLE_DIR,
    or repo-relative paths like dmf-env/manifests/hetzner-arm.yaml.
  - Same rule applies to any operator username embedded in comments,
    docstrings, error messages, or example output. Substitute
    `<operator-name>` in prose.
  - The placeholder convention for prose is `<operator>` or
    `<placeholder-name>` (e.g. `<lan-ip>`, `<control-node-public-ip>`).
  - If your tool output happens to echo an absolute path with the
    operator name, that's fine for in-pane diagnostics — but DO NOT
    embed it into the files you write.
```

### RAIL: REPORTING

```
REPORTING (what to send back):
  - Each step's exit code (especially for `tofu`, `ansible-playbook`,
    `kubectl`, build commands).
  - File list: every file created or modified, repo-relative.
  - Any errors or anomalies encountered, even if recovered.
  - Any decisions you made that the brief left ambiguous — flag them
    so the orchestrator can sanity-check.
  - Redacted command output when the output contains credentials,
    tokens, IPs, or operator-identifying paths.
  - Redaction is REQUIRED for BOTH halves of a credential pair:
    access-key-IDs are operator-identifying even when not secret.
    Substitute `<redacted-keyid>` / `<redacted-secret>` in progress
    messages, error-diagnostic prose, and final reports alike. If an
    upstream tool (e.g. `aws s3api`) returns an error containing the
    access-key-ID, redact before quoting the error back to the
    orchestrator. Reasoning: a leaked keyID identifies the operator's
    cloud account; combined with a transcript search anyone could
    pivot to scoping attacks.
  - DO NOT include the brief itself or large chunks of it in your
    response — the orchestrator already has it. Reference sections
    by §number instead.
```

### RAIL: CLUSTER

```
CLUSTER OPS (ADR-0010):
  - All cluster mutation goes through `dmf-env/bin/run-playbook.sh`.
    Do NOT invoke `ansible-playbook` directly against the cluster.
  - Do NOT run `kubectl apply`, `kubectl patch`, `kubectl delete`,
    `helm upgrade`, or `helm install` directly. Those go through the
    relevant Ansible role + run-playbook.sh.
  - Read-only kubectl (`get`, `describe`, `logs`) is fine for
    verification.
  - Cluster context: confirm `kubectl config current-context` returns
    the expected env (hetzner-arm) before any cluster-touching step.
  - Never copy /etc/rancher/k3s/k3s.yaml off the control node.
```

### RAIL: LIVE_INFRA

```
LIVE INFRA MUTATION (irreversible cloud resources):
  - This dispatch will create real cloud resources with cost
    implications. Each `tofu apply`, `aws s3api create-bucket`, or
    similar call is a real action.
  - Always run `tofu plan` before `tofu apply` and inspect the output.
    Confirm it matches the brief's expected resource list EXACTLY.
    Anything unexpected → STOP and report.
  - Use `-target=<module.path>` to scope plans/applies to the slice
    you're working on. Out-of-scope drift is a real risk.
  - Apply from the saved plan binary (`tofu apply <plan-file>`), not
    by re-running `tofu apply` against fresh state. This ensures the
    apply is bound to what you (and the orchestrator) reviewed.
  - For Object Lock COMPLIANCE buckets specifically: objects uploaded
    are irreversibly retained for the configured period. Empty buckets
    can be deleted; buckets with locked objects cannot.
  - After the apply, verify each resource exists with the expected
    config (e.g. get-object-lock-configuration shows
    ObjectLockEnabled=Enabled with the right retention).
```

### RAIL: SECRETS (lite — for docs-only dispatches)

```
SECRETS (docs-only, ADR-0007):
  - Do not embed any literal credential, token, or password value in
    a doc file. Example values must be obviously-fake placeholders:
    `<from-b2-console>`, `<redacted>`, `AKIA-EXAMPLE`, etc.
  - Do not include operator-identity paths like /Users/<operator>/...
    in any doc; use $HOME or env-var forms.
```

---

## Standard preamble (use at the top of every brief)

```
[Profile: <one of READ_ONLY_RESEARCH / CODE_EDIT / LIVE_INFRA_MUTATION /
CLUSTER_OPS / DOCS_ONLY>]

You are picking up a slice of the DMF Tier A implementation work as
the orchestrator's delegate. Run from the dmfdeploy umbrella cwd
unless told otherwise.

Read first (paths repo-relative):
  docs/processes/agent-prompt-templates.md   (this file — apply the
                                              rails for your profile)
  <task-specific reading list>

Apply the safety rails for profile <profile-name> verbatim. They are
non-negotiable.

Task: <description>
```

## Standard closer

```
DO NOT commit. Report when done with:
  - Per-step exit codes
  - File list (repo-relative paths)
  - Any anomalies or scope expansions you considered
  - Then stop and wait for orchestrator integration.
```

---

## Incidents and lessons

A log of where these rails came from. Update on any new incident.

### 2026-05-11 — Cloudflare DNS token in pane transcripts

**What happened:** During Phase 2 live B2 apply, qwen-right hit a
`tofu plan` prompt for `cloudflare_api_token`, then `cat`ted
`~/.config/cf/dns.txt`. The token landed in qwen-right's transcript
AND in the orchestrator's transcript via `agent-bridge read`.

**Operator response:** Acknowledged; tokens will be rotated before
publishing. Direction given: include safety-rail prompts in every
future dispatch brief.

**Rail added:** SECRETS now explicitly forbids `cat` on
`~/.config/<provider>/*.txt` and points at `bin/tf-apply.sh` as the
correct wrapper.

### 2026-05-11 — Operator-identity path leaks

**What happened:** Several Phase 1 + Phase 2 commits initially
included `/Users/<operator>/...` absolute paths in docs and configs.
gitleaks `dmf-operator-identity` rule caught each one before commit,
but only after several rounds of orchestrator-side rework.

**Rail added:** IDENTITY now mandates env-var / repo-relative paths.

### 2026-05-11 — Argv-shaped credential pass

**What happened:** qwen-right's first-pass bootstrap-secrets.sh
change wrote `bao kv put PATH access_key_id="${ACCESS_KEY}"` (argv).
Mirrored an existing pre-existing pattern in the same script.

**Rail clarification:** SECRETS now explicitly forbids credentials in
argv. Existing in-repo patterns that violate this are tech debt;
new code must use stdin / wrapper scripts.

### 2026-05-11 — Access-key-ID in qwen progress messages

**What happened:** During the Phase 2 retry of the B2 live apply,
qwen-right echoed the operator's B2 access-key-ID inline in its
progress messages, error diagnostics, and task-list outputs. The
keyID landed in the operator's pane AND in the orchestrator's
transcript via `agent-bridge read`. The REPORTING rail at the time
called for "Redacted command output when the output contains
credentials, tokens, IPs, or operator-identifying paths" but did not
explicitly call out **access-key-IDs (the public half of a credential
pair)** as a redaction target.

**Operator response:** Acknowledged; tokens will be rotated before
publishing. Direction given: tighten the redaction rail to make both
halves of a credential pair non-negotiable.

**Rail tightened:** REPORTING now explicitly mandates redaction of
both access-key-ID AND application-key in progress messages, error
diagnostics, and final reports. Substitution tokens
`<redacted-keyid>` and `<redacted-secret>` are now the standard.

### 2026-05-11 — tofu plan without -target

**What happened:** First qwen-right invocation ran `tofu plan` against
the full hetzner-arm root module. Combined with the operator's
intentional cluster teardown, this would have shown drift on compute
resources and could have led to accidental recreation.

**Rail added:** LIVE_INFRA mandates `-target=<module.path>` on every
plan/apply.
