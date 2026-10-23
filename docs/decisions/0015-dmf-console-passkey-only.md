# ADR-0015: DMF Console uses passkey-only authentication flow

**Status:** Accepted
**Date:** 2026-05-04
**Deciders:** @<handle>

## Context

DMF Console is the operator-facing control surface for the dmfdeploy platform. The desired login experience is
**passkey-first** (or passkey-only): the user should not type a password, and ideally should not even type a username
if the browser already holds a passkey for the domain. The previous `default-authentication-flow` always renders a
username form first.

## Decision

The DMF Console OIDC provider (`oidc-dmf-console`) uses the dedicated `dmf-passkey-login` flow as its
`authentication_flow`. It does not use the shared `default-authentication-flow`.

**`dmf-passkey-login` flow** (defined in `16-passwordless-bootstrap.yaml.j2`):
1. `AuthenticatorValidateStage` is WebAuthn-only, `not_configured_action: deny`
2. `UserLoginStage` creates the session

This means:
- **Users with a passkey**: single click, browser popup, authenticated
- **Users without a passkey**: denied access (must be enrolled first via the invitation flow at
  `/api/admin/invitations`)
- **Break-glass/admin users** (akadmin, break-glass): use the Authentik admin UI directly or the break-glass flow URL
  described in the 2026-05-29 amendment

Other apps (Forgejo, NetBox, Grafana, LibreNMS, Zot, AWX) kept `default-authentication-flow` when this ADR was first
accepted. The 2026-05-29 amendment moved them to `dmf-passkey-login`.

### Amendment 2026-05-29: brand-wide passkey-first

Problem statement: see the [archive record](../archive/decisions/0015-dmf-console-passkey-only.md).

**Extended posture:** the dmfdeploy platform is **passkey-first across the brand**. The Authentik portal and every
app's SSO redirect land directly on the passkey picker (`dmf-passkey-login`: a WebAuthn-only
`AuthenticatorValidateStage` with `not_configured_action: deny`, then `UserLoginStage`, with no identification stage
and so no username field). Password is retained **only as an explicit break-glass path**. It is never a default.

**Two levers** (both required, because a provider's `authentication_flow` overrides the brand default, so flipping the
brand alone would not move the apps): the 6 non-Console providers in `20-app-providers.yaml.j2` pin
`authentication_flow: dmf-passkey-login`, and `16-passwordless-bootstrap.yaml.j2` patches the built-in default brand
(`domain: authentik-default`) to set `flow_authentication: dmf-passkey-login`.

**Break-glass invariant (must be preserved):** `default-authentication-flow` stays **defined** but is no longer any
brand or provider default. akadmin and the break-glass operator log in via its direct URL
`/if/flow/default-authentication-flow/`, which still presents username+password. The existing
`default-authentication-identification` override (blueprint 16) is left **as-is**.

First-passkey enrollment runs on its own `dmf-bootstrap-passkey-enrollment` flow, which `dmf-passkey-login` does not
gate. Service accounts (AWX/NetBox/Forgejo/Grafana) use API tokens. They do not use browser SSO, so neither lever
touches them. The separate, unimplemented enrollment-flow username prompt item is not affected by this amendment.

Status remains **Accepted**; this amendment widens scope from console-only to brand-wide.

## Consequences

- **No password fallback**: `not_configured_action: deny` means users without a registered passkey cannot log in at
  all. The enrollment path (`/api/admin/invitations` → passkey enrollment flow) must work reliably.
- **Admin break-glass**: `akadmin` and `break-glass` users cannot log in via the DMF Console OIDC flow. This is
  intentional: admin users access the console via the Authentik admin UI or other mechanisms.
- **Password only at the break-glass URL**: since the 2026-05-29 amendment, every app uses `dmf-passkey-login`.
  Username and password remain only at the direct `default-authentication-flow` URL, for akadmin and the break-glass
  operator.

## Enforcement

The Authentik blueprints declare the flow, so a re-run of 110-authentik.yml restores it:
`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/templates/blueprints/16-passwordless-bootstrap.yaml.j2`
and `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/templates/blueprints/20-app-providers.yaml.j2`. No
test or CI check asserts them.

## Status

Accepted

Alternatives, deliberation and implementation detail for this decision are in the [archive
record](../archive/decisions/0015-dmf-console-passkey-only.md).
