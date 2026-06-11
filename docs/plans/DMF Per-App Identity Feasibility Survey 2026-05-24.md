---
status: executed
date: 2026-05-24
---
# DMF Per-App Identity Feasibility Survey

**Date:** 2026-05-24
**Owner:** claude-top (per agent-bridge delegation from claude-bottom, 2026-05-24)
**Status:** Complete — ready to fold into [DMF Identity and Authority Model](../architecture/DMF%20Identity%20and%20Authority%20Model.md) §7 and to seed ADR-0028.
**Live env probed:** `g2r6-foa9` (Hetzner CAX21 ARM64, nbg1), read-only.
**Pairs with:** [ADR-0024 — Two-Identity Admin Model](../decisions/0024-two-identity-admin-model.md);
[2026-05-23 App-Admin Drift Realignment Handoff](../handoffs/DMF%20App-Admin%20Drift%20Realignment%20Handoff%202026-05-23.md);
`dmf-infra/k3s-lab-bootstrap/playbooks/audit-admin-identities.yml`.

This survey is the promotion gate for §5 D3 of the architecture model
("per-app local-account rule binding pending feasibility survey"). For
each of seven apps in scope, the survey reports whether the slogan's
break-glass-only-local-account rule is feasible, whether
Authentik-mediated OIDC projection is feasible, how the app's
OIDC/social-auth pipeline behaves with respect to shadow accounts, and
whether the app warrants a sanctioned exception in ADR-0028.

LibreNMS is intentionally deferred (not deployed on lab clusters yet);
the survey is revisited at LibreNMS landing.

---

## 1. Bottom-line matrix

| App | break-glass feasible | OIDC projection feasible | shadow account | sanctioned exception |
|---|---|---|---|---|
| Authentik | yes | n/a (Authentik *is* the IdP) | not-observed | **yes** — `akadmin` bootstrap convention (pre-cleared, confirmed) |
| AWX | yes (precondition: rename local username to avoid OIDC-username collision) | yes (SAML, working) | **sanction** — `<operator>22daa48fb6594ba3` shadow superuser observed; classify as expected social_django behaviour and document; suppression requires SAML pipeline customisation deferred to a later milestone | none required (shadow is a consequence of the precondition above; once break-glass username is collision-free the shadow stops appearing) |
| NetBox | yes | yes (OIDC, working) | not-observed (pipeline uses `associate_by_email` + `SOCIAL_AUTH_OIDC_USERNAME_KEY: preferred_username`, so no shadow) | none required |
| Forgejo | yes | yes (OIDC, working) | not-observed (chart config sets `account_linking: auto` + `username_source: userid`, so no shadow) | none required |
| Zot | yes (must keep `admin` username — htpasswd-only local auth) | partial — Authentik OIDC client provisioned by blueprint; activation handled by `vertical-security/191-zot-oidc.yml` (off by default) | not-observed | **yes** — htpasswd format constraint pins username to `admin` (pre-cleared, confirmed) |
| Grafana | yes | yes (OIDC `generic_oauth`, working; `disable_login_form: true` + `auto_login: true`) | not-observed (Grafana links OIDC identities to existing users by `auth_id`; new OIDC sign-ups get usernames distinct from the chart-default local `admin`) | **yes** — `admin` chart default (pre-cleared, confirmed) |
| dmf-cms | n/a (no local user DB by design) | yes (OIDC-only, working — passkey flow per ADR-0015) | n/a | none required |

**Exception list for ADR-0028:** Authentik (`akadmin`), Zot (`admin`),
Grafana (`admin`). Three apps, all three already pre-cleared in
ADR-0024 §3, confirmed unchanged here.

**AWX shadow superuser is NOT a sanctioned exception in the ADR-0028
sense.** It is a *current-state observation* of OIDC social-auth
deduplication behaviour given a username collision between the local
bootstrap admin (`<operator>`) and the same operator's
SAML-projected identity (also `<operator>`). The architectural fix —
renaming the AWX local admin to a non-colliding break-glass identity
(e.g. `awx-break-glass`) — is captured in §3.2 as a follow-on
implementation item, not as an ADR-0028 carve-out.

