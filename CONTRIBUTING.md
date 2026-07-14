# Contributing to dmfdeploy (umbrella)

The umbrella workspace for the DMF Platform: consolidated knowledge base (`docs/`), ADRs, plans, skills, and cross-repo status (handoffs are archived in `docs/handoffs/`; live progress is issue comments). Code lives in the component repos.

This repo is part of the **DMF Platform**. GitHub is the canonical home and the
single source of truth: all changes land via **Pull Request** against `main`.
(The full pre-publish history lives in a LAN-only `dmfdeploy-archive` Forgejo
repo, reachable as a read-only `archive` git remote — it is **not** an upstream
and is never a contribution path.)

## New contributor path

1. **Orient:** [`docs/THESIS.md`](docs/THESIS.md) (what this is) →
   [`docs/JOURNEY.md`](docs/JOURNEY.md) (how it got here) →
   [`docs/decisions/INDEX.md#start-here`](docs/decisions/INDEX.md#start-here) (the
   core ADRs that bind you, marked ★). [`docs/OPEN-QUESTIONS.md`](docs/OPEN-QUESTIONS.md)
   tells you honestly what is frozen, unproven, or undecided.
2. **Find work:** the live backlog is
   [GitHub Issues](https://github.com/dmfdeploy/dmfdeploy/issues), scheduled on
   the [org project board](https://github.com/orgs/dmfdeploy/projects/1).
   Questions go to [Discussions](https://github.com/dmfdeploy/dmfdeploy/discussions) (Q&A).
   The canonical statement of how Issues/milestones/board/Discussions and the
   documentation rules fit together is
   [`docs/WORKING-MODEL.md`](docs/WORKING-MODEL.md) — read it once.
3. **Do the work:** claim or open an issue; non-trivial work gets an on-disk
   spec in `docs/plans/` carrying `tracking_issue` frontmatter. The completing
   PR carries a fully-qualified `Closes dmfdeploy/dmfdeploy#N` reference — the
   daily `issue-close-reconciler` auto-closes the umbrella issue from it
   (cross-repo included), and manual close is a fallback only. You still flip the
   plan's frontmatter by hand in that same PR (the reconciler never touches it).
   (Issues are canonical for liveness; frontmatter for design state.)
4. Fork or branch, open a PR against `main`, CI green, commits **signed off**
   (see DCO below).

## Proposing architecture: the RFC → ADR pipeline

Cross-cutting decisions live as ADRs in `docs/decisions/` (see
[INDEX.md](docs/decisions/INDEX.md)). To propose one:

1. Open an **RFC thread** in Discussions (category: *RFC*) describing context,
   options, and your recommendation. Substantial design debate happens there.
2. When it converges, write the ADR (copy `docs/decisions/0000-template.md`,
   next free number) and open a PR linking the RFC thread.
3. When the ADR merges, post an **announcement thread** in Discussions for that
   ADR (one thread per ADR going forward; the pre-existing back-catalog is
   covered by the pinned "Decision record" index thread).

Small, single-repo decisions don't need this — use the issue itself.

### ADR conventions

Every ADR (copy `docs/decisions/0000-template.md`) carries:

- a top-of-doc **Rule:** line — the binding constraint in one imperative sentence,
  so a reader gets the obligation without reading the whole doc;
- an **Enforcement** section (`## Enforcement`) — how the decision is kept honest
  (script / CI gate / skill), or "discipline only" stated explicitly;
- filename `NNNN-kebab-title.md` (monotonic number) and an Index row in
  [`docs/decisions/INDEX.md`](docs/decisions/INDEX.md); the core ADRs newcomers
  must read are marked **★** there.

## Branch & PR model

- **GitHub Pull Requests only.** Direct push to `main` is blocked; force-push is
  banned; linear history is required.
- Topic branches: **`<handle>/<short-slug>`** (e.g. `jdoe/fix-probe-path`). One
  logical change per branch; rebase onto `main` rather than long-lived branches.
- **Conventional Commits** (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`,
  `test:`, `build:`, `ci:`) are **required** on `main` and checked in CI. Other
  prefixes are rejected.
- A reviewer (per `CODEOWNERS`) and green required checks are needed to merge.

## Developer Certificate of Origin (DCO)

We use the [Developer Certificate of Origin](https://developercertificate.org/),
not a CLA. **Every commit must be signed off:**

```bash
git commit -s -m "fix: correct the probe path"
```

This appends a `Signed-off-by: Your Name <you@example.com>` trailer certifying you
have the right to submit the work under the project license. A **DCO check** runs
on every PR and fails if any commit is missing the trailer. Amend with
`git commit --amend -s` or rebase with `git rebase --signoff main` to fix. PRs are
**rebase-merged** by default so your signed-off commits land on `main` unchanged.

## Versioning & releases

Component repos carry VERSION files; the umbrella holds docs/ADRs/plans. Per
**ADR-0005**, `VERSION` is the single source of truth in each component repo —
any release-tagged change must update it in the same commit. **No VERSION bump → no
release.** Release tags are `v<VERSION>`, created by release automation, never by
hand.

## Secrets & public-safety posture

**Secrets stay in OpenBao.** Never commit, track, or reference credentials, tokens,
keys, kubeconfigs, or Terraform state — not even with a "remove later" TODO. Use
**placeholder syntax** for any IPs, DNS names, or operator identity in code, docs,
PR descriptions, or issues (`<control-node-public-ip>`, `dmf.example.com`,
`<handle>`). A local pre-commit gitleaks hook runs on commit, and CI runs
secret-scanning + scrub gates on every PR — but redaction is your responsibility
first. If you need a secret, ask a maintainer — do not improvise a transport.

## Must / Must not

### MUST
- Open changes as **GitHub PRs against `main`** with **signed-off** commits.
- Use Conventional Commit messages and `<handle>/<short-slug>` topic branches.
- Follow the boot ritual (read STATUS.md, the claimed tracking issue's comments, ADRs) before touching any DMF repo.
- Use **placeholder syntax** for all IPs / DNS / operator identity in every artifact.

### MUST NOT
- Commit secrets, tokens, keys, kubeconfigs, or Terraform state.
- Push directly to `main`, force-push, or use `--no-verify` / `--no-gpg-sign`.
- Paste secrets, real IPs/DNS, or operator identity into issues, PRs, or CI logs.

## AI agent contract

Much of this platform is built by AI agents. Agents contribute the same way:
**PRs against `main`, signed off, CI green.** Additionally, agents must run cluster
mutation only via `bin/run-playbook.sh` (ADR-0010), must not use
`--no-verify`/`--force`/`--no-gpg-sign`, and must stop and ask before modifying a
sub-repo with uncommitted state.

## Reporting security issues

See [`SECURITY.md`](SECURITY.md). **Do not** open a public issue for a vulnerability.

## License & spec

Contributions are licensed under [Apache 2.0](LICENSE). The canonical governance
model is **ADR-0041 — DMF Release and Contribution Model** in the dmfdeploy
umbrella repo (`docs/decisions/`).
