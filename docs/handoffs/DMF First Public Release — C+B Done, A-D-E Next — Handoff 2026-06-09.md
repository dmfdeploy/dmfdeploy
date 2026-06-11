# DMF First Public Release — Handoff (2026-06-09)

> **Read this first if your task is the first public GitHub release.** It is the
> resume point after Workstreams **C** (ADR digests) and **B** (dmf-env public
> scrub) landed. Workstreams **A**, **D**, **E** remain.

**Author:** umbrella session (claude), orchestrating qwen-left (lifting) +
codex (independent cross-check).
**Canonical plan:** [`docs/plans/DMF First Public Release Plan 2026-06-09.md`](../plans/DMF%20First%20Public%20Release%20Plan%202026-06-09.md)
— read it in full; it carries every locked decision and the per-workstream steps.

---

## TL;DR

We are preparing a clean first public release of the DMF Platform repos on
GitHub. The model and all forks are **decided** (see Locked decisions). Two
workstreams are **done + committed**; three remain. Each remaining workstream
should follow the proven loop: **write a self-contained spec → codex cross-checks
it → qwen lifts → claude verifies (grep-proof + tests) → codex agrees → commit.**

## Locked decisions (do not re-litigate)

| Fork | Decision |
|---|---|
| Canonical-source model | **GitHub-canonical-forward.** One-time clean import; afterward GitHub `main` is the source of truth. **Forgejo `main` must stop being the full-history branch** (one public DAG). No "Forgejo push-mirror → GitHub". |
| Forgejo after flip | **Retire-to-archive.** Full pre-publish history kept permanently in LAN-only `<owner>/<repo>-archive`; working clones add a read-only `archive` remote so agents keep history access. |
| dmf-env | **Publish a sanitized public `dmf-env`, KEEPING the name** (dmf-init hardcodes the `dmf-env` checkout dir). Provider scope = **Hetzner + sandbox only**. |
| dmf-promsd | **Publish** for v0.1 (it's in dmf-init's runtime set). |
| External contributors | **DCO** (`Signed-off-by:` + PR check), not CLA. |
| GitHub org tier | **Free** → rulesets only on public repos → use the **locked-window flip** (flip public owner-only/no-push, then immediately set branch+tag rulesets + secret scanning, verify `git push --tags` is rejected, then accept PRs). |
| ADR consolidation | **Digest-in-place** — no renumber/merge/delete (≈385 in-code ADR refs). |
| CI/CD | **Gates first, release automation next.** Hosted runners only (fork-PR RCE). |

Final public set (9 GitHub repos): `dmf-platform` (umbrella), `dmf-cms`,
`dmf-runbooks`, `dmf-central`, `dmf-infra`, `dmf-media`, `dmf-init`,
**`dmf-env`** (sanitized), **`dmf-promsd`**. `dmf-env` was the historical "never
public" repo — that gate is reversed per ADR-0035 (per-env state is operator-local).

## DONE (committed)

### Workstream C — ADR digests (umbrella `9dbdccb` plan/spec, `0a8ba77` digests)
- 4 canonical digests under `docs/decisions/digests/` (identity, secrets-and-unseal,
  catalog-and-execution, deployment-scope-and-release) with verbatim ADR-cited bullets.
- Canonical-pointer headers prepended to superseded/amended ADRs **0004, 0011,
  0016, 0024, 0027** (bodies unchanged). INDEX theme-cluster table wired to the digests.
- Portfolio-review nits were already fixed (verify-only). No code touched.

### Workstream B — dmf-env public scrub (dmf-env `1827085`, umbrella `641ebf1`)
- Removed all env data (`inventories/`, `manifests/`, retired `aliyun-media` spike),
  dropped-provider assets (aliyun/aws roots+modules+tasks, broken `aws-sample`),
  `agentic/`, operator-notes docs, `DEPLOYMENT.md`.
- **Full-cleaned the legacy dual-layout resolver** — env state is operator-local
  only (`~/.dmfdeploy/envs/<env>/`); `DMF_ENV_LAYOUT` is always `new`. Disabled the
  stale `bootstrap-secrets init` (hard-error → use init-wizard.sh) + removed dead
  legacy helpers. Hetzner-only guards on tf-apply/tf-destroy (reject sandbox before
  `TF_DIR`). Removed old-layout `b2-diag.sh`.
- Scrubbed every retired env-id + operator identity; rewrote README / terraform-README
  / CLAUDE / QWEN for the public generic posture.
- **New gate: `bin/dmf-env-public-surface-gate.sh`** (umbrella) — fail-closed:
  anchored path-depth allowlist + ban list + retired-name scan + custom DMF rules
  (operator-identity / internal-topology / dev-credential rules via **`git grep`**, covering
  tracked hidden files) + default gitleaks. Allowlisted in `.gitleaks.toml`.
- **Verification:** all 4 dmf-env unit tests pass; identity/old-layout sweep empty;
  gate reports `OK — dmf-env tree is public-safe`; codex agreed.
- Spec: `docs/plans/DMF Workstream B — dmf-env Public-Surface Scrub Spec 2026-06-09.md`.

## NEXT — Workstreams A, D, E (not started)

Each needs its own execution spec + codex cross-check before lifting. Suggested
order: **D (low-risk governance docs) → A (the actual import) → E (CI)**, but A and
D are largely independent. See the master plan for the full step lists.

