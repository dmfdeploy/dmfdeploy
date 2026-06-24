# DMF sslip.io + Container Productization + WP4 e2e Handoff

**Date:** 2026-06-08
**Status:** ✅ **v0.1 cold-bootstrap smoke gate CLOSED.** A fresh from-scratch **sslip.io**
bootstrap (env `pzbi-ed8q`) ran on the productized **`dmf-init:prod`** container with **zero
runtime patching**; mandatory passkeys enrolled **2/2 (two distinct authenticators), D8 green**,
invite lifecycle clean. Two plans fully delivered + an ADR decided.
**Build model:** orchestrated — Claude drove + verified; **qwen-left** lifted all code WPs (incl.
two verification-caught fixes); **codex** reviewed the sslip.io change set.
**Plans delivered:** `docs/plans/DMF Sandbox Zero-Setup Addressing (sslip.io) Plan 2026-06-07.md`,
`docs/plans/DMF dmf-init Container Productization Plan 2026-06-07.md`.
**Decision recorded:** `docs/decisions/0040-public-tls-tiering-and-dmfdeploy-io-psl.md` (Accepted).
**Memory:** `project_dmf_init_container_env_location`, `project_public_tls_tiering_adr0040`,
`feedback_unwedge_qwen_with_ctrl_y`.

## What this was

Closing the last manual walls in the OSS sandbox lane: (1) the **DNS / `/etc/hosts`** wall
(→ sslip.io), (2) the **invite-burned-on-failure** bug, (3) loud **CA-trust UX**, and (4) the
**container productization** gaps that forced ~10 hand-patches on the first `tzje-voik` run — then
proving it all with a real from-scratch bootstrap and live passkey enrollment.

## Shipped (all on `main`, pushed to LAN Forgejo)

| Area | Repo | Commit(s) |
|---|---|---|
| sslip.io default base domain (+ label cosmetic, opt-out contract, conditional copy) | dmf-env | `a6d5433`, `2e47e67`, `5f13bcc` |
| invite reusable within TTL (`single_use=False`) + docs | dmf-infra | `1492abc`, `d6459ba` |
| loud/scoped CA-trust UX | dmf-init | `a74c616` |
| Dockerfile deps (dig/htpasswd/helm 3.18.4 + py-libs→3.13) | dmf-init | `f459884` |
| `200-baseline` trixie-safe pip | dmf-infra | `2f4bd1a` |
| `unseal-openbao.sh` no macOS `security` on sandbox | dmf-env | `079cf52` |
| sslip.io plan amend (label cosmetic) | umbrella | `601c0e8` |
| ADR-0040 (TLS tiering) Proposed→Accepted | umbrella | `5801822`, `9b54cd2` |
| productization plan | umbrella | `7b8a795` |

**Two bugs caught by verification (not by green recaps):** WP1 `pip3` installed into the 3.12
python, not Ansible's 3.13 (fixed → `/usr/bin/python3 -m pip`); WP3 keyed sandbox detection off a
non-existent `posture` field (fixed → `dmf_provider`/`dmf_release_profile`, proven `IS_SANDBOX=1`).

## Verification (live, env `pzbi-ed8q` = `<aliyun-sandbox-node-ip-dashed>.sslip.io`, Alibaba node <aliyun-sandbox-node-ip>)

- **WP4 from-scratch bootstrap PASS** on `dmf-init:prod`, **no runtime patching**; `PLAY RECAP
  failed=0`, 37 pods Running, console healthz 200 (7 apps, OIDC), AWX token authenticates as
  `dmf-cms-svc`, checkpoint-3 backed up.
- **sslip.io chain:** `console.<aliyun-sandbox-node-ip-dashed>.sslip.io/healthz → 200`, `auth.… → 302`, **no
  `/etc/hosts`**. (WP1 sslip.io default also proven in the real container render.)
- **WP1/WP2/WP3 engaged:** zero missing-tool errors; trixie PyYAML pre-task ran; sandbox `unseal`
  step ran without `require security` abort.
- **Passkeys / D8:** 2/2 confirmed, **two distinct aaguids** (Google Password Manager + Apple
  Passwords) → real diversity; full invite lifecycle proven (mint reusable-within-TTL → enroll →
  requirement met → invite auto-deleted, 0 remaining).

## Decision (ADR-0040)

OSS ships **TLS Tiers 1 (own-domain ACME) + 2 (local-CA/sslip.io)** only; the one-time CA-trust
step stays the accepted OSS cost. **`dmfdeploy.io` (Tier 3) deferred to a future managed-service
model**, kept separate to protect domain reputation. Recorded dead-ends (don't re-propose):
sslip.io+LE fails (not on PSL → shared rate-limit); can't self-issue browser-trusted certs from a
wildcard leaf or without an audited sub-CA. Open hardening for the managed phase: attestation-gated
issuance (R1) + hardware-inaccessible keys (R2) — protect reputation, not cross-tenant secrecy.

## Open / next

- **Cleanup (pending operator decision — under discussion):** obsolete interim image
  `dmf-init:wp3`; stopped container `dmf-init-marty` (its `/data` volume holds the old `tzje-voik`
  backups — keep); stale **host** `dmf_init.main` process squatting `:8091` (unrelated montest dev
  server); the live `pzbi-ed8q` cluster on Alibaba (costs — leave up vs teardown).
- **Still tracked:** dmf-init **image publish path** (still local-only, ADR-0036); dmf-promsd
  repo-fetch + image publish (`project_dmf_promsd_bootstrap_integration_gaps`); console latent
  bugs (`project_dmf_cms_changes_page_bugs`, `project_dmf_cms_catalog_double_launch`).
- **Note:** the running env uses container `dmf-init-wp4` (image `dmf-init:prod`); env state +
  backups in docker volume `dmf-init-wp4-data` (`project_dmf_init_container_env_location` covers
  the topology, written for the prior `dmf-init-marty`/`tzje-voik` — same pattern).
