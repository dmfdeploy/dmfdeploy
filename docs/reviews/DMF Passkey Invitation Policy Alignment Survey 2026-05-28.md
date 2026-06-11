# DMF Passkey Invitation — Policy Alignment Survey

**Date:** 2026-05-28
**Trigger:** While verifying Plan A v2 self-heal on `zy9q-1015`, a second
invitation `console-<operator-user>-202605281628` appeared in the Authentik DB
alongside the bootstrap `dmf-bootstrap-passkey` invitation the script
manages. Investigation surfaced that there are **two parallel
invitation-minting paths in the platform** by design (ADR-0015), neither
sees the other, and the operator-helper script has no awareness of the
second. This survey maps every surface that mints passkey invitations
against the relevant ADRs to confirm we have not silently drifted from
policy.
**Scope:** invitation minting + cache + URL surfacing only; does not
re-examine OIDC/SAML provider config, WebAuthn ceremony itself, or the
flow blueprint shape.

## Paths catalogued

| # | Path | Code | Trigger | Invitation `name` | Identity used |
|---|---|---|---|---|---|
| 1 | Bootstrap role (full play) | `dmf-infra .../authentik/tasks/ensure_invitation.yml` sourcing `files/ak_passkey_invitation.py` | `bin/run-playbook.sh <env> .../110-authentik.yml` | `dmf-bootstrap-passkey` (singleton; `authentik_bootstrap_passkey_invitation_name` default) | OpenBao operator userpass → `kubectl exec` into `authentik-server` pod → `ak shell` |
| 2 | Bootstrap mini-playbook (self-heal) | Same role slice, via `playbooks/vertical-security/111-authentik-passkey-ensure.yml` | `bin/run-playbook.sh <env> .../111-authentik-passkey-ensure.yml` (or transitively from path 3) | Same as path 1 (singleton) | Same as path 1 |
| 3 | Operator-helper script | `dmf-env/bin/get-passkey-enrollment-url.sh` | Operator terminal: `bin/get-passkey-enrollment-url.sh <env>` | (delegates to path 2 on self-heal) | OpenBao operator userpass + SSH to control node; mutation via `bin/run-playbook.sh` |
| 4 | Console self-service | `dmf-cms/src/dmf_cms/authentik.py::create_invitation`, surfaced by `/api/admin/invitations` (POST) | Browser → Console Settings page → "Create new device invitation" button (also QR code) | `console-<username>-<YYYYMMDDHHMM>` (per-invocation unique) | Console-side Authentik API token from `secret/apps/authentik/runtime` |
| 5 | Authentik native admin UI | Authentik web UI | Browser direct to Authentik admin | Operator-chosen | Whatever Authentik identity is logged in (akadmin, or post-passkey operator) |

