# DMF Platform — Move 2 Learnings (vertical slice)

**Date:** 2026-05-04
**Scope:** dmf-cms Workflows → AWX → NetBox vertical slice (Move 2 from the
strategic review at `docs/reviews/dmf-platform-strategic-review-2026-04-30.md`)
**Status:** Move 2 acceptance criteria met (8/8 below). This doc is the closing
deliverable — per the plan, *"the write-up captures what was learned... is the
actual deliverable of Move 2; the working code is incidental."*

---

## TL;DR

The vertical slice closed end-to-end. Console click → AWX job → NetBox-derived
inventory → result back works. Four architectural assumptions tested:

| Assumption | Verdict | Evidence |
|---|---|---|
| NetBox `ipam.Service` can hold the app catalog | ✅ Confirmed | 10 apps registered (`roles/common/dmf-born-inventory/defaults/main.yml`) |
| dmf-cms `app-contract` survives a live backend | ✅ Confirmed (with reshape) | Contract narrowed; OIDC + exposure moved to NetBox |
| Runtime auth composes (Authentik OIDC → dmf-cms → AWX → NetBox) | ✅ Confirmed (with caveats) | `699-cms-smoke-test.yml` passes; per-user identity not preserved |
| `ipam.Service` is the right NetBox shape | ⚠️ Mostly — schema gotcha | NetBox v4 generic-relation change broke the original spec |

The strategic review's commit gate is **half-met**. Move 1 (NMOS spike on
`dmf-media/`) is the remaining gate item.

---

## What landed

Five Pieces from the Move 2 plan, plus an added piece for runtime tokens:

| Piece | Plan | Reality | Files |
|---|---|---|---|
| 1 | Extend NetBox SoT for L6 apps | Done | `roles/common/dmf-born-inventory/tasks/{main,app-service}.yml`, defaults add 10 apps |
| 2 | AWX service-account token | Done | `playbooks/697-cms-awx-token.yml` |
| 2b | NetBox + Forgejo runtime tokens (added) | Done | `playbooks/698-cms-netbox-forgejo-tokens.yml` |
| 3 | AWX job template for `eso-openbao-health-check` | Done | `roles/stack/operator/awx-integration/tasks/main.yml` (publishes runbook to Forgejo, creates JT) |
| 4 | dmf-cms Workflows page wires through to AWX | Done | `dmf-cms/src/dmf_cms/awx.py`, `main.py:282-345` |
| 5 | Console integration smoke | Done | `playbooks/699-cms-smoke-test.yml` |

