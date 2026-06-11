---
status: executed
date: 2026-06-04
executed: 2026-06-04
---
# DMF NetBox-SoT Token-Mint Hardening Task (2026-06-04)

**Role split (agentic):** codex lifts, qwen-left reviews, Claude (orchestrator)
verifies + integrates. Reply protocol at the bottom — follow it verbatim.

**Repo:** `dmf-infra` (component repo, sibling of the umbrella). Work **directly
on `main`** — no feature branches (pre-public/solo policy). One file is in scope:

```
k3s-lab-bootstrap/roles/stack/operator/netbox-sot/tasks/main.yml   (2350 lines)
```

This file mints NetBox service tokens via `kubectl exec … manage.py shell`,
reuses them from OpenBao when still valid, and persists them back to the env's
OpenBao runtime secret (`netbox_sot_runtime_secret_path`).

---

## Background — the FIX5 precedent (already landed: `6322343`)

`manage.py shell` prints banner lines (e.g. `NNN objects imported`) to stdout, so
capturing the token with `| tail -n 1` can grab the wrong line and yield an
**empty** token. FIX5 fixed this **for the PromSD mint only** by switching to a
sentinel:

```diff
- print(f"{TOKEN_PREFIX}{token.key}.{token.token}")
+ print("PROMSD_TOKEN=" + TOKEN_PREFIX + token.key + "." + token.token)
...
- … manage.py shell < /tmp/nbs-token-promsd.py | tail -n 1
+ … manage.py shell < /tmp/nbs-token-promsd.py | grep '^PROMSD_TOKEN=' | tail -n 1 | cut -d'=' -f2-
```

See the PromSD command block at **L85–L118** for the reference pattern.

---

## Task A — 4-mint sentinel hardening

Apply the FIX5 sentinel-capture pattern to the **four legacy mints** that still
use the fragile `print(f"…")` + `| tail -n 1`:

| Mint     | `set_fact` block | python print line | capture line |
|----------|------------------|-------------------|--------------|
| admin    | L15–30           | L28               | L30          |
| awx      | L32–47           | L45               | L47          |
| librenms | L49–64           | L62               | L64          |
| catalog  | L67–82           | L80               | L82          |

For each, choose a distinct sentinel prefix (`ADMIN_TOKEN=`, `AWX_TOKEN=`,
`LIBRENMS_TOKEN=`, `CATALOG_TOKEN=`) and mirror the PromSD capture exactly:
`… | grep '^XXX_TOKEN=' | tail -n 1 | cut -d'=' -f2-`. Keep everything else
(the `Token.objects.filter(...).delete()` / `create(...)` logic, `write_enabled`
flags, `when:` guards, heredoc quoting) **unchanged**. Token semantics must be
identical; only the stdout capture changes.

## Task B — ESO token-path / finding #5 (investigate, then fix)

**Symptom (observed live on `montest`, env `8f2y-sgg7`):** after FIX5 landed, a
re-run of playbook 691 did **not** repopulate
`secret/apps/netbox/runtime#promsd_api_token` in OpenBao — it stayed **empty** —
so the ESO-projected K8s secret was empty and the adapter pod had its token
**injected by hand** (`kubectl set env`). Goal: a re-run reliably re-mints **and
persists** a non-empty token, and ESO projects it, with **no manual injection**.

**Where to look (read these, form a root-cause hypothesis before editing):**

- PromSD reuse gate **L1733–1763** and mint gate **L1765–1783**. All hinge on
  `netbox_sot_promsd_token_effective | length == 0`. Trace what happens when the
  persisted value is **present-but-empty-string** (`promsd_api_token: ""`) from a
  prior broken run: does reuse correctly skip, does mint correctly fire, does
  `netbox_sot_promsd_token_effective` end up non-empty?
- The persisted-tokens read **L283–L309** (`_netbox_sot_persisted_tokens`) — a
  `length > 0` test treats empty-string as absent, confirm that's consistent.
- The OpenBao write-back: secret-patch assembly **L1821–L1842** (`combine`d
  `promsd_api_token`) and the actual `kv patch`/persist task further down
  (search below L1844 for the `bao kv patch` / vault-edit apply). **Does the
  persist step run on a re-run, and does it write the non-empty value?** A gate
  that only persists "created/rotated" tokens could skip when the value was
  reused-or-empty.
- **ESO resync:** even if OpenBao gets the value, the projected K8s secret may be
  stale. Determine whether the role should annotate/force an ExternalSecret
  refresh (e.g. `force-sync`) or whether ESO's poll interval is sufficient.
  Document the conclusion; only add a refresh nudge if genuinely needed.

**Deliverable for B:** a minimal, idempotent fix (could be a corrected `when:`
guard, an empty-string-aware gate, and/or an ESO refresh) **plus** a 3–6 line
root-cause note in your reply explaining what actually caused the empty token.
Do **not** invent a live cluster — reason from the code + the symptom. Flag
anything that can only be confirmed on the next fresh bootstrap as such.

---

## Constraints

- Single file, `main` branch, in `dmf-infra`.
- Preserve `no_log: true`, all `when:` guards, and idempotency (safe to re-run).
- Don't touch token semantics, `write_enabled` flags, or unrelated tasks.
- `ansible-lint` / `yamllint` clean if those run in the repo; at minimum the YAML
  must parse and the jinja must be well-formed.
- Two logical commits is fine: `fix(netbox-sot): sentinel capture for all 4
  legacy token mints` and `fix(netbox-sot): <root-cause> so promsd token
  persists + ESO resyncs on re-run`. End commit messages with the
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` trailer.

## Reply protocol (bidirectional)

When done (or blocked), report back to the orchestrator via agent-bridge:

```
~/.claude/skills/agent-bridge/bin/agent-bridge send claude-bottom -- "DONE: <1-line summary>; commits <shas>; root-cause: <one line>"
```

Use `HALTED:` or `BLOCKED: <reason>` instead of `DONE:` if you cannot finish.
Keep the working tree on `main`; do not push (the orchestrator handles review +
push after qwen-left reviews).
