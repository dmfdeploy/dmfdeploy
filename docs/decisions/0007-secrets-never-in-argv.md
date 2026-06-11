# ADR-0007: Secrets never in argv, env, /tmp, or AI transcripts

**Status:** Accepted
**Date:** 2026-05-03
**Deciders:** @<handle>

## Context

DMF infrastructure has many secrets: OpenBao master shares, Zot registry
credentials, Hetzner / Cloudflare / Tailscale provider tokens, app admin
passwords, AWX/NetBox/Forgejo API tokens. These flow through scripts, playbooks,
and shells operated by both humans and AI agents. Each medium has a different
leak surface: argv (visible via `ps`), environment (`/proc/<pid>/environ`),
`/tmp` files (other users on the host), shell history (persistent on disk),
AI conversation transcripts (captured to prompt cache and possibly telemetry).

A leaked secret is rarely "just" leaked — telemetry, crash dumps, sync'd
shell history, screenshot captures, and prompt caches all retain copies that
are hard to scrub.

## Decision

Hard rules that apply to every script, skill, playbook task, and human
operator working in any DMF repo:

1. **Never put a secret in argv** (`docker login -u u -p PASS`,
   `curl -d '{"password":"..."}'`, `bao operator unseal <share>`,
   `export TOKEN=xxx` on the command line).
2. **Never echo, cat, or pipe a secret to stdout when running through an AI
   agent.** The agent's tool output lands in the conversation transcript and
   prompt cache.
3. **Never copy `/etc/rancher/k3s/k3s.yaml` (or equivalent cluster-admin
   credentials) off the control node.**
4. **Never paste OpenBao Shamir share contents into chat, recordings,
   screenshots, or notes.**
5. **Sweep `/tmp` periodically** for stale `openbao-vars-*` and grep
   `dmf-playbook-logs/` for accidentally-logged secrets.
6. **Treat any session that retrieved a secret as compromised for that
   secret's lifetime** — rotate after.

Mechanisms: pipe via stdin (`printf '%s' "$x" | tool`), use `read -s` for
interactive input, use `--password-stdin` for tools that support it, prefer
tools that fetch+use a secret server-side without exposing it to the operator
(e.g. playbook 650 doing `docker login` inside an isolated docker config).

## Consequences

- **Positive:** named threat-model surfaces (argv, env, /tmp, transcripts) are
  easier to audit than vague "be careful with secrets."
- **Positive:** the hard rules give agents and humans a clear "stop, don't do
  that" trigger when they see one of these patterns being proposed.
- **Negative:** longer commands (`printf '%s' "$x" | docker login --password-stdin`
  vs `docker login -u u -p PASS`). Acceptable tax.
- **Negative:** some legacy docs (e.g. earlier examples in
  `DEVELOPMENT-AND-BUILD-RULES.md` §3) showed argv patterns. They've been
  superseded but not all references rewritten.

## Alternatives considered

- **"Use OpenBao for everything."** Necessary but not sufficient — once the
  secret is fetched, it still has to flow through some channel to where it's
  used; the rules are about *that* channel.
- **"Trust the operator."** Solo developer discipline is reliable; multi-agent
  collaboration is not, especially when one agent's transcript may be visible
  to humans/services the operator hasn't audited.

## Enforcement

§0 of `dmf-cluster-access`, `dmf-cms-build-and-release`, and
`dmf-openbao-unseal` skills. `bin/unseal-openbao.sh` is the reference
implementation of "share never in argv/env/tmp." Agent boot ritual (umbrella
CLAUDE.md) tells agents to read these §0 sections every session.
