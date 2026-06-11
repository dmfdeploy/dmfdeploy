---
status: draft
date: 2026-05-28
---
# DMF Authentik Bootstrap Enrollment — Drop Username Prompt Plan

**Date:** 2026-05-28
**Status:** Plan (not yet implemented)
**Related:** ADR-0015 (passkey-only), ADR-0028 D8 (≥2 passkeys per human)

## Problem

The DMF bootstrap passkey enrollment flow currently asks the operator
to re-type their username/email after they click the single-use
invitation URL. The invitation already carries the user identity in
its `fixed_data` (`username`, `email`, `name`); the prompt is
redundant friction and a minor UX wart at the first impression of the
platform.

Today's flow on `dmf-bootstrap-passkey-enrollment`:

| Order | Stage | Source |
|---|---|---|
| 5 | `authentik_stages_invitation.invitationstage` (`dmf-bootstrap-passkey-invitation`) | blueprint 16 |
| **10** | **`authentik_stages_identification.identificationstage` (`dmf-bootstrap-passkey-identification`)** | **blueprint 16 — the prompt** |
| 20 | `authentik_stages_authenticator_webauthn.authenticatorwebauthnstage` (`dmf-webauthn-stage`) | blueprint 15 |
| 100 | `authentik_stages_user_login.userloginstage` (`dmf-bootstrap-passkey-user-login`) | blueprint 16 |

The identification stage is bound at order=10 with
`user_fields: [username, email]` and `show_matched_user: true`. The
invitation stage at order=5 already populates `flow_plan.context`
with the invitation's `fixed_data`, so the identification stage is
re-asking for what is already known.

## Goal

Clicking the enrollment URL goes **straight to WebAuthn
registration** for the pre-seeded ops user — no identification form.
Subsequent stages (WebAuthn setup, user login) unchanged.

## Approach (option 2 from the 2026-05-28 conversation)

Replace the identification stage with an
`authentik_stages_user_write.userwritestage` configured to **match an
existing user without creating one**. The invitation's `fixed_data`
populates `prompt_data` (`username`/`email`); the user_write stage
uses that to look up the existing User row (created earlier by
blueprint `15-ops-user-webauthn`) and binds it to the flow's
`pending_user`. The downstream WebAuthn enrollment then proceeds
against the bound user with no UI.

Considered and rejected:

- **Drop the identification stage entirely.** Without an explicit
  user-binding stage, the WebAuthn stage has no `pending_user` to
  attach the device to. The invitation stage alone doesn't bind a
  user — it only validates the token and dumps `fixed_data` into
  flow context.
- **Replace identification with `user_write` set to `always_create`.**
  Would create a second User row on every enrollment attempt and
  break the assumption that the ops user is pre-seeded by blueprint
  15. Rejected.
- **Leave it; document as known UX.** Pre-existing posture, but the
  first-impression friction is avoidable for free. Rejected.

## Files touched (single file)

`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/templates/blueprints/16-passwordless-bootstrap.yaml.j2`

### Removed entries

- `authentik_stages_identification.identificationstage`
  `dmf-bootstrap-passkey-identification` (current lines 82-93)
- `authentik_flows.flowstagebinding`
  `dmf-bootstrap-passkey-identification-binding` (current lines
  129-141)

### Added entries

```yaml
- model: authentik_stages_user_write.userwritestage
  id: dmf-bootstrap-passkey-user-write
  state: present
  identifiers:
    name: dmf-bootstrap-passkey-user-write
  attrs:
    name: dmf-bootstrap-passkey-user-write
    user_creation_mode: never_create
    # Inactive users are accepted (the ops user is `is_active: true`
    # per blueprint 15, but this guards against future role changes).
    create_users_as_inactive: false

- model: authentik_flows.flowstagebinding
  id: dmf-bootstrap-passkey-user-write-binding
  state: present
  identifiers:
    target: !Find [authentik_flows.flow, [slug, {{ authentik_bootstrap_passkey_enrollment_flow_slug }}]]
    stage: !KeyOf dmf-bootstrap-passkey-user-write
    order: 10
  attrs:
    target: !Find [authentik_flows.flow, [slug, {{ authentik_bootstrap_passkey_enrollment_flow_slug }}]]
    stage: !KeyOf dmf-bootstrap-passkey-user-write
    order: 10
    evaluate_on_plan: false
    re_evaluate_policies: true
```

### One-time cleanup of stale entries

Authentik blueprints do **not** garbage-collect entries removed from
a YAML file — the previously-applied
`dmf-bootstrap-passkey-identification` stage + binding will linger
in the DB after we redeploy the blueprint with the entries removed.
Two options:

1. **Declarative cleanup in the same blueprint** (recommended):
   ```yaml
   - model: authentik_flows.flowstagebinding
     id: legacy-dmf-bootstrap-passkey-identification-binding
     state: absent
     identifiers:
       target: !Find [authentik_flows.flow, [slug, {{ authentik_bootstrap_passkey_enrollment_flow_slug }}]]
       order: 10
       stage: !Find [authentik_stages_identification.identificationstage, [name, dmf-bootstrap-passkey-identification]]

   - model: authentik_stages_identification.identificationstage
     id: legacy-dmf-bootstrap-passkey-identification
     state: absent
     identifiers:
       name: dmf-bootstrap-passkey-identification
   ```
   These can be deleted from the blueprint after one successful
   round-trip on every live env (`g2r6-foa9`, current sandbox env).
   Worth committing them in their own paragraph block so the cleanup
   intent is visible.

2. **One-shot ansible task**. Adds drift from the declarative model
   for one cleanup; rejected unless option 1 hits an edge case.

## Verification

On a fresh sandbox (post-implementation):

1. `bin/run-playbook.sh <env> .../playbooks/vertical-security/110-authentik.yml`
   — re-applies blueprint 16, removes legacy stage + binding, adds
   user_write stage + binding, mints fresh invitation.
2. `bin/get-passkey-enrollment-url.sh <env>` (now self-healing per
   Plan A v2 just landed) — returns fresh URL.
3. Click URL in incognito browser.
   - **Expected**: lands directly on WebAuthn registration prompt
     for the ops user (e.g. `<operator-user>`); no username/email form.
   - **Negative**: visit
     `https://<authentik-host>/if/flow/dmf-bootstrap-passkey-enrollment/`
     without `itoken=` → invitation stage rejects with "no
     invitation" (invitation stage at order=5 still gates).
4. Complete enrollment; verify confirmed passkey count incremented in
   `bin/get-passkey-enrollment-url.sh <env>` output.
5. Re-run script — script reports passkey requirement met (after the
   second device is enrolled), returns "no new enrollment URL
   needed".
6. Authentik DB sanity:
   ```python
   from authentik.flows.models import Flow, FlowStageBinding
   f = Flow.objects.get(slug="dmf-bootstrap-passkey-enrollment")
   for b in f.stages.through.objects.filter(target=f).order_by("order"):
       print(b.order, b.stage.name)
   ```
   Expected ordering: 5 invitation → 10 user_write → 20 webauthn → 100 user_login.
7. Browser matrix: Safari (Touch ID), Chromium (passkey via Mac
   passwords / browser autofill). Both should show the WebAuthn
   prompt directly without an intermediate identification form.

## Open questions

- **`pretend_user_exists` semantics on user_write.**
  `authentik_stages_user_write.userwritestage` with
  `user_creation_mode: never_create` is documented but rarely
  exercised in our setup. Need to confirm in a live test that when
  the invitation's `fixed_data.email` matches an existing User row,
  the stage silently binds without re-prompting. Authentik's
  invitation stage stores `fixed_data` under
  `prompt_data` — user_write reads from `prompt_data.username` and
  `prompt_data.email` to look up.
- **Blueprint cleanup of legacy entries on environments that won't
  be rebuilt.** Currently:
  - `g2r6-foa9` (cloud) and the current sandbox env both have the
    identification stage applied. Both need the new blueprint
    applied after this lands. The declarative `state: absent`
    cleanup handles both.
  - If the legacy blueprint entries' `id:` was different in earlier
    runs, the cleanup `state: absent` needs to match by identifier
    fields (which is why option 1 above uses
    `identifiers: name: dmf-bootstrap-passkey-identification`).
- **ADR-0028 compatibility.** D8 mandates ≥2 confirmed devices, not
  the identification UX. No conflict. Worth a one-line footnote in
  the implementation PR pointing at this plan so the reasoning is
  reviewable.
- **WebAuthn stage UV requirement.** The webauthn stage has
  `user_verification: required` and `resident_key_requirement:
  required`. Both fine for the new flow; no change needed.
- **No-itoken access path.** Today, visiting the enrollment URL
  without `?itoken=` causes the invitation stage at order=5 to
  reject. That behavior is preserved by this plan (we don't touch
  order=5).

## Sequencing

Land this **after** Plan A v2 has been verified end-to-end (operator
enrolls both passkeys successfully on the current flow), so a single
PR doesn't change two things at once.

The implementation diff is small (1 file, ~30 lines net) but the
verification matrix is non-trivial (browser-side WebAuthn). Plan one
focused session on `zy9q-1015` or a fresh sandbox.

## Commit shape

Single `dmf-infra` commit:

```
feat(authentik): drop username prompt from bootstrap enrollment flow

Replace the identificationstage at order=10 with a user_write stage
configured to match the pre-seeded ops user from the invitation's
fixed_data (never_create mode). Operator clicks the enrollment URL
and lands directly on the WebAuthn registration prompt — no
intermediate username form.

Legacy stage + binding removed declaratively via state: absent
entries (Authentik blueprints don't GC removed entries). The
state: absent block is safe to delete once every live env has
re-applied blueprint 16.

Verified on <env>: …

Refs: docs/plans/DMF Authentik Bootstrap Enrollment Drop Username
Prompt Plan 2026-05-28.md
```