---

## 2. Methodology

Per app:

1. **Code review** — grepped the app's role
   (`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/<app>/`) for local
   user creation paths (`User.objects.create`, `gitea admin user`,
   htpasswd templates, chart `adminUser` value), for OIDC/social-auth
   pipeline configuration, and for any operator-side defaults that
   would create local users at install time.
2. **Authentik blueprint cross-check** — confirmed each app has an
   OIDC/SAML provider + application object in
   `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/templates/blueprints/20-app-providers.yaml.j2`
   with `ops-admin` projection (where applicable).
3. **Live read-only probe against `g2r6-foa9`** — listed full user table
   (not just admin assertion) for each app via `kubectl exec` from the
   control node. Read-only commands only; no secrets emitted to argv,
   per ADR-0007. Patterns mirror
   `dmf-infra/k3s-lab-bootstrap/playbooks/audit-admin-identities.yml`,
   extended to enumerate full user tables (not just superusers).
4. **ADR-0024 cross-check** — re-confirmed the three pre-cleared
   exceptions (Authentik `akadmin`, Zot `admin`, Grafana `admin`).

The survey is a docs-only artefact. No code changes in `dmf-infra`. No
write paths exercised against the cluster.

### 2.1 Secrets discipline incident (in-band)

During the live probe of `dmf-cms`, an `env | grep` pass on the
running pod surfaced `DMF_CONSOLE_OIDC_CLIENT_SECRET` into the agent
transcript. Per `dmf-cluster-access` §0 + ADR-0007, this session is
treated as compromised for that one secret. **Remediation:** rotate
the `DMF Console` OIDC provider's client_secret in Authentik
(blueprint at
`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/templates/blueprints/20-app-providers.yaml.j2`
lines around the `oidc-dmf-console` entry) and re-run the dmf-cms
deploy playbook to re-inject. No other secrets were touched. This
incident does not affect the survey's correctness — only the
operational cleanup list at the end of this doc.

---

## 3. Per-app deliverables

### 3.1 Authentik

```yaml
app: authentik
break_glass_feasible:        yes
oidc_projection_feasible:    n/a   # Authentik IS the IdP
shadow_account_behaviour:    not-observed
sanctioned_exception_reason: "akadmin is the Authentik install-time
                              bootstrap convention; the operator never
                              logs in as akadmin and instead enrols a
                              passkey under their own username
                              (vault_bootstrap_admin_username =
                              <operator>); break-glass user explicitly
                              provisioned as a separate identity"
evidence:
  - dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/defaults/main.yml:18
      authentik_breakglass_secret_path: secret/apps/authentik/breakglass
  - dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/defaults/main.yml:59
      authentik_bootstrap_admin_username: akadmin
  - dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/templates/blueprints/16-passwordless-bootstrap.yaml.j2:172
      "# exists. Password remains available for break-glass and akadmin only."
  - g2r6-foa9 live user enumeration (read-only, 2026-05-24):
      akadmin (superuser, active), break-glass (superuser, active),
      <operator> (superuser, active, passkey-enrolled),
      ak-outpost-aa1e939a9e0a4195a4173376e352626d (service, active)
```

**Notes.** Authentik occupies a special row in the matrix: it cannot
project itself via OIDC because it IS the IdP. The operator's day-to-
day identity (`<operator>`) is the *local* Authentik account with a
passkey enrolled and group membership in `authentik Admins` and
`ops-admin`. The slogan still holds — humans log in with passkeys —
just without an OIDC indirection.

`akadmin` is a sanctioned exception: it's the Authentik convention,
deliberately preserved per ADR-0024 §3. The operator never logs in as
`akadmin` in normal operation. `break-glass` is a separately
provisioned account per
`authentik_breakglass_secret_path = secret/apps/authentik/breakglass`.

