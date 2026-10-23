# ADR-0015 archive: DMF Console uses passkey-only authentication flow

This file holds material moved out of [ADR-0015](../../decisions/0015-dmf-console-passkey-only.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

### A1 — Keep `default-authentication-flow` but remove the password stage
Would require modifying the shared flow, affecting all apps. Rejected
because other apps (AWX, NetBox, etc.) need password fallback for
service accounts and non-passkey users.

### A2 — Create a new identification stage with no `user_fields`
Authentik's identification stage requires at least one user_field;
setting it empty causes the stage to error. Rejected — the framework
doesn't support this pattern.

### A3 — Use `default-authentication-flow` with a policy binding
Could add a policy to skip the identification stage for DMF Console
users, but this adds complexity and fragility. The dedicated flow is
cleaner and matches Authentik's intended pattern for passkey-only apps.

## Amendment 2026-06-12 — cosmetic normalization (no decision change)

Converted the YAML frontmatter to the standard `**Status:**` / `**Date:**` /
`**Deciders:**` header, switched the em-dash title to the `ADR-NNNN:` form, and
reworded the self-referential "ADR-0015 precursor". Closes the §5 format nit in
the [2026-05-27 ADR Portfolio Review](../../reviews/dmf-adr-portfolio-review.md).

## Decision — blueprint change diff (moved from the ADR)

The blueprint change is in `20-app-providers.yaml.j2`:
```diff
       authentication_flow: !Find [authentik_flows.flow, [slug, dmf-passkey-login]]
```

## Amendment 2026-05-29 — problem and operator finding (moved from the ADR)

The original decision scoped passkey-only to the DMF Console alone; every
other app (Forgejo, AWX, NetBox, LibreNMS, Grafana, Zot) and the Authentik
portal itself still defaulted to `default-authentication-flow`, which renders
a username form before the WebAuthn popup. The operator found this friction
(username prompt before the passkey picker) unacceptable for the whole brand,
not just the console, and chose to extend the posture **platform-wide**.

## Moved from the ADR on 2026-10-23

### Context (full original text)

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

### Amendment 2026-05-29: two levers (full original text)

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

### Amendment 2026-05-29: break-glass invariant (full original text)

**Break-glass invariant (must be preserved):** `default-authentication-flow`
stays **defined** but is no longer any brand or provider default. akadmin and
the break-glass operator log in via its direct URL
`/if/flow/default-authentication-flow/`, which still presents
username+password. The existing `default-authentication-identification`
override (blueprint 16) is left **as-is**; it now serves that break-glass
default-flow page (passkey-first with password fallback) rather than the main
login path.

### Amendment 2026-05-29: cold bootstrap and scope (full original text)

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

### Positive consequences (original)

### Positive
- **Smooth UX**: DMF Console login matches the Pocket-ID model: one click,
  browser passkey popup, done. No username field, no password field.
- **Security**: passkey-only removes the password attack surface entirely
  for the operator console.
- **Declarative**: the blueprint is idempotent; re-running 110-authentik.yml
  won't revert the change.
