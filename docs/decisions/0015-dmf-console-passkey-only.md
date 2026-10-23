# ADR-0015: DMF Console uses passkey-only authentication flow

**Status:** Accepted
**Date:** 2026-05-04
**Deciders:** @<handle>

## Context

DMF Console is the operator-facing control surface for the dmfdeploy platform.
The desired login experience is **passkey-first** (or passkey-only): the
user should not type a password, and ideally should not even type a
username if the browser already holds a passkey for the domain.

The previous configuration wired the DMF Console OIDC provider to
`default-authentication-flow`, which includes an identification stage
that always renders a username form. Even after removing `prompt=login`
from the OIDC redirect (an earlier precursor fix in dmf-cms v0.6.1),
the user still saw:

1. Authentik identification page with "Email or Username" field
2. Browser passkey popup appearing below it
3. Manual username entry required before the passkey could be used

This is not smooth — it contradicts the Pocket-ID reference model where
a single "Sign In" button triggers the browser passkey popup directly,
with no username field.

## Decision

The DMF Console OIDC provider (`oidc-dmf-console`) uses the dedicated
`dmf-passkey-login` flow as its `authentication_flow`, not the shared
`default-authentication-flow`.

**`dmf-passkey-login` flow** (defined in `16-passwordless-bootstrap.yaml.j2`):
1. `AuthenticatorValidateStage` — WebAuthn-only, `not_configured_action: deny`
2. `UserLoginStage` — creates the session

This means:
- **Users with a passkey**: single click → browser popup → authenticated
- **Users without a passkey**: denied access (must be enrolled first via
  the invitation flow at `/api/admin/invitations`)
- **Break-glass/admin users** (akadmin, break-glass): use the Authentik
  admin UI directly or the break-glass flow URL described in the 2026-05-29
  amendment

Other apps (Forgejo, NetBox, Grafana, LibreNMS, Zot, AWX) kept
`default-authentication-flow` when this ADR was first accepted. The
2026-05-29 amendment moved them to `dmf-passkey-login`.

### Amendment 2026-05-29: brand-wide passkey-first

Problem statement: see the [archive record](../archive/decisions/0015-dmf-console-passkey-only.md).

**Extended posture:** the dmfdeploy platform is **passkey-first across the brand**.
The Authentik portal and every app's SSO redirect land directly on the passkey
picker (`dmf-passkey-login`: a WebAuthn-only `AuthenticatorValidateStage` with
`not_configured_action: deny`, then `UserLoginStage` — no identification stage,
so no username field). Password is retained **only as an explicit break-glass
path**, never as any default.

**Two levers** (both required — a provider's `authentication_flow` overrides
the brand default, so flipping the brand alone would not move the apps):

1. **Per-provider** — the 6 non-Console providers in
   `20-app-providers.yaml.j2` now pin `authentication_flow: dmf-passkey-login`
   instead of `default-authentication-flow`. The Console provider already used
   `dmf-passkey-login` and is unchanged.
2. **Brand default** — `16-passwordless-bootstrap.yaml.j2` patches the built-in
   default brand (`domain: authentik-default`) to set
   `flow_authentication: dmf-passkey-login`. This covers the portal and any
   future provider that does not pin its own flow. `state: present` with the
   domain identifier patches only `flow_authentication`, leaving branding
   title/logo and other flow slots intact.

**Break-glass invariant (must be preserved):** `default-authentication-flow`
stays **defined** but is no longer any brand or provider default. akadmin and
the break-glass operator log in via its direct URL
`/if/flow/default-authentication-flow/`, which still presents
username+password. The existing `default-authentication-identification`
override (blueprint 16) is left **as-is**; it now serves that break-glass
default-flow page (passkey-first with password fallback) rather than the main
login path.

**Cold-bootstrap reasoning:** `dmf-passkey-login`'s `not_configured_action:
deny` means that, pre-enrollment, every passkey-gated entry point denies. This
does **not** brick a cold bootstrap because first-passkey enrollment runs on
its own `dmf-bootstrap-passkey-enrollment` flow
(`designation: enrollment`, `authentication: require_unauthenticated`), reached
via the invitation token Ansible mints after the blueprint applies — it is not
gated by `dmf-passkey-login`. Service accounts (AWX/NetBox/Forgejo/Grafana) use
API tokens, not browser SSO, so they are untouched by either lever.

Status remains **Accepted**; this amendment widens scope from console-only to
brand-wide. See `docs/archive/plans/DMF Authentik Brand-Wide Passkey-First Login Plan
2026-05-29.md` for the file edits and verification matrix. The separate
`docs/archive/plans/DMF Authentik Bootstrap Enrollment Drop Username Prompt Plan
2026-05-28.md` (enrollment-flow username prompt) is a distinct, unimplemented
item and is **not** affected by this change.

## Consequences

### Positive
- **Smooth UX**: DMF Console login matches the Pocket-ID model: one click,
  browser passkey popup, done. No username field, no password field.
- **Security**: passkey-only removes the password attack surface entirely
  for the operator console.
- **Declarative**: the blueprint is idempotent; re-running 110-authentik.yml
  won't revert the change.

### Negative / Trade-offs
- **No password fallback**: `not_configured_action: deny` means users
  without a registered passkey cannot log in at all. The enrollment path
  (`/api/admin/invitations` → passkey enrollment flow) must work reliably.
- **Admin break-glass**: `akadmin` and `break-glass` users cannot log in
  via the DMF Console OIDC flow. This is intentional: admin users access
  the console via the Authentik admin UI or other mechanisms.
- **Password only at the break-glass URL**: since the 2026-05-29 amendment,
  every app uses `dmf-passkey-login`. Username and password remain only at the
  direct `default-authentication-flow` URL, for akadmin and the break-glass
  operator.

## Status

Accepted

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0015-dmf-console-passkey-only.md).
