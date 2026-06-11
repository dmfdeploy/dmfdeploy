---
status: executed
date: 2026-04-27
---
# DMF AWX Authentik SAML Plan

## Decision

AWX should use Authentik SAML for human SSO/admin access, not Generic OIDC.

AWX 24.6.1 has a Generic OIDC backend, but the official AWX docs state that it
does not support team and organization mapping. That makes it unsuitable for
passwordless admin access, because Authentik can authenticate the user but AWX
cannot turn Authentik group membership into AWX authorization through that OIDC
path.

SAML is the supported path for this use case. AWX SAML supports identity
provider configuration, user flag mapping, organization mapping, and team
mapping. Authentik's own AWX integration guide also uses SAML.

## Target Model

- Authentik remains the human identity provider.
- Authentik group `ops-admin` maps to AWX superuser via
  `SOCIAL_AUTH_SAML_USER_FLAGS_BY_ATTR`.
- AWX local admin remains enabled for break-glass and bootstrap automation.
- The local AWX admin username is `awx-local-admin`, intentionally distinct
  from the Authentik human username `<operator>` to avoid AWX local/SAML username
  collisions.
- AWX integration automation continues to use local admin/service-token API
  authentication, not browser SAML.

## Authentik Provider Shape

- Provider type: SAML
- Application slug: `awx`
- ACS URL: `https://awx.dmf.example.com/sso/complete/saml/`
- Audience: `awx`
- Issuer: `https://awx.dmf.example.com/sso/metadata/saml/`
- SP binding: `post`
- Signing key: `authentik Self-signed Certificate`
- Property mappings: username, uid, email, name, groups

## AWX Settings Shape

- `SOCIAL_AUTH_SAML_SP_ENTITY_ID`: `awx`
- `SOCIAL_AUTH_SAML_ENABLED_IDPS.authentik.url`:
  `https://auth.dmf.example.com/application/saml/awx/sso/binding/redirect/`
- `SOCIAL_AUTH_SAML_ENABLED_IDPS.authentik.entity_id`:
  `https://awx.dmf.example.com/sso/metadata/saml/`
- `SOCIAL_AUTH_SAML_ENABLED_IDPS.authentik.x509cert`: the Authentik signing
  certificate, stripped of PEM headers and newlines
- `SOCIAL_AUTH_SAML_USER_FLAGS_BY_ATTR`: map SAML groups containing
  `ops-admin` to `is_superuser`

## Guardrails

- Do not disable local AWX auth during bootstrap.
- Do not use SAML as the API automation credential.
- Fetch the Authentik signing certificate dynamically after Authentik is
  deployed; do not hardcode a generated certificate into repo defaults.
- Keep the previous AWX OIDC provider out of the linked Authentik application.

## Verification

- Render/syntax-check the Authentik and AWX playbooks.
- After deploy, verify:
  - Authentik application `awx` points at a SAML provider.
  - AWX `print_settings` shows populated SAML IdP config.
  - AWX `/sso/login/saml/?idp=authentik` redirects to Authentik.
  - Authentik login as `<operator>` creates/updates an AWX superuser.
  - AWX API automation still authenticates via local/service credentials.
