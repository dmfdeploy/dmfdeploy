# DMF App-Admin Drift Realignment Handoff

**Date:** 2026-05-23
**Origin:** Convergence queue item #1
(`docs/plans/DMF Convergence Next Steps Queue 2026-05-23.md` §#1). The
2026-05-14 audit characterised a 6-flag `-e` override tax on
`bootstrap-configure` runs against `aliyun-123`. This session verified
the tax is **structurally retired** on wizard-fresh greenfields (Branch A
of the plan) and landed a small refactor + a permanent audit playbook.

## TL;DR

- **No drift on `g2r6-foa9`.** Live admin usernames in 5 audited apps
  (AWX / Forgejo / NetBox / Zot / Authentik) all match role defaults.
  LibreNMS intentionally skipped (not deployed on lab clusters).
- The 6-flag tax was an `aliyun-123`-specific artefact, retired with the
  env. On `g2r6-foa9` (and any future wizard-fresh env), `vault_bootstrap_admin_username`
  is seeded by `dmf-env/bin/bootstrap-secrets.sh:926` into the SOPS bundle
  → exported through `run-playbook.sh` → resolved by role defaults
  consistently across roles.
- **New audit playbook** `audit-admin-identities.yml` ships in `dmf-infra` so
  any future env runs the same drift check in 2 minutes (vs waiting for
  a bootstrap-configure failure).
- **698 refactor** consolidates Forgejo admin-username resolution: reads
  from `secret/apps/forgejo/admin → .username` (the canonical
  `common/app-admin-facts` path), with the legacy fallback chain
  preserved. Dead `cms_netbox_admin_user: admin` removed (was unused —
  NetBox token creation bypasses HTTP auth via Django shell).

## What landed

### `dmf-infra@<commit>` — audit playbook + 698 refactor

- **New `playbooks/audit-admin-identities.yml`** — read-only assertion
  playbook. Five per-app blocks (AWX shell_plus query, Forgejo
  `gitea admin user list`, NetBox Django shell, Zot htpasswd cut,
  Authentik group-membership). Each: debug + assert that the role-default
  expected username appears in the live admin list. Tagged
  `vertical-security` + `audit-admin-identities`.
- **`playbooks/698-cms-netbox-forgejo-tokens.yml` refactor:**
  - Removed dead `cms_netbox_admin_user: admin` (line 27) — NetBox token
    creation uses Django shell (no HTTP admin auth), so this var was
    never consumed. Replaced with a comment explaining the bypass.
  - Extended the existing OpenBao read at line ~295 to also parse the
    `.username` field alongside `.password`. New `_cms_forgejo_admin_user`
    fact resolves via: OpenBao → `forgejo_admin_username` →
    `vault_bootstrap_admin_username` → `dmfadmin`.
  - Replaced three `url_username:` references (lines ~402/417/441) with
    `{{ _cms_forgejo_admin_user }}`. The `cms_forgejo_admin_user` var
    is no longer needed as an override surface; `forgejo_admin_username`
    or `vault_bootstrap_admin_username` cover the legacy override paths.

### Verification

- `audit-admin-identities.yml` on `g2r6-foa9`: PLAY RECAP
  `ok=16 changed=0 failed=0`. All 5 apps pass no-drift assertions.
  Audit output captured at
  `/tmp/dmf-playbook-logs/audit-admin-identities-20260523-205633.log`.
- `698-cms-netbox-forgejo-tokens.yml` standalone rerun on `g2r6-foa9`:
  PLAY RECAP `ok=27 changed=0 failed=0 skipped=35`. The refactored
  Forgejo identity-resolution tasks (Read / Parse / Set) executed; the
  consumer tasks (`url_username:` references) were gated on
  `not _cms_forgejo_token_exists` and skipped because tokens already
  exist (idempotent rerun behaviour). The refactor is structurally
  correct; full consumer-path exercise would require a token rotation
  or a fresh env.

## Audit findings — full record

Per-app verdict from `audit-admin-identities.yml` on `g2r6-foa9`:

| App | Expected | Live | Verdict |
|---|---|---|---|
| AWX | `<operator-user>` (role-resolved from `vault_bootstrap_admin_username`) | `<operator-user>` + a shadow `<operator-user>22daa48fb6594ba3` superuser (likely OIDC-created) | no_drift |
| Forgejo | `<operator-user>` | `<operator-user>` | no_drift |
| NetBox | `<operator-user>` | `<operator-user>` | no_drift |
| Zot | `admin` (role hardcodes) | `admin` (htpasswd) | no_drift |
| Authentik | `akadmin` (role hardcodes) | `akadmin` + `break-glass` (both in `authentik Admins` group) | no_drift |

**Notes:**

- **AWX shadow superuser `<operator-user>22daa48fb6594ba3`.** Looks like an
  OIDC-created shadow account created when the operator logged in via
  Authentik. Confirmed superuser. Not a drift, but worth a future audit:
  is this expected behaviour or unintended? If unintended, the AWX OIDC
  social-auth config may be over-privileging. **Followup tracked here,
  not blocking.**
- **Authentik `break-glass`** is the documented break-glass identity
  per `authentik` role docs. Expected.
- **NetBox / AWX shell preamble noise.** The audit playbook captures
  shell_plus / Django shell preamble lines in `stdout_lines` alongside
  the actual usernames. Assertions still pass (`'<operator-user>' in [...]` is
  true regardless of preamble), but the debug output is verbose.
  Followup: filter the preamble in `audit-admin-identities.yml` for
  cleaner reports.

## What this closes

- **STATUS.md "Open run-12+ override list" subsection.** Now retired —
  the override list was an `aliyun-123` artefact. `g2r6-foa9` runs
  greenfield with zero overrides. Any future env created by the wizard
  will inherit the same behaviour: `vault_bootstrap_admin_username`
  seeded from SOPS bundle → consistent across roles.
- **2026-05-14 audit plan** — superseded by this handoff. The plan's
  Path 1/2/3 framework remains valid reference for any future drift
  incident; the immediate workaround inventory is retired.
- **2026-05-23 convergence queue §#1** — collapse to one-line DONE.

## What's still owed (followups, non-blocking)

1. **`awx_control_node_ssh_privkey_path` flag.** Not a credential
   drift; a workstation-path drift. Currently hardcoded to
   `/Volumes/<operator>/secure/awx-control-node.privkey`, conflicting
   with the bundle-dir Option-2 decision (`$HOME/secure/dmf-bootstrap`).
   Three resolution candidates documented in 2026-05-14 plan §5.3.
   **Defer to next session** as a separate small followup.
2. **Audit playbook preamble noise.** `awx-manage shell_plus` and
   `python manage.py shell` print module-import preamble on stdout
   before the username output. The assertions are tolerant
   (`'<operator-user>' in [...]` is true regardless), but debug output is verbose.
   Cheap fix: redirect preamble to `/dev/null` inside the kubectl exec
   command, or use `awk` to take only the last lines.
3. **AWX shadow superuser audit.** Why does `<operator-user>22daa48fb6594ba3`
   exist as a superuser? Likely AWX OIDC social-auth created it when
   the operator first logged in via Authentik. If unintended, AWX OIDC
   config may need narrowing. Read-only investigation only; not a
   security incident given the operator IS authoritative on this
   cluster.
4. **Wire `audit-admin-identities.yml` into `bootstrap-verify.yml`** —
   same shape as the `verify-openbao-identity-model.yml` followup from
   the 2026-05-23 ADR-0021 handoff. Pair them at the next
   bootstrap-verify touch.

## Cross-references

- ADR-0024 — Two-Identity Admin Model (helper role precedent).
- ADR-0007 — Secrets never in argv (pattern followed throughout).
- `docs/plans/DMF App Admin Account Drift Audit and Realignment Plan 2026-05-14.md`
  — original audit + remediation framework, superseded by this handoff
  for the immediate work but kept as Path 1/2/3 reference.
- `docs/plans/DMF Convergence Next Steps Queue 2026-05-23.md` — §#1
  now closed (DONE marker added in this commit).
- `dmf-env/bin/bootstrap-secrets.sh:926` — where
  `vault_bootstrap_admin_username` is seeded from the SOPS bundle.
- `dmf-infra/k3s-lab-bootstrap/roles/common/app-admin-facts/` — the
  canonical OpenBao-backed admin facts pattern that the 698 refactor
  now mirrors inline.