The `ak-outpost-*` user is a service account for an Authentik
*outpost* (proxy/forward-auth/LDAP outpost mechanism). It is
machine-identity-plane material per D5 — non-superuser, expected,
documented.

### 3.2 AWX

```yaml
app: awx
break_glass_feasible:        yes
oidc_projection_feasible:    yes
shadow_account_behaviour:    sanction
sanctioned_exception_reason: "social_django creates a shadow superuser
                              `<operator>22daa48fb6594ba3` because the
                              SAML pipeline's default username-collision
                              behaviour appends a UUID suffix when an
                              existing local user with the same username
                              already exists. The local user is the
                              bootstrap admin <operator>; the SAML
                              identity also serialises to <operator>;
                              social_django's create_user step appends
                              the hex suffix rather than associating.
                              Architectural fix is to rename the local
                              AWX admin to a non-colliding break-glass
                              username (e.g. awx-break-glass); short of
                              that, the shadow is the expected,
                              documented behaviour and must not be
                              treated as drift."
evidence:
  - dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx/defaults/main.yml:40-47
      awx_saml_enabled: true; awx_saml_admin_group: ops-admin
  - dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx/defaults/main.yml:70-75
      awx_saml_user_flags_by_attr.is_superuser_attr =
        "http://schemas.xmlsoap.org/claims/Group"
      is_superuser_value: ["ops-admin"]
  - dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx/templates/awx-instance.yml.j2:64
      AUTHENTICATION_BACKENDS includes social_core.backends.saml.SAMLAuth
  - dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml:647
      is_superuser: false  (awx-svc service account creation; machine-identity plane)
  - dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/templates/blueprints/20-app-providers.yaml.j2
      AWX SAML provider with ops-admin group projected via
      "goauthentik.io/providers/saml/groups" property mapping
  - g2r6-foa9 live user enumeration (read-only, 2026-05-24):
      <operator> (superuser, active, bootstrap-admin),
      <operator>22daa48fb6594ba3 (superuser, active, SAML shadow),
      awx-svc (non-superuser, active, machine-identity),
      dmf-cms-svc (non-superuser, active, machine-identity)
  - Drift Realignment Handoff 2026-05-23 §"AWX shadow superuser"
      — same shadow observed; classification deferred to this survey
```

**Why "sanction" and not "suppress" for now.** Both fixes are
non-trivial:

- *Suppress at SAML config*: customise `SOCIAL_AUTH_PIPELINE` to
  include `associate_by_email` (like NetBox does) or
  `associate_by_uid` before `create_user`. AWX exposes
  `SOCIAL_AUTH_SAML_USER_FLAGS_BY_ATTR` but not a clean knob for
  pipeline replacement; the customisation lands in `extra_settings`
  in the AWX CR template, which is achievable but requires
  AWX-version-compatible pipeline definitions and live testing
  against `g2r6-foa9` — out of scope for a docs-only survey.
- *Rename local admin*: set the role default to `awx-break-glass`, or
  use an inventory override during a migration window, re-run the AWX
  role, and migrate the existing local admin's ownership of jobs/tokens
  to the renamed account. Simple in concept, destructive on an existing
  env. Most cleanly executed at the next greenfield bootstrap rather
  than on `g2r6-foa9`.

The architectural fix landed in `dmf-infra@c426dc0` as the ADR-0028 D3
follow-on. For this survey, AWX is classified `sanction` so that the
historical live state on `g2r6-foa9` is understood as a collision
artefact, not a fourth exception.

**Service accounts are correctly classified.** `awx-svc` and
`dmf-cms-svc` are machine-identity-plane (D5): created by the
`awx-integration` role explicitly with `is_superuser: false`, scoped
to job-launch use, with personal_tokens stored at the canonical
OpenBao path. No reclassification needed.

### 3.3 NetBox

