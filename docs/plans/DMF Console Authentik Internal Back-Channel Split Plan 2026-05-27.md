---
status: executed
date: 2026-05-27
---
# DMF Console Authentik Internal Back-Channel Split Plan (2026-05-27)

**Status:** Approved (operator + codex cross-check), ready to implement
**Repos:** `dmf-cms` (code + chart + release), `dmf-infra` (cms role wiring)
**Closes:** WP1S "remaining gate #2 — CMS server-side Authentik HTTPS trust (runtime OIDC)"
**ADRs applied:** [ADR-0023](../decisions/0023-internal-service-dns-for-cross-app-wiring.md) (cluster-internal svc DNS for cross-app wiring), [ADR-0030](../decisions/0030-console-i18n-and-airgap-posture.md) (air-gap, zero external runtime calls), [ADR-0015](../decisions/0015-dmf-console-passkey-only.md) (passkey-only OIDC).

## Problem

On `wobe-9n0c` (local-CA TLS lane, base domain `boxsand.dmf.test`):

- New `dmf-cms` pod is **CrashLoopBackOff**. Startup lifespan `_bootstrap_console_groups`
  (`main.py:123`) calls the Authentik management API over `https://auth.boxsand.dmf.test`;
  the pod does not trust the in-cluster local CA → `ssl CERTIFICATE_VERIFY_FAILED` →
  `Application startup failed. Exiting.`
- **Login → 500.** `/auth/login` calls `discovery_document()` (`security.py:127`), a
  server-side OIDC discovery fetch to the same public HTTPS host before any browser
  redirect → same cert failure → unhandled → 500.

Root cause: **dmf-cms makes server-side (pod-to-pod) HTTPS calls to Authentik over the
public ingress host.** AWX, NetBox, and Forgejo are already wired to cluster-internal
service DNS over plain HTTP (`http://<svc>.<ns>.svc.cluster.local`) per ADR-0023.
**Authentik is the only back-channel still on the public TLS host** — that is the bug.

## Decision

Do **not** mount the local CA into the pod (tactical debt; keeps pod-to-pod traffic on
the public route; depends on ingress TLS being warm for server-side calls; spreads CA
plumbing into every pod). Instead, bring Authentik into ADR-0023 compliance like the
other three clients, with an explicit **front-channel / back-channel split**:

- **Front-channel (browser, off-cluster):** OIDC `authorize` redirect, the OIDC callback
  `redirect_uri`, and the passkey **enrollment URL** stay on the **public** host
  `https://auth.boxsand.dmf.test`. The browser cannot resolve `*.svc.cluster.local`, and
  ADR-0023 explicitly reserves public TLS URLs for user-facing flows. The public issuer
  stays the **canonical identity issuer**.
- **Back-channel (pod, in-cluster):** Authentik management API + OIDC discovery / token /
  userinfo / jwks move to `http://authentik-server.authentik.svc.cluster.local` (port 80,
  plain HTTP, internal). Proven live: internal discovery returns HTTP 200.

This removes all server-side TLS from dmf-cms in every environment (sandbox, cloud, fully
air-gapped). The only remaining cert is the user-facing ingress, whose trust is a
browser/operator concern (install the in-cluster local CA root once, or a real cert where
a public domain exists) — never a pod runtime dependency. Satisfies ADR-0030's
"zero external runtime calls / works unplugged".

### Why the runtime split is safe (codex cross-check, 2026-05-27)

`dmf-cms` authenticates by **successful code exchange + userinfo claims**; it does **not**
validate or use the `id_token`, and the stored nonce (`main.py:164`) is not validated.
So the fact that Authentik derives `iss` and all endpoints from the request Host (internal
back-channel → internal `iss`) is **not a runtime blocker**. Guardrails from the review:

- `redirect_uri` MUST remain the **public** callback in both the authorize and token
  requests (Authentik enforces exact-match).
- **PKCE stays enabled** — Authentik provider has `pkce_required: true`. Non-negotiable.
- Keep the **public issuer canonical** in config/naming; the internal URL is explicitly a
  transport, never the semantic issuer (protects a future move to real ID-token validation).
- Logout is local session-clear + redirect today (no RP-initiated OIDC logout); if that
  changes, the end-session URL is front-channel and must stay public.

## Implementation

### A. `dmf-cms` code

**`settings.py`**
- `OIDCSettings`: add `backchannel_issuer_url: str = ""`
  (env `DMF_CONSOLE_OIDC_BACKCHANNEL_ISSUER_URL`). `issuer_url` stays the public canonical
  issuer. `configured` unchanged (still keyed on the public `issuer_url`).
