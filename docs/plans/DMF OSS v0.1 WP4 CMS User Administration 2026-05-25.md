---
status: executed
date: 2026-05-25
executed: 2026-06-08
---
# DMF OSS v0.1 WP4 - CMS User Administration

> **⚠️ RE-SCOPED (2026-05-25): scope-trimmed for v0.1.** Under
> [WP0](DMF%20OSS%20v0.1%20WP0%20Release%20Contract%20and%20Profile%20Matrix%202026-05-25.md) /
> [ADR-0031](../decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md):
> - **v0.1 gate = seeded admin can log in via passkey + the backend role guards
>   needed for the deploy path.** That is all v0.1 requires (it gates contributor
>   *replicability*, not a user-admin product).
> - **Full signup / admin-approval queue / role-assignment UI / disable-revoke
>   lifecycle moves to v0.2** — unless a given piece is already near-complete by
>   tag time, in which case it may ride along but still does not gate.
> - **DMF Console stays passkey-only** ([ADR-0015](../decisions/0015-dmf-console-passkey-only.md)).
>   Do **not** weaken this to "TOTP or passkey" for the console. SNS/OTP, where a
>   profile has it, is for out-of-band / break-glass / step-up — never console login.
> - The MFA-enforcement and SNS-OTP sections below are **v0.2 / AWS-lane**
>   material, not v0.1 sandbox gate material.
>
> So the v0.1-binding subset of this doc is: the **role model (§5)** and the
> **backend authorization matrix (Phase 1)** as they guard the deploy path, plus
> **seeded-admin passkey login**. The rest is v0.2.

**Status:** Active — scope-trimmed (v0.1 = seeded-admin passkey + role guards; rest → v0.2)
**Date:** 2026-05-25
**Anchor:** [WP0 Release Contract & Profile Matrix](DMF%20OSS%20v0.1%20WP0%20Release%20Contract%20and%20Profile%20Matrix%202026-05-25.md)
**Parent mission (superseded):** [DMF OSS v0.1 Release Mission 2026-05-25.md](DMF%20OSS%20v0.1%20Release%20Mission%202026-05-25.md)
**Outcome (v0.1 subset):** The CMS lets the **seeded admin log in via passkey**
and enforces **backend role guards** on the deploy path. Full user
onboarding/approval/role-assignment/MFA-enforcement lifecycle is **v0.2**.

---

## 1. Problem

The CMS has Authentik integration and an admin page, but it does not yet
provide a complete user administration workflow for an initial public release.

The missing release behavior is not just UI. The backend needs explicit user
lifecycle mutations and the frontend needs to make authorization state
operable by an admin.

---

## 2. Goals

1. Support user signup or admin-created invite.
2. Support admin approval/denial of pending users.
3. Support admin role assignment.
4. Support user disable/revoke behavior.
5. Require a second factor for admin and privileged operational flows.
6. Use passkeys/TOTP as preferred factors and AWS SNS-backed OTP/SMS/email as
   an optional fallback or step-up path.
7. Enforce an API authorization matrix for admin and operational actions.
8. Make the `/admin` route itself admin-only, not just its API calls.
9. Add focused tests for role derivation, forbidden access, MFA enforcement,
   and user lifecycle.

---

## 3. Non-Goals

- Full enterprise IAM policy editor.
- Multi-tenant organizations.
- Self-service privilege escalation.
- Replacing Authentik as the identity provider.
- SMS-only admin authentication.
- Large redesign of the CMS shell.

---

## 4. Current State

Relevant files:

- `dmf-cms/src/dmf_cms/main.py`
- `dmf-cms/src/dmf_cms/authentik.py`
- `dmf-cms/src/dmf_cms/security.py`
- `dmf-cms/frontend/src/pages/Admin.tsx`
- `dmf-cms/frontend/src/pages/overview/AdminOverview.tsx`
- `dmf-cms/frontend/src/api/hooks.ts`
- `dmf-cms/frontend/src/App.tsx`
- `dmf-cms/frontend/src/components/ProtectedRoute.tsx`
- `dmf-cms/frontend/src/components/Sidebar.tsx`

Already present:

- Authentik OIDC session auth.
- Role mapping for `viewer`, `operator`, `engineer`, and `admin`.
- Startup seeding for the role groups.
- Admin-gated endpoints for listing users/groups/health/jobs.
- React admin page that shows integration health, users, and groups.
- Passkey invitation mechanics for the current user path.

Observed gaps:

- No admin-created invite for a target user.
- No pending signup/approval queue.
- No backend role mutation endpoint.
- Authentik helper has add-group behavior, but no exact role set/remove flow.
- No user disable/deactivate/revoke flow.
- `/admin` is hidden in the sidebar for non-admins, but direct navigation is
  not clearly route-gated before API calls fail.
- Some operational APIs require only an authenticated user, not a role.
- No explicit MFA enforcement matrix exists for admin/operator actions.
- No SNS-backed OTP/SMS/email delivery path is defined.
- Headscale must consume the same Authentik/OIDC authority and should not
  create a parallel user/role model.

---

## 5. Proposed Role Model

Keep the initial role names already present in code:

