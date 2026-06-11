# ADR-0002: Two-repo model — generic playbooks vs private inventory

**Status:** Accepted
**Date:** 2026-04-17 (reaffirmed 2026-05-03 in umbrella consolidation)
**Deciders:** @<handle>

## Context

The platform's ansible code mixes two kinds of artifact: (a) generic, reusable
playbooks/roles that any DMF deployment could consume, and (b) site-specific
configuration — real IPs, OpenBao secret paths, ingress URLs, terraform state
location. Mixing them in one repo means either leaking site secrets into a
public repo or making the public repo useless to anyone but the originating operator. Career
credibility goal (i) and OSS goal (iii) require the generic part to be public.

## Decision

Two separate git repos:

- **`dmf-infra`** — public, generic playbooks/roles only. No real IPs, no
  passwords, no site URLs. Hardcoded values are forbidden; everything is
  parameterized by inventory variables.
- **`dmf-env`** — private, site-specific. Holds `inventories/<env>/`,
  `manifests/<env>.yaml` (Resource Profiles), `terraform/<env>/`, and the `bin/`
  wrappers that read OpenBao secrets / provider tokens at runtime.

Playbooks are run via `dmf-env/bin/run-playbook.sh <env-name> <path-to-generic-playbook>`.

## Consequences

- **Positive:** `dmf-infra` can be open-sourced without a secret-scrubbing
  pass. The repo's value (idempotent, EBU-aligned playbooks) is portable.
- **Positive:** site-specific config has a clean home. Adding a new environment
  is mostly a `cp -r inventories/example inventories/<new>` plus filling in
  values.
- **Negative:** two repos to clone and keep in sync. The wrapper scripts
  reference each other via `..` paths; standalone clones of one without the
  other don't work for live runs.
- **Negative:** secrets boundary discipline must be enforced — anything sensitive
  must NOT land in `dmf-infra`. PR reviewers and pre-commit hooks have to
  catch leaks.

## Alternatives considered

- **Single private repo.** Simpler tooling, defeats the credibility/OSS goals.
- **Single public repo with secrets in OpenBao only.** All references would need
  to be runtime-resolved; some structural config (real ingress URLs in
  `external_base_url`) is awkward to fully externalize. Two-repo model is more
  practical.

## Enforcement

`dmf-infra/CLAUDE.md` states the rule explicitly. Pre-commit / CI checks
that scan for hardcoded IPs (`grep -E '178\.|46\.225\.|10\.0\.0\.'`) or known
domains in `dmf-infra` would catch most violations; not yet wired
automatically. ADR-0007 (secrets discipline) reinforces the boundary.
