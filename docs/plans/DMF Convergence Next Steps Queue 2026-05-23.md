---
status: historical
date: 2026-05-23
---
# DMF Convergence Next Steps Queue

**Date:** 2026-05-23
**Origin:** End of a long convergence session. The original prompt was
"converge project sprawl + reduce open ADR queue"; that pass landed.
ADR-0021 then closed as a doc-rebase rather than implementation (the code
already shipped 2026-05-13 + was live-verified on g2r6-foa9). This doc
captures the four candidate next steps surfaced at that point so a future
session can pick up cleanly.

The list is intentionally short and ranked by impact-per-effort. None of
these is blocking; all of them are convergence-flavoured cleanup that
moves the platform toward "experiment phase: does the architecture survive
contact with reality?" (ADR-0004).

---

## #1 — App-admin drift realignment

**DONE 2026-05-23** — audit on `g2r6-foa9` found no drift (the 6-flag tax
was an `aliyun-123` artefact, retired with the env). New
`audit-admin-identities.yml` playbook ships in `dmf-infra` for future
envs; 698 refactored to read Forgejo username from
`secret/apps/forgejo/admin → .username` (dead `cms_netbox_admin_user`
removed). `awx_control_node_ssh_privkey_path` deferred as a separate
followup (workstation-path drift, not credential). See
[`docs/handoffs/DMF App-Admin Drift Realignment Handoff 2026-05-23.md`](../handoffs/DMF%20App-Admin%20Drift%20Realignment%20Handoff%202026-05-23.md).

<details>
<summary>Original §#1 scope (kept for reference)</summary>

