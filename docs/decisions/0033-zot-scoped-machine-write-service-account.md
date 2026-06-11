# ADR-0033: Zot machine-write operations use a scoped service account, never the admin/break-glass account

**Status:** Accepted
**Date:** 2026-05-27
**Deciders:** @<handle> (raised the question while reviewing the playbook-630 on-node fix: "are we using only the local admin account for Zot? That isn't aligned with C3/C4"), with Claude investigation
**Refines:** [ADR-0028](0028-identity-and-authority-chain.md) C3 (machines use scoped service accounts) + C4 (no routine operation may require a break-glass account). Sibling of [ADR-0032](0032-catalog-launcher-scoped-netbox-writer.md) (same C3 fix for NetBox). Related: [ADR-0024](0024-two-identity-admin-model.md) §3 (sanctioned exceptions), [ADR-0007](0007-secrets-never-in-argv.md).

## Context

ADR-0028 splits identity into four planes: **human authority = Authentik (OIDC/SAML)**, **machine authority = per-app *native* scoped service accounts (stored in OpenBao, *not* projected from Authentik)**, custody = OpenBao, audit = native logs → WORM. C1 names Authentik the sole *human* authority; C3 binds machine work to scoped native service accounts; C4 forbids any *routine* operation from requiring a break-glass account.

Every app has been brought into line with C3 except Zot:

| App | Machine identity (M2M) | Distinct from break-glass? |
|---|---|---|
| NetBox | `dmf-catalog-svc` token (ADR-0032) | yes |
| Forgejo | `forgejo-svc` token | yes |
| AWX | scoped tokens | yes |
| **Zot** | **`admin` (= the break-glass)** | **no** |

Zot's htpasswd file holds a single user, `admin`, which ADR-0024 §3 / ADR-0028 sanction as Zot's **break-glass** identity (htpasswd-only local auth; the username is pinned to `admin` and consumed by every Zot client). But that same `admin` is also the de-facto **machine-write** identity for every authenticated write path:

- **playbook 630** (`630-zot-seed-platform.yml`) — seeds GHCR→Zot at bootstrap *and on every image update* (re-run when a new dmf-cms / awx-ee / nmos tag ships). Routine.
- **zot-mirror** (`roles/base/zot-mirror`) — the steady-state backup cron, reads `secret/apps/zot/admin` and authenticates as `admin`. Routine, scheduled.

So a routine, scheduled operation requires the break-glass account — a direct C4 conflict — and the machine plane reuses break-glass custody instead of a scoped service account — a C3 conflict. The Per-App Identity Feasibility Survey (2026-05-24) scoped Zot's exception narrowly to the break-glass **username** question and never separately evaluated the machine-write path; OIDC would not have closed it either, since Zot's OIDC grant is to the *human* `ops-admin` group and machine push (skopeo) uses basic auth, not a browser flow. Consumer **pulls** are already anonymous (`anonymousPolicy: read`) and are unaffected.

This is the same class of gap ADR-0032 closed for NetBox ("a steady-state automated action using superuser custody to paper over a missing least-privilege identity"), one app over. Blast radius is lower than NetBox's — Zot holds public images mirrored from GHCR, not secrets — but the principle violation is real and was hardening into "how it works."

## Decision

**Zot machine-write operations (image/chart seeding and backup mirroring) authenticate with a dedicated, write-scoped native service account — never the `admin`/break-glass htpasswd user.** Concretely:

1. **New service account `zot-svc`** (per the `<system>-svc` convention), provisioned as a second htpasswd user in the `zot-htpasswd` Secret alongside `admin`. Its password is an independent random secret seeded to OpenBao at `secret/apps/zot/service` and exported as `vault_zot_service_password` — separate custody from the break-glass `admin` password at `secret/apps/zot/admin`.
2. **Scope via Zot `accessControl`:** `zot-svc` gets `["read", "create", "update"]` on `**` repositories — enough to push new manifests/blobs/tags. **No `delete`, no admin policy.** A compromised seeder token can add/overwrite images, not purge the registry or change auth.
3. **Consumers repointed to `zot-svc`:** playbook 630 and zot-mirror use `zot-svc` for every authenticated call. The `admin` credential must not appear in any steady-state playbook, role default, cron, or ESO-mounted secret.
4. **`admin` demoted to dormant break-glass.** It remains the sole `adminPolicy` user (full `read,create,update,delete`) for emergency/manual recovery, satisfying C4: no routine path touches it. ADR-0028's sanctioned-exception list is **unchanged** — Zot `admin` stays as the break-glass username; this ADR only clarifies that the exception covers *break-glass*, not the *machine-write* path, and adds the missing C3 service account.
5. **eso-reader policy** extended to read the new service path (`secret/data/apps/+/service`) so zot-mirror's ESO ClusterSecretStore can mount the `zot-svc` credential. (The existing glob is `secret/data/apps/+/admin`.)

This decision is implemented together with the **playbook-630 execution-model fix** (630 now runs on the control node, `hosts: k3s_control[0]`, not workstation `localhost`) — see the [implementation plan](../plans/DMF%20Zot%20Machine-Identity%20Service%20Account%20Plan%202026-05-27.md). The two are coupled because both edit 630's credential handling.

## Consequences

- **Positive** — Closes the last C3/C4 gap in the app fleet; Zot's machine plane matches NetBox/Forgejo/AWX. Backup cron and image seeds run under a named, scoped, audited identity; break-glass `admin` goes dormant. Compromise of the seeder token cannot delete images or alter Zot auth.
- **Negative** — A second htpasswd user + accessControl policy + a new OpenBao path + ESO policy widening; multi-repo work (dmf-infra zot role, 630, zot-mirror, openbao policy; dmf-env bootstrap-secrets seeding). The zot role's htpasswd task must emit two bcrypt lines instead of one.
- **Neutral** — Pulls are already anonymous; only the authenticated write path changes. `admin` still exists (break-glass), just unused by automation. Existing envs migrate by re-running the zot role + seed-bao (adds the second user/secret; idempotent).

## Alternatives considered

1. **Project the machine identity from Authentik (OIDC/SAML).** Rejected — and it is a category error: ADR-0028 C3 makes machine authority *native per-app service accounts in OpenBao*, explicitly **not** Authentik (which is the *human* authority, C1). OIDC/SAML are interactive browser flows; `skopeo` and cron jobs cannot perform them, and machine work must not depend on the IdP being reachable. Even Zot's OIDC grant targets the human `ops-admin` group.
2. **Keep using `admin` (just document it).** Rejected — that is the status quo C3/C4 violation; documenting a routine path onto the break-glass account does not make it compliant.
3. **Give `zot-svc` full `delete`/admin too (simpler policy).** Rejected — least privilege: a seeder/mirror never deletes. `read,create,update` is the minimal write scope.
4. **Store the `zot-svc` secret under `secret/apps/zot/admin` to dodge the ESO policy change.** Rejected — collapses the two identities back into one custody path and defeats the separation. A distinct path + a one-line policy widening is the clean form.

## Enforcement

- The zot role owns the `zot-svc` user + its accessControl policy; a `bootstrap-verify`-class assertion confirms `zot-svc` exists, is non-admin (no `delete`, not in `adminPolicy`), and that no steady-state path references the `admin` credential.
- Review gate on 630 + zot-mirror + any future Zot writer: a reference to `secret/apps/zot/admin` / `zot_admin_*` from a steady-state automation path is a violation — flag against this ADR.
- Natural home for the automated check is the audit-admin-identities / bootstrap-convergence verifier (ADR-0028 D2), alongside the ADR-0032 NetBox check.
