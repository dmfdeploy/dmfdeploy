# DMF Release and Contribution Model

**Status:** Accepted — ratified as ADR-0041 (2026-06-09)
**Date:** 2026-05-07
**Audience:** human contributors and LLM agents working in any DMF repo

This is the canonical answer to "where does it go, how does it move, and what
must never leak." It codifies the four public-push decisions (2026-05-07) and
the three control layers — **structural**, **procedural**, **defensive** —
that bound every contribution.

---

## 1. Repository topology

| Repo | Public? | Role |
|---|---|---|
| `dmfdeploy` (umbrella) | Public | Docs, ADRs, plans, handoffs, skills, status |
| `dmf-cms` | Public | Operator console (React + FastAPI) |
| `dmf-runbooks` | Public | AWX launcher playbooks + catalog NetBox-side roles (Path A for 693-class infra plays; EE-as-runtime + Helm chart for `media-*` JTs per [ADR-0025](../decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md), 2026-05-19) |
| `dmf-infra` | Public | Generic Ansible playbooks/roles |
| `dmf-central` | Public | Central services scaffolding |
| `dmf-media` | Public | Media-domain catalog metadata + future Layer 5 roles |
| `dmf-init` | Public | Day-0 stateless init/bootstrap container (React + FastAPI) |
| `dmf-env` | **Public (sanitized generic surface — ADR-0035)** | Generic environment tooling: `bin/` scripts, `terraform/modules/`, neutral `tasks/`/`templates/`. Per-env state is operator-local and never committed. |
| `dmf-promsd` | Public | NetBox-driven Prometheus service-discovery (dynamic monitoring targets) |

GitHub destination: **`github.com/dmfdeploy/<repo>`** (org `dmfdeploy`).
**GitHub `main` is the single source of truth** — all forward work lands via
Pull Requests against `main`. Forgejo is archive-only: LAN Forgejo repos
(`<repo>-archive`) are read-only history snapshots, not an upstream or
contribution path. `bin/sync-to-github.sh` was a one-time import tool and
is now retired. No agent or human pushes directly to `main`.

## 2. License

**Apache 2.0** in every public repo. Each public repo carries:
- `LICENSE` (Apache 2.0 verbatim) at root
- `NOTICE` listing upstream-derived components (e.g. `sony/nmos-cpp` images)
- `## License` section in `README.md`: name, link to `LICENSE`, attribution note

For files materially derived from another open-source project: standard SPDX
header and a `NOTICE` entry. We don't relicense; we attribute.

## 3. Where things live (structural)

| Artifact type | Canonical location |
|---|---|
| Architecture references | `dmfdeploy/docs/architecture/` |
| Architecture Decision Records | `dmfdeploy/docs/decisions/` (numbered, indexed) |
| Plans (dated, scoped work) | `dmfdeploy/docs/plans/` (must carry supersession header when overtaken) |
| Handoffs (session intent) | `dmfdeploy/docs/handoffs/` (most recent is canonical) |
| Reviews / audits / sessions | `dmfdeploy/docs/{reviews,audits,sessions}/` |
| Skills (operational procedure) | `dmfdeploy/.claude/skills/<name>/SKILL.md` |
| Cross-repo state | `dmfdeploy/STATUS.md` (auto + `<!-- HUMAN-START -->` block) |
| Code, charts, roles | Component repos only — never in umbrella |
| Per-repo agent guidance | Repo-local `CLAUDE.md` / `AGENTS.md` (boot ritual + repo-specific only; cross-cutting state stays in umbrella) |

**No artifact lives in two places.** When something moves, the source side
gets a one-line pointer with a date.

## 4. Versioning & releases (procedural)

- **VERSION file at repo root in every public repo.** Single source of truth
  for the repo's release version (already established per ADR-0005).