```yaml
app: netbox
break_glass_feasible:        yes
oidc_projection_feasible:    yes
shadow_account_behaviour:    not-observed
sanctioned_exception_reason: none
evidence:
  - dmf-infra/k3s-lab-bootstrap/roles/stack/operator/netbox/defaults/main.yml:5
      netbox_superuser_username: "{{ vault_bootstrap_admin_username | default('dmfadmin') }}"
  - dmf-infra/k3s-lab-bootstrap/roles/stack/operator/netbox/defaults/main.yml:15-21
      netbox_oidc_enabled: true; netbox_oidc_admin_group: ops-admin
  - dmf-infra/k3s-lab-bootstrap/roles/stack/operator/netbox/templates/values.yml.j2:27-37
      SOCIAL_AUTH_PIPELINE includes social_core.pipeline.social_auth.associate_by_email
      BEFORE social_core.pipeline.user.create_user; OIDC users reuse
      the existing record matched by email rather than creating shadow
  - dmf-infra/k3s-lab-bootstrap/roles/stack/operator/netbox/tasks/main.yml:402
      SOCIAL_AUTH_OIDC_USERNAME_KEY: preferred_username
      (preferred_username = <operator>, matches the local superuser)
  - dmf-infra/k3s-lab-bootstrap/roles/stack/operator/netbox/templates/values.yml.j2:50-58
      netbox.sso_pipeline_roles.set_role projects ops-admin → is_superuser+is_staff
  - g2r6-foa9 live user enumeration (read-only, 2026-05-24):
      <operator> (superuser, active),
      awx-netbox (non-superuser, active, machine-identity),
      dmf-cms-svc (non-superuser, active, machine-identity),
      forgejo-svc (non-superuser, active, machine-identity)
```

**Notes.** NetBox is the model case for D3. The SOCIAL_AUTH_PIPELINE
explicitly includes `associate_by_email` before `create_user`, so
OIDC login deduplicates against the existing local superuser record
(matched by email) rather than creating a shadow. Combined with
`SOCIAL_AUTH_OIDC_USERNAME_KEY: preferred_username`, the OIDC user
maps cleanly to the same row as the local user.

Break-glass promotion path: rename
`netbox_superuser_username` from `vault_bootstrap_admin_username` to a
dedicated `netbox-break-glass` literal in the role default, with the
operator's day-to-day access via OIDC only. Low-risk change.

Service users (`awx-netbox`, `dmf-cms-svc`, `forgejo-svc`) are
intentional machine-identity-plane entries, created by integration
playbooks with scoped permissions.

### 3.4 Forgejo

```yaml
app: forgejo
break_glass_feasible:        yes
oidc_projection_feasible:    yes
shadow_account_behaviour:    not-observed
sanctioned_exception_reason: none
evidence:
  - dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo/defaults/main.yml:38-40
      forgejo_admin_username: "{{ vault_bootstrap_admin_username | default('dmfadmin') }}"
  - dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo/defaults/main.yml:41-53
      forgejo_oauth_enabled: true; forgejo_oauth_admin_group: ops-admin;
      forgejo_oauth_account_linking: auto
      forgejo_oauth_username_source: userid
  - dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo/templates/values.yml.j2:37-39
      gitea admin chart values: username/password/email seeded from the
      role's vault_bootstrap_admin_* chain
  - dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/templates/blueprints/20-app-providers.yaml.j2
      Forgejo OAuth2 provider with DMF groups scope mapping
  - g2r6-foa9 live user enumeration (read-only, 2026-05-24, gitea admin user list):
      <operator> (admin, active),
      forgejo-svc (non-admin, active, machine-identity),
      dmf-cms-svc (non-admin, active, machine-identity)
```

**Notes.** Forgejo's `account_linking: auto` + `username_source: userid`
gives the equivalent of NetBox's `associate_by_email` behaviour: OIDC
identities link to existing local accounts rather than creating
shadows. Live data confirms — exactly one `<operator>` user, admin
flag set.

Break-glass promotion path: rename local admin from
`vault_bootstrap_admin_username` to a dedicated
`forgejo-break-glass` literal. Forgejo's OIDC config then projects
`<operator>` as the ops-admin-group-mapped admin, and the local
identity is dormant.

### 3.5 Zot

