# ADR-0005: dmf-cms VERSION file is the single source of truth

**Status:** Accepted
**Date:** 2026-05-02 (formalized by `DEVELOPMENT-AND-BUILD-RULES.md`)
**Deciders:** @<handle>

## Context

The dmf-cms artifact has a version that must agree across five locations:
`pyproject.toml`, `frontend/package.json`, `charts/dmf-cms/Chart.yaml` (two
fields), `charts/dmf-cms/values.yaml` `image.tag`, plus the Ansible role's
`cms_image_tag` default in `dmf-infra`. Manual editing has historically
let one or more of these drift, producing pods running an image you no longer
have local, or releases that build at one tag and deploy at another.

## Decision

The file `dmf-cms/VERSION` (single line: `MAJOR.MINOR.PATCH`) is the **only**
location where the version is set. All other version fields are derived from it
by `scripts/sync-version.sh`. The `cms_image_tag` Ansible default is a
`lookup('file', ...)` reading the same `VERSION` file at playbook runtime.

The container image is **always** tagged
`registry.dmf.example.com/dmf-cms:<VERSION>`. No `latest` tag, no `v` prefix in
the image tag, no pre-release suffixes (`-rc1`, `-dirty`). `imagePullPolicy:
IfNotPresent` is intentional — bumping `VERSION` is the only way to force a pull.

## Consequences

- **Positive:** drift is mechanically detectable (`scripts/sync-version.sh --check`).
  CI can fail PRs that break the contract.
- **Positive:** the Ansible role can be re-run safely without downgrading the
  image to a hardcoded value.
- **Positive:** version traceability — every image label carries its VERSION
  and git SHA, so `docker inspect <image>` is forensically useful.
- **Negative:** the rule must be enforced; manual edits to `pyproject.toml`
  silently break it until the next `--check`.
- **Negative:** no flexibility to ship "test" images at non-semver tags. Use
  `--no-push --dirty` for local test instead.

## Alternatives considered

- **Keep version in `pyproject.toml`, derive others.** Same pattern, different
  primary file. `VERSION` was chosen because it's a one-line plain-text file
  that's trivial to read from any language/tool (Python, JSON, YAML, shell).
- **`latest` tag for "current".** Pods cache by tag and won't repull
  `latest` reliably; a known anti-pattern.

## Enforcement

`scripts/sync-version.sh --check` (run in CI on every PR; today the check is
local-only, formal CI is pending). `scripts/build-image.sh` and
`scripts/release.sh` both refuse to run if `--check` fails. The
`dmf-cms-build-and-release` skill encodes the workflow.
