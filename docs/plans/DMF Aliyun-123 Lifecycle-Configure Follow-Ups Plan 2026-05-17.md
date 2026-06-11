---
status: historical
date: 2026-05-17
---
# DMF Aliyun-123 Lifecycle-Configure Follow-Ups Plan

> **2026-05-19 update — `media-launch-nmos-cpp` failure (AWX job 44) escalates to architectural pivot.**
> The first `media-launch-nmos-cpp` run on aliyun-123 (2026-05-17 18:17 UTC,
> AWX job 44) failed at `UNREACHABLE!` because
> `dmf-runbooks/playbooks/launch-nmos-cpp.yml:28-34` hardcodes the Hetzner
> private-IP map. Root-cause fix is no longer a band-aid — it lands as the
> [DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19](./DMF%20Cluster-Internal%20Ansible%20Execution%20and%20Catalog%20Helm%20Pivot%20Plan%202026-05-19.md)
> (Helm chart + EE-as-runtime; [ADR-0025](../decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md) — note ADR-0024 remains reserved for §B.1/§C.3 below).
> aliyun-123's failing launch is the **verification target** of that plan;
> success there closes this loop.

**Date:** 2026-05-17
**Author:** session-collaborative (Claude orchestrator + operator)
**Cluster:** `aliyun-123` (other envs may inherit some fixes — flagged per item)
**Status:** Plan — execution pending operator approval

---

## 1. Context

Today's session (2026-05-16/17) implemented the three gaps from
[`docs/plans/DMF Lifecycle-Configure Bootstrap Completion Plan 2026-05-15.md`](DMF%20Lifecycle-Configure%20Bootstrap%20Completion%20Plan%202026-05-15.md)
and surfaced a fourth gap (catalog-project sync) along the way. The four
shipped commits on `dmf-infra@main`:

| Commit | Topic |
|---|---|
| `a891ecb` | feat(lifecycle-configure): seed repos, CMS perms, fail-loud JT (Gap A + B + C) |
| `f1ba770` | fix(forgejo-bootstrap): seed-local-repos exclude .git and binary files (Gap A bug #1, superseded) |
| `440ec61` | fix(forgejo-bootstrap): seed via deny-list (`.git/`) instead of allow-list patterns (Gap A bug #2) |
| `8d20e71` | fix(awx-integration): trigger AWX project sync per catalog project |

A live end-to-end run on `aliyun-123` validated all four. The §6 acceptance
checks from the source plan all pass:

- Forgejo `dmf-runbooks` contains `playbooks/`
- AWX `dmf-runbooks` project synced fresh (revision `aea4a518…`, playbooks indexed)
- Catalog JTs `media-launch-nmos-cpp` (id=15) and `media-finalise-nmos-cpp` (id=16) exist
- `dmf-cms-svc` returns HTTP 200 on `/api/dcim/sites/` and `/api/ipam/services/` (was 403 before)
- dmf-cms `/api/catalog` endpoint reachable and OIDC-gated as designed

That work uncovered (or carried forward) a set of follow-up items spanning
inventory hygiene, silent-failure cleanup, doc-vs-implementation drift,
strategic-tier workstreams, and decision-class issues. This plan collects
all of them with the right level of context for a fresh agent to pick up
and execute.

**Important prior reading** (cold-pickup agents must read these first):

1. Umbrella [`CLAUDE.md`](../../CLAUDE.md) — boot ritual, repo map, conventions
2. [`docs/agentic/CONSTITUTION.md`](../agentic/CONSTITUTION.md) — 14 non-negotiable rules (Rule 1 push gate, Rule 4 skill gates, Rule 5 decision rubric, Rule 7 trust-but-verify, Rule 8 placeholders)
3. [`docs/handoffs/DMF Aliyun-123 Bootstrap Green-Run + ADR-0023 + Runner Spike Handoff 2026-05-14.md`](../handoffs/DMF%20Aliyun-123%20Bootstrap%20Green-Run%20%2B%20ADR-0023%20%2B%20Runner%20Spike%20Handoff%202026-05-14.md) — the 11 walls debugged, override list, ADR-0023 amendment, runner-pod spike status
4. [`docs/plans/DMF App Admin Account Drift Audit and Realignment Plan 2026-05-14.md`](DMF%20App%20Admin%20Account%20Drift%20Audit%20and%20Realignment%20Plan%202026-05-14.md) — per-app drift shapes + Path 1/2/3 remediation taxonomy
5. [`docs/decisions/0023-internal-service-dns-for-cross-app-wiring.md`](../decisions/0023-internal-service-dns-for-cross-app-wiring.md) — caller-location split; scope amendment
6. [`docs/decisions/0016-awx-control-node-ssh-via-cloud-init-and-openbao.md`](../decisions/0016-awx-control-node-ssh-via-cloud-init-and-openbao.md) — AWX→control-node SSH execution model (relevant to Item B.2)
7. Skill `§0`s before any cluster-touching work: `.claude/skills/dmf-cluster-access/SKILL.md`, `.claude/skills/dmf-openbao-unseal/SKILL.md`

---

## 2. Items in scope, grouped by class

### Class A — Quick wins (estimated ≤ 2 hours total)

Each is independently shippable; commit per item. None require a cluster
mutation beyond a `bootstrap-configure` re-run.

#### A.1 — Pin `awx_control_node_ssh_privkey_path` in `aliyun-123` inventory

**Problem:** the role default
(`roles/stack/operator/awx-integration/defaults/main.yml:98`)
is `/mnt/secure/awx-control-node.privkey`. That path does not exist on
the operator's Mac. `hetzner-arm`'s inventory overrides to
`/Volumes/<user>/secure/awx-control-node.privkey` (line 73). `aliyun-123`'s
inventory has no override → today's `bootstrap-configure` failed at
`Read AWX SSH privkey from disk for OpenBao bootstrap` (post-693 task,
`failed=1` in run 2026-05-17T12:51).

**Fix:** add the same line to `dmf-env/inventories/aliyun-123/group_vars/all/main.yml`.
The `openbao_juicefs_mount_path: /Volumes/<user>/secure` is already defined
in `openbao_secrets.yml`; consider deriving from it (per 2026-05-14
handoff §4 suggestion) to eliminate a redundant constant:

```yaml
awx_control_node_ssh_privkey_path: "{{ openbao_juicefs_mount_path }}/awx-control-node.privkey"
```

If deriving, do it consistently on hetzner-arm too (currently hardcoded).

**Repos:** `dmf-env` (private inventory) only. If derivation pattern is
chosen, no `dmf-infra` change needed; the role default stays as the
safe-on-other-platforms fallback.

**Verify:** `bin/run-playbook.sh aliyun-123 bootstrap-configure.yml` (with
the username override from item B.1) reaches `failed=0` after this fix.

#### A.2 — Audit + pin missing `aliyun-123` inventory keys against `hetzner-arm`

**Problem:** `aliyun-123` was set up minimally. Compared to `hetzner-arm`'s
inventory, it's missing pins for: `netbox_namespace`, `netbox_chart_version`,
`netbox_version`, `netbox_base_path`, `netbox_db_*`, `netbox_storage_*`,
`awx_namespace`, `awx_admin_user`, `awx_operator_version`, `forgejo_*`,
`librenms_*`. Some are intentional (LibreNMS not deployed); most are
relying on role defaults that happen to match hetzner-arm's pinned values
**today** — fragile across version bumps.

**Fix:** compare the two inventories side-by-side. For each missing key:

- **Same as role default and stable across versions:** leave unset; add a
  comment block at top of `aliyun-123/group_vars/all/main.yml` listing
  which keys are deliberately inheriting defaults.
- **Matches hetzner-arm's explicit pin:** copy the pin to aliyun-123.
- **Differs intentionally (e.g. LibreNMS not deployed):** add a comment
  documenting why.

**Investigation command:**

```bash
diff <(grep -E '^[a-z]' dmf-env/inventories/hetzner-arm/group_vars/all/main.yml | sed 's/:.*//' | sort) \
     <(grep -E '^[a-z]' dmf-env/inventories/aliyun-123/group_vars/all/main.yml | sed 's/:.*//' | sort)
```

**Repos:** `dmf-env` only.

**Verify:** the diff above returns only intentional differences.

#### A.3 — Remove the three adjacent `failed_when: false` defects in `awx-integration`

**Problem:** qwen surfaced three sites where `failed_when: false` silently
swallows real errors in
`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml`:

- **OpenBao token revoke** (~line 279) — AWX-source-token cleanup; revoke
  failure is benign but should still be logged
- **GIT_SSL_NO_VERIFY project env PATCH** (~line 701) — accepts `[200, 400]`
  with `failed_when: false`; same anti-pattern as Gap C
- **OpenBao SSH key read** (~line 1248) — slurp wrapped in fail-silent;
  related to today's privkey failure (item A.1)

**Fix:** apply the same pattern as commit `a891ecb` Gap C:

- Remove `failed_when: false` from each.
- For the env PATCH: GET-by-id first; conditional POST/PATCH; accept only
  the success code.
- For the OpenBao token revoke: if revoke truly is best-effort, surface
  it explicitly with a `block:`/`rescue:` + a `debug:` warning, not a
  silent skip.
- For the SSH key slurp: with A.1 fixed, this should never fail in healthy
  state; fail-loud surfaces inventory drift (the same way A.1 surfaced today).

**Repos:** `dmf-infra` only. One commit per site (or one bundled commit
with clear message).

**Verify:** repeat `bootstrap-configure.yml` on `aliyun-123`; should still
reach `failed=0` (after A.1+B.1 land).

#### A.4 — NetBox `Site` object renamed from "DMF hetzner-arm" to env-specific

**Problem:** on `aliyun-123`, NetBox shows one `Site` object named
`"DMF hetzner-arm"` (slug `dmf-hetzner-arm`). This is metadata drift from
the cluster's bootstrap-provision phase. Harmless functionally but
misleading in the operator console.

**Fix:** trace where the Site object is created (likely
`roles/stack/operator/netbox-sot/` or `roles/common/sot-bootstrap/`),
parameterize the name/slug on a per-env var (e.g.
`netbox_site_name: "DMF aliyun-123"`).

**Repos:** `dmf-infra` (parameterization) + `dmf-env` (per-env pin).

**Verify:** post-fix, `curl https://netbox.<lan-host>/api/dcim/sites/`
shows `name="DMF aliyun-123"`.

#### A.5 — `ntfy` notification skip in `110-authentik`

**Problem:** the "Send passkey enrollment URL via ntfy" task in
`110-authentik.yml` was `skipping` on `aliyun-123` — gated by a `when:`
clause (likely missing `ntfy_topic` or `ntfy_enabled` var).
Flagged in 2026-05-14 handoff §6.3, deferred.

**Fix:**

```bash
grep -nA 5 "Send passkey enrollment URL via ntfy" \
  dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/tasks/main.yml
```

Decide whether ntfy is supported on `aliyun-123` (operator question). If
yes, add the required var to inventory. If no, document the deliberate
skip (e.g. add a `debug:` task that prints "ntfy notification skipped —
no `ntfy_topic` configured").

**Repos:** `dmf-env` (inventory) or `dmf-infra` (debug message).

---

### Class B — Persistent app-admin drift (operator decision pending)

The 2026-05-14 drift audit identified four apps with username/password
drift on `aliyun-123`. As of 2026-05-17, status:

| App | Drift shape | Today | Long-term |
|---|---|---|---|
| Authentik | none | — | — |
| AWX | username + password | Path 2 resync done (Y2026-05-14); `-e awx_integration_admin_user=<user>` + `-e awx_admin_user=<user>` needed per run | Path 3 patch OR fresh rollout |
| Forgejo | username-only | `-e forgejo_admin_username=<user>` + `-e cms_forgejo_admin_user=<user>` needed per run | Path 3 patch OR fresh rollout |
| NetBox | username-only | `-e netbox_sot_admin_username=admin` (or `netbox_superuser_username=admin`) | Path 3 patch OR fresh rollout |
| Zot | password-only | Path 2 done (htpasswd regen) | — |

#### B.1 — Decide between Path 3 patches vs fresh rollout

**Decision required from operator.** This is an ADR-class choice:

- **Path 3 (incremental):** patch each role to read the live admin username
  from cluster state (mirrors `awx_integration_read_admin_password_from_cluster=true`).
  Per-app, three patches total. Survives future drift; survives fresh
  rollout (no-op when defaults already align).
- **Fresh rollout:** Layer-1 reset + full bootstrap on aliyun-123. Aligns
  live state with role defaults. Burns the cluster down. Several hours +
  loss of any non-replayable state.
- **Hybrid:** Path 3 for AWX (highest blast radius); fresh rollout when
  there's a natural reason (e.g. cluster being rebuilt for another reason).

**Suggested ADR title:** `ADR-0024: Live-state read pattern for app admin identities (vs fresh rollout)`.

**Reference docs:**
- 2026-05-14 drift audit §5.3 (Path 3 design)
- 2026-05-14 drift audit §5.6 (fresh rollout cost)
- Existing precedent: `awx_integration_read_admin_password_from_cluster`

**Until decided:** operator continues with the multi-flag override (item
B.2 makes that less annoying).

#### B.2 — Convenience wrapper for the operator override set

**Problem:** every `bootstrap-configure` run on `aliyun-123` currently
needs 5–6 `-e` flags (see 2026-05-14 handoff §9). Easy to forget one.

**Fix:** small wrapper at `dmf-env/bin/run-configure-aliyun-123.sh` (or
generalized as `bin/run-playbook-with-drift-overrides.sh` reading a
per-env YAML). The wrapper:

1. Reads `dmf-env/inventories/<env>/drift-overrides.yml` (new file —
   per-env override map).
2. Translates each k:v into `-e k=v` flags.
3. Prepends them to `bin/run-playbook.sh` args.

**Repos:** `dmf-env` only. Add `drift-overrides.yml.example` documenting
the schema.

**Verify:** wrapper produces an identical command line to the operator's
current manual incantation; one-shot test against `--check` mode.

#### B.3 — Cross-playbook variable-name fragmentation (out-of-scope but tracked)

Drift audit §5.4 and our 2026-05-15 plan §5.2 both flag this. Same admin
identity referenced under different var names across 691–698. Three
consolidation options (audit doc §5.4).

**Defer to:** after B.1 ADR is answered. If B.1 = fresh rollout, this
gets cheaper because most overrides become unnecessary post-rollout.
If B.1 = Path 3, consolidation becomes part of the Path 3 design.

---

### Class C — Strategic workstreams (carried from 2026-05-14)

These items are large, were already planned, and are referenced here so
this plan is a complete single-entry index for the next agent.

#### C.1 — Runner-pod spike Phases 2–4

**Plan:** [`docs/plans/DMF In-Cluster Ansible Runner Pod Implementation Plan 2026-05-14.md`](DMF%20In-Cluster%20Ansible%20Runner%20Pod%20Implementation%20Plan%202026-05-14.md)

**Status:** Phase 1 done (`dmf-infra@ff36ee8`). Phases 2–4 ready for
cold-pickup. Estimated 3–4 focused hours.

**Once it lands:**
- ADR-0023's §Scope caveat collapses (caller-location is uniformly in-pod)
- 698's `*_host` derivation reverts to internal-DNS defaults
- Override list shrinks further

**Verification gate:** plan doc has explicit phase-by-phase acceptance.

#### C.2 — Internal Service DNS migration execution

**Plan:** [`docs/plans/DMF Internal Service DNS Migration Survey 2026-05-14.md`](DMF%20Internal%20Service%20DNS%20Migration%20Survey%202026-05-14.md)

**Status:** methodology + known-surface table populated; execution
deferred. Walk §3 table; classify each `dmf.example.com` reference into
bins A/B/C/D × P/C/O; migrate (A,P) and (A,C) per decision matrix.
Approximately 8–10 playbook files.

**Blocked by:** C.1 for the (A,C) → (A,P) collapse (transitionally
coexists).

#### C.3 — ADR-0024 (or equivalent): fresh-rollout decision

**Trigger:** item B.1. The ADR codifies (a) when to fresh-rollout
`aliyun-123`, (b) what state to preserve (operator passkey, custom
catalog entries, image registry contents), (c) how to validate parity
post-rollout.

**Estimated effort:** 30–60 min for ADR draft; the rollout itself is a
half-day.

---

### Class D — Hygiene + doc-vs-implementation drift

#### D.1 — Break-glass JSON missing `root_token`

**Source:** 2026-05-15 plan §5.1.

**Problem:** `DEPLOYMENT.md` §7 (lines 219–220) states root token is
retained for `app-admin-facts` per-app secret writes; openbao role
(`roles/stack/operator/openbao/tasks/main.yml:~1530`) does NOT include
it in `openbao_breakglass_content`. On `aliyun-123`, the break-glass JSON
contains unseal keys + AppRole + service-account passwords, no root token.

**Fix:** ADR or bugfix. Either:
- Update the docs to say root token is deliberately NOT persisted
  (matches current code), and document the alternative path
  `app-admin-facts` uses (operator userpass login). OR
- Add `root_token` to `openbao_breakglass_content` (matches docs); audit
  who else needs it; rotate proactively.

**Decision required from operator.** Recommend the docs-fix path —
keeping the root token out of the JSON file is better security posture.

#### D.2 — Stale break-glass hygiene check

**Source:** 2026-05-14 handoff §6.4.

**Action:**

```bash
sha256sum /Volumes/<user>/secure/openbao-breakglass/hetzner-lab/openbao-keys-automation.json
sha256sum /Volumes/<user>/secure/openbao-breakglass/aliyun-123/openbao-keys-automation.json
```

If equal: hygiene incident — rotate. If different: no action.

#### D.3 — NetBox `drf-spectacular` partial-failure mode

**Source:** 2026-05-15 plan §5.3.

`roles/stack/operator/netbox/tasks/main.yml:590-656` — drf-spectacular
patch workflow can leave the Deployment stuck if the ConfigMap creation
fails silently. Add a `block:`/`rescue:` with explicit assertion of
ConfigMap presence before patching.

**Repos:** `dmf-infra`.

#### D.4 — `STATUS.md` operator-notes section update

Today's session changed cross-cluster role behavior (4 commits to
`dmf-infra`). Per Constitution Rule 6, the `<!-- HUMAN-START -->` block
of `STATUS.md` needs an entry summarizing:

- 2026-05-17 — Bootstrap-configure completion plan landed end-to-end;
  catalog-project sync (`8d20e71`) added as a follow-up; aliyun-123
  validated; remaining failure is inventory gap (item A.1).

#### D.5 — Handoff doc for today's session

Per Rule 6 + standard practice, write
`docs/handoffs/DMF Aliyun-123 Lifecycle-Configure Completion Handoff 2026-05-17.md`
covering: the 4 commits, the live validation, items deferred to this plan.
Cross-link this plan from the handoff.

#### D.6 — Mark 2026-05-15 plan as complete

`docs/plans/DMF Lifecycle-Configure Bootstrap Completion Plan 2026-05-15.md`
— add a `## 8. Completion status` section at the bottom citing the four
commits and pointing to this follow-ups plan.

---

### Class E — Bonus: items observed today not previously tracked

#### E.1 — Forgejo `dmf-runbooks` was already populated at run-time despite seed never executing

**Observation:** today's three bootstrap-configure runs all took the
idempotent-skip path for the seed task — required_files (the two playbook
references) already returned 200 from the Forgejo API. But qwen's
diagnostic at the start of the session reported the repo had only
README.md. Something filled in the playbooks between then and today's
runs, outside the harness.

**Likely cause:** operator out-of-band push to Forgejo, OR a prior session
that succeeded silently.

**Action:** confirm with operator. If unexplained, audit the Forgejo
audit log for the dmf-runbooks repo to see who pushed and when. Low
urgency — system is consistent now.

#### E.2 — AWX `admin_user` value is the operator's username, not `awx-local-admin`

**Observation:** today's AWX API probes confirmed
`spec.admin_user: <operator-username>` on `aliyun-123`'s AWX CR. The
`aliyun` and `hetzner-arm` inventories both pin `awx_admin_user: awx-local-admin`.
This means `aliyun-123` was bootstrapped before the operator chose the
`awx-local-admin` rename convention.

**Action:** ties into B.1 ADR. Either (a) Path 3 patch reads live
`admin_user` from CR spec (no inventory pin needed), or (b) fresh rollout
aligns with `awx-local-admin` per inventory pin.

---

## 3. Suggested execution order

Class A items are all independent, mostly mechanical, and have clear
acceptance — knock them out first to clean the slate.

```
A.1 ──┐
A.2 ──┼── (parallelizable, then one `bootstrap-configure` re-run on aliyun-123 to verify)
A.3 ──┤
A.4 ──┤
A.5 ──┘
   │
   ▼
D.4 + D.5 + D.6 (doc updates while context is fresh)
   │
   ▼
B.1 ──── (decision-class, operator-driven — ADR + path choice)
   │
   ├──→ B.2 (only valuable if path = override-permanence)
   │
   ▼
C.1 ──── Runner-pod Phases 2–4
   │
   ▼
C.2 ──── Internal DNS migration
   │
   ▼
B.3 ──── Variable-name consolidation (cheapest after fresh rollout)
```

D.1, D.2, D.3 are independent hygiene items — drop in wherever capacity
exists. E.1 and E.2 are observational; act on them only if context
demands.

---

## 4. Acceptance criteria

This plan is "done" when:

- All Class A items are committed to `dmf-env` and/or `dmf-infra` and a
  fresh `bootstrap-configure.yml` run on `aliyun-123` reaches `failed=0`
  end-to-end without any `-e` overrides for paths/keys (admin-username
  overrides may persist depending on B.1's outcome).
- Class D items D.4/D.5/D.6 are landed (umbrella docs).
- Class B.1 has either an answered ADR or an explicit operator decision
  recorded in `docs/agentic/decisions-open.md` (gate name suggestion:
  `app-admin-drift-resolution-path`).
- Class C items remain on the queue with their own plan docs as the
  cold-pickup entry points (no further work in this plan).
- Items D.1, D.2, D.3 are either resolved or filed as Forgejo issues
  with `type:bug` / `type:workaround` per
  `docs/agentic/ISSUE-TEMPLATES.md`.

---

## 5. Forgejo issue candidates

Per Constitution Rule 11, only the orchestrator runs
`bin/agentic/issue-open.sh`. Recommended issues to file (in priority order):

| Item | Type | Scope | Effort | Body source |
|---|---|---|---|---|
| A.1 | `workaround` → `bug` | dmf-env | S | this plan §A.1 |
| A.3 | `bug` (×3) | dmf-infra | S each | this plan §A.3 |
| A.4 | `bug` | dmf-infra | S | this plan §A.4 |
| A.5 | `workaround` | dmf-infra | S | this plan §A.5 |
| B.1 | `decision-requested` | dmf-infra | M-L | drift audit §5 + this plan §B.1 |
| D.1 | `decision-requested` | dmf-infra | S | this plan §D.1 |
| D.3 | `bug` | dmf-infra | S | this plan §D.3 |

C.1, C.2, C.3 already have dedicated plan docs; no issue needed unless
they get re-prioritized.

---

## 6. Cluster verification commands (post-execution)

For the agent picking up this plan: after Class A items are landed,
re-run the §6 verification battery from
`docs/plans/DMF Lifecycle-Configure Bootstrap Completion Plan 2026-05-15.md`,
**without** the `awx_control_node_ssh_privkey_path` workaround. All five
checks must still pass AND PLAY RECAP must show `failed=0`.

Probe commands (live cluster):

```bash
# AWX auth context (use spec.admin_user from CR)
ssh -i ~/.ssh/id_ed25519_k3s_aliyun k3s-admin@<control-node-public-ip> bash <<'REMOTE'
USER=$(sudo k3s kubectl get awx -n awx -o jsonpath='{.items[0].spec.admin_user}')
PWD=$(sudo k3s kubectl get secret -n awx awx-admin-password -o jsonpath='{.data.password}' | base64 -d)
curl -sk -u "$USER:$PWD" "https://awx.<lan-host>/api/v2/projects/9/" \
  | python3 -m json.tool
REMOTE

# Catalog JTs
ssh -i ~/.ssh/id_ed25519_k3s_aliyun k3s-admin@<control-node-public-ip> bash <<'REMOTE'
USER=$(sudo k3s kubectl get awx -n awx -o jsonpath='{.items[0].spec.admin_user}')
PWD=$(sudo k3s kubectl get secret -n awx awx-admin-password -o jsonpath='{.data.password}' | base64 -d)
curl -sk -u "$USER:$PWD" "https://awx.<lan-host>/api/v2/job_templates/" \
  | python3 -c 'import sys,json; r=json.loads(sys.stdin.read())["results"]; [print(j["name"], j.get("playbook")) for j in r if j["name"].startswith("media-")]'
REMOTE

# dmf-cms-svc NetBox perms
ssh -i ~/.ssh/id_ed25519_k3s_aliyun k3s-admin@<control-node-public-ip> bash <<'REMOTE'
TOKEN=$(sudo k3s kubectl get secret -n dmf-cms dmf-cms-runtime -o json | python3 -c 'import sys,json,base64; print(base64.b64decode(json.load(sys.stdin)["data"]["netboxApiToken"]).decode())')
curl -sk -H "Authorization: Bearer $TOKEN" "https://netbox.<lan-host>/api/dcim/sites/" -w '\nHTTP %{http_code}\n'
REMOTE
```

Use placeholder syntax (`<control-node-public-ip>`) in any handoff doc or
issue body (Constitution Rule 8).

---

## 7. Glossary

| Term | Meaning |
|---|---|
| Gap A / B / C | The three changes shipped in 2026-05-15 plan: seed Forgejo repos, dmf-cms-svc NetBox perms, fail-loud catalog JT POST |
| Path 1 / 2 / 3 | Drift-audit remediation taxonomy: `-e` override / in-pod resync / role-side patch |
| Catalog project | An AWX project that holds catalog launcher playbooks (`dmf-runbooks`, `dmf-media`, `dmf-infra`) — distinct from the main `awx-automation` project |
| Caller location | ADR-0023 vocabulary: where the TCP-opening process runs (control-node vs in-pod) — determines whether internal-DNS or public-URL applies |
| Runner-pod | The in-cluster ansible execution model from ADR-0023 + Runner Pod plan; flips configure-stage ansible from "from operator's Mac" to "from a Pod inside aliyun-123" |