```yaml
app: zot
break_glass_feasible:        yes
oidc_projection_feasible:    partial   # blueprint provisions; activation deferred
shadow_account_behaviour:    not-observed
sanctioned_exception_reason: "zot's local auth surface is htpasswd-only;
                              the canonical username is hardcoded `admin`
                              and consumed by every Zot client (cms, awx,
                              etc.) that reads secret/apps/zot/admin from
                              OpenBao. Renaming would require coordinated
                              client-side updates with no operational
                              benefit, so the literal `admin` is retained
                              as the documented break-glass identity."
evidence:
  - dmf-infra/k3s-lab-bootstrap/roles/stack/operator/zot/defaults/main.yml:29-41
      zot_admin_user: admin   (with multi-line comment explaining the
      historical bug where vault_bootstrap_admin_username caused drift)
  - dmf-infra/k3s-lab-bootstrap/roles/stack/operator/zot/defaults/main.yml:43-57
      zot_oidc_enabled: false in the role default; OIDC client wiring
      handled by playbooks/vertical-security/191-zot-oidc.yml
  - dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/templates/blueprints/20-app-providers.yaml.j2:282-318
      Zot OAuth2 provider + application present in the blueprint
  - g2r6-foa9 live htpasswd enumeration (read-only, 2026-05-24):
      admin   (single user in the htpasswd file)
```

**Notes.** Zot's local auth is intentionally minimal — htpasswd file
with a single bootstrap user, anonymous-read enabled. Per the role
default's inline commentary, the literal `admin` is a deliberate
convention chosen to match the OpenBao path
`secret/apps/zot/admin` that downstream clients consume. Renaming
would create coordinated-update toil with no security benefit.

OIDC activation lives in
`playbooks/vertical-security/191-zot-oidc.yml` and is off in the role
default. Whether OIDC is enabled by default in steady state is an
operational call separate from this survey.

### 3.6 Grafana

```yaml
app: grafana
break_glass_feasible:        yes
oidc_projection_feasible:    yes
shadow_account_behaviour:    not-observed
sanctioned_exception_reason: "the grafana helm chart's adminUser
                              parameter defaults to `admin`; the role
                              consumes the chart default (does not
                              override). OIDC `generic_oauth` is the
                              day-to-day path with login form disabled
                              and auto-login enabled; the local `admin`
                              is unreachable via the UI in steady state
                              and reserved as break-glass."
evidence:
  - dmf-infra/k3s-lab-bootstrap/roles/base/grafana/defaults/main.yml:5
      grafana_admin_password: "{{ vault_grafana_admin_password | default(vault_bootstrap_admin_password | mandatory) }}"
      (no grafana_admin_user override — chart default `admin` is used)
  - dmf-infra/k3s-lab-bootstrap/roles/base/grafana/defaults/main.yml:10-19
      grafana_oidc_enabled: true; grafana_oidc_admin_group: ops-admin;
      grafana_oidc_allow_sign_up: true; grafana_oidc_auto_login: true;
      grafana_oidc_disable_login_form: true; grafana_oidc_use_pkce: true
  - dmf-infra/k3s-lab-bootstrap/roles/base/grafana/templates/values.yml.j2:2,7
      adminPassword + envFromSecret pattern for the OIDC env vars
  - dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/templates/blueprints/20-app-providers.yaml.j2
      Grafana OAuth2 provider with DMF groups scope mapping
  - g2r6-foa9 live (read-only, 2026-05-24):
      K8s secret `grafana` admin-user field = `admin`
      (full grafana.db user table not enumerable read-only without a
      sidecar; design-level confidence based on the chart's
      auth.generic_oauth + role_attribute_path behaviour)
```

**Notes.** Grafana's identity model is the closest analogue to the
slogan in its current form. The `admin` local user is the helm chart
default, dormant in steady state (login form disabled, auto-redirect
to OIDC). OIDC users created via Grafana's auto-sign-up land in the
`grafana.db` user table with their OIDC username (`<operator>`,
distinct from `admin`) — no collision, no shadow.

