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
the [2026-05-27 ADR Portfolio Review](../../reviews/DMF%20ADR%20Portfolio%20Review%202026-05-27.md).

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
