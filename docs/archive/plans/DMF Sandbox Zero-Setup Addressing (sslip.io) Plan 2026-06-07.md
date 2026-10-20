---
status: executed
date: 2026-06-07
executed: 2026-06-08
---
# DMF Sandbox Zero-Setup Addressing — sslip.io (2026-06-07)

**Status:** Proposed task spec (operator-approved 2026-06-07, sandbox lane only).
**Scope:** `sandbox-single-node` profile **only**, addressing change. **Passkeys stay
mandatory** (ADR-0028 D8 unchanged — no exception, no relaxation, in any lane).
**Origin:** the first container-driven VPS deploy (env `tzje-voik`, 2026-06-07) + the operator
discussion that followed. See handoff `DMF First Container-Driven VPS Deploy + Passkey UX
Handoff 2026-06-07.md`.
**Decision basis:** [[project_phase]] v0.1 = *reproducible by a stranger*. The remaining
setup wall in the sandbox lane is **DNS / `/etc/hosts`** — a tester may not know how (or be
allowed) to add `*.<env>.dmf.test` entries. This plan removes that wall **without** weakening
the security posture.

---

## What this changes (and what it deliberately does NOT)

**Changes:** the sandbox base domain defaults to **sslip.io**, so app hostnames resolve with
zero `/etc/hosts` edits.

**Does NOT change:** passkeys remain **mandatory** (≥2 confirmed, ADR-0028 D8); the local-CA
TLS model stays; OIDC, apps, and host-based routing are untouched. The CA-trust step is still
required (it's the price of the mandatory passkey on a local-CA env) — so this plan also
tightens the **CA-trust UX** and fixes the **invite-on-failed-attempt** bug, since smooth
mandatory enrollment now matters more.

**Explicitly rejected — `IP/<app>` path-based revert.** Large refactor (OIDC redirect
URIs/cookies are host-bound; AWX fights sub-paths) **and** regressive — WebAuthn RP IDs
**cannot be IP addresses**, so it would make the mandatory passkey impossible. Host-based
addressing is load-bearing; keep it.

---

## Decision: default the sandbox base domain to sslip.io

`sslip.io` resolves `anything.<node-ip>.sslip.io → <node-ip>` automatically — no account, no
setup:

```
auth.<node-ip-dashed>.sslip.io    → <node-ip>      (no /etc/hosts)
console.<node-ip-dashed>.sslip.io → <node-ip>
netbox.<node-ip-dashed>.sslip.io  → <node-ip>       … etc.
```

The base domain becomes `<node-ip-dashed>.sslip.io` (e.g. `<aliyun-sandbox-node-ip-dashed>.sslip.io`) instead of
`<label>.dmf.test`. **Nothing else changes** — still host-based, OIDC untouched, apps
untouched; the local CA issues a wildcard for `*.<node-ip-dashed>.sslip.io`. Because
`<ip>.sslip.io` is a *valid domain* (unlike a bare IP), the **WebAuthn RP ID is valid and
mandatory passkeys keep working**.

`.dmf.test` + `/etc/hosts` stays available as the **air-gapped** opt-out (sslip.io is a
third-party public-DNS dependency and needs the node internet-reachable on 443).

---

## Scope of change

### A. sslip.io base domain (the one real change) — `dmf-env/bin/init-wizard.sh`
Sandbox path (`collect_inputs` / `load_inputs_noninteractive` + `render_sandbox_inventory` +
`render_manifest_sandbox`):
- When no explicit base domain is given, derive `BASE_DOMAIN=<node-ip-dashed>.sslip.io` from
  `SANDBOX_NODE_IP` — use the **reachable IP the tester's browser will use** (for a NAT'd node
  that's the public IP, *not* the private `k3s_node_ip`). Provide a `.dmf.test` opt-out for
  air-gapped runs.
- Local-CA SANs already render `*.${BASE_DOMAIN}` + `${BASE_DOMAIN}`; no change beyond the
  base-domain value. WebAuthn RP ID derives from the request host → `*.<ip>.sslip.io` works.

### B. CA-trust UX (passkeys are mandatory → make the required step loud)
- The dmf-init `ca-cert` pause / quickstart must state plainly: **you must trust the DMF Local
  CA or passkey enrollment will fail silently** ("Registration cancelled or timed out" is a
  non-secure-context symptom, not a real cancel).
- Recommend bounding blast radius: trust the CA in **Firefox's own store** (separate from the
  OS) or a dedicated browser profile, and document removal.

### C. Fix the invite-consumed-on-failed-attempt bug (authentik role / `ensure_invitation`)
The single-use enrollment invite is consumed even when the WebAuthn ceremony *fails*, so every
retry shows "invalid invite" and masks the real (CA-trust) cause. Consume the invite **only on
successful enrollment**, or have `get-passkey-enrollment-url.sh` auto-re-mint on each call.