### A — Clean history import + canonical flip (per repo, except dmf-runbooks)
- dmf-runbooks is **already public at v0.1.2** — release forward, never rewrite.
- Build the **export-scan harness**: stage each repo's clean orphan-commit export
  under a predictable path; **bake governance + CI files INTO the export tree
  before the orphan commit** (so the public repo starts at exactly 1 scanned
  commit); run scrub + commit-author + gitleaks + hygiene on that exact tree. For
  `dmf-env`, also run `bin/dmf-env-public-surface-gate.sh`.
- `sync-to-github.sh` is an **import-only** tool (hardcodes v0.1.0, excludes
  dmf-promsd, commit-author allowlist rejects external authors) — use for the
  initial import, then retire/replace. It needs dmf-promsd added (whitelist +
  `github_repo_name()`) for the import.
- Import to **private** GitHub repos first → verify 1 commit/no archive refs →
  locked-window public flip → set branch+tag rulesets (protect `v*`, block
  `archive/*`) + native secret scanning → retire Forgejo to `<repo>-archive`.

### D — GitHub-first governance
- Rewrite each repo's `CONTRIBUTING.md` (the existing ones describe the OLD
  Forgejo-canonical / "no direct push to GitHub" model). Carry forward the rules
  from `docs/architecture/DMF Release and Contribution Model.md` §5–§7.
- Add `SECURITY.md` + private vuln reporting; `.github/` issue+PR templates with a
  "never paste secrets/IPs/operator identity" banner; confirm CODEOWNERS; wire the
  **DCO** check; promote the Release & Contribution Model doc to **ADR-0018**.

### E — CI/CD (hosted runners only)
- E1 (before flip): per-repo PR gates — gitleaks, scrub, lint, commitlint, trivy;
  fork-PR hardening (`pull_request` not `pull_request_target`, `permissions:
  read-all`, no PR-job secrets, SHA-pinned actions, base-branch/locked reusable
  workflow); validate the dmf-init image build against the 14 GB hosted-runner disk.
- E2 (after flip): `release.sh` (VERSION→tag→GHCR) + an **umbrella release
  manifest** (pinned per-repo SHAs) as the compatibility gate. The dmf-init Forgejo
  workflow is host-agnostic and ports with a `runs-on:` change.

## Orchestration model (how this work is run)

- **claude (umbrella session)** = orchestrator + verifier. Writes specs, verifies
  every qwen claim against the tree (grep-proof + re-runs tests), integrates,
  commits. **Do not trust a DONE report** — re-verify (qwen has a history of
  confident-but-wrong claims; this session it falsely reported the gate "public-safe").
- **qwen-left** = the lift (mechanical + spec'd logic edits). `/clear` it before
  each new slice; pair with a self-contained on-disk spec. Dispatch via the
  **agent-bridge** skill (`~/.claude/skills/agent-bridge/bin/agent-bridge`). If it
  wedges on a retry prompt, unwedge with `tmux send-keys -t %0 C-y` (don't take over).
- **codex** = independent adversarial cross-check, until codex + claude agree. It
  reads the repo, not just the prompt — give it concrete questions; expect multiple
  rounds (B's spec took 4). Reply protocol is auto-stamped by agent-bridge.

## Key gotchas / non-obvious

- **`.gitleaks.toml` allowlist:** any new file that *intentionally* contains the
  operator-identity / topology / dev-credential patterns (e.g. the surface-gate,
  spec docs with the patterns in their grep) must be added to the matching per-rule
  `[[rules.allowlists]]` or the umbrella pre-commit hook blocks the commit.
- **Gate-tool lessons (baked into `dmf-env-public-surface-gate.sh`):** scan ALL
  tracked files (no per-file exemption — that's a permanent false-pass); use
  `git grep`, not `rg` (rg skips hidden files like `.sops.yaml`); anchored
  path-depth allowlist (`^tests/[^/]+$`) so nested fixtures fail closed.
- **dmf-env keeps its name** — do not rename to `dmf-env-tools` (runtime hardcodes
  the checkout dir: `dmf-init/src/dmf_init/{bootstrap_steps.py:224,main.py:399}`).
- **No live env** exists (all retired) — dmf-env changes are validated by its 4 unit
  tests + the gate + codex, not a live run.

## Doc index (where everything lives)

- Master plan: `docs/plans/DMF First Public Release Plan 2026-06-09.md`
- C spec: `docs/plans/DMF Workstream C — ADR Digest Execution Spec 2026-06-09.md`
- B spec: `docs/plans/DMF Workstream B — dmf-env Public-Surface Scrub Spec 2026-06-09.md`
- ADR digests: `docs/decisions/digests/`
- Surface gate: `bin/dmf-env-public-surface-gate.sh`
- Import tool (import-only): `bin/sync-to-github.sh`; scrub: `bin/scrub-public-repos.sh`
- Release/contribution model (→ ADR-0018): `docs/architecture/DMF Release and Contribution Model.md`
- 2026-05-07 publish-prep gates (still relevant for A): `docs/handoffs/DMF Public Publish Readiness Handoff 2026-05-07.md`
- Memory: `project_first_public_release_plan` (locked decisions + progress).

**Resume at:** pick Workstream D or A, write its execution spec, codex-review it,
then dispatch qwen.
