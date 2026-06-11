---
status: executed
date: 2026-05-29
---
# DMF Authentik Brand-Wide Passkey-First Login Plan

**Date:** 2026-05-29
**Status:** Plan (code edits staged; live verification pending)
**Related:** ADR-0015 (passkey-only) + its 2026-05-29 brand-wide amendment;
ADR-0023 (CMS↔Authentik back/front-channel split); ADR-0028 D8 (≥2 passkeys
per human). Sibling to — but independent of —
`DMF Authentik Bootstrap Enrollment Drop Username Prompt Plan 2026-05-28.md`
(enrollment-flow username prompt; **not** touched here, still unimplemented).

## Problem

ADR-0015 made only the **DMF Console** passkey-only. Every other app
(Forgejo, AWX, NetBox, LibreNMS, Grafana, Zot) and the Authentik **portal**
itself still defaulted to `default-authentication-flow`, whose identification
stage renders a username/email form before the browser WebAuthn popup. The
operator's friction (UX Constitution §4.3: a username prompt appears *before*
the passkey picker on the default flow) applies brand-wide, not just to the
console.

The operator has **locked** the decision: make the platform **brand-wide
passkey-first**. The portal and every SSO redirect should land directly on the
passkey picker; password is kept **only** as an explicit break-glass path. This
plan records the edits and the verification matrix. Scope is not re-litigated.

## Two levers (both required)

A provider's `authentication_flow` **overrides** the brand default. So flipping
the brand alone leaves the apps on their pinned flow, and flipping the apps
alone leaves the portal on the username form. Both levers must move:

1. **Per-provider** — in `20-app-providers.yaml.j2`, pin the 6 non-Console
   providers to `dmf-passkey-login` (Console already used it).
2. **Brand default** — in `16-passwordless-bootstrap.yaml.j2`, patch the
   built-in default brand to `flow_authentication: dmf-passkey-login`. Covers
   the portal and any future provider that does not pin its own flow.

`dmf-passkey-login` (already defined in blueprint 16) is the passkey-first
flow: an `AuthenticatorValidateStage` (`device_classes: [webauthn]`,
`webauthn_user_verification: required`, `not_configured_action: deny`) at
order 10, then a `UserLoginStage` at order 100. No identification stage ⇒ no
username field ⇒ the browser passkey picker is the first and only prompt.

## Exact file edits

All edits are **on disk in `dmf-infra` (branch `main`)**; nothing committed or
deployed by this plan.

### Lever 1 — `roles/stack/operator/authentik/templates/blueprints/20-app-providers.yaml.j2`

Six lines changed (the Forgejo, AWX SAML, NetBox, LibreNMS, Grafana, Zot
providers), each from:

```yaml
      authentication_flow: !Find [authentik_flows.flow, [slug, default-authentication-flow]]
```
to:
```yaml
      authentication_flow: !Find [authentik_flows.flow, [slug, dmf-passkey-login]]
```

The DMF Console provider (`oidc-dmf-console`) already used `dmf-passkey-login`
and is **left untouched**. Post-edit the file has 7 `dmf-passkey-login`
references (6 flipped + console) and 0 `default-authentication-flow`
references.

### Lever 2 — `roles/stack/operator/authentik/templates/blueprints/16-passwordless-bootstrap.yaml.j2`

Append a brand entry (co-located with the flow it references, so it can use
`!KeyOf dmf-passkey-login-flow` rather than a cross-blueprint `!Find`):

```yaml
  - model: authentik_brands.brand
    id: default-brand-passkey-first
    state: present
    identifiers:
      domain: authentik-default
    attrs:
      flow_authentication: !KeyOf dmf-passkey-login-flow
```

`state: present` keyed on `domain: authentik-default` **patches only**
`flow_authentication` on the existing default brand; branding title/logo,
recovery/invalidation/user-settings flow slots are left intact. Blueprints are
auto-discovered by fileglob and applied in sorted basename order
(15 → 16 → 20), and the brand entry follows the flow definition within file 16,
so the `!KeyOf` reference always resolves.