---

## Implementation steps (dispatch to qwen-left; Claude verifies)

1. sslip.io base-domain default in `init-wizard.sh` (with `.dmf.test` opt-out). (qwen)
2. Invite-on-failure fix in the authentik role / helper (qwen).
3. CA-trust UX copy in the dmf-init `ca-cert` pause + quickstart (qwen; small).
4. **Verify (Claude):** fresh sandbox bootstrap → reach `console.<node-ip>.sslip.io` with **no
   /etc/hosts**; trust the CA once; enroll the **mandatory** passkeys end-to-end; confirm
   retries no longer hit "invalid invite"; `bootstrap-sandbox-verify` D8 passkey check green.

No ADR change — ADR-0028 D8 is preserved.

## Out of scope (separate plans)

- **Maintainer "real" test profile — `<env>.dmfdeploy.io` + DNS-01.** For maintainers who hold
  the `dmfdeploy.io` domain + DNS token: cert-manager does DNS-01 (works for **LAN or cloud**
  nodes — DNS-01 needs only a TXT record, no inbound), publish A/`*` records → node IP (LAN
  private IPs are valid in public DNS; watch router **DNS-rebinding protection**). Gives
  **publicly-trusted certs, no CA install**, mandatory passkeys, LAN-or-cloud — the upgrade
  path that removes even the CA-trust step. Reuses the existing cloud DNS-01 machinery on a
  single BYO node. Separate plan: "Single-node DNS-01 profile."
- **localhost-origin sandbox** (WebAuthn over `http://localhost`, no cert) — needs RP-ID/OIDC
  wired to `localhost` + a working forward. Deferred.

---

# Work packages — cold-agent implementation spec

> A freshly-cleared agent can execute from here without prior context. Do WP0 first.

## WP0 — Onboarding (every agent, first)
- **Boot ritual:** `cd "$DMFDEPLOY_UMBRELLA" && git fetch && git pull`; `bin/generate-status.sh
  --no-fetch`; read `STATUS.md`, this plan, and `docs/handoffs/DMF First Container-Driven VPS
  Deploy + Passkey UX Handoff 2026-06-07.md`; skim `docs/decisions/INDEX.md` (ADR-0028 D8,
  ADR-0031 sandbox profile).
