---
status: draft
date: 2026-05-23
---
# DMF AWX Catalog Credential Type Migration Plan

**Date:** 2026-05-23
**Status:** Proposed (deferred — staged followup to Lane B Chart 0.1.1 closure)
**Owner:** next session on `awx-integration` role
**Related:** ADR-0014, ADR-0024, ADR-0025

## Problem

The `media-launch-nmos-cpp` JT (and `media-finalise-nmos-cpp` sibling)
inject NetBox API tokens into each catalog Job Template as plaintext
`extra_vars`. The token values are written by the `awx-integration`
role's `awx_catalog_job_templates` default at
`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/defaults/main.yml:135-146`
and POSTed onto the JT as the `extra_vars` field at
`tasks/main.yml:1330` and `:1393`.

That is the lowest-effort path to "the launcher playbook reads these
variables," but it has a real exposure problem: **AWX's JT-launch API
response body echoes the full JT spec, including the plaintext
`extra_vars`.** Any caller with `execute` on the JT (which is everyone
who can launch it — dmf-cms catalog page, our agentic-harness session,
a 3rd-party consumer per ADR-0027) sees the tokens on the
`POST /api/v2/job_templates/<id>/launch/` response. That includes
`vault_netbox_api_token` and `vault_netbox_admin_token`, both of which
grant broad NetBox write access.

Observed live in the 2026-05-23 session: launching JT 14 returned the
two tokens in the response body, into the orchestrator's transcript.
For the experiment phase this was acceptable per ADR-0004; before any
non-experiment caller invokes the launch endpoint, the tokens must be
behind AWX's credential-encryption boundary.

## Goal

Replace plaintext `extra_vars` token injection with an AWX **Custom
Credential Type**. AWX stores credential field values encrypted in
PostgreSQL, returns `$encrypted$` placeholders on every API read, and
merges injected variables into the playbook execution context — so the
launcher playbook continues to read `vault_netbox_api_token` the same
way. The launch-endpoint response no longer leaks the value.

## Scope

In:
- New Custom Credential Type `DMF NetBox API`
- New credential object `dmf-netbox-tokens` populated from
  `awx_integration_netbox_token` + `awx_integration_netbox_admin_token`
- `awx_catalog_job_templates` default restructured to split:
  - operational `extra_vars` (URL, anything non-sensitive)
  - `extra_credentials` (names of credentials to attach)
- `awx-integration/tasks/main.yml` extended with credential-type-ensure,
  credential-ensure, and JT-credential-attach tasks
- Idempotent cleanup: existing JTs' plaintext NetBox keys stripped from
  `extra_vars` on every 693 run

Out:
- Refactoring the launcher playbook (`launch-nmos-cpp.yml`) — no
  changes needed because credential-injected `extra_vars` reach the
  playbook context identically
- Migrating other plaintext credentials (none currently — only the two
  NetBox tokens hit JT extra_vars today)
- ADR amendment — the change is implementation-level inside ADR-0014's
  multi-project AWX layout

## Custom Credential Type design

`name`: `DMF NetBox API`
`description`: NetBox API + admin tokens for catalog launcher JTs

```yaml
inputs:
  fields:
    - id: netbox_url
      type: string
      label: NetBox API base URL
    - id: api_token
      type: string
      label: NetBox API token (read/write data)
      secret: true
    - id: admin_token
      type: string
      label: NetBox admin token (custom-fields, schema)
      secret: true
  required:
    - netbox_url
    - api_token
    - admin_token

injectors:
  extra_vars:
    netbox_api_url: "{{ netbox_url }}"
    vault_netbox_api_token: "{{ api_token }}"
    vault_netbox_admin_token: "{{ admin_token }}"
```

The injector keys match what the launcher currently reads, so no
playbook-side change.

## Default-side restructure

`awx-integration/defaults/main.yml` change:

```yaml
# before
awx_catalog_job_templates:
  - name: media-launch-nmos-cpp
    …
    extra_vars:
      netbox_api_url: "{{ awx_integration_netbox_url }}"
      vault_netbox_api_token: "{{ awx_integration_netbox_token | default(…) }}"
      vault_netbox_admin_token: "{{ awx_integration_netbox_admin_token | default(…) }}"

# after
awx_catalog_job_templates:
  - name: media-launch-nmos-cpp
    …
    extra_vars: {}                      # nothing injected here
    extra_credentials:
      - dmf-netbox-tokens
```

The two tokens flow into AWX once (via the credential-ensure task) and
attach to each JT by name (via JT-credential-attach).

## Task additions in `tasks/main.yml`

Approximate task ordering (insert after the existing `forgejo-scm`
credential block at lines 684–746; before the JT lookup at 1297):

