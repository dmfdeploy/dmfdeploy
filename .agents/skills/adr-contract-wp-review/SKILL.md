---
name: adr-contract-wp-review
description: Review implementation work packages against a frozen ADR contract — verify each WP faithfully implements the contract's schema, types, and behavior before downstream WPs proceed
source: auto-skill
extracted_at: '2026-06-04T12:00:00Z'
type: durable-pattern
scope: review-workflow
owner: operator
review_by: '2027-01-14'
---

# ADR Contract Work-Package Review

When an ADR defines a contract (schema, types, behavior, interfaces) and multiple work packages implement pieces of it, each WP must be reviewed for **fidelity to the frozen contract** — not just "does the code work" but "does it implement the contract exactly as the ADR specifies, so downstream WPs can rely on it?"

## When to use

- An ADR has been frozen (e.g. ADR-0038 monitoring contract) and WPs are implementing pieces.
- A WP commit is ready for review and gates downstream WPs.
- The ADR defines concrete terms: field types, choice sets, address composition, relabeling contracts, API endpoints, caching cadence.

**Read-only.** Do not edit the WP code. Produce a verdict + prioritized findings.

## Procedure

### 1. Ground yourself

Read these in order:
1. **The frozen ADR** — focus on the contract terms (schema tables, field types, choice sets, endpoint specs, cache cadence, naming conventions).
2. **The plan's WP description** — what this WP was supposed to implement.
3. **The committed files** — read top-to-bottom, all files in scope.
4. **The sibling pattern** — if the WP says "mirror X role" or "follow Y pattern", read X/Y to verify fidelity.

### 2. Map ADR contract terms to WP implementation

Build a mental (or scratch) table:

| ADR contract term | WP implements? | Where | Correct? |
|---|---|---|---|
| `metrics_port` = integer | Yes/No | file:line | ✓/✗ |
| `monitoring:scrape` tag created | Yes/No | file:line | ✓/✗ |
| `dmf_blackbox_probe_modules` choice set with 4 values | Yes/No | file:line | ✓/✗ |
| Service reachable as `blackbox.monitoring.svc` | Yes/No | file:line | ✓/✗ |

Every contract term in the ADR must appear in this table. Missing terms = gaps.

### 3. Check WP-type-specific criteria

#### For Ansible role WPs (NetBox taxonomy, Helm deployments, etc.)

| Check | What to look for |
|---|---|
| **Idempotency** — fetch-then-create-if-missing, no PATCH on type drift, warn-only on drift. | Tags: fetch all, compute existing set, create only when not in list. Choice sets: lookup-create-reconcile. Custom fields: lookup-POST-if-missing + warn-on-type-drift. |
| **Play header** — matches app-role anatomy: `hosts: k3s_control[0]` (or consistent with siblings), `become: true`, `gather_facts: false`, `roles: [base/cluster-ready, …]`. | Verify against sibling roles (prometheus, loki, etc.). |
| **Naming/namespace** — service names match what downstream WPs expect (e.g. `fullnameOverride: blackbox` → `blackbox.monitoring.svc`). | Cross-check against ADR and vendored configs. |
| **Choice sets match** — WP1 choice set values == WP2 module names == WP3/adapter enum expectations. | Enumerate values from both sides; confirm exact match. |
| **Sibling safety** — OpenBao writes use `kv patch` (not `kv put`) on populated paths; `put` only on first-create with existence gate. | Check `put` vs `patch` logic; confirm no sibling key wipe on re-run. |
| **AIR-GAP (ADR-0034)** — public repo add at bootstrap is OK for sandbox; image mirror to Zot must be a later WP, not omitted. | Confirm divergence from siblings is noted and deferred intentionally. |
| **Sandbox sizing** — resources sized relative to known siblings (above alertmanager, below Prometheus for heavy components). | Compare `requests/limits` to prometheus/loki/AM defaults. |

#### For FastAPI service WPs (adapters, bridges, internal services)

| Check | What to look for |
|---|---|
| **Lane contracts** — each endpoint returns correct `[{targets, labels}]` shape; `__address__` composed per ADR spec; `__param_module`/`__metrics_path__` labels correct. | Compare endpoint output to ADR lane table. |
| **Cache cadence** — background timer (not per-request); TTL matches ADR; all endpoints serve from cache; thread-safe snapshot. | Verify `_run` loop uses `sleep(ttl)`, not request-triggered refresh. |
| **NetBox client** — read-only (GET), paginated (follows `.next`), tag-filtered, token from env, `validate_certs` configurable. | No POST/PUT/DELETE; pagination loop present; token from settings. |
| **Health/readiness** — health reports cache age + last error; readiness returns 503 when stale. | `/healthz` and `/readyz` both use cache state, not just "process alive". |
| **Tests exercise behavior** — each lane tested with fixture data; missing-field exclusion tested; pagination tested; cache refresh + staleness tested. | Not just "endpoint returns 200" — assert exact targets/labels. |
| **Dockerfile** — non-root user (USER directive), correct base image, no secrets baked in. | Check for `USER` or equivalent; no COPY of secret files. |

### 4. Judge downstream impact

For each gap found, ask: **which downstream WP agent is blocked?**

- If WP1 creates the wrong choice set value, WP3 adapter will emit labels the scrape config doesn't recognize → WP5 blocks.
- If WP2 deploys blackbox with wrong service name, WP5 http_sd relabeling targets a non-existent host → WP5 blocks.
- If WP3 adapter queries NetBox per-request instead of from cache, the ADR's scaling guarantee is violated → silent correctness issue.

Name the blocked agent in the finding.

### 5. Produce the verdict

```
REVIEW WP<N>: PASS with <N> P<N> nits / CHANGES-NEEDED

1. <Contract term 1>: ✓ / ✗ — <detail, file:line>
2. <Contract term 2>: ✓ / ✗ — <detail, file:line>
...

P2/P3 nits:
- <nit description>

Downstream WPs [are/are not] blocked.
```

## Principles

- **The ADR is the contract, not the plan.** The plan may have more context, but the frozen ADR defines what implementers must satisfy.
- **Fidelity > cleverness.** A WP that implements the contract exactly is better than one that improves it but diverges.
- **Name the blocked downstream agent.** Every gap should say which WP is blocked, not just "this is wrong."
- **Idempotency is non-negotiable for Ansible.** Re-runs must be no-ops; drift is warn-only, never PATCH.
- **Cache cadence is a correctness property, not a perf optimization.** The ADR's refresh_interval + cache TTL define the worst-case churn latency — per-request queries violate the contract.
- **Check sibling patterns, not just the code.** If a WP says "mirror X", verify the mirror is faithful, not just "works."
- **Sibling safety on secrets.** `kv patch` preserves siblings; `kv put` on an existing path can wipe. The existence gate (put first, patch after) must be explicit.