- **Repos/branch:** changes touch `dmf-env`, `dmf-infra`, `dmf-init` (sibling repos).
  🔒 **HARD CONSTRAINT (operator, 2026-06-07): ALL work lands on `main`. No feature branches.**
  Verify `git -C <repo> rev-parse --abbrev-ref HEAD` == `main` before any commit; **ask before
  touching a sub-repo with dirty state** (another agent's WIP). Do NOT push unless told.
- **Live env for verification:** sandbox `tzje-voik` is up on a real VPS (SSH/IP in STATUS).
  The dmf-init container `dmf-init-marty` + colima may still be running.
- **Commits:** conventional-commit messages, end with `Co-Authored-By: Claude Opus 4.8
  <noreply@anthropic.com>`. If dispatched via agent-bridge, reply `DONE <hashes>` / `BLOCKED
  <reason>` to the caller.
- **Guardrails:** sandbox lane ONLY; **passkeys stay mandatory** — do NOT touch the ≥2 assert
  (`ensure_invitation.yml:21-28`) or any cloud-lane behaviour; no ADR change.

## WP1 — sslip.io default sandbox base domain  ·  repo `dmf-env`
**File:** `bin/init-wizard.sh`. `BASE_DOMAIN` is hardcoded `${SANDBOX_LABEL}.dmf.test` at **3
sites**: `:371` (`validate_inputs`), `:553` (`collect_inputs_interactive`), `:745`
(`load_inputs_noninteractive`).
**Change:**
- Add `derive_sandbox_base_domain()`. **A `sandbox.label` is cosmetic — it does NOT opt out
  of sslip.io** (amended 2026-06-07 per codex review + operator decision (b): forcing
  `.dmf.test` on naming would silently reintroduce the `/etc/hosts` wall this plan removes).
  The **only** opt-outs are `sandbox.addressing: hosts` **or** an explicit
  `sandbox.base_domain`; both yield `<label>.dmf.test`. **Otherwise default** to
  `<node-ip-dashed>.sslip.io` — dash-encode `SANDBOX_NODE_IP` (`.`→`-`, e.g.
  `<aliyun-sandbox-node-ip>`→`<aliyun-sandbox-node-ip-dashed>`). IPv4 only; if `SANDBOX_NODE_IP` is not an IPv4, fall back
  to `.dmf.test` and `warn`.
- `SANDBOX_NODE_IP` must be the **browser-reachable** IP (already = `ansible_host`; for a NAT'd
  node that's the public IP, **not** `k3s_node_ip`).
- Answers-file: new optional `sandbox.addressing: sslip.io|hosts` (default `sslip.io`); honour
  an explicit `sandbox.base_domain` as the opt-out. A bare `sandbox.label` stays cosmetic (it
  does **not** opt out). Wire interactive (`:541-553`) + non-interactive (`:733-745`); compute
  once in `validate_inputs` so all three sites agree. The interactive label prompt is optional
  (empty → auto-derive from node IP).
- Update the `:541` info copy and the `:1855` summary line (no longer always `.dmf.test`).
- SANs already render `*.${BASE_DOMAIN}` + `${BASE_DOMAIN}` — no change beyond the value.
**Acceptance:** `bin/init-wizard.sh --non-interactive answers.yaml` (provider `sandbox`, no
label, `node_ip=<aliyun-sandbox-node-ip>`) → rendered `manifest.yaml`, `inventory/group_vars/all/main.yml`
(`dmf_sandbox_base_domain`), and `hosts` carry `<aliyun-sandbox-node-ip-dashed>.sslip.io` and SAN
`*.<aliyun-sandbox-node-ip-dashed>.sslip.io`. The opt-out paths — `sandbox.addressing: hosts` **or** an explicit
`sandbox.base_domain` — still yield `<label>.dmf.test`; a bare `sandbox.label` does **not**
(it stays sslip.io). *(Verified 2026-06-07: codex render matrix — `default_no_label` &
`label_default` → `<aliyun-sandbox-node-ip-dashed>.sslip.io`, `hosts_optout` → `demo.dmf.test`, `explicit_base`
→ `custom.example.test`; `dig console.<aliyun-sandbox-node-ip-dashed>.sslip.io` → `<aliyun-sandbox-node-ip>`.)*

## WP2 — enrollment invite reusable within TTL  ·  repo `dmf-infra`
**File:** `k3s-lab-bootstrap/roles/stack/operator/authentik/files/ak_passkey_invitation.py`
(create `:97` `single_use=True`; re-assert `:113-114`).
**Change:** set `single_use=False` (both the `create()` and the re-assert block) so the
short-TTL invite survives a **failed** WebAuthn attempt and retries reuse the same URL until a
passkey is confirmed or TTL expires. Update the "single-use" wording in
`ensure_invitation.yml:78` and in `dmf-env/bin/get-passkey-enrollment-url.sh` hints.
**Tradeoff (document in commit + the authentik role README):** the link becomes reusable for
its TTL window (`authentik_bootstrap_passkey_invitation_ttl_hours`), bounded by TTL + the
enrollment flow + the operator identity. Acceptable for the operator bootstrap link. *(Alt:
keep `single_use` and redesign the flow to consume only on success — heavier; deferred.)*
**Acceptance:** on the live env, fail a WebAuthn attempt, reload the **same** URL → reaches the
enrollment stage again (no "invalid invite") until a passkey is confirmed or TTL passes.

## WP3 — CA-trust UX loud + scoped  ·  repo `dmf-init`
**Files:** `src/dmf_init/bootstrap_steps.py` (`ca-cert` pause, `:458`) + `frontend/src/
BootstrapView.tsx` (`ca-cert` UI `:777-820`; the `security add-trusted-cert` command is already
at `:811/:820`).
**Change:** the `ca-cert` pause copy must state plainly that trusting the CA is **required** for
the mandatory passkey, and that an untrusted cert makes WebAuthn **fail silently**
("Registration cancelled or timed out" = non-secure-context, not a real cancel). Add the
**Firefox-own-store / dedicated-profile** recommendation to bound blast radius + a removal note.
**Acceptance:** the pause renders the warning + scoped-trust guidance; `npm run build` so it
ships in the image.

## Verification (Claude, after WP1–WP3 land)
Fresh sandbox bootstrap with sslip.io → reach `console.<node-ip>.sslip.io` with **no
/etc/hosts**; trust the CA once; enroll the **mandatory** passkeys end-to-end; confirm retries
no longer hit "invalid invite"; `bootstrap-sandbox-verify` D8 passkey check green.

## Not in these WPs (separate TODOs, needed to actually run a container bootstrap)
The dmf-init **image** still needs `yq`/`dig`/`helm`/`htpasswd` + controller py-libs baked in,
and `200-baseline` trixie-safe pip, and `unseal-openbao.sh` to not require macOS `security`
(sandbox). See TODOS §"dmf-init CONTAINER path — productization" + memory
`project_dmf_init_container_bootstrap_gaps`.
