---
status: active
date: 2026-10-27
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/15
---

# Forgejo Authentik contributor policy plan

## Decision

Approved Authentik users may automatically receive a Forgejo account so their
issues, plans, commits, reviews, and approvals retain one attributable human
identity. This is not open registration: an Authentik application binding
allows only `forgejo-contributor` or `ops-admin` members to reach Forgejo.
The `ops-admin` group remains the sole source of Forgejo administrator status.

The account identifier is the OIDC `sub`, emitted by Authentik as `user_uuid`.
It is stable across display-name changes. Forgejo may refresh display fields,
but it must not merge accounts by a matching email address. Local registration
and generic OpenID sign-up are disabled; OAuth auto-registration remains only
for the approved Authentik application path.

Membership in `forgejo-contributor` establishes eligibility to log in and
receive a normal Forgejo account. It does not grant instance administration,
organisation ownership, or repository write access. Maintainers grant those
rights through Forgejo organisations, teams, and protected-branch review rules,
where the resulting collaboration trail is recorded.

## Scope and constraints

- Implements #15 and the Phase-1 work order's closure of unapproved Forgejo
  account creation. Authentik OAuth auto-provisioning remains enabled only for
  users bound to the Forgejo application through `forgejo-contributor` or
  `ops-admin`.
- Follows ADR-0028: Authentik remains the human identity authority;
  break-glass accounts stay dormant; routine work is individually attributable.
- No shared accounts, identity aliases, or email-based automatic linking.
- No live inspection, migration, or access change is part of this plan. Existing
  accounts are audited before a rollout and any collision is handled as an
  explicit migration, never by automatic merging.

## Implementation

1. In `dmf-infra`, declare the non-administrative `forgejo-contributor`
   Authentik group and bind both it and `ops-admin` to the Forgejo application.
   Verify the application has bindings: unbound Authentik applications allow all
   authenticated users.
2. Preserve the current `user_username` subject and add a fail-closed guard that
   rejects `user_uuid`. The component change does not mutate Forgejo identity
   rows or claim migration completion. Before enabling `user_uuid`, document
   and test a supported, backed-up migration for every Forgejo identity field
   used by the deployed version, then inventory existing identities and stop
   on any missing or ambiguous mapping. Do not recover by matching email or
   creating a second account. Retain Forgejo's `USERNAME: userid` setting and
   disable automatic account linking.
3. Disable Forgejo local registration and generic OpenID signup while retaining
   OAuth auto-registration for the Authentik source. Add a render/static test
   showing only the Authentik source can create an approved user's account.
4. Extend `audit-admin-identities.yml` or its companion verifier to report
   unexpected Forgejo administrators and local users separately, without
   emitting personal details or credentials. Add a no-live test fixture for
   permitted `forgejo-break-glass`, Authentik `ops-admin`, service identities,
   and normal contributors.
5. Add an operator runbook describing the evidence chain: Authentik subject and
   group decision; Forgejo account and repository events; pull-request review
   and protected-branch history. It must state that a team/repository grant is
   a separate, auditable action after account provisioning.

## Acceptance evidence

- Rendered Authentik blueprint includes both explicit Forgejo application group
  bindings and no unbounded access path.
- Rendered Forgejo configuration disables local/generic signup, auto-registers
  only through the named Authentik source, uses UUID-backed `sub`, and does not
  use automatic account linking.
- A regression test proves that the deployed blueprint keeps
  `user_username`; a separate guard test proves that `user_uuid` is rejected
  until a supported migration exists. The component change does not claim that
  live identities have already been migrated.
- Tests cover allowed contributor, allowed administrator, and denied ordinary
  Authentik user paths without using a live identity or cluster.
- The cross-app audit reports no bootstrap administrator as a routine Forgejo
  identity and documents any pre-existing user collision before rollout.
- Deployment evidence records the configuration revision and an approved
  contributor's Forgejo account creation without exposing tokens or personal
  data.

## Rollout and recovery

Apply through the sanctioned `dmf-env` playbook path. Before the policy is
enforced, take a read-only inventory of existing Forgejo accounts and their
external identity bindings. If an existing account has a collision, stop its
automatic login and perform a reviewed account-link migration; do not enable
email-based linking to make the error disappear. A rejected user remains unable
to log in; removing their Authentik group ends future Forgejo access, while
repository history remains attributable to the account that created it.