- `AuthentikSettings`: add `public_base_url: str = ""`
  (env `DMF_CONSOLE_AUTHENTIK_PUBLIC_BASE_URL`), used only to build user-facing enrollment
  URLs. `api_url` stays the API-call base (now internal).

**`security.py`**
- Add a `_backchannel_base(settings)` helper → `backchannel_issuer_url or issuer_url`.
- `discovery_document`: fetch `.well-known` from the back-channel base (internal when set).
- `build_authorize_url`: build the browser authorize URL from the **public** `issuer_url`
  origin, not from `discovery["authorization_endpoint"]` (which is internal under the
  split). Take the discovery authorize **path**, swap scheme+host to the public origin.
- `exchange_code_for_token` / `fetch_userinfo`: use `discovery["token_endpoint"]` /
  `["userinfo_endpoint"]` (internal under the split). `redirect_uri` is passed in from
  `main.py` via `request.url_for("oidc_callback")` (public) — unchanged. PKCE verifier
  forwarding unchanged.

**`authentik.py`**
- `create_invitation`: build `enrollment_url` from `public_base_url` (fallback to `api_url`
  if unset, preserving local/dev behaviour), not from the internal `api_url`.

**(Hardening, optional in this PR)** make `_bootstrap_console_groups` non-fatal: log and
continue if Authentik is transiently unreachable, so a back-channel hiccup degrades group
seeding rather than crashlooping the whole console. Flag for review; keep minimal.

**`tests/test_main.py`** — prove:
1. authorize redirect origin == public issuer origin;
2. callback `redirect_uri` is the public callback in both authorize and token requests;
3. token + userinfo calls hit the internal back-channel origin;
4. PKCE `code_verifier` is forwarded to the token request;
5. `enrollment_url` uses the public base.

### B. `dmf-cms` chart (`charts/dmf-cms`)
- `templates/deployment.yaml`: add env `DMF_CONSOLE_OIDC_BACKCHANNEL_ISSUER_URL`
  (from `.Values.oidc.backchannelIssuerUrl`, emit only if set) and
  `DMF_CONSOLE_AUTHENTIK_PUBLIC_BASE_URL` (from `.Values.authentik.publicBaseUrl`, if set).
- `values.yaml`: document both new keys (default empty).

### C. `dmf-infra` cms role (`roles/stack/operator/cms`)
- `templates/values.yml.j2`:
  - `authentik.apiUrl` → `http://authentik-server.{{ authentik_namespace | default('authentik') }}.svc.cluster.local`
  - new `authentik.publicBaseUrl` → `https://{{ authentik_host }}`
  - new `oidc.backchannelIssuerUrl` →
    `http://authentik-server.{{ authentik_namespace | default('authentik') }}.svc.cluster.local/application/o/{{ cms_oidc_application_slug }}`
  - `oidc.issuerUrl` (public canonical) unchanged.
- Internal back-channel is the **default in all envs** (uniform with awx/netbox/forgejo);
  public issuer stays for the browser. Lab/cloud get the same alignment.

### D. Release (per `dmf-cms-build-and-release` skill)
- Bump `dmf-cms/VERSION` `0.9.0 → 0.9.1`; `scripts/sync-version.sh`.
- Build → publish to GHCR (`publish-to-ghcr.sh`) → mirror into cluster Zot (playbook 630)
  → deploy (playbook 650). Operator-gated steps (GHCR creds, cluster secrets) flagged.

### E. Verify on `wobe-9n0c`
- New pod reaches Running (no crashloop) — group bootstrap succeeds over internal API.
- Login end-to-end: browser hits **public** authorize; pod does token + userinfo over
  **internal** plain HTTP; session built from userinfo; lands authenticated.
- Mint a passkey invitation → `enrollment_url` is the **public** host.
- Pod makes **zero** HTTPS calls to `auth.boxsand.dmf.test` (confirm via logs / no cert
  errors).

## Sequencing
1. dmf-cms code + chart + tests (one PR) → codex review of the diff.
2. dmf-infra cms role wiring (one PR).
3. Release 0.9.1 + deploy.
4. Live verification on `wobe-9n0c`.

## Out of scope / follow-ups
- Real ID-token validation (signature + canonical public `iss` + nonce) — the back-channel
  setting is named so this can land later without a config change.
- AWX/NetBox vestigial `sslVerify` knobs (clients are already plain-HTTP internal) — tidy
  separately.