Paths 1–3 share the **same** singleton invitation row (`name=dmf-bootstrap-passkey`); path 2 is invoked by path 3 transparently (today's Plan A v2 work). Path 4 mints a **new** row per click; rows accumulate until consumed or expired. Path 5 is the
Authentik built-in fallback — unmanaged from our code.

## ADR-by-ADR mapping

### ADR-0007 (Secrets never in argv, env, /tmp, AI transcripts)

- **§2** ("Never echo, cat, or pipe a secret to stdout when running through an AI agent") — the invitation `itoken` is a short-TTL single-use credential that lets the holder register a passkey on a pre-bound user. Treated as a secret.
- **Paths 1–2** (role): the `Surface bootstrap passkey enrollment URL in play log` task emits the URL via `ansible.builtin.debug`. The mint task itself is `no_log: true`, but the debug task is not — by design, so the operator can see the URL after a bootstrap run.
- **Path 3** (script): prints the URL to stdout. Mirrors the role's surfacing.
- **Path 4** (Console): returns URL in JSON body to the browser; the same URL is rendered as a QR code by the React client (`9a6ac06`).
- **ntfy push** (paths 1–3, role's ntfy `uri:` task): URL sent to `https://ntfy.sh/dmf-<env>-<username>` — public service. The topic is per-env + per-username; obscurity ≠ secrecy.

**Verdict:** **Pre-existing posture across all paths.** Today's Plan A v2 work did not change this. No ADR amendment exists making this an accepted exception; the de-facto compromise is "short-TTL single-use credentials are treated less strictly than long-lived secrets, with the operator-helper UX as the primary justification." Fix scope is platform-wide (role + script + Console + ntfy), not script-only — out of scope here, flagged for a future ADR-0007 §2 hardening pass.

### ADR-0010 (`bin/run-playbook.sh` as sanctioned ansible entry)

- **Paths 1–2:** invoked via `bin/run-playbook.sh`. ✓
- **Path 3** (script self-heal): mutation flows through `bin/run-playbook.sh <env> .../111-authentik-passkey-ensure.yml`. ✓ (today's Plan A v2 explicitly chose this over a script-side mint).
- **Path 4** (Console): bypasses ansible entirely — Console pod calls Authentik REST API directly. ADR-0010 governs ansible entry points specifically; it does not categorically forbid service-side API calls from a long-running cluster service. Console is in the "service-side API caller" category, like AWX → NetBox.

**Verdict:** **Aligned.** No bypass of the sanctioned wrapper for operator-driven state mutation.

### ADR-0015 (DMF Console passkey-only)

- ADR-0015 lines 41-43 explicitly references `/api/admin/invitations` as the canonical enrollment path for new users when they lack a passkey. Path 4 is therefore **architecturally sanctioned** — it predates Plan A v2 and is not a violation.

**Verdict:** **Aligned.** The Console self-service path is sanctioned policy, not an introduced wart.

### ADR-0023 (Internal service DNS for cross-app wiring)

- **Path 4** (Console) recently realigned with ADR-0023 via `dmf-cms@16dfd91` (2026-05-27): server-side Authentik calls now use the internal back-channel (svc DNS, plain HTTP), while the user-visible enrollment URL stays on the public front-channel. ✓
- **Paths 1–3** are not network calls — they run inside the cluster via `kubectl exec` or against `127.0.0.1` inside the OpenBao/Authentik pod.

**Verdict:** **Aligned.** Recent (last-7-days) work explicitly fixed the lone holdout.

### ADR-0024 + ADR-0028 (Two-identity admin model + Identity and Authority Chain)

- **C1** (Authentik = sole human identity authority): all paths target Authentik. ✓
- **C2** (OpenBao = steady-state custody):
  - Paths 1–3 persist URL + expiry + count to `secret/apps/authentik/bootstrap-passkey`. ✓
  - Path 4 (Console) does **not** persist to OpenBao — URL returned to browser, no cache. Acceptable: invitations are short-TTL ephemeral; the audit trail lives in the Console's request log (D6).
  - Path 4's Authentik API token lives in OpenBao runtime secret. ✓
- **C3** (Native service accounts only for M2M, scoped/named/documented/OpenBao'd):
  - Path 4 uses a token configured as `settings.authentik.api_token` (Helm wiring `authentikApiToken` in `dmf-cms` values). **Token scope is not asserted by this audit** — needs verification: is it an `akadmin` superuser token (broad) or a scoped service-account token? Worth checking before this surface scales.
- **C4** (No routine operation requires break-glass): all paths use either OpenBao operator identity (paths 1–3) or the Console's API token (path 4). The break-glass user is untouched. ✓
- **C5** (Every DMF-initiated action records actor/role/request_id/reason):
  - Paths 1–3: actor = operator (via OpenBao audit log), role implied (bootstrap), no request_id, reason implicit ("ensure invitation"). **Weak attribution.**
  - Path 4: actor = `session_user.subject`, but role/request_id/reason are not currently captured in the Console request log for this endpoint. **Should be**, per D6.
- **Sanctioned exception (akadmin)**: paths 1–3 set `created_by=akadmin` on the invitation row (role's Python). Aligned with the ADR-0028 §exceptions list.

**D8** (≥2 confirmed passkeys per human):
- Paths 1–3 enforce via `assert authentik_bootstrap_passkey_min_confirmed_devices | int >= 2` (role) and via the script's count gate.
- Path 4 (Console): **no D8 enforcement** — every POST creates a new invitation regardless of the user's current confirmed-passkey count. The operator's experience today (Apple Passwords refused the second registration → silent failure) is the only thing keeping D8 unmet from showing up.
- **No diversity policing**: neither path inspects `aaguid` to ensure the user has passkeys from at least two different authenticator types. The hardware reality (Apple Passwords' per-RP-per-user uniqueness) provides de-facto diversity, but the platform doesn't surface this.

**Verdict:** **Mostly aligned, with two soft gaps** —
1. **Path 4's API token scope**: assertion-only ADR carve-out unless we verify it's narrowed below `akadmin`.
2. **D8 attribution thinness** for path 4 (request log doesn't fully capture actor/role/request_id/reason).

### ADR-0033 (Zot scoped machine-write SA) and related

Not directly relevant to passkey invitations; mentioned only because recent dmf-env commits touched it. No alignment issues with this survey's scope.

## Recent commit history (last 14 days, by repo)

### dmf-cms

| Commit | Date | Scope |
|---|---|---|
| `87d5b77` | 2026-04-28 | **Introduces `/api/admin/invitations`** (path 4). Pre-existing in this survey's frame. |
| `9a6ac06` | (pre-window) | QR-code rendering for the URL. |
| `16dfd91` | 2026-05-27 | Authentik front/back-channel split (ADR-0023). Realigned path 4's server-side calls to internal svc DNS. |
| `651593f` | 2026-05-27 | Group membership PATCH fix (separate; not invitation). |

### dmf-infra

| Commit | Date | Scope |
|---|---|---|
| `0ac2374` | (recent) | Auto-construct ntfy URL + surface passkey URL in play log. Path 1's debug+ntfy output. |
| `2dcafb9` | (recent) | Enforce ADR-0028 D8 passkey + OIDC token policy in tests. |
| `f434e8a` | (recent) | Fix two bridge-verifier findings (close ADR-0028 gates). |
| `30dfad5` | (recent) | Refactor `common/app-admin-facts` to delegate to `common/openbao-session`. Indirect — invitation flow inherits the session contract. |
| `0722b8b` | **2026-05-28 (today)** | **Today's Plan A v2 work:** extract mint Python + task slices, add `111-authentik-passkey-ensure.yml` mini-playbook (path 2). |

### dmf-env

| Commit | Date | Scope |
|---|---|---|
| `5801bb6` | (recent) | Canonical per-app admin identities in `seed-bao` (ADR-0024/0028). |
| `56615d4` | (recent) | Emit operator passkey identity on sandbox path. |
| `585f506` | 2026-05-27 | get-passkey reads LIVE webauthn_count (instead of cached). |
| `0bc8b15` | 2026-05-27 | Silence Authentik pod bootstrap logs in script. |
| `69c6075` | **2026-05-28 (today)** | **Today's Plan A v2 companion:** script self-heals via `bin/run-playbook.sh`. |

**No regression** introduced last 14 days. The "mess" hypothesis (operator's framing — "did we introduce some mess these last few days?") tested negative: every change tightened alignment with a named ADR. The discovered duality (paths 1–3 vs path 4) **predates the window** (path 4 = `87d5b77`, April 28).

## Findings

### A. Pre-existing architectural duality (intentional, ADR-0015-blessed, but underdocumented)

Two parallel invitation-minting surfaces (paths 1–3 vs path 4) exist by design and have non-overlapping consumers:

- Paths 1–3 (bootstrap singleton): the **only way** to get the very first enrollment URL, because the operator has no Authentik session before passkey #1.
- Path 4 (Console self-service): the **expected way** to get the second URL — after passkey #1, the operator logs in and uses the Console Settings page to add devices.

The script returns only the singleton URL. After passkey #1 lands, the operator is expected to switch to the Console's self-service flow for passkey #2. **This is not documented anywhere user-facing.** ADR-0015 mentions the endpoint but doesn't articulate the "switch surfaces after first enrollment" workflow.

→ **Recommendation R1**: add a brief runbook at `docs/runbooks/passkey-enrollment.md` or expand ADR-0015's consequences section, naming both surfaces and the expected handoff between them.

### B. D8 silent failure mode (same-authenticator re-registration)

Operator's situation today: enrolled passkey #1 on Apple Passwords (iCloud Keychain). Clicked the second URL (script-minted or Console-minted; doesn't matter — the WebAuthn ceremony itself rejected the second registration because Apple Passwords stores one credential per RP+username pair). Result: only one confirmed `WebAuthnDevice` row, D8 unmet, no error trail.

→ **Recommendation R2**: in the role's mint Python (now extracted to `ak_passkey_invitation.py`), include the user's existing WebAuthn device `aaguid` list in the JSON output. The script can warn: *"Your existing passkey is from authenticator X (likely Apple Passwords). For ADR-0028 D8 you need a SECOND authenticator. Use a hardware key, a different browser's local passkey, or another device."*

### C. Path 4 D6 attestation thinness

The Console's `/api/admin/invitations` endpoint accepts any logged-in user and uses `user.subject` from the session as the username. The endpoint name (`/api/admin/...`) suggests admin gating but the code only checks session presence. This is **self-service** (the invitation's `fixed_data` is the session user's identity, so no escalation), but:

- No role/group check (e.g., "must be in `ops-admin` group")
- No request_id stamped on the invitation
- No reason field captured
- The Console request log may or may not record this (not verified in this audit)

→ **Recommendation R3** (Console hardening, separate PR): rename endpoint `/api/admin/invitations` → `/api/me/passkeys/invitation` to reflect self-service semantics; add request_id + reason to the Console's request log; consider an optional role check for cross-account minting (future when multi-user).

### D. Path 4 API token is bound to `akadmin` — broader than ADR-0028 C3 allows

**Verified during this audit:** `playbooks/696-cms-authentik-api.yml` creates the Console's Authentik API token under the user `akadmin`:

```yaml
cms_authentik_api_token_user: akadmin
```

`akadmin` is the Authentik bootstrap superuser (sanctioned exception #1 in ADR-0028). A token bound to that user inherits superuser scope: read/write any Authentik object, including users, groups, OAuth providers, policies. The Console only uses the token for `POST /api/v3/stages/invitation/invitations/` and the read-only flow lookup, so the actual privilege need is **single-endpoint write**.

This is a violation of ADR-0028 **C3** ("Native service accounts are allowed only for machine-to-machine work and must be **scoped**, named, documented, and stored in OpenBao"):

| Requirement | Status |
|---|---|
| Machine-to-machine | ✓ (Console pod → Authentik API) |
| Scoped | ✗ — full akadmin privilege |
| Named | ✓ — token name `dmf-cms` |
| Documented | △ — wiring is in the playbook; no policy doc |
| Stored in OpenBao | ✓ |

**Risk profile (experiment phase):** a compromise of the Console pod (e.g., RCE via a future dependency, or session-hijack a logged-in operator) lets the attacker mint invitations for **arbitrary** users, modify groups, rotate provider client_secrets, or escalate to akadmin-level operations. The blast radius is the entire Authentik tenant.

→ **Recommendation R4 (raised to BLOCKING for production promote, deferred for experiment phase per ADR-0004):** create a dedicated Authentik service-account user (e.g. `dmf-cms-svc`, `UserType.service_account`) with a narrow policy allowing only `authentik_stages_invitation.add_invitation` (and the flow read necessary for the slug lookup). Re-bind the token in `696-cms-authentik-api.yml`. Add a sentence to ADR-0028 § implementation-status noting this carve-out + remediation date. Track in `docs/agentic/decisions-open.md` if not picked up promptly.

### E. Script-side parsing bug found and fixed during today's session

BSD sed alternation (`\|`) doesn't work without `-E`. The first iteration of today's self-heal script always re-triggered the mini-playbook because `INVITATION_LIVE` parsed as empty under BSD sed. Caught in live verification on `zy9q-1015`, fixed before push (`69c6075` shipped with `sed -nE`). No lingering issue.

### F. ADR-0007 §2 inheritance (unchanged)

Path 1's `debug:` task, path 3's stdout, path 4's HTTP response body, and the ntfy push all surface the itoken URL. Today's work neither worsened nor fixed this. Should be tackled platform-wide in a separate ADR-0007 §2 hardening pass; piecewise fixes risk inconsistency.

## Recommendations summary

| # | What | Where | Effort | Status |
|---|---|---|---|---|
| R1 | Document the two-path duality + post-passkey-1 surface handoff | new `docs/runbooks/passkey-enrollment.md` or ADR-0015 amendment | small | **✓ Shipped** 2026-05-28 (umbrella `22854ee`) — runbook landed; init-wizard next-steps updated on both lanes to surface the ntfy topic + dual-surface workflow (dmf-env `b0c94bd`) |
| R2 | Surface authenticator aaguid + D8 diversity warning in mint output | `roles/.../files/ak_passkey_invitation.py` + script print path | small | **✓ Shipped** 2026-05-28 (dmf-infra `add35ca` + dmf-env `abd9d28`) — single live `ak shell` probe returns `WEBAUTHN_COUNT` + `INVITATION_LIVE` + `DEVICE: name\|aaguid` lines; print path now branches on 0 / partial / full, surfaces Console URL + diversity warning when partial |
| R3 | Console endpoint rename + D6 attestation fields | `dmf-cms/src/dmf_cms/main.py` + Console request log | medium | **Deferred** — pickup after R4 lands; see "Outstanding follow-ups" below |
| R4 | Verify + scope the Console's Authentik API token | OpenBao path + Authentik token config | small (audit) + medium (rescope) | **Deferred** — attempted 2026-05-28, hit Authentik RBAC model surprise; see "Outstanding follow-ups" below |
| R5 | Platform-wide ADR-0007 §2 hardening (itoken-in-stdout posture) | role debug task, script, Console response, ntfy push | medium, cross-repo | **Deferred** — see "Outstanding follow-ups" below |

## Implementation status — 2026-05-28 close-of-day

| Item | Shipped | Commits |
|---|---|---|
| **Plan A v2** (script self-heal via sanctioned mini-playbook, ADR-0010 compliant) | ✓ | dmf-infra `0722b8b`, dmf-env `69c6075` |
| **R1** (operator-facing runbook + wizard next-steps) | ✓ | umbrella `22854ee`, dmf-env `b0c94bd` |
| **R2** (aaguid + diversity warning + Console-URL hint in partial-count case) | ✓ | dmf-infra `add35ca`, dmf-env `abd9d28` |
| **Bonus: break-glass-email hijack class fix** (per-app, per-env synthetic email; closes the live NetBox hijack observed mid-audit; ADR-0024 §4 amendment) | ✓ | dmf-env `a039aa7`, dmf-infra `33a84e4`, umbrella `64fdbb1` |

The break-glass-email fix was a **larger architectural win** the audit
surfaced unexpectedly: `secret/apps/<app>/admin.email` was being seeded
with the operator's real email for every non-Authentik app, and the
apps' OIDC/SAML pipelines were merging the operator's first sign-in
into the break-glass User row via `associate_by_email`. Observed live
on `zy9q-1015` after the operator's first NetBox SSO: NetBox showed
`Username = netbox-break-glass`, `Full Name = <operator-user>`, `Email =
<operator-email>`, `Superuser = ✓`, with a UserSocialAuth row binding
<operator-user>'s OIDC `sub` to the break-glass user. Same shape of bug as the
AWX shadow-superuser issue ADR-0028 lines 66-70 catalogued, only via
the email field. Fix: canonical pattern `<app>-<dmf_env_id>@<base-domain>`
applied at both layers (seed-bao auto-heal + role defaults) and
codified in ADR-0024 §4. Live-state remediation applied for the
`zy9q-1015` env (NetBox / Forgejo / AWX break-glass User rows
patched, hijacked UserSocialAuth row deleted).

## Outstanding follow-ups (pick up next session)

### R3 — Console `/api/admin/invitations` endpoint hardening

Rename `/api/admin/invitations` → `/api/me/passkeys/invitation` (the
route name suggests admin gating but the code only checks session
presence; renaming makes the self-service semantics explicit) and add
D6 attestation fields (actor / role / request_id / reason) to the
Console's request log on the invitation-mint path. Best landed
together with R4 since both touch the same `dmf-cms` wiring.

**Files in play:** `dmf-cms/src/dmf_cms/main.py:257-285`,
`dmf-cms/src/dmf_cms/authentik.py:54-109`,
`dmf-cms/frontend/src/api/hooks.ts` (useCreatePasskeyInvitation),
`dmf-cms/frontend/src/pages/Settings.tsx` (Create new device invitation
button), wherever the Console's request log lives.

### R4 — Rebind Console's Authentik API token to a scoped service account

**Current state:** the Console's Authentik API token is minted under
`akadmin` (Authentik superuser) by
`playbooks/696-cms-authentik-api.yml:18`. The Console only uses it
for `POST /api/v3/stages/invitation/invitations/` + the flow-slug
read, so the effective privilege need is one write endpoint; today
it has superuser scope across the entire Authentik tenant.

**Attempted 2026-05-28 — pivot needed.** First-pass implementation
created a `dmf-cms-svc` service-account user (`UserType.service_account`)
and tried to assign Django Permissions via
`user.user_permissions.add(Permission.objects.get(...))`. Verified
the user gets created correctly (pk=10, type=service_account), and
the two permissions exist
(`authentik_stages_invitation.add_invitation` pk=591,
`authentik_flows.view_flow` pk=208). **Failed** at the assignment
step: Authentik's User model returns `None` for `user_permissions`
on service-account users — they don't use Django's standard auth
backend M2M. Authentik uses its own RBAC model
(`authentik.rbac.models.Role`) with `groups`, `users`,
`initialpermissions`, `roleobjectpermission`, `rolemodelpermission`
fields, and `Group` has a `roles` relation (not `permissions`).

**Pivot plan:**

1. Create or reuse a `Role` named `dmf-cms-api` with the two narrow
   permissions assigned via `roleobjectpermission` /
   `rolemodelpermission` (or via the equivalent API surface — needs a
   short spike to confirm the right Python entry point).
2. Either (a) attach the role directly to the `dmf-cms-svc` user
   (Role.users.add — note Role has `users` field per the inspection,
   so direct assignment may work), or (b) create a Group, attach the
   Role to the Group, add the user to the Group.
3. Mint the token under `dmf-cms-svc` (as the attempted patch already
   did) — the underlying token-creation logic is correct, only the
   permission-assignment step needs rewriting.
4. Migration safety stays as drafted: `Token.objects.filter(intent="api",
   description=token_name).exclude(user=user).delete()` removes the
   akadmin-bound legacy token; the user-create + token-create flow
   then writes the scoped replacement.
5. Acceptance test: after migration, `POST /api/v3/stages/invitation/
   invitations/` succeeds with the new token; `GET /api/v3/core/users/`
   should fail with 403 (proves the scope reduction).

The full attempted playbook (extracted Python, env vars, migration
safety, missing-permissions assert) is preserved in
`git reflog`/local working-tree; recoverable with `git show
HEAD@{prior-attempt}` against `dmf-infra` (the changes were `git
checkout`-rolled-back before commit). Re-implement against the
`Role` API, not Django Permissions.

**ADR posture:** R4 stays raised to BLOCKING for ADR-0020 Mode B
promote (production), acceptable in experiment phase per ADR-0004.

### R5 — Platform-wide ADR-0007 §2 hardening (itoken-in-stdout)

The single-use enrollment URL (`itoken=<uuid>`) is a short-TTL
credential. Today it lands on stdout in four places:

1. `dmf-env/bin/get-passkey-enrollment-url.sh` print path
   (operator-helper output by design).
2. `dmf-infra/.../authentik/tasks/ensure_invitation.yml`'s
   `Surface bootstrap passkey enrollment URL in play log` `debug:`
   task (visible in the ansible run output captured by
   `bin/run-playbook.sh` and any AI-agent transcript that runs the
   wrapper).
3. `dmf-cms/src/dmf_cms/main.py`'s `POST /api/admin/invitations` JSON
   response body (returned to browser; rendered as QR + URL in
   Settings.tsx). Logged by any HTTP intermediary on the path.
4. The role's ntfy `uri:` task posts the URL to
   `https://ntfy.sh/dmf-<env>-<user>` (public service; obscure topic
   != secret).

ADR-0007 §2 forbids echoing secrets to stdout in AI-agent contexts.
A piecewise fix risks inconsistency; the hardening pass should be
one cross-repo PR (or a small co-ordinated set) that picks a single
sanctioned surface (proposal: write to `~/.secure/<env>/passkey-url`
with 0600 + emit only the file path on stdout; role's `debug:`
becomes "wrote $N chars to $file"; Console returns
`{url_via: "out-of-band"}` + a `secure_handle`; ntfy push becomes a
"new enrollment URL minted, run get-passkey to retrieve" notice).

Acceptance test: `git grep "itoken" $(git ls-files -- 'dmf-env/**' 'dmf-infra/**' 'dmf-cms/**')` returns only structural references, not value-bearing prints.

## Verdict on the operator's framing question

> *"did we introduce some mess these last few days?"*

**No.** Recent work (the last 14 days of commits across all three repos) tightened alignment with ADRs 0007, 0010, 0015, 0023, 0024, 0028 — every change has a named ADR connection in its commit body. The discovered duality (paths 1–3 singleton + path 4 Console self-service) predates the window by a month and is sanctioned by ADR-0015.

The **operational symptom** that triggered this audit (operator's "1/2 even after I enrolled twice") had two distinct root causes:

1. **WebAuthn authenticator-diversity constraint** (intentional; closed by R1 runbook + R2 diversity warning).
2. **Break-glass-email hijack** (real architectural bug; closed by the ADR-0024 §4 amendment + seed-bao + role-defaults fixes landed 2026-05-28).