1. **Look up `DMF NetBox API` credential type** by name.
2. **Create-if-missing** with the schema above (POST
   `/api/v2/credential_types/`). Body: `{name, kind: "cloud", inputs,
   injectors}`. PATCH-if-present so schema bumps are idempotent.
3. **Look up `dmf-netbox-tokens` credential** by name and credential
   type id.
4. **Create-if-missing** (POST `/api/v2/credentials/`). Body:
   `{name, organization, credential_type, inputs: {netbox_url,
   api_token, admin_token}}`. PATCH-if-present.
5. **After existing JT-create/PATCH (lines 1311–1404)**: per JT in
   `awx_catalog_job_templates`, GET `/api/v2/job_templates/<id>/credentials/`
   and POST-attach any missing entry from
   `jt_item.extra_credentials | default([])`. Idempotent.
6. **Cleanup task — strip plaintext NetBox keys from existing JT
   `extra_vars` on every run.** Necessary because the existing live
   JTs have the plaintext tokens baked in (the field is preserved
   across PATCHes that don't supply it). Pattern: for each catalog
   JT, GET `extra_vars`, remove `netbox_api_url`,
   `vault_netbox_api_token`, `vault_netbox_admin_token` keys if
   present, PATCH back. `no_log: true` on the PATCH (the GET response
   will still contain the values once during cleanup — fine because
   the playbook log itself is not transcript-visible like the API
   launch response is).

## Verification

After 693 re-run:

1. **AWX UI: JT has credential attached.** `https://awx.<domain>/#/templates/job_template/<id>/details` shows `dmf-netbox-tokens` in the credentials list.
2. **JT extra_vars no longer carries the tokens.** GET
   `/api/v2/job_templates/<id>/` shows `extra_vars` is either `{}` or
   contains only non-sensitive keys.
3. **Launch endpoint response sanitised.** POST
   `/api/v2/job_templates/<id>/launch/` response body's
   `extra_vars` field is empty/sanitised (no plaintext tokens visible).
4. **Launcher still works.** Job runs to completion; NMOS Query API
   returns HTTP 200; NetBox `lifecycle:active` tag still flips.
5. **Idempotency.** Second 693 run reports 0 changed on credential
   type / credential / attachment / cleanup tasks.

## Effort estimate

- Credential type + credential ensure tasks: ~30 min
- JT-attach + extra_vars cleanup: ~30 min
- Defaults restructure: ~10 min
- Live verification cycle (693 re-run, launch, inspect, idempotency
  check): ~30 min

Total ~100 min for one careful session. Comfortably one PR / commit
worth.

## Out-of-scope nuances captured here so they don't get lost

- **Per-env netbox_url:** the credential's `netbox_url` input value
  should come from `awx_integration_netbox_url` (the in-cluster
  service DNS, e.g. `http://netbox.netbox.svc.cluster.local`), which
  is already the per-env-resolvable Jinja expression in defaults. The
  credential value is rendered at role-run time, not at credential-
  use time, so the per-env binding is correct.

- **Token-rotation flow:** when `awx_integration_netbox_token` rotates
  in OpenBao + role-runtime, 693's credential-ensure task should
  PATCH the credential's `inputs` to push the new value. PATCH on
  `/api/v2/credentials/<id>/` with `{inputs: {api_token: "<new>"}}`
  re-encrypts and updates without exposing old or new value to the
  response.

- **Why `kind: "cloud"`:** AWX Custom Credential Types must declare a
  kind. `cloud` is the standard for "credential carrying secrets but
  not a built-in machine/network type." Other valid kinds are `net`
  and `vault`; `cloud` is the right shape semantically.

- **Why not `kind: "vault"`:** that kind is reserved for
  AWX-Vault-decrypt credentials (encrypted-Ansible-vault file
  unlock). Not what we're doing.

- **ADR-0024 alignment:** the migration reduces the surface that
  needs to know app-admin tokens. The role default's existing
  `awx_integration_netbox_token | default(vault_netbox_api_token,
  …)` chain stays — only the JT-storage shape changes.

## Where to pick up

Next session:

1. Open `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml`.
2. Find the existing `forgejo-scm` credential block at lines 684–746;
   model the new credential-type-ensure + credential-ensure tasks on
   it. Differences: it's a credential **type** plus an instance, not
   just a credential against a built-in type.
3. Modify `awx_catalog_job_templates` default + JT-create/PATCH POSTs
   to consume `extra_credentials` list.
4. Add the post-attach cleanup loop.
5. Run 693 against g2r6-foa9, walk the 5 verification checks above.
6. Land in a single commit `fix(awx-integration): migrate catalog JT
   NetBox tokens to Custom Credential Type` with reference back to
   this plan doc.
7. Close the open followup in
   `dmfdeploy/docs/handoffs/DMF Lane B Chart 0.1.1 Landed Handoff 2026-05-23.md`
   and the STATUS.md operator-notes structural-note bullet.