The full `grafana.db` user enumeration was not feasible during this
survey without a sidecar pod (sqlite3 missing from the chart image,
DB file locked by the live grafana process). The design-level read
is sufficient: chart auth.generic_oauth with `role_attribute_path`
mapping ops-admin → `Admin` is the canonical Grafana pattern and is
observed via the `grafana_oidc_admin_group` default. Live UI access
confirms OIDC login works end-to-end (operator has used the console
in this session).

### 3.7 dmf-cms

```yaml
app: dmf-cms
break_glass_feasible:        n/a   # no local user database by design
oidc_projection_feasible:    yes   # OIDC is the only auth path
shadow_account_behaviour:    n/a
sanctioned_exception_reason: "dmf-cms has no local user table. All
                              identity is OIDC + Starlette session.
                              The `/api/admin/users` endpoint proxies
                              to Authentik's API to list users; dmf-cms
                              itself stores only session state.
                              Break-glass for dmf-cms = (a) Authentik's
                              break-glass account + dmf-cms OIDC client
                              still functioning, OR (b) the operator's
                              direct kubectl access + OpenBao retrieval
                              when dmf-cms or OIDC are unavailable."
evidence:
  - dmf-cms/src/dmf_cms/security.py:15-20
      ROLE_ORDER = ("viewer", "operator", "engineer", "admin")
      ROLE_GROUPS = { "admin": {"dmf-console-admin"}, ... }
  - dmf-cms/src/dmf_cms/security.py:25-90
      UserIdentity dataclass; user_from_claims / session_user are the
      only identity surfaces; no SQLAlchemy or persistent user model
  - dmf-cms/src/dmf_cms/main.py:81-118
      "Seed dmf-console-* groups and assign bootstrap user to admin
      (startup only)"  — startup hook that adds the OIDC-bootstrap user
      to the dmf-console-admin group in Authentik (group membership
      lives in Authentik, not dmf-cms)
  - dmf-cms/src/dmf_cms/main.py:477-512
      api_admin_users: lists users by calling list_users() against
      Authentik's API with an Authentik API token
  - dmf-cms/src/dmf_cms/main.py:401-409
      role-gated endpoints check user.role == "admin" (role derived
      from OIDC groups claim via current_role())
  - dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/templates/blueprints/20-app-providers.yaml.j2:240-278
      DMF Console OIDC provider uses dmf-passkey-login auth flow
      (passkey-only per ADR-0015)
  - g2r6-foa9 live (read-only, 2026-05-24):
      dmf-cms namespace runs deployment/dmf-cms (no statefulset, no
      database, no PVC — confirmed by `kubectl get
      deploy,svc,statefulset` returning only the deployment)
```

**Notes.** dmf-cms is the reference case for D4 — the slogan's first
line ("humans log in with passkeys") with no operational compromise.
The console has no local user persistence; the "users" the admin
console can see are an API view onto Authentik's user table.

Break-glass for dmf-cms is not a per-app concern: if dmf-cms is down
or OIDC is broken, the operator falls back to kubectl + OpenBao
retrieval of downstream credentials (the same path used to bootstrap
the platform before dmf-cms shipped). This is consistent with the
custody plane's role in the four-plane diagram (§6 of the architecture
doc): the platform's recovery story rides on the custody plane, not
on app-local back doors.

---

## 4. Exception list for ADR-0028

Three apps require sanctioned exceptions in ADR-0028's binding text.
All three are pre-cleared in ADR-0024 §3 and confirmed unchanged here:

1. **Authentik** — local admin username pinned to `akadmin` (the
   Authentik bootstrap convention). Humans never log in as `akadmin`;
   they enrol a passkey under their `OPERATOR_USERNAME` and log in via
   that. A separately provisioned `break-glass` user covers the
   recovery scenario.
2. **Zot** — local admin username pinned to `admin` (htpasswd format
   constraint + downstream-client convention at
   `secret/apps/zot/admin`). Renaming would require coordinated
   client-side updates with no security benefit.