**Why it earns the top slot.** Every `bootstrap-configure` run today
needs six `-e` override flags (see STATUS Recent Activity §"aliyun-123
bootstrap-configure" 2026-05-14):

```
-e netbox_sot_admin_username=admin
-e forgejo_admin_username=<user>
-e awx_integration_admin_user=<user>
-e awx_admin_user=<user>
-e cms_forgejo_admin_user=<user>
-e awx_control_node_ssh_privkey_path=/Volumes/<user>/secure/awx-control-node.privkey
```

This tax compounds at every greenfield. ADR-0024 (Two-Identity Admin
Model, Accepted) addresses the K8s-Secret-backed admin half via the new
`common/admin-identity-resolve` helper role. NetBox + Forgejo store
their local admin in OpenBao (`secret/apps/<app>/admin` via
`common/app-admin-facts`), so the helper-as-shipped doesn't apply to
them. The path-style flag (`awx_control_node_ssh_privkey_path`) is
neither — it's an operator-workstation file location that's currently
inventory-baked instead of derivable.

**Why now.** Tier A bootstrap-correctness is otherwise clean as of
2026-05-23 (ADR-0021 verified, Lane B chart 0.1.1 landed, retired-IP
fallbacks gone). The 6-flag tax is the next visible piece of greenfield
friction.

**Scope sketch.**

1. **NetBox + Forgejo username derivation via `common/app-admin-facts`.**
   The `secret/apps/<app>/admin` path already exists per ADR-0024
   scope-deltas. Two pieces of work:
   - Confirm `common/app-admin-facts` already reads the username field
     (per the 2026-05-08 Pre-Bao Secrets Design, ADR-0024 deciders).
   - Refactor `playbooks/698-cms-netbox-forgejo-tokens.yml` and the
     NetBox/Forgejo install paths to consume the helper output instead of
     `netbox_sot_admin_username` / `forgejo_admin_username` inventory
     vars.
2. **AWX admin/integration username convergence.** ADR-0024 already
   wired the helper into `awx-integration/tasks/main.yml` (PR2 landed).
   The remaining 3 AWX-shaped flags (`awx_admin_user`,
   `awx_integration_admin_user`, `cms_forgejo_admin_user`) need to be
   audited — likely they're already covered and just need to be removed
   from the override list, or one final consumer path missed the helper.
3. **`awx_control_node_ssh_privkey_path`.** Move the path into OpenBao
   (`secret/platform/awx/control_node_ssh_privkey_path`) or derive it
   from `DMF_BOOTSTRAP_BUNDLE_DIR` + a known relative path. The current
   `/Volumes/<user>/secure/...` hardcode breaks the Option-2 bundle-dir
   decision (`$HOME/secure/dmf-bootstrap`).
4. **Live verification on a fresh greenfield.** The only honest way to
   prove the flag list is retired is to spin up a wizard env without
   any of the six `-e` flags and confirm `bootstrap-configure.yml`
   reaches `failed=0`. Two existing retired envs (`aliyun-123`,
   `hetzner-arm`) are inappropriate — only a fresh wizard run validates
   the greenfield path.

**Effort estimate:** ~3-4 hours of in-repo work + an end-to-end
greenfield test that needs operator coordination (new env spin-up is a
~30-60 min wall-clock playbook with Hetzner provisioning).

**Entry points:**
- `dmf-infra/k3s-lab-bootstrap/roles/common/admin-identity-resolve/` — ADR-0024 helper role.
- `dmf-infra/k3s-lab-bootstrap/roles/common/app-admin-facts/` — the OpenBao-backed equivalent.
- `dmf-infra/k3s-lab-bootstrap/playbooks/698-cms-netbox-forgejo-tokens.yml` — narrow PR1 fix at `dmf-infra@4f7f505` (Forgejo username fallback chain); needs refactor to the helper pattern.
- `docs/plans/DMF App Admin Account Drift Audit and Realignment Plan 2026-05-14.md` — original audit/plan; verify against current state.
- STATUS §"aliyun-123 bootstrap-configure" — authoritative source for the 6-flag list.

**Acceptance criteria.**

- `bootstrap-configure.yml` on a fresh greenfield env completes
  `failed=0` with **zero** `-e` overrides beyond the env name.
- The 6-flag list in STATUS Recent Activity §"aliyun-123 bootstrap-
  configure" is updated to reflect retirement, with a backref to the
  closure work.
- A verifier playbook (or extension to an existing `verify-*` playbook)
  asserts each admin identity is resolvable from its sanctioned source
  (K8s Secret for K8s-Secret-backed; OpenBao path for OpenBao-backed).

**Risks.**

- Touching the admin-identity surface during bootstrap is high-blast-
  radius. Stage the changes; rerun on g2r6-foa9 (current live env)
  before declaring done.
- The current 6-flag override list works — there is no incident, only
  friction. Don't break what works; the goal is to *remove* the
  overrides, not to *change* what they currently override.

</details>

---

## #2 — Wire `verify-openbao-identity-model.yml` into `bootstrap-verify.yml`

**DONE 2026-05-23** (`dmf-infra@596b28b`) — wired in alongside
`audit-admin-identities.yml` (§#1 byproduct) and `verify-oidc-admin-bridge.yml`
(ADR-0024 PR2). End-to-end run on g2r6-foa9 with
`--skip-tags verify-oidc-bridge`: `ok=86 changed=3 failed=0`.
**Real finding surfaced**: OIDC verifier fails on g2r6-foa9 because
`authentik-runtime` Secret is missing `AUTHENTIK_BOOTSTRAP_TOKEN` —
new entry in STATUS as "Open finding — Authentik runtime token."

<details>
<summary>Original §#2 scope (kept for reference)</summary>

**Why.** The new verifier shipped in `dmf-infra@1d337f4` is currently
only run on demand. Wiring it into `bootstrap-verify.yml` makes every
future env's post-seed run automatically exercise the AC-5 deny matrix
+ the ESO reconcile checks. Closes a non-blocking followup from the
2026-05-23 handoff.

**Scope.**

- Find the existing `bootstrap-verify.yml` (or whatever the verify
  wrapper is currently named — STATUS § Tier A Phase 3 references it).
- Add an `import_playbook:` (or `include`) for
  `verify-openbao-identity-model.yml`, gated on the relevant
  `vertical-security` tag.
- Optionally also include `verify-oidc-admin-bridge.yml` if it's not
  already wired (ADR-0024 PR2 may or may not have done this).

**Effort estimate:** ~15 minutes + a single bootstrap-verify rerun on
g2r6-foa9 to confirm.

**Entry points:**
- `dmf-infra/k3s-lab-bootstrap/bootstrap-verify.yml` (per the Tier 1
  bootstrap split landed 2026-05-08).
- `dmf-infra/k3s-lab-bootstrap/playbooks/verify-openbao-identity-model.yml` (new this session).
- `dmf-infra/k3s-lab-bootstrap/playbooks/verify-oidc-admin-bridge.yml` (ADR-0024 PR2).

**Acceptance criteria.**

- `bootstrap-verify.yml` on g2r6-foa9 runs the AC-5 matrix and reports
  `failed=0`.
- Both `verify-*` playbooks are referenced from the wrapper.

</details>

---

## #3 — Move 7: pick the next public-publish repo

**Why.** ADR-0020 Mode A is now Accepted *policy* (not just discipline).
The publish pipeline for `dmf-runbooks` is proven (LAN Forgejo push →
GitHub push-mirror → per-env pull-mirror). The next public-publish makes
DMF go from "one launcher repo published" to "a real OSS platform
visible on GitHub."

**Scope (per repo — pick one).**

- **`dmf-cms`** — most visible (the operator Console; the headline
  artifact). Pre-publish hygiene: gitleaks audit (operator-identity
  patterns), `bin/scrub-public-repos.sh` clean, LICENSE/NOTICE,
  README polish, CODEOWNERS, branch-protection setup. Estimated leak
  surface unknown but probably small (TypeScript/React + FastAPI,
  not infra/inventory-shaped).
- **`dmf-infra`** — heaviest pre-publish leak audit per STATUS
  (~200 operator-identity-pattern matches in `k3s-lab-bootstrap/` per
  the umbrella scrub script). Carries the most operational value (other
  forks can use the playbooks as-is). Higher friction, higher payoff.
- **`dmf-media`** or **`dmf-central`** — both are slim scaffolds today
  (`dmf-media` has the NMOS catalog YAML + the chart; `dmf-central` is
  a Phase-0 scaffold). Trivial publishes but also low information
  density for first-time visitors.

**Effort estimate (per repo):** half-day to full-day depending on
audit findings. `dmf-cms` is likely the cleanest; `dmf-infra` is the
heaviest.

**Entry points:**
- `bin/scrub-public-repos.sh` — umbrella scrub gate.
- `docs/handoffs/DMF dmf-runbooks Path A Public Publish Completion Handoff 2026-05-22.md` — the published-as-template procedure.
- `docs/handoffs/DMF dmf-runbooks Public History Remediation Handoff 2026-05-23.md` — what to look out for (per-repo `.gitleaks.toml` operator-identity patterns, public guard-file leaks).
- `docs/plans/DMF Release and Contribution Model Implementation Plan 2026-05-11.md` — the master Release Phase plan.

**Acceptance criteria.**

- Repo's `main` branch is public on `github.com/dmfdeploy/<repo>`.
- Branch protection: linear history, force-push + delete blocked,
  applies to admins.
- LAN Forgejo push-mirror live; in-cluster Forgejo pull-mirror live
  (only if the repo is one the cluster consumes — not all of them are).
- Pre-publish leak audit clean per umbrella scrub script.

**Risks.**

- Public-history leak (per dmf-runbooks 2026-05-23 remediation
  precedent). Walk through that handoff before pushing — the
  per-repo `.gitleaks.toml` itself can leak identity patterns in a
  public repo, and the umbrella scrub script's `.gitleaks.toml`
  allowlist was fixed but each repo's local copy needs the same
  treatment.

---

## #4 — Wind down (the meta-option)

If the next session opens with limited time, the cleanest move is
**none of the above**, and instead a session-end handoff capturing
what's now true:

- Multi-thread day landed: ADR-0020/0026 promoted/refreshed,
  decisions-open trimmed, bundle-dir §D Option 2 chosen, Lane B chart
  0.1.1 end-to-end, retired-cluster fallbacks gone, init-wizard
  hardened, ADR-0021 verified + Tier A blocker retired.
- Three Proposed ADRs remain (0022 / 0026 / 0027), each with a
  well-formed promotion gate.
- App-admin drift is the next greenfield-friction win.
- Move 7 is the next strategic milestone.

This option is in the queue not because winding down is a deliverable,
but because picking it up *consciously* is healthier than opening
another long thread by accident.

---

## How to use this doc

Pick **one** item per session. Each top-level section is self-contained;
no item depends on another's landing. Once an item lands, replace its
section with a one-line `**DONE 2026-mm-dd** — see <handoff link>.` and
leave the rest of the doc in place. When all four are addressed, archive
the file with a `SUPERSEDED` banner.
