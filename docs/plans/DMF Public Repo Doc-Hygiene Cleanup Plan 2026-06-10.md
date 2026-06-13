---
status: executed
date: 2026-06-10
executed: 2026-06-10
---
# DMF Public Repo Doc-Hygiene Cleanup Plan — 2026-06-10

**Status:** Approved (operator decisions locked 2026-06-10) — ready to execute
**Owner:** <handle>
**Scope:** All 8 public component repos under `github.com/dmfdeploy/`
**Trigger:** First public release completed 2026-06-10. A two-agent audit
(claude + codex cross-check) of the public surface found stale facts, a
self-declared "NOT for main" spike-doc leak, and scattered private-topology
references. This plan turns that audit into per-repo PRs.

> **Auth note (execution-time):** PRs are submitted **as `<handle>`** using the
> token from macOS Keychain. `gh` is already authenticated as `<handle>`
> (keyring, `repo` scope). For an explicit token transport use
> `GH_TOKEN=$(security find-generic-password -s ghcr.io -a <handle> -w)` —
> retrieved **only at push time**, never echoed, logged, or committed. Keychain
> entry: service `ghcr.io`, account `<handle>` (the username, not the email).

---

## 1. Goal

Make every public repo's documentation **factually correct, free of must-not-main
spike content, and free of clearly-private references**, while **preserving the
learnings** (operator's explicit goal). This is doc/hygiene only — no behavioral
code change, so **no `VERSION` bump and no release** (ADR-0005: no bump → no
release; these are `docs:` / `chore:` / `fix:` commits).

## 2. Decisions taken (operator, 2026-06-10)

| # | Decision | Choice |
|---|----------|--------|
| D1 | MXL spike/handoff docs marked "NOT for main" on public main | **Relocate learnings to umbrella (sanitized), then remove from public repos.** codex concurred independently. |
| D2 | Internal-flavored context (agent files, `.forgejo` workflows, archive-remote mentions) | **Scrub clearly-private only.** Keep agent files (`CLAUDE.md`/`AGENTS.md`/`QWEN.md`) and the `dmf-*-archive` CONTRIBUTING mention; fix the wrong/private bits inside them. |
| D3 | `.forgejo/` workflows | **KEEP.** Operator confirmed the LAN Forgejo **runner is live** — these are functional CI, not stale placeholders. No removal. |
| D4 | Where PR work happens | **`~/repos/dmfgithub/dmfdeploy/<repo>`** — fresh clones with `git@github.com:dmfdeploy/...` origin, no Forgejo conflation. The `~/repos/dmfdeploy/<repo>` working clones (LAN origin) are NOT used for PRs. |

## Execution status (2026-06-10)

- ✅ **Mechanical tier** + ✅ **Judgment tier** applied and acceptance-verified in the
  **`~/repos/dmfgithub/dmfdeploy/<repo>`** clones (dmf-infra 16 files, dmf-cms 5,
  dmf-central 3, dmf-media 3, dmf-runbooks 1). Done via qwen-left (lifting) +
  claude (verify + port). Working `~/repos/dmfdeploy` clones reverted to clean.
- ⏳ **Remaining:** (1) MXL relocation PR-0 (umbrella sanitized doc + remove the
  spike/handoff docs & 910/915 playbooks from the dmf-infra/dmf-media GitHub clones);
  (2) MXL **product-wording** scrub (dmf-cms mxl-flows-page + dmf-media chart/docker
  metadata — generic provider/tailnet wording); (3) path neutralization in **non-markdown**
  files (`.sh`/`.yaml`/`Dockerfile` — claude, careful); (4) git: branch + signed-off
  commits + PRs as `<handle>`.
- ❌ **Dropped:** `.forgejo` removal (D3 — runner is live).

## 3. Verified findings inventory (merged claude + codex audit)

All line numbers verified against working trees on 2026-06-10. Severity:
🔴 wrong/leak · 🟠 stale · 🟡 minor · ✅ verified-clean (no action).

### 3.1 Cross-cutting
- 🟠 **"all 6 repos" → "all repos"** in agent files (future-proof: a bare
  "all repos" never goes stale as the repo set changes, unlike a hardcoded
  count). Files: `dmf-infra` (CLAUDE 21, AGENTS 18, QWEN 19), `dmf-cms`
  (CLAUDE 19, AGENTS 19, QWEN 17), `dmf-central` (CLAUDE 19, QWEN 19),
  `dmf-media` (CLAUDE 19, QWEN 19), `dmf-runbooks` (CLAUDE 21). `dmf-init`
  already says "all repos" (the target wording); `dmf-promsd` has no agent files.
- 🔴 **MXL spike/handoff leak (D1):**
  - `dmf-infra`: `playbooks/910-mxl-media-nodes.yml`, `playbooks/915-mxl-cms-override.yml`,
    `docs/mxl-media-nodes-plan.md` — banners "SPIKE … NOT for main", live slug
    `g2r6-foa9`, Aliyun/tailnet topology.
  - `dmf-media`: `docs/mxl-fabrics-runbook.md`, `docs/mxl-fabrics-workstream-c-handoff.md`
    — "Branch for ALL work: feat/mxl-single-node-spike (must NOT merge to main)",
    `g2r6-foa9`, `aliyun-media-0[12]`, "GREEN 2026-05-30".
- 🟡 **MXL product wording** (KEEP the artifacts, scrub wording): `dmf-cms`
  `docs/mxl-flows-page.md` + `frontend/.../MxlFlows.tsx`; `dmf-media`
  `charts/mxl-fabrics-demo/*`, `docker/mxl-fabrics/*` — generic provider/tailnet
  wording, drop spike/branch references in comments/metadata.
- 🟡 **Hardcoded operator-local paths** (`~/repos/...`): `dmf-cms` (QWEN 59,
  `docs/DEVELOPMENT-AND-BUILD-RULES.md` 113/241, `docs/IMPLEMENTATION-STRATEGY.md` 423,
  `scripts/build-image.sh` 131/135, `scripts/release.sh` 142/148/157); `dmf-media`
  (`bin/publish-chart-to-ghcr.sh` 12, `dev/lima/*.yaml`, `docker/mxl-fabrics/Dockerfile`);
  `dmf-infra` (`docs/SECURITY-REMEDIATION-GUIDE.md`, `roles/README.md`, `ee/README.md`);
  `dmf-env` (`bin/run-playbook.sh` ~199, `init-wizard.sh`).
- 🟡 **`.forgejo/` workflows shipped alongside canonical GitHub CI**: `dmf-infra`,
  `dmf-cms`, `dmf-central`, `dmf-media`, `dmf-init`. (`dmf-cms` CI is a "update
  when stack chosen" placeholder; `dmf-init` `build-bundle.yml` has "future
  GitHub setup" framing.)

### 3.2 `dmf-infra`-specific
- 🔴 `README.md:23` `github: lkirc/dmf-infra` → `dmfdeploy/dmf-infra`
  (contradicts `SECURITY.md:7`). Same `lkirc` ×5 in `k3s-lab-bootstrap/docs/repo-strategy.md`
  (31, 203, 233, 279, 415). **6 total.**
- 🔴 `README.md` "Two-Repo Model" block (16–25): stale framing; mentions `gitlab`;
  implies `dmf-env` is the private repo (it is **public** generic tooling — ADR-0035).
- 🟠 `README.md` Project Structure (196–224): lists non-existent `vertical-control/`;
  omits real `vertical-resilience/`; playbook range "…693-*" should reach 699;
  omits `bootstrap-*.yml` family, `lifecycle-configure.yml`, `charts/`, `ee/`,
  `providers/`, `tests/`.
- 🟠 `README.md:238` `cluster.example.net` → `dmf.example.com` (project placeholder).
- 🟡 `README.md:189` Loki listed as a service URL — it's an IngressRoute
  (`/loki`, `/loki/ready`), not a human UI. Reword, don't delete.
- 🟠 `CLAUDE.md` ADR-0025 "incoming additions" (2026-05-19) → past tense (`ee/`
  + `630-zot-seed-platform.yml` have landed).
- 🟠 **Broken intra-repo links**: `docs/dmf-platform-plan.md:310` quoted broken ref to `../CLAUDE.md`
  resolves to missing `k3s-lab-bootstrap/CLAUDE.md` (real one is repo root →
  `../../CLAUDE.md`); `docs/openbao-policy-reconciliation-agent-prompt.md:47`
  links `698-cms-smoke-test.yml` but smoke-test is `699` (698 is
  `cms-netbox-forgejo-tokens`). **NB: the wrong filename appears 6× in that doc
  (lines 25, 47, 106, 194, 291, 316), not just the L47 link — all fixed.**
- 🟠 **Stale numbering / pre-OpenBao conventions** in `k3s-lab-bootstrap/docs/`:
  `forgejo.md` (`31-forgejo`, `--vault-password-file ~/.vault_pass`),
  `integration-sot.md` (`40/41`, `vault.yml`), `cluster-ready.md`,
  `awx-integration-plan.md`, `ci-cd-proposal.md` (mentions GitLab + dev `vault.yml`),
  `hardening.md` (`05-harden`).
- 🟠 `repo-strategy.md`, `dmf-platform-plan.md` — pre-migration planning docs,
  superseded by ADR-0041; need a "superseded/historical" banner.

### 3.3 Other repos
- 🟠 `dmf-media/README.md:10` and `dmf-central/README.md:17`: "`dmf-env` —
  environment-specific inventory" → generic env-provisioning tooling (ADR-0035).
- 🟠 `dmf-cms` `<note-store>` refs: `CLAUDE.md:53`, `AGENTS.md:34`
  (`<note-store>/tmp/dmf-portal-mockup-2025.png`) — known TODOS-hygiene item.
- 🟡 `dmf-init/test/e2e/profile.montest.env` `PASSPHRASE=montest-test-pass` —
  test fixture (`dmf.test`, `/tmp`), not a real secret. Optional clarifying comment.

### 3.4 ✅ Verified clean (no action — recorded so we don't re-litigate)
- `lkirc` is **isolated to `dmf-infra`** (0 hits in the other 7).
- No mislabeled GitHub org refs — all `github.com/...` are legit upstream
  download/source URLs or correct `dmfdeploy` self-refs.
- No raw-IP leaks: `203.0.113.x` / `192.0.2.x` (RFC 5737 TEST-NET),
  `192.168.105.0/24` (Lima default), `10.0.0.0/8` (generic CIDR) — all placeholders.
  Scrub gates held.
- Secret-ish literals are all **`tests/` fixtures**: `correct horse battery
  staple`, `super-secret`, `test-token`, `abc123`, `montest-test-pass`.
- No broken intra-repo markdown links outside `dmf-infra`.

### 3.5 Operator follow-ups (NOT in any PR — out of public scope)
- `dmf-env` local `.git/config` has an embedded basic-auth LAN remote
  (`http://<handle>:<redacted>@<lan-forgejo-ip>/...`). Untracked, not public — but consider
  rotating that LAN credential / switching to SSH.
- Confirm Forgejo→GitHub push-mirror is **off** for every repo (per STATUS.md it
  was removed for `dmf-runbooks`; re-verify the rest) so LAN commits never
  re-leak to public.

---

## 4. Execution: umbrella relocation first, then per-repo PRs

### PR-0 — Umbrella MXL relocation (gates PR-1 & PR-4) — lands in umbrella, not a public PR
The umbrella already holds the MXL **design** learnings (`docs/plans/DMF MXL
Single-Node Media Node Spike Plan 2026-05-17.md`, `…Loopback Execution Plan
2026-05-29.md`, `…On-Demand Media Function Cycle Plan 2026-06-01.md`,
`docs/reviews/dmf-mxl-upstream-profile-and-contribution-review-2026-06-01.md`,
ADR-0017). Steps:
1. Diff the public spike/handoff docs against those — identify content **not
   already captured** (notably the **GREEN 2026-05-30 operational result** and
   the workstream-C handoff specifics: join workflow, taints, route persistence).
2. Capture the unique narrative in `docs/sessions/DMF MXL Fabrics Spike Result
   2026-05-30.md` (sanitized: `<env>` for `g2r6-foa9`, `<media-node-N>` for node
   names, generic provider). Cross-link the existing plans/ADR.
3. Commit to umbrella (LAN). This unblocks the public removals.

### PR-1 — `dmf-infra` (`<handle>/public-doc-cleanup`)
- `README.md`: `lkirc`→`dmfdeploy` (L23); rewrite Two-Repo block (L16–25) →
  "Part of the DMF Platform" (the public repos under `dmfdeploy/`; `dmf-env` is
  public generic tooling, per-env state operator-local per ADR-0035; drop
  `gitlab`); reword Loki (L189); `cluster.example.net`→`dmf.example.com` (L238);
  fix Project Structure (L196–224): drop `vertical-control/`, add
  `vertical-resilience/`, range →699, add bootstrap/lifecycle-configure/charts/ee/providers/tests.
- `CLAUDE.md`: "all 6 repos"→"all repos" (L21); ADR-0025 block → past tense.
- `AGENTS.md:18`, `QWEN.md:19`: "all 6 repos"→"all repos".
- `k3s-lab-bootstrap/docs/repo-strategy.md`: `lkirc`→`dmfdeploy` ×5 + superseded-by-ADR-0041 banner.
- `k3s-lab-bootstrap/docs/dmf-platform-plan.md`: fix L310 link (`../../CLAUDE.md`) + superseded banner.
- `k3s-lab-bootstrap/docs/openbao-policy-reconciliation-agent-prompt.md`: `698-cms-smoke-test.yml`→`699-cms-smoke-test.yml` (all 6 instances). ✅ DONE.
- Stale-numbering docs (forgejo/integration-sot/cluster-ready/awx-integration-plan/ci-cd-proposal/hardening):
  update numbering + OpenBao-wrapper convention, or add "historical" banner where a rewrite is too deep.
- Hardcoded paths (SECURITY-REMEDIATION-GUIDE, roles/README, ee/README) → relative/placeholder.
- **Remove (post PR-0):** `playbooks/910-mxl-media-nodes.yml`, `playbooks/915-mxl-cms-override.yml`, `docs/mxl-media-nodes-plan.md`.

### PR-2 — `dmf-cms` (`<handle>/public-doc-cleanup`)
- `CLAUDE.md:19`, `AGENTS.md:19`, `QWEN.md:17`: "all 6 repos"→"all repos".
- `<note-store>` mockup ref (`CLAUDE.md:53`, `AGENTS.md:34`) → neutralize/relocate the image reference.
- Hardcoded paths (QWEN, DEVELOPMENT-AND-BUILD-RULES, IMPLEMENTATION-STRATEGY, build-image.sh, release.sh) → placeholder/relative.
- `docs/mxl-flows-page.md` + chart metadata: generic provider/tailnet wording (product **stays**).
- `.forgejo/workflows/ci.yml`: remove (GitHub canonical; it's a placeholder).

### PR-3 — `dmf-central` (`<handle>/public-doc-cleanup`)
- `CLAUDE.md:19`, `QWEN.md:19`: "all 6 repos"→"all repos".
- `README.md:17`: stale `dmf-env` line → generic tooling.
- `.forgejo/workflows/ci.yml`: remove.

### PR-4 — `dmf-media` (`<handle>/public-doc-cleanup`) — heaviest
- `CLAUDE.md:19`, `QWEN.md:19`: "all 6 repos"→"all repos".
- `README.md:10`: stale `dmf-env` line → generic tooling.
- **Remove (post PR-0):** `docs/mxl-fabrics-runbook.md`, `docs/mxl-fabrics-workstream-c-handoff.md`.
- `charts/mxl-fabrics-demo/*`, `docker/mxl-fabrics/*`: scrub spike/branch/Aliyun wording → generic (product **stays**).
- Hardcoded paths (`bin/publish-chart-to-ghcr.sh`, `dev/lima/*.yaml`, Dockerfile comment) → neutralize.
- `.forgejo/workflows/ci.yml`: remove.

### PR-5 — `dmf-runbooks` (`<handle>/public-doc-cleanup`)
- `CLAUDE.md:21`: "all 6 repos"→"all repos". (Smallest PR.)

### PR-6 — `dmf-init` (`<handle>/public-doc-cleanup`)
- Agent files already say "all repos" (the target wording) — no change needed.
- `.forgejo/workflows/{ci,build-bundle}.yml`: drop "future GitHub setup" framing / remove placeholder CI.
- `profile.montest.env`: optional one-line comment marking it a test fixture.

### PR-7 — `dmf-promsd`
- **None.** Verified clean. (Listed for completeness.)

---

## 5. PR mechanics (every public PR)

1. **Add GitHub remote** (local clones currently point only at `forgejo-<handle>`/LAN;
   `sync-to-github.sh` is retired):
   `git -C <repo> remote add github git@github.com:dmfdeploy/<repo>.git`
   (gh is SSH-authed as `<handle>`).
2. **Branch**: `git switch -c <handle>/public-doc-cleanup` (off `main`).
3. **Commits**: Conventional Commits, **signed off** (`-s`), authored
   `<handle> <6800371+<handle>@users.noreply.github.com>`. **No `Co-Authored-By: Claude`
   / "Generated with Claude Code" trailer** — the operator authors the work
   (agent attribution policy, 2026-06-10). One logical change per commit
   (e.g. `docs: correct GitHub org and repo-count`, `chore: remove must-not-main mxl spike artifacts`).
4. **No `VERSION` bump** (doc-only; ADR-0005).
5. **Gates**: local pre-commit gitleaks + CI `guard`/`ci` must be green. Our
   changes reduce surface, so expect green; re-run `bin/export-scan.sh <repo>` if unsure.
6. **Push as `<handle>`** (Keychain token — see auth note up top). `gh pr create`
   against `dmfdeploy/<repo>` `main`.
7. **Merge**: branch protection requires a PR + green checks + CODEOWNERS review;
   `<handle>` is maintainer → review + **rebase-merge** so signed-off commits land unchanged.
8. **Post-merge**: re-confirm no Forgejo→GitHub push-mirror on the repo.

## 6. Sequencing

1. **PR-0** (umbrella relocation) — unblocks removals.
2. **PR-1 `dmf-infra`** + **PR-4 `dmf-media`** — the leak + the two biggest.
3. **PR-2/3/5/6** (cms, central, runbooks, init) — independent, parallelizable.
4. **PR-7 `dmf-promsd`** — nothing to do.
5. Operator follow-ups (§3.5) — separate, non-PR.

## 7. Acceptance per PR
- `git -C <repo> grep -n "lkirc"` → 0 (dmf-infra).
- `git -C <repo> grep -n "all 6 repos"` → 0.
- No `g2r6-foa9` / `feat/mxl-single-node-spike` / "NOT for main" in tracked files
  of `dmf-infra` and `dmf-media`.
- No broken intra-repo markdown links (link-check).
- CI `guard` + `ci` green on the PR.
- Product MXL chart/console artifacts still build/render (dmf-media/dmf-cms).

## 8. Audit provenance
- Round 1 (`dmf-infra`) + Round 2 (7 repos): claude survey, codex
  (`gpt-5.5`, xhigh) independent cross-check via `agent-bridge`. All findings in
  §3 were grep/read-verified against working trees on 2026-06-10.
