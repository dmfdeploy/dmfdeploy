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
4. **Set up and run the checks.** [Develop and test](#develop-and-test) lists
   the prerequisites and the commands CI runs.
5. **Open a pull request.** Fork or branch, then open a pull request against
   `main`. Sign off every commit (see [DCO](#developer-certificate-of-origin-dco)),
   link the issue as [What a pull request needs](#what-a-pull-request-needs)
   describes, and wait for the checks to pass. If the pull request completes an
   umbrella issue, write `Closes dmfdeploy/dmfdeploy#N` in its description.

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

## Develop and test

This section is the one place for setup and test commands. The README,
`AGENTS.md` and the other docs point here. The one test command, `bin/check.sh`,
is the command that the CI jobs run. Where CI doesn't run a check, the text
says so.

### Prerequisites

- **Python 3.11 or later.** `bin/gen-gitleaks-rules.py` reads TOML with the
  standard library's `tomllib`, which first shipped in 3.11. The checks need no
  Python packages, so you don't need a virtual environment.
- **bash and git.** The checks run on the bash 3.2 that macOS ships and on
  newer versions.
- **[ShellCheck](https://www.shellcheck.net/)**, for the `shellcheck` step.
- **`jq` and `ruby`.** The hygiene checks and the ruleset test use them.
  macOS includes `ruby`.
- **Network access.** The first run of `bin/dmf-scan self-test` downloads a
  pinned release of gitleaks into your temporary directory and checks its
  checksum. The secret-scan checks use that copy and ignore any gitleaks that
  you installed.
- **[Vale](https://vale.sh/) 3.25.1 or later**, for the voice checks. CI
  installs 3.26.0. With an older version, `tests/voice-changed-links.sh` fails.

You don't need a cluster, a cloud account, secrets, or a container runtime. The
tests use fixtures and stand-in commands for `gh`, `helm` and `docker`.

### Set up

Run these commands from a fresh clone. The first one confirms the Python
version, and `vale sync` fetches the Google style package that `.vale.ini`
uses. The package isn't committed.

```bash
git clone https://github.com/dmfdeploy/dmfdeploy.git
cd dmfdeploy
python3 --version
vale sync
```

### Run the checks

Run this command from the repository root before you push:

```bash
bin/check.sh
```

The script runs the steps of the `shellcheck`, `review-comments`, `check-docs`,
`skills-sync`, `surface`, `static` and `vale` jobs, and each of those jobs
calls `bin/check.sh` with its step name. Other required checks, such as the
secret scans and the commit checks, run in CI only; see [Checks that need more
than a checkout](#checks-that-need-more-than-a-checkout). A green local run is
good evidence that the matching CI job passes, though your tool versions and
platform can differ from the CI runner's. To run only the steps that match your
change, name them:

```bash
bin/check.sh surface vale
```

Before it runs anything, the script checks that the steps you chose have their
tools, and it lists what is missing. Run times come from one laptop:

| Step | What it runs | CI job | Time |
| --- | --- | --- | --- |
| `shellcheck` | ShellCheck over the scripts, then the self-tests and regression tests of the other gates, including the acceptance matrix and the secret-scan library | `shellcheck` in `ci.yml` | About two minutes |
| `review-comments` | The check that rejects review history in comments, and its self-test | `review-comments` in `ci.yml` | About half a minute |
| `check-docs` | The plans index, the doc gate and the working-model block | `check-docs` in `ci.yml` | A few seconds |
| `skills-sync` | The check that `.agents/skills/` is the only tracked skills store | `skills-sync` in `ci.yml` | A few seconds |
| `surface` | The fixture tests, then size budgets, filenames, archive placement, the status log and ADR enforcement, each in strict mode | `surface` in `surface.yml` | About 50 seconds |
| `static` | The issue forms, `CODEOWNERS` and the PR template, then the fixtures for those checks | `static` in `title-check.yml` | A few seconds |
| `vale` | The voice checks: the whole tree, the clean set, the fixtures, and the mutation test | `vale` in `vale.yml` | About half a minute |

The `shellcheck` job runs the regression tests for the other gates, which is
more than its name says. Its step also confirms that
`.github/expected-ruleset.json` holds the keys that the drift check reads.

CI runs the `vale` step only when your pull request changes a path that the
scope step in `vale.yml` lists, such as a README, an ADR, or a file under
`.github/`. On a pull request, that step also compares the files you touched
with the base branch, so that none gains an error-level voice alert. To run
that comparison, commit your change, then run
`VOICE_RATCHET_BASE=origin/main bin/check.sh vale`. To lint a draft before you
commit it, run `bin/check-voice.sh FILE`.

### Checks that need more than a checkout

None of the preceding checks needs a live cluster, cloud credentials, or an
image build. These checks need something else:

| Check | What it needs | Runs in |
| --- | --- | --- |
| `actionlint`, `trivy`, `gitleaks` over the pull request's commits | A pinned tool that the workflow downloads, and the pull request's commit range | CI only |
| `commitlint`, `dco`, `issue-link`, `title` | The pull request's commits, body, labels, and title from GitHub | CI only |
| `pr-body-lint` | The pull request body. It posts an advisory comment and never blocks a merge. | CI only |
| `governance-drift` | The live branch ruleset. Runs daily. | CI only |
| `backlog-hygiene` | The live issues. Runs daily. Its `--self-test` runs offline. | CI only |
| `bin/publish-image-to-ghcr.sh`, `bin/publish-chart-to-ghcr.sh` | Container tooling or Helm, and registry credentials | A maintainer's machine. No workflow calls them. |

[`docs/WORKING-MODEL.md`](docs/WORKING-MODEL.md) section 7 lists every check
with its trigger and says which ones block a merge.

The `bin/check-live-env-leak.sh` gate compares your change with the
environment identifiers in the operator-local store. Without that store, it
announces that it skipped the check.

### Install the hooks

Maintainers run this once in each clone:

```bash
bin/install-hooks.sh
```

The script sets `core.hooksPath` to `.githooks/`. The `pre-commit` hook scans
the staged changes for secrets and live environment identifiers. Then it runs
only the doc gates that your staged paths can affect: the scripts catalog, the
plans index, `check-docs`, the surface checks, the working-model block and the
skills sync. The `pre-push` hook scans the commits you push. To skip the doc
gates for one commit, set `STATUS_HOOK_SKIP=1`. That never skips the secret
scans.

The secret scans need a pattern manifest that only maintainers hold, at
`~/.dmfdeploy/pattern-manifest.private.toml`. To keep it somewhere else, set
`DMF_PATTERN_MANIFEST_PRIVATE`. Without the manifest, both hooks refuse every
commit and push with a `CONFIG_ERROR` message. If you don't have it, skip
`bin/install-hooks.sh`. CI runs the public secret scans on every pull request,
and `bin/check.sh` covers the doc gates except the scripts catalog check that
the next paragraph describes. When you add a script under `bin/` or `tests/`
or change its header comment, run `bin/generate-scripts-catalog.sh --check`
yourself.

The scripts catalog `docs/SCRIPTS.md` lists the scripts of the component repos
too. When your commit touches `bin/` or `tests/`, the hook checks that the
catalog is current, and that check fails unless the component repos sit next to
this one. CI doesn't check the catalog. After you add a script or change its
header comment, run `bin/fix-docs.sh` with the component repos in place to
regenerate it.

## Branch & PR model

- **GitHub Pull Requests only.** Direct push to `main` is blocked; force-push is
  banned; linear history is required.
- Topic branches: **`<handle>/<short-slug>`** (for example, `jdoe/fix-probe-path`). One
  logical change per branch; rebase onto `main` rather than long-lived branches.
- **Conventional Commits** are **required** on `main` and checked in CI. The
  [next section](#what-a-pull-request-needs) lists the accepted types.
- A reviewer (per `CODEOWNERS`) and green required checks are needed to merge.
  [`docs/WORKING-MODEL.md`](docs/WORKING-MODEL.md) section 7 lists the required
  checks.

## What a pull request needs

CI checks each of these.

- **An issue link in the PR body.** Write a fully qualified reference to an
  issue in the [dmfdeploy/dmfdeploy](https://github.com/dmfdeploy/dmfdeploy/issues)
  backlog, such as `Refs dmfdeploy/dmfdeploy#912`. Use `Closes dmfdeploy/dmfdeploy#N`
  if the pull request finishes the issue. The component repos reject a bare
  `#N`, because it points at their own repo. This repo's check accepts it, but
  use the qualified form everywhere. The check also accepts `Fixes`,
  `Resolves` and an issue URL. If your change has no issue, such as a typo fix,
  a maintainer can add the `no-issue` label. Only people with triage access can
  add labels, so if you open the pull request from a fork, ask in the PR. The
  check runs again when you edit the body or when a label changes. The label
  skips the reference check only. A closing keyword next to a negation, such as
  `does not close`, still fails, and so does a link to an agent session.
- **A DCO sign-off on every commit.** Use `git commit -s`. See the
  [next section](#developer-certificate-of-origin-dco).
- **Conventional commit subjects.** Use `type(scope): summary`, with one
  optional scope. The scope may use only `a-z`, `0-9`, `.`, `_` and `-`. The
  types are `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `build`, `ci`,
  `perf`, `revert` and `style`. An `!` before the colon marks a breaking
  change. Other types, such as `wip`, are rejected, and so is a scope list such
  as `(api,ui)`. A commit message that links to an agent session fails too.
- **A title without an `[auto]` prefix.**
- **Passing CI.** The checks in [Develop and test](#develop-and-test) are the
  ones CI runs, plus the scans in the table there that need GitHub.
- **A plan update, when your change completes a plan.** Set the plan's
  frontmatter in the same pull request. See [How work is tracked](#how-work-is-tracked).

The voice check on the PR title and body is advisory. It posts a comment and
never blocks the merge.

## Match the evidence to the change

Show a reviewer what proves your change, in proportion to its size.

- **A docs edit** needs `bin/check.sh check-docs surface vale` and
  `bin/check-voice.sh` on the files you wrote. It doesn't need a test.
- **A script, workflow or check change** needs a test that fails on the old
  behavior and passes on the new one, in `tests/`. Paste the runner's summary
  line into the PR description. If a gate has a fixture set, add a bad fixture
  that the gate must reject.
- **A fix for a defect class** needs a search for siblings. Search the repo for
  the pattern's signature, and say in the PR description whether each match is
  affected. The fix is not done until the siblings are listed.
- **A change you can't run here**, such as one that needs a live environment,
  says so in the PR description, along with what you ran instead.

## Representative tasks

Each task says whether you can do and test it offline or whether it needs a
live environment.

| Task | Offline or live | Where to start |
| --- | --- | --- |
| Fix or improve a page in `docs/` | Offline | Edit the page, then run `bin/check.sh check-docs surface vale` and `bin/check-voice.sh` on it. |
| Propose an architecture decision | Offline | Start an RFC in Discussions, then copy `docs/decisions/0000-template.md`. See [the RFC process](docs/decisions/README.md). Run `bin/check.sh check-docs`. |
| Write or update a plan | Offline | Add the file to `docs/plans/` with `tracking_issue` frontmatter. Run `bin/fix-docs.sh` to regenerate the index, then `bin/check.sh check-docs`. |
| Fix or extend a script in `bin/` | Offline | Extend its self-test or its test in `tests/`, add the test to the `shellcheck` step of `bin/check.sh`, and run that step. |
| Add or change a check or a workflow | Offline for the logic, CI for the effect | Add a fixture and a regression test in `tests/`, and run `bin/check.sh shellcheck static`. Only CI runs `actionlint`. |
| Add an agent skill | Offline | Write it in `.agents/skills/_inbox/`, then run `bin/sync-skills.sh --promote <name>` and `bin/sync-skills.sh --check --umbrella-only`. See `.agents/skills/README.md` and ADR-0042. |
| Prove a platform change on a running environment | Live | Open the pull request in the component repo that holds the code. A maintainer runs it against an environment. Cluster changes go through `bin/run-playbook.sh` in dmf-env (ADR-0010). |

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
