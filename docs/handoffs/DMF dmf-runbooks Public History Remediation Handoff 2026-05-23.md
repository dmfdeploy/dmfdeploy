# DMF dmf-runbooks Public History Remediation Handoff

**Date:** 2026-05-23
**Repo:** `dmf-runbooks`
**Public target:** `github.com/dmfdeploy/dmf-runbooks`

## TL;DR

The public `dmf-runbooks` repo has been re-orphaned again as `v0.1.2` to
remove user-specific environment details from public history. The public
GitHub surface now has exactly one branch and one tag:

```text
refs/heads/main  -> 0eb94d1
refs/tags/v0.1.2 -> 0eb94d1
```

The old public tags `v0.1.0` and `v0.1.1` were deleted from GitHub and LAN
Forgejo because they made superseded topology comments reachable. The stale
`master` branch was deleted locally and from both configured remotes
(`origin`, `github`).

## What Changed

### dmf-runbooks

New public orphan commit:

```text
0eb94d1 v0.1.2 - public history remediation
```

The tree is based on the ADR-0025 Lane B landed state and includes these
public-readiness cleanups:

- `VERSION` bumped to `0.1.2`.
- `.gitleaks.toml` no longer encodes operator-specific identity strings in the
  public repo. It keeps a public-safe subset: default gitleaks, placeholder
  credential detection, private-network literal detection, and macOS metadata
  detection.
- `.github/CODEOWNERS` now uses `@dmfdeploy/maintainers` rather than a
  personal account handle.
- `roles/nmos-cpp/README.md` and scripts use relative checkout commands and
  generic password-manager placeholders instead of operator-local shell
  examples or retired environment names.
- `CONTRIBUTING.md` no longer contains broken relative links into the umbrella
  repo when viewed standalone on GitHub.

### Umbrella

`bin/scrub-public-repos.sh` was fixed so it can be used as a real gate again:

- empty `CONTEXT_PATTERNS` no longer trips `set -u`;
- `.gitleaks.toml` and `.github/CODEOWNERS` are no longer globally allowlisted
  for identity matches, because those files can themselves leak identity
  breadcrumbs in public repos.

## Public Ref State

GitHub final check:

```text
0eb94d1a5b6f4b655943938b4abc072321878e42 refs/heads/main
0eb94d1a5b6f4b655943938b4abc072321878e42 refs/tags/v0.1.2
```

LAN Forgejo final check:

```text
0eb94d1a5b6f4b655943938b4abc072321878e42 refs/heads/main
0eb94d1a5b6f4b655943938b4abc072321878e42 refs/tags/v0.1.2
```

Local-only forensic refs retained on the operator workstation:

```text
archive/pre-public-remediation-2026-05-23
archive/pre-publish-2026-05-07
pre-republish-2026-05-21
```

Do not push `--tags` from this repo. Publish only explicit public tags.

## Verification

Fresh public clone at `/private/tmp/dmf-runbooks-public-final-20260523`:

```text
git log --oneline --decorate --all
0eb94d1 (HEAD -> main, tag: v0.1.2, origin/main, origin/HEAD) v0.1.2 - public history remediation
```

Gates:

```text
gitleaks detect --log-opts=main --no-banner --redact  -> no leaks found
gitleaks detect --log-opts=--all --no-banner --redact -> no leaks found
gitleaks detect --no-git --no-banner --redact         -> no leaks found
bin/scrub-public-repos.sh dmf-runbooks                -> OK - clean for public publish
```

Additional literal scans against the fresh public clone found no matches for
the previously flagged operator identity, retired environment names, concrete
private/mesh IPs, or local filesystem paths.

## Branch Protection

GitHub branch protection on `main` was temporarily removed to allow the
sanitized force-push, then restored:

- required linear history: enabled
- force-pushes: disabled
- deletions: disabled
- applies to admins: enabled
- required status checks: none yet

## Follow-Ups

- Confirm the GitHub org team `@dmfdeploy/maintainers` exists; otherwise
  CODEOWNERS review requests will not resolve as intended.
- Avoid exposing private scrub-rule values inside public per-repo
  `.gitleaks.toml` files. Keep operator-specific identity detection in the
  private umbrella scrub gate.
- For the remaining public repo expansion, add a pre-publish check that scans
  public gate files themselves rather than allowlisting them by default.