| Role | Release meaning |
|---|---|
| `viewer` | Read-only access to status, catalog, and non-sensitive dashboards. |
| `operator` | Can launch safe operational workflows and view run state. |
| `engineer` | Can launch higher-risk deploy/teardown/configuration workflows. |
| `admin` | Can manage users, roles, identity integration, and release-critical settings. |

The exact permission matrix should be encoded in tests, not just documented.

---

## 6. MFA / Two-Factor Policy

Preferred factors:

- WebAuthn/passkeys for admin users.
- TOTP as a broadly compatible fallback.

AWS SNS-backed SMS/email OTP:

- Allowed as an out-of-band delivery path for fallback, recovery, or step-up
  checks.
- Not acceptable as the only admin authentication posture unless a future ADR
  explicitly accepts that tradeoff.
- Must be auditable when used for admin approval, role changes, or recovery.

Release rule:

- Admin users must have at least one approved second factor before performing
  user administration.
- Operator/engineer workflow launch may require step-up depending on the final
  endpoint matrix.

---

## 7. Implementation Phases

### Phase 1 - Authorization matrix

- Inventory CMS endpoints and classify each as public, authenticated, operator,
  engineer, or admin.
- Add backend helpers such as `require_role_at_least("operator")`.
- Apply role gates to deploy/teardown/workflow launch endpoints.
- Add frontend route metadata for required roles.
- Define which CMS/Auth groups are allowed to use Headscale and how those
  groups map through OIDC claims.

Acceptance:

- Viewer cannot launch workflows or access admin APIs.
- Non-admin direct navigation to `/admin` is blocked cleanly.

### Phase 2 - Authentik user lifecycle helpers

Add or extend helpers in `authentik.py` for:

- Create user or invite target user.
- List pending/inactive users or invitation state.
- Set exactly one `dmf-console-*` role group.
- Remove user from old role groups.
- Deactivate or disable user.
- Revoke or expire invitation where supported.

Acceptance:

- Backend can express all required lifecycle mutations through Authentik.
- Role assignment is not additive drift across multiple role groups.

### Phase 3 - Backend admin API

Add admin-only endpoints such as:

- `POST /api/admin/users/invite`
- `GET /api/admin/invitations`
- `PATCH /api/admin/users/{username}/role`
- `PATCH /api/admin/users/{username}/status`
- `DELETE /api/admin/invitations/{id}` or equivalent revoke action

Exact paths can follow existing FastAPI naming, but the operations must be
covered.

Acceptance:

- Admin can invite, approve/activate, assign role, disable, and revoke.
- Non-admin requests return 403.

### Phase 4 - MFA enforcement and SNS delivery

- Configure Authentik/CMS MFA policy for admin and privileged roles.
- Decide whether Authentik can publish through SNS directly or whether a small
  CMS/bridge service is needed.
- Add second-factor enrollment status to admin user data.
- Add step-up checks for sensitive admin actions if supported by the session
  model.
- Emit audit records for MFA enrollment, fallback OTP use, and failed attempts.

Acceptance:

- Admin user management requires an approved second factor.
- SNS-backed OTP/SMS/email delivery works if enabled.
- SMS/OTP fallback does not replace passkey/TOTP as the preferred factor.

### Phase 5 - Frontend admin page

Update `/admin` to include:

- Invite user dialog.
- Pending signup/invite queue.
- Active user table.
- Role selector with save state.
- MFA enrollment/status indicator.
- Disable/revoke actions.
- Integration health and error banners.

Design constraints:

- Keep it operational and dense; this is an admin tool, not a landing page.
- Use existing CMS components and query hooks.
- Avoid nested cards or marketing-style panels.

Acceptance:

- Admin can complete the full user lifecycle from the CMS.
- UI handles loading, error, empty, and forbidden states.

### Phase 6 - Tests

Add focused tests for:

- Role extraction from Authentik groups.
- Role ordering and minimum-role checks.
- MFA-required admin actions.
- SNS/OTP delivery adapter behavior where implemented.
- Admin-only endpoints.
- Forbidden non-admin access.
- Role mutation behavior.
- Frontend route/visibility behavior where existing test tooling supports it.

Acceptance:

- CI/local test command proves the user admin release path.

---

## 8. Dependencies

- WP3 ntfy may provide invite notification delivery.
- WP1/WP3 provide AWS SNS topic and delivery configuration.
- WP3 consumes the Authentik/OIDC group model for Headscale.
- WP2 seed flow must ensure Authentik admin/API credentials exist reliably.
- WP5 verifies the final user lifecycle in a release install.

---

## 9. Risks

- Authentik API semantics can make invitation vs signup approval different
  flows. Pick one minimal release flow and document it.
- Role assignment can drift if a user remains in multiple role groups. Enforce
  exact role membership.
- Frontend-only hiding is not authorization. Backend checks are the release
  gate.
- SMS OTP can be phished or SIM-swapped. Keep passkeys/TOTP as the preferred
  admin factors.

---

## 10. Done Definition

WP4 is done when an admin can onboard a user, assign a role, and revoke access
from the CMS, privileged actions require the approved MFA posture, and backend
tests prove role-gated operations cannot be performed by lower-privilege users.