The existing `default-authentication-identification` override (blueprint 16,
the `default-authentication-identification-passkey` entry) is **left as-is** —
it is no longer the main login path; it now decorates the break-glass
`default-authentication-flow` page (passkey-first with password fallback).

## Break-glass invariant (must be preserved)

- `default-authentication-flow` stays **defined**; it is simply no longer any
  brand or provider default.
- akadmin / break-glass operator logs in by navigating directly to
  `/if/flow/default-authentication-flow/`, which still presents
  username + password.
- Service accounts (AWX, NetBox, Forgejo, Grafana) authenticate with **API
  tokens**, not browser SSO, so neither lever affects them.

## Cold-bootstrap reasoning

`dmf-passkey-login`'s `not_configured_action: deny` means that, before any
passkey is enrolled, every passkey-gated entry point denies. This does **not**
brick a cold bootstrap:

- First-passkey enrollment runs on the separate
  `dmf-bootstrap-passkey-enrollment` flow (`designation: enrollment`,
  `authentication: require_unauthenticated`), reached via the single-use
  invitation token Ansible mints **after** the blueprint applies. That flow is
  not gated by `dmf-passkey-login`.
- Once the operator has enrolled (ADR-0028 D8 recommends ≥2 passkeys), the
  brand-wide passkey-first path is live for the portal and all apps.

## Verification matrix

Apply on the live env (current env id in `STATUS.md`). If Authentik is already
running, a single `110-authentik.yml` re-apply is enough. If the target VM is
freshly (re)created with no cluster yet — as `y834-bcwe`'s Lima VM is at time of
writing (deleted + recreated empty 2026-05-29) — this is a **full cold
bootstrap**, and the blueprint changes apply as part of that run. Either way the
checks below are what to confirm afterward:

```bash
cd dmf-env
# already-running cluster: targeted re-apply
bin/run-playbook.sh <env-id> ../dmf-infra/k3s-lab-bootstrap/playbooks/vertical-security/110-authentik.yml
# empty VM: full cold bootstrap per the canonical sequence (110 runs within it)
```

| # | Check | Expected | Automatable? |
|---|---|---|---|
| 1 | `110-authentik.yml` re-applies cleanly | blueprints applied, no `!Find`/`!KeyOf` preflight failures | yes |
| 2 | Authentik **portal** (`/if/flow/`-default brand) entry | lands directly on passkey picker, **no** username/email form | **no — human passkey gate** |
| 3 | One app SSO redirect (e.g. Forgejo "Sign in with Authentik") | lands directly on passkey picker, no username form | **no — human passkey gate** |
| 4 | Break-glass `/if/flow/default-authentication-flow/` | still presents username + password | partial (page loads via curl; full login is human) |
| 5 | Console (`oidc-dmf-console`) login | unchanged passkey-first behaviour | **no — human passkey gate** |
| 6 | Default brand object | `flow_authentication` = dmf-passkey-login; branding title/logo unchanged | yes (API/`ak` shell read-back) |
| 7 | Service-account API tokens (AWX/NetBox) | unaffected — automation still runs | yes |

**The human passkey gate (rows 2/3/5) is the one un-automatable step:** WebAuthn
user-verification requires a real authenticator the operator must exercise in a
browser. The orchestrator drives this manually after reviewing the diff.

## Rollback

Reverting is **not symmetric** between the two levers — mind the Authentik
blueprint GC gotcha (blueprints do **not** delete DB objects for entries removed
from the YAML; same class the 2026-05-28 enrollment plan calls out):

- **Lever 1 (providers):** `git checkout` `20-app-providers.yaml.j2` restores
  `authentication_flow: default-authentication-flow`. Those provider entries
  still exist (only the value changed), so a `110-authentik.yml` re-apply
  updates them back cleanly.
- **Lever 2 (brand):** simply *removing* the brand entry and re-applying does
  **not** revert the DB — the default brand keeps
  `flow_authentication: dmf-passkey-login`. To roll back, keep an explicit brand
  entry that sets `flow_authentication` back to `default-authentication-flow`
  (the platform's pre-amendment default), then re-apply — or reset it via the
  `ak` shell / API.

No data migration; the `default-authentication-flow` flow and the break-glass
page were never deleted, so rollback is config-only.