Original plan numbered Piece 5 as `698-cms-integration-smoke`. Reality renumbered:
`698` became NetBox+Forgejo runtime tokens (a piece the plan didn't anticipate),
`699` became the smoke test. The lifecycle-provision import order matches.

---

## Q1 — Did NetBox SoT survive driving real AWX inventory?

**Yes, but the original schema spec was wrong on NetBox v4.**

The Move 2 plan listed `device:` as the FK field on `ipam.Service`. Reality:

```yaml
# roles/common/dmf-born-inventory/tasks/app-service.yml:47-49
# NetBox v4: Service uses a generic relation, not a direct device FK.
parent_object_type: dcim.device
parent_object_id: "{{ dmf_born_inventory_load_balancer_id }}"
```

NetBox v4 changed `Service.device` from a direct ForeignKey to a generic
relation. The `device_id=` query filter "may be ignored" (per inline comment);
the role pivoted to filter-by-name lookups, which works because app keys are
unique in our scope.

**What this means:** any future plans referencing the NetBox model should
target NetBox v4 docs explicitly. The "host-running-app-on-port" mental model
still applies, but the API shape changed mid-version. Worth an ADR if we
commit to NetBox as the catalog SoT in v1.

**Fields actually used:** `name`, `protocol`, `ports`, `parent_object_type/id`,
`description`, `comments`, `tags`. **No custom fields.** The plan's strategy
("add CFs when dmf-cms tries to read this and finds a field missing") is
preserved — nothing has yet tried to read a missing field, so no CFs were
added.

**App count:** 10 apps registered — `landing`, `authentik`, `forgejo`, `awx`,
`netbox`, `grafana`, `prometheus`, `loki`, `zot`, `dmf-cms`. Matches plan.

---

## Q2 — Did the dmf-cms `app-contract` survive a live backend?

**Yes, kept static as recommended (D4 = A). But the contract narrowed,
not widened.**

Plan implied the contract would carry OIDC client + exposure. Actual:

```python
# dmf-cms/src/dmf_cms/contracts.py:16-22
@dataclass(frozen=True)
class AppContractEntry:
    key: str
    display_name: str
    lane: str          # public | private
    summary: str
    deep_links: list[AppLink] = field(default_factory=list)
```

Fields **missing** vs. what the plan implied: `oidc_client_id`, `exposure`.
Those landed in NetBox `ipam.Service.comments` instead, on the
deployment-registers-itself side.

**Naming inconsistency surfaced:** the contract uses `lane: public|private`;
NetBox uses `exposure: public|private`. Same concept, two names. Not breaking
anything yet, but if a release-1 feature needs to join across both, one of the
two has to give.

**Implication for v1:** the contract is functioning more as a **static
operator-facing index** (display name, summary, deep links) than as a **dynamic
catalog**. Release-1 work that landed during this period (v0.4.0 Layer 1-3
backend API, role-aware dashboards, v0.6.0 Prometheus alert bell) does *not*
enrich the contract — it queries NetBox / AWX / Prometheus directly. That
suggests the contract's long-term role is "navigation manifest", not "service
catalog". The catalog SoT is NetBox.

**Pivot to NetBox-discovered (D4 option B) is still queued as a TODO** —
should now be cheap because the field gap is small.

---

## Q3 — Did runtime auth composition work end-to-end?

**Yes for the service-account path (D3 = A). The `/me/` verification idea
from the plan didn't survive contact.**

Auth path delivered:

```
Authentik OIDC → dmf-cms session
                 ↓ (no propagation)
dmf-cms → AWX  : OAuth2 svc-account token (dmf-cms-svc)
AWX → NetBox   : NetBox service-account token (already wired in 691-netbox-sot)
AWX → Forgejo  : Forgejo SCM token (already wired in 692-forgejo-bootstrap)
```

**AWX OAuth2 was heavier than bare bearer.** Plan flagged this; reality
confirmed. AWX uses OAuth2 applications + tokens, not opaque bearers — token
creation is a multi-step API call (POST to `/applications/`, then `/tokens/`).
Reflected in the "~30 min → ~45 min" bump the plan flagged for D3 option A.

**The `/me/` endpoint had quirks.** Plan: "curl `/api/v2/me/` from inside the
pod, assert `username: dmf-cms-svc`." Reality: two commits had to work around
`/me/` (`7d881a7 Fix AWX token verification to work around /me/ endpoint
issue`, `b2d8245 Fix AWX /me/ endpoint response parsing`). The smoke test
ended up verifying via `/api/v2/inventories/?format=json` instead — 200 = token
authenticates, count present = real response. More robust than checking a
specific identity.

**Per-user identity is not preserved.** dmf-cms acts as `dmf-cms-svc` for all
AWX operations. AWX's audit trail shows the service account, not the operator.
This is a **known release-1 gap**, deferred deliberately. If the gap matters
for compliance / audit, it converts D3 option A → option B (rebuild
AWX↔Authentik as OIDC + token pass-through). That's a separate decision now,
not blocked by anything Move 2 surfaced.

---

## Q4 — Was `ipam.Service` the right NetBox shape?

**For the spike, yes. For release-1, probably yes plus custom fields.**

The built-in model accepts the data. The pattern composes — apps are
"things-running-on-the-LB-on-port-443" and Service is exactly that abstraction.

What's missing for a release-1 Service Catalog page:
- **Owner** — currently in `comments` as a free-text "Owner: svc/<key>" line. Should be a CF or a real FK to a NetBox tenant/contact.
- **Lifecycle status** — the plan listed `lifecycle:active` as a tag; tag works for filtering but not for state machines. CF needed if release-1 wants to express "deploying / active / draining / retired".
- **Dependency graph** — there's no link between Service objects expressing "Forgejo depends on Authentik for OIDC". CFs or a NetBox plugin.
- **Health URL / probe** — currently inferred from hostname; release-1 health view will need a structured probe field.

**Recommendation:** when release-1 starts pulling from NetBox for the Service
Catalog page, add CFs lazily as those reads find gaps. This matches the plan's
strategy and avoids premature taxonomy.

---

## Acceptance criteria — all met

From the Move 2 plan §"Acceptance":

- [x] `694-born-inventory.yml` registers ≥10 apps as NetBox `ipam.Service` records (10 in defaults)
- [x] `forgejo-svc` exists as NetBox user (parallel to awx-svc, librenms-svc)
- [x] `dmf-cms-svc` AWX user + token persisted in OpenBao + dmf-cms-runtime Secret (697-cms-awx-token.yml)
- [x] `eso-openbao-health-check` AWX job template auto-created from Forgejo SCM (`awx-integration/tasks/main.yml`)
- [x] dmf-cms Workflows page has working Run + status polling (`awx.py:108-176`, `main.py:282-345`)
- [x] `699-cms-smoke-test.yml` asserts /healthz + AWX token validity + inventories reachable
- [x] After lifecycle-provision passes, the loop closes
- [x] **A write-up captures what was learned** — this document

---

## Bonus learnings (not in plan)

These weren't predicted by Move 2 but emerged during execution. Each is
durable knowledge worth preserving.

### NetBox v4 token format

NetBox v4 uses "v2 tokens": full token = `TOKEN_PREFIX + key + "." + secret`.
The DB stores only `key`; the secret half is **only available at creation
time**. Must be captured to OpenBao on first run. API auth uses
`Authorization: Bearer <full_token>`.

Documented in `dmf-infra/CLAUDE.md` ("Token updates in NetBox SoT
playbook").

### Heredoc + Ansible footgun

`cmd: >-` (folded scalar) collapses heredoc body onto one line; Python's
argparse then errors. Working pattern: `set_fact` with `|-` literal block,
then `argv:` form invoking `/bin/sh -c "{{ _the_cmd }}"`. Documented in
`docs/handoffs/DMF Bootstrap User Privileges Handoff 2026-05-03.md` §6.1.

### OpenBao mode toggle was failing open

Chain review finding #5. The `*_persist_to_openbao` derived var would silently
fall through to vault.yml if any of 5 OpenBao vars was missing. Fixed early in
this work cycle (commit `9bdf758`) — added a fail-closed assert. Generalizes
to: derived booleans across required sets should fail loud on partial config.

### Bootstrap operator privilege discovery

Implementing Move 2 surfaced that `<operator>` (the bootstrap OIDC user) wasn't an
Authentik superuser. Plan exists at
`docs/handoffs/DMF Bootstrap User Privileges Handoff 2026-05-03.md` —
group-level `is_superuser: true` on the `ops-admin` blueprint group, not
user-level. Still pending application as of this writing.

**Generalizes to:** post-deploy admin status across OIDC-federated apps does
not propagate from the IdP user-row. Each app surfaces it differently
(NetBox `is_superuser`, Grafana `isAdmin`, Zot `adminPolicy.users` ignores
OIDC groups, etc.). Release-1 needs an opinion on operator-vs-user privilege
modeling — not blocking Move 2 closure but blocking "smooth onboarding."

### Numbering ≠ ordering still drifts

Chain review finding #1 wasn't fixed in this round. New playbooks 697 / 698 /
699 were appended in lifecycle-provision order, which is consistent with
existing practice but doesn't fix the underlying mismatch (`650-dmf-cms.yml`
sorts before 691-694 numerically, runs after them in lifecycle-provision).
Cleanup deferred to commit-phase per chain review's recommendation.

### Move 2 became the launchpad for release-1

dmf-cms shipped through v0.6.0 during the same window — Layer 1-3 backend API
(v0.4.0), role-aware dashboards (v0.3.8 / v0.3.10), Prometheus notification
bell (v0.6.0), self-bootstrapping groups (v0.5.0). The "vertical slice" became
the foundation for release-1 work landing on top, ahead of the strategic
review's commit gate.

This is the right direction *if* the foundation actually held — and the four
Q's above say it did, with one schema correction. Not a problem; worth
flagging because the strategic review framed Move 2 as a falsifying spike,
not as a launch.

---

## Commit gate status

Strategic review's gate (verbatim):

> When dmf-cms release-1's first vertical slice is running end-to-end against
> real backends **AND** one NMOS registry is deployed in `dmf-media`,
> write `docs/architectural-commitments-v1.md` and stop reshaping the
> foundations.

| Condition | Status |
|---|---|
| First vertical slice end-to-end | ✅ DONE (this Move 2 work) |
| NMOS registry in `dmf-media` | ❌ NOT STARTED (Move 1) |
| `docs/architectural-commitments-v1.md` | Not yet written |

The gate is **half-met** by an AND. Two reasonable next moves:

- **(a)** Run Move 1 (NMOS spike on `dmf-media/`) to close the AND; then
  draft `architectural-commitments-v1.md` from both experiments combined.
- **(b)** Draft a *provisional* `architectural-commitments-v1.md` now from
  Move 2's findings alone, marked as "Move 2 commitments only — Move 1
  pending"; amend after NMOS lands.

Lean: **(a)**. Move 1 is the bigger thesis-killer; if NMOS doesn't deploy on
commodity k3s, several Move 2 commitments would be premature. Worst case for
(a): another ~1-2 days, after which we have a complete commit document.

---

## Implications for the next moves

1. **Move 1 (NMOS spike) is now the highest-priority unaddressed work** — it
   was already #1 in the strategic review, and Move 2's closure makes it the
   sole remaining gate item.

2. **Public push (Path A from this session's framing) is unblocked by Move 2**
   — the umbrella docs now have a concrete experiment narrative to point at,
   which is a stronger portfolio artifact than abstract architecture diagrams.
   The push doesn't have to wait for Move 1 if the README frames the
   experimental status accurately.

3. **`app-contract` pivot to NetBox-discovered (TODO)** is now low-risk and
   small. Probably ~1 hour.

4. **Bootstrap operator privilege model** needs an opinion before release-1
   onboards a second human operator. Group-level superuser plan exists; just
   needs application + sweep across other apps.

5. **NetBox v4 schema awareness** should land in the per-repo CLAUDE.md as a
   gotcha. Already partly there; the `parent_object_type/id` change isn't
   yet documented outside this file.

---

## Cross-reference

- Strategic review: [`docs/reviews/dmf-platform-strategic-review-2026-04-30.md`](dmf-platform-strategic-review-2026-04-30.md)
- Chain review: [`docs/reviews/dmf-platform-chain-review-2026-04-30.md`](dmf-platform-chain-review-2026-04-30.md)
- Move 2 task spec: [`docs/plans/dmf-platform-move-2-task-2026-04-30.md`](../plans/dmf-platform-move-2-task-2026-04-30.md)
- Bootstrap user handoff (related side-quest): [`docs/handoffs/DMF Bootstrap User Privileges Handoff 2026-05-03.md`](../handoffs/DMF%20Bootstrap%20User%20Privileges%20Handoff%202026-05-03.md)
- DMF Platform Plan (canonical architecture): [`docs/architecture/DMF Platform Plan.md`](../architecture/DMF%20Platform%20Plan.md)

---

## Single-line verdict

**The vertical slice held. NetBox `ipam.Service` is a viable catalog SoT
once the v4 generic-relation schema is respected. Service-account auth
composes; per-user identity is a separate, deferrable problem. The commit
gate is half-met; Move 1 (NMOS) closes it.**
