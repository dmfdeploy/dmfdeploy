# Contributing to dmfdeploy

This repository is the umbrella for the dmfdeploy platform. It holds the
knowledge base (`docs/`), the decision records, the plans, and the agent
skills. Code lives in the component repos, and they follow the same rules.

## How to contribute

1. **Get oriented.** Read [`docs/THESIS.md`](docs/THESIS.md) for what the
   platform claims, then the [core decisions](docs/decisions/INDEX.md#start-here)
   marked ★. [`docs/OPEN-QUESTIONS.md`](docs/OPEN-QUESTIONS.md) lists what is
   frozen, unproven, or undecided.
2. **Find work.** The backlog is
   [GitHub Issues](https://github.com/dmfdeploy/dmfdeploy/issues), grouped
   into [milestones](https://github.com/dmfdeploy/dmfdeploy/milestones) as
   described in [ROADMAP.md](ROADMAP.md). Comment on an issue to claim it, or
   open a new one. Ask questions in the
   [Q&A category](https://github.com/dmfdeploy/dmfdeploy/discussions/categories/q-a)
   of Discussions.
3. **Propose a change.** A bug fix or a small change needs only its issue.
   A substantial decision across repos starts as an RFC in Discussions; the
   [RFC process](docs/decisions/README.md) explains the steps.
4. **Open a pull request.** Fork or branch, then open a pull request against
   `main`. Sign off every commit (see [DCO](#developer-certificate-of-origin-dco)),
   and wait for the checks to pass. If the pull request completes an umbrella
   issue, write `Closes dmfdeploy/dmfdeploy#N` in its description.

## How work is tracked

The canonical rules for issues, milestones, the project board, Discussions,
and documents are in [`docs/WORKING-MODEL.md`](docs/WORKING-MODEL.md). The
parts that matter for most pull requests:

- Non-trivial work gets a plan in `docs/plans/` with `tracking_issue`
  frontmatter.
- A fully qualified `Closes dmfdeploy/dmfdeploy#N` lets the daily
  issue-close reconciler close the umbrella issue, from any repo. Closing
  the issue by hand is a fallback.
- The reconciler never touches plan frontmatter. Update it by hand in the
  same pull request.

Issues are canonical for liveness, and plan frontmatter is canonical for
design state.

GitHub is the single source of truth, and every change lands through a pull
request against `main`. An older private archive of the pre-publish history
exists. It is read-only and is never a contribution path.

## Architecture decisions

Cross-cutting decisions live as ADRs in `docs/decisions/`, listed in the
[decision index](docs/decisions/INDEX.md). The
[RFC process and the ADR conventions](docs/decisions/README.md) describe how
to propose one and what every ADR carries.

## Branch & PR model

- **GitHub Pull Requests only.** Direct push to `main` is blocked; force-push is
  banned; linear history is required.
- Topic branches: **`<handle>/<short-slug>`** (for example, `jdoe/fix-probe-path`). One
  logical change per branch; rebase onto `main` rather than long-lived branches.
- **Conventional Commits** (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`,
  `test:`, `build:`, `ci:`) are **required** on `main` and checked in CI. Other
  prefixes are rejected.
- A reviewer (per `CODEOWNERS`) and green required checks are needed to merge.

## Developer Certificate of Origin (DCO)

We use the [Developer Certificate of Origin](https://developercertificate.org/).
We do not use a CLA. **Every commit must be signed off:**

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
**ADR-0005**, `VERSION` is the single source of truth in each component repo.
Any release-tagged change must update it in the same commit. **No VERSION bump → no
release tag.** Release tags are `v<VERSION>`, created by release automation, never by
hand. The project publishes git tags. It has no GitHub releases.

## Secrets & public-safety posture

**Secrets stay in OpenBao.** Never commit, track, or reference credentials, tokens,
keys, kubeconfigs, or Terraform state, even with a "remove later" TODO. Use
**placeholder syntax** for any IPs, DNS names, or operator identity in code, docs,
PR descriptions, or issues (`<control-node-public-ip>`, `dmf.example.com`,
`<handle>`). A local pre-commit gitleaks hook runs on commit, and CI runs
secret-scanning + scrub gates on every PR, but redaction is your responsibility
first. If you need a secret, ask a maintainer. Do not improvise a transport.

## Must / Must not

### MUST
- Open changes as **GitHub PRs against `main`** with **signed-off** commits.
- Use Conventional Commit messages and `<handle>/<short-slug>` topic branches.
- Before you change any dmfdeploy repo, read the operator notes in pinned issue [#618](https://github.com/dmfdeploy/dmfdeploy/issues/618), the comments on the issue you claimed, and the ADRs that apply. For the live state of the repos, run `bin/generate-status.sh`. [STATUS.md](STATUS.md) only points to where current state lives.
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
model is **ADR-0041** (DMF Release and Contribution Model) in the dmfdeploy
umbrella repo (`docs/decisions/`).
