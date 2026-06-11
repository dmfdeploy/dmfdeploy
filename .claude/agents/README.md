# DMF Platform Subagents

This directory contains specialized Claude Code subagents tailored to the DMF Platform's architecture and workflows. Claude Code can **automatically select the right subagent** based on the description fields below, or you can explicitly request a specific agent by name.

## Automatic Routing

When you submit work to Claude Code:

1. The main session reads the `description` field in each agent's frontmatter
2. It routes to the best-matching agent based on keywords and context
3. The specialized agent handles the task with domain expertise and scoped tool access

**If routing feels wrong**, improve the description field. Descriptions should be narrow and keyword-rich to avoid over-matching.

## Agents

| Agent | Model | Best For |
|-------|-------|----------|
| **Architecture Reviewer** | Opus | System design, cross-repo boundaries, EBU layer decisions, refactoring scope |
| **Kubernetes Operator** | Sonnet | k3s manifests, Helm charts, cluster bootstrap, pod troubleshooting |
| **Security & Secrets** | Opus | OpenBao, OIDC, RBAC, threat modeling, credentials, privilege review |
| **Frontend & UX** | Sonnet | React components, dmf-cms console, design system compliance, dashboards |
| **Network & Media** | Opus | NMOS, ST2110, multicast, media flows, broadcast orchestration |
| **Test Runner** | Sonnet | Tests, CI failures, linting, type errors, regressions |
| **Quick Fixer** | Haiku | Typos, formatting, import cleanup, trivial mechanical changes |
| **Docs Writer** | Sonnet | READMEs, runbooks, ADRs, setup instructions, handoff notes |
| **Process Documentation** | Sonnet | BPMN 2.0 (ISO/IEC 19510) process diagrams, ISO 5807 flowcharts, workflow docs |

## Using Agents Explicitly

You can request a specific agent by name:

```
/agent architecture-reviewer <your task>
/agent k8s-operator <your task>
/agent security-secrets <your task>
...
```

## Agent Design Philosophy

- **Opus for high-risk reasoning** — architecture, security, media network analysis
- **Sonnet for normal engineering** — most frontend, backend, and infrastructure work
- **Haiku for cheap tasks** — formatting, typos, simple syntax fixes
- **Conservative tool access** — read-only agents don't have Bash; only critical agents get full access
- **Domain expertise in descriptions** — keywords guide automatic routing without blocking fallback

## Improving Routing

If Claude Code routes a task to the wrong agent:

1. Check the winning agent's description — is it too broad?
2. Check the losing agent's description — is it too narrow?
3. Edit the `description` field in the agent's frontmatter to better distinguish it
4. Example: "When..." and "Also for..." clauses narrow the scope

A good description:
- ✅ **Specific keywords** — "NMOS IS-04", "St2110", "multicast"
- ✅ **Explicit boundaries** — "Also for media-domain...", "Not for generic networking"
- ✅ **No overlap** — each agent's domain is distinct
- ❌ **Vague** — "when working on anything infrastructure-related"

## Creating New Agents

Before adding an agent:

1. Identify a recurring task type (10+ sessions worth)
2. Check if an existing agent covers it (improve description instead)
3. Create a `.md` file with `name`, `description`, `tools`, and `model` frontmatter
4. Write clear instructions scoped to the agent's domain
5. Update this README

## Agent Lifecycle

Agents are living documents. If you find:

- **Routing issues** — update the description field
- **Scope creep** — split the agent or clarify boundaries
- **Unused agents** — consider removing them
- **Tool permission creaks** — expand tool access conservatively