3. **Grafana** — local admin username pinned to `admin` (helm chart
   default). Login form disabled; OIDC is the day-to-day path. Local
   admin is dormant unless OIDC is broken. Operator decision 2026-05-25:
   keep this as a sanctioned ADR-0028 exception; no Grafana rename.

**No fourth exception is required by this survey.** AWX's shadow
superuser is not an ADR-0028 exception — it is the current-state
artefact of a username collision that the architectural model already
prescribes the fix for (rename the local admin to a non-colliding
break-glass identity). The fix is queued as an implementation item
under D3, not as an ADR carve-out.

---

## 5. Follow-on implementation items (not blocking ADR-0028)

These are concrete changes the survey surfaces that ADR-0028 + its
implementation plan should pick up:

1. **AWX: rename local admin to non-colliding break-glass identity.**
   Implementation: introduce an `awx_admin_user: awx-break-glass`
   override in the env inventory (or in role defaults guarded by an
   ADR-0028 feature flag), execute on next greenfield bootstrap, plan
   a one-time migration for `g2r6-foa9` (ownership reassignment of
   jobs/tokens from current `<operator>` superuser to the new
   break-glass account before re-running the AWX role). Eliminates the
   shadow-superuser class entirely. Owner: ADR-0028 implementation
   session.
2. **NetBox + Forgejo: rename local admin to non-colliding break-glass
   identity (mirror of #1).** Landed in `dmf-infra@3953c62` as
   `netbox-break-glass` and `forgejo-break-glass`. Grafana was
   evaluated during the same sweep and intentionally not renamed:
   ADR-0028's sanctioned Grafana `admin` exception remains because the
   login form is disabled, OIDC auto-login is the routine path, and the
   chart-default local admin is dormant break-glass only.
3. **dmf-cms OIDC client_secret rotation.** Operational cleanup from
   §2.1 of this survey — the secret value entered the agent
   transcript and must be rotated. Path: Authentik blueprint
   `DMF Console` provider → regenerate client_secret → re-run
   dmf-cms deploy playbook to inject the new value via env.
4. **Zot OIDC default-on decision.** Independent of identity rule
   binding; the role default is `zot_oidc_enabled: false` and the
   activation lives in a separate vertical-security playbook. ADR-0028
   should record whether the slogan implies Zot OIDC is on by default
   in steady state.
5. **Audit playbook extension.** The existing
   `audit-admin-identities.yml` checks for *drift* (admin matches
   expected username). Extend it with a *count* mode that enumerates
   full user tables and flags any local users not in
   `{<vault_bootstrap_admin_username>, <documented break-glass>,
   <documented service accounts>}`. Catches shadow accounts proactively.
   This is the natural follow-on to the Drift Realignment Handoff's
   "AWX shadow superuser audit" item #3.
6. **Grafana full-DB enumeration in the audit playbook.** Add a
   read-only sidecar-based grafana.db user enumeration to
   `audit-admin-identities.yml`. Low priority — the design-level
   read is sufficient for the slogan's purposes.

These six items are recommendations, not part of the survey's binding
output. ADR-0028 may bundle them differently or sequence them
explicitly.

---

## 6. Provenance

- **Drafter:** claude-top (this pane), via agent-bridge dispatch from
  claude-bottom (2026-05-24).
- **Architecture doc owner:** claude-bottom — author of
  `docs/architecture/DMF Identity and Authority Model.md`, will fold
  the §1 matrix into §7 of that doc on receipt of the agent-bridge
  notification.
- **Live observation env:** `g2r6-foa9` (read-only kubectl exec via
  SSH to control node `g2r6-foa9-node-03` at the public IP for that
  env's host — concrete value in `dmf-env/inventories/g2r6-foa9/hosts.ini`).
- **Operator concept gate:** the platform operator (single-operator
  scope per architecture model §1).
- **Three-reviewer pattern continuation:** this survey is the
  evidence-gathering input to ADR-0028; ADR-0028 itself remains
  pending claude-bottom + codex review of the resulting binding text.
