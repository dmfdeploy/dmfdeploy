# DMF First Container-Driven VPS Deploy + Passkey UX Handoff

**Date:** 2026-06-07
**Status:** ✅ Full DMF v0.1 stack deployed + verified on real non-Lima infra, driven entirely
through the **dmf-init container**. Operator passkeys enrolled (2/2). Two `dmf-infra` fixes
committed to `main`. One new plan + several productization items opened.
**Build model:** orchestrated — Claude drove + verified; qwen-left lifted the two committed
playbook fixes.
**Plan opened:** `docs/plans/DMF Sandbox Zero-Setup Addressing (sslip.io) Plan 2026-06-07.md`
**Memory:** `project_dmf_init_container_bootstrap_gaps`

## What this was

First real end-to-end DMF bootstrap **through the dmf-init Docker container** (every prior
real run used the Mac+Lima e2e harness, which runs dmf-init as a host process — so the
**container path had never actually run a bootstrap**). Target: a real, **non-Lima** VPS.

- **Node:** generic ARM64 Debian **13 (trixie)** VPS — Alibaba ECS, login user `ecs-user`
  (NOT `ec2-user`), **NAT'd** (public IP for SSH, private `eth0` for k3s). Concrete IP/slug
  live operator-side / in STATUS, referenced here as `<node-public-ip>`.
- **Env:** `tzje-voik` (`tzje-voik.dmf.test`), operator `marty-mcfly`, no label (env-id is the
  subdomain). Profile: `sandbox-single-node` (ADR-0031 O1, local-CA).
- **Result:** node `Ready`, all pods Running across authentik/awx/cert-manager/dmf-cms/
  external-secrets/forgejo/monitoring/netbox/openbao/zot; `bootstrap-sandbox-verify` green
  (console smoke: healthz 200, AWX token authenticates as `dmf-cms-svc`); checkpoint-3 backup
  written to both remotes.

## How it was driven (reproduce / manage)

- `docker build` the dmf-init image; run it with the **6 component repos bind-mounted
  read-only** at `/data/repos/<repo>` (skips `/api/repos/fetch`), `/data` on a docker volume.
  A small in-container Python driver hits `render → backup → bootstrap/start` + streams with
  auto-resume. Container name `dmf-init-marty` (still running on colima as of handoff).
- **Retries reuse the same env** (`resume_env_id`) — rendering a new env each retry causes
  k3s node-name churn that evicts the verify pod. Each driver run needs a fresh single-use
  launch token (container restart).
- The live cluster is reachable from the operator Mac only after opening **443/80 in the
  Alibaba security group** (node nftables is `policy accept`; the cloud SG was the only gate).
  Browser access needs `/etc/hosts` → node IP + the local CA trusted.

## Committed fixes (`dmf-infra` `main`)

| Commit | Fix | Why |
|---|---|---|
| `a8c804e` | netbox: discover drf-spectacular pod with node-side `k8s_info`, not controller `lookup('k8s')` | A `lookup` always runs on the controller regardless of `delegate_to`; it only ever worked because a Mac has an ambient `~/.kube/config`. The headless container has none → hard-fail at arg-resolution (`failed_when` can't catch templating errors). **Only such lookup in the tree** (verified by per-task scan). |
| `2f7741d` | landing-page: `openssl base64 -A -in` instead of macOS `base64 -i` | GNU base64 treats `-i` as `--ignore-garbage` and wraps at 76 cols → k8s rejects the newlines in `binaryData`. |

## Open productization items (workarounds were runtime-only — NOT committed)

The dmf-init **container** needs these to run a bootstrap without manual patching:

- **Dockerfile** is missing: `yq` (kislyuk), `dig` (bind9-dnsutils), `helm`, `htpasswd`
  (apache2-utils), and the controller py-libs `jmespath`/`netaddr`/`passlib`/`jsonpatch`/
  `kubernetes` (install into `/usr/bin/python3` = the 3.13 ansible uses; `--ignore-installed
  PyYAML` first).
- **`200-baseline`** node `pip install kubernetes` is not Debian-13/trixie-safe (apt PyYAML
  6.0.2 has no RECORD and blocks the wheel's `pyyaml>=6.0.3`). Pre-install
  `PyYAML>=6.0.3 --ignore-installed` then kubernetes, or pin a kubernetes version.
- **`unseal-openbao.sh`** unconditionally `require security` (macOS Keychain) — breaks in the
  Linux container even though the sandbox self-unseals (Shamir 1/1). Should not require
  `security` for the sandbox profile (we shimmed a no-op `security` to reach its exit-2).
- GitHub 504s fetching helm charts (ESO) from the China-region node — transient, retry.

## Passkey UX → new plan

Operator passkeys enrolled (2/2, "Apple Passwords"). The real friction was **CA trust**: the
"Registration cancelled/timed out" failures were WebAuthn refusing a **non-secure context**
(untrusted local CA); it worked the instant the CA was trusted (padlock green). Compounded by
a **single-use invite consumed on each failed attempt** → "invalid invite" on every retry,
which masked the cause.

Operator decision (refined): **keep passkeys mandatory** (ADR-0028 D8, all lanes — no
exception) and instead remove the *other* setup wall — **DNS/`/etc/hosts`** — by defaulting the
sandbox base domain to **sslip.io** (`<node-ip>.sslip.io` resolves with zero setup; keeps the
whole host-based architecture; RP ID stays a valid domain so mandatory passkeys still work).
The CA-trust step remains (required for the mandatory passkey on a local-CA env), so the plan
also makes that step loud and fixes the invite-consumed-on-failure bug. An `IP/<app>` path
revert was rejected (huge refactor + WebAuthn RP IDs can't be IPs). DNS-01 with the project
domain `<env>.dmfdeploy.io` (trusted certs, no CA install, LAN-or-cloud) is the separate
maintainer profile; localhost-origin deferred.

> ⚠️ Note left live on `tzje-voik`: the bootstrap-passkey invitation was temporarily made
> multi-use for debugging, then **reverted** (single_use=True + expired). No standing risk.

## Next intent

1. Execute the **Sandbox Zero-Setup Addressing (sslip.io)** plan (qwen lifts, Claude verifies)
   — sslip.io base-domain default + invite-on-failure fix + loud CA-trust UX. Passkeys stay
   mandatory.
2. Productize the dmf-init container gaps (Dockerfile + 200-baseline + unseal-openbao) — this
   is the literal "cold-bootstrap smoke gate" class the v0.1 plan calls for.
3. Optional: tear down `dmf-init-marty` + colima when done driving; the durable artifact is
   the `tzje-voik` cluster itself.