- **SemVer.** Patch for bugfixes, minor for features, major for breaking changes.
- **Conventional Commits** (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`,
  `test:`, `build:`, `ci:`) — required on `main`. Other prefixes rejected by CI.
- **CHANGELOG.md** generated from commits at release time
  (`bin/generate-changelog.sh` per repo, idempotent).
- **Release tag = `v<VERSION>`** matching `VERSION` exactly. Tag is created by
  `bin/release.sh` after CI passes; nobody tags by hand.
- **No version bump → no release.** A merged PR that doesn't change `VERSION`
  ships nothing on its own.

## 5. Branch & review model (procedural)

- `main` is default in every repo. No `master` anywhere (cleaned up 2026-05-07).
- **Direct push to `main` is blocked on every public repo** (GitHub branch
  protection). PRs only.
- **Topic branch naming:** `<initials-or-handle>/<short-slug>` (e.g.
  `<handle>/release-model-impl`, `<handle>/nmos-spike`). Keep slugs short and
  hyphen-separated; one branch per logical change. Long-lived feature
  branches discouraged — rebase frequently against `main`.
- **Required status checks** before merge: `lint`, `test`, `secrets-scan`,
  `commit-message-lint` (Conventional Commits). Linear history required.
- **Cross-repo work**: umbrella plan or handoff lands first; then per-repo PRs
  reference it by path.
- **Subrepo dirty state requires user approval to modify** (already in
  CLAUDE.md boot ritual; reinforced here).
- **External contributor flow — RESOLVED.** GitHub-first PRs with DCO.
  Contributors (human or agent) fork or branch, open PRs against `main` on
  GitHub, sign off all commits (`git commit -s`), and pass required CI checks
  (DCO, Conventional Commits, secrets scan). No Forgejo round-trip path is
  needed — GitHub is canonical.

## 6. Defensive (security)

Three concentric layers. None individually sufficient; together they make a
secret leak require defeating all three.

1. **Pre-commit (local)** — `gitleaks` runs on every commit; refuses on hit.
   Hook installed via `bin/install-hooks.sh` (already exists; extend it).
2. **Pre-receive (Forgejo, server-side)** — `gitleaks` runs on every push.
   Cannot be bypassed with `--no-verify`.
3. **CI (GitHub Actions on the public mirror)** — `gitleaks` + `trivy`
   filesystem scan on every PR and on the `main` branch tip after every push.

**Baseline `.gitignore` at every repo root** must block:
```
*.kubeconfig
*.tfstate
*.tfstate.*
.terraform/
hosts.ini
openbao-*
*.pem
*.key
secret_id*
.env
.env.*
```
**CODEOWNERS at every public repo root** protects high-risk paths
(`bin/run-playbook.sh`, anything matching `*openbao*`, `*shamir*`,
`*tfstate*`, `inventories/`, `terraform/`) requiring `@<handle>` review.

**Forbidden in public repos under any circumstance:**
- Cluster IPs (Hetzner external + LAN `<lan-ip>`)
- `dmf.example.com` hostnames (or any `*.<lan-host>`)
- Plaintext credentials in remote URLs (the `dev:changeme` smell)
- Kubeconfigs, Terraform state, AWX project tokens, OpenBao share material

The pre-publish scrub (run by `bin/sync-to-github.sh`) is what enforces this
list — an explicit allowlisted set of patterns; failure aborts the push.

## 7. LLM agent contract

Agents have additional rules on top of the above. Codified in
`.claude/settings.json` (and equivalent for other agent runtimes), enforced
via Claude Code's permission hooks.

**Agents must:**
- Run the boot ritual (CLAUDE.md §1) at session start
- Read the relevant skill `§0` before any cluster, secrets, or release operation
- Use `bin/run-playbook.sh` for cluster mutation (ADR-0010)
- Use `bin/sync-to-github.sh` for any GitHub push
- Stop and ask before touching a sub-repo with dirty state
- Stop and ask before any operation marked 🔴 in `dmf-cluster-access`

**Agents must never:**
- Use `--no-verify`, `--force`, `--no-gpg-sign` on git commands
- Run `kubectl apply`, `kubectl patch`, `helm upgrade` directly (playbook only)
- Write into the operator's secure-store mount (`<secure-store>/`) or any path under `/etc/rancher/`
- Echo, cat, or pipe a secret to stdout (skill §0 of `dmf-cluster-access`)
- Push directly to `main`, including via `git push --set-upstream`
- Create or modify GitHub Actions workflows without operator review
  (CODEOWNERS-protected)

These are enforced by Claude Code hooks where possible; the rest is reviewed
via CODEOWNERS on `.github/` and `bin/`.

## 8. Enforcement summary

| Rule | Enforced by |
|---|---|
| Apache 2.0 + LICENSE present | `bin/check-public-repo-hygiene.sh` (CI) |
| Conventional Commits | `commitlint` in CI |
| VERSION drift = no release | `bin/release.sh` reads `VERSION`; tag mismatch = fail |
| No secrets in commits | `gitleaks` (pre-commit + CI); DCO on PRs |
| No forbidden patterns in public repos | CI gitleaks/scrub gates; CODEOWNERS review |
| Branch protection (no direct main push) | GitHub repository rulesets |
| Linear history | GitHub repository rulesets (rebase-merge only) |
| Sub-repo dirty state respected | Boot ritual + agent settings hook |
| Cluster ops only via playbook | ADR-0010 + agent settings denylist |

Anything not enforced by a script or CI gate is **discipline only** and will
drift. We add a row to this table whenever a new invariant becomes load-bearing.

---

## Ratified as ADR-0041 (2026-06-09)

This doc was accepted and promoted to ADR-0041. Resolved follow-ups:

- ~~Per-repo `CONTRIBUTING.md` with the MUST / MUST NOT distillation~~ — done (Workstream D).
- ~~Resolve the §5 external-contributor model~~ — resolved: GitHub-first PRs with DCO.

Remaining CI / governance items (Workstreams A + E1/E2):

- Wire Conventional Commits + commitlint in CI (E1).
- Stand up the GitHub `dmfdeploy` org and configure branch protection / rulesets (A).
- Per-repo VERSION audit (every public repo must have one) — dmf-env added 0.1.0.
