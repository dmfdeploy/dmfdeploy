---
name: issues-cruncher
description: Orchestrate a multi-agent trio (Claude orchestrator + qwen implementer + codex adversary) to take a GitHub issue end-to-end — scope, branch, implement, cross-check, verify, PR, land — with evidence-gated conventions and risk-tiered ceremony. Use when asked to "crunch an issue", "pick up issue N with the trio", "orchestrate the agents on a backlog item", or to start fresh on the backlog.
type: operational-procedure
scope: agent-workflow
owner: operator
review_by: '2027-01-14'
---

# Issues Cruncher

The orchestrator's playbook for landing a backlog issue with a trio. **This file is
the thin engine + hard gates only.** Load a `references/` file when its phase needs
it — do not inline its content here.

> Roles: **orchestrator** (you, ~80% of the value — scope + verify + git/PR),
> **implementer** (qwen — precise lifting), **adversary** (codex — conditional,
> non-load-bearing cross-check). The trio is optional: degrade to orchestrator-solo
> when no panes are live (Tier 1) — see `references/tiers.md`.

## Hard gates (never skip, any tier)

1. **No silent defaults.** Every convention the run relies on must come from the
   profile with *evidence + confidence + expiry*. Unknown ⇒ **ask or block**.
   Absence ≠ policy. (`references/repo-profile.md`)
2. **Lease before you touch.** Confirm clean/owned state across every repo you'll
   modify, and **claim the issue**, before branching. Never trust the shared
   checkout — isolate with a `git worktree` if other agents are active.
3. **Verify on disk, never agent reports.** Re-check every claim against the actual
   code/tests yourself. (`references/guardrails.md`)
4. **Discrimination + independent regression.** A regression test must *fail on the
   old code*, not just pass on the new — and the fix author and the test's
   discrimination check must not be the same agent in the same pass.
5. **Scope freeze.** Discoveries become follow-up issues unless they block the
   current one.
6. **Re-verify after every review/CI fix.** Prior adversary/CI passes are void once
   code changes.
7. **Human approval gate** for destructive / migration / costed-cloud / public-publish
   / dependency-license actions. Green ≠ mergeable if rules can be bypassed.
8. **Anti-churn rules travel in the dispatch, verbatim.** Every WO and every gate
   request carries the five rules from `references/anti-churn-rules.md` — comment
   fidelity, ownership-move lifecycle test, counts-as-pasted-output, sibling sweep,
   premise citation (`references/anti-churn-rules.md`, the delimited
   DISPATCH-PAYLOAD block). **Never cite them from memory**: roughly two thirds
   of one session's gate findings were self-inflicted, and the root cause was
   rules decaying from "remembered convention" within the same session. The
   adversary has **no memory store** — it reads canonical skills natively
   (ADR-0042) but nothing memory-resident reaches it.

## The loop (8 phases)

0. **Preflight** — sync; build the **repo profile** (detect→confirm→cache with
   evidence fingerprints, `references/repo-profile.md`); verify the trio is live
   (`references/harness-ops.md`); pick the CI/tracker adapter
   (`references/github-adapter.md`).
1. **Select & scope** *(orchestrator only — never delegated)* — choose a
   trio-suitable issue; read the code; find root cause; **find a precedent in the
   repo to mirror**; set the **risk tier** (`references/tiers.md`); surface genuine
   design forks to the human. Output: a precise written brief (root cause, fix
   shape, `file:line`, acceptance criteria, **explicit discriminating-test
   requirement**).
2. **Branch** — from the adapter's default branch; isolate via worktree if needed.
3. **Dispatch to implementer** — hand the implementer the brief **with the five
   anti-churn rules pasted verbatim** (`references/anti-churn-rules.md`); gate the
   commit until cross-check + verify pass (`references/implementer-primer.md`).
4. **Cross-check (conditional)** — invoke codex only on risk signals / low
   confidence; treat its verdict as a second angle, not a gate
   (`references/adversary-primer.md`). The gate request carries the same five
   rules, and records the exchange per `agent-conversation-recording`.
5. **Verify** *(orchestrator — local / pre-commit)* — on disk; run tests via the
   project's runner; run the **discrimination check**; lint; **clean-tree** verify
   from a *local export* (`git archive`/`ls-tree`) where built artifacts can mask
   fallbacks. This gate needs no push (`references/guardrails.md`).
6. **Commit (gated)** — **the orchestrator** commits/amends/pushes, after the verify
   gate passes, to the profile's conventions (hygiene from the profile). The
   implementer only stages and reports; it never commits.
7. **Push → fresh-checkout verify → PR → CI → land → close → cleanup** — push;
   **fresh-checkout verify the *pushed* branch** (catches what a dirty local tree
   masks — this is the post-push half of verification, separate from Phase 5); open
   the PR with the **evidence bundle**; CI truth from the adapter (not lagging
   aggregations); route reviewer rounds back to phase 3 and **re-verify**; on merge,
   honor the profile's close behavior (don't assume auto-close) and clean up the
   branch/worktree.

## Tier in one line

Tier = highest **risk signal** touched (concurrency/locks/subprocess, auth-flow,
data migration, money, destructive, public contract), re-evaluated at fixed
checkpoints; escalate-only mid-run without human OK. Tier 1 = orchestrator solo;
Tier 2 = + implementer + verify; Tier 3 = full trio + *expect* an external review
round. (`references/tiers.md`)

## References (load on demand)

| File | When |
|---|---|
| `references/repo-profile.md` | Phase 0 — detect/confirm/cache conventions with evidence |
| `references/github-adapter.md` | Phase 0/7 — CI + tracker truth, close-keyword probing, merge guard |
| `references/dmf-profile.md` | This environment's concrete profile facts |
| `references/tiers.md` | Phase 1 — risk-signal tiers + checkpoint gates |
| `references/guardrails.md` | Phases 5–7 — the hard-gate checklist in full |
| `references/harness-ops.md` | agent-bridge operation (liveness, flush, hung-agent policy) |
| `references/orchestrator-primer.md` | Your lane, in depth |
| `references/implementer-primer.md` | qwen's lane (authored by qwen) |
| `references/adversary-primer.md` | codex's lane (authored by codex) |
| `references/anti-churn-rules.md` | Phases 3–5 — the five rules pasted verbatim into every WO and gate dispatch |

## Reuse (compose, don't duplicate)

This skill is the orchestrator spine over existing implementer/verification skills
in the canonical store `.agents/skills/` (never a generated `.claude/`/`.qwen/`
view): `cold-agent-execution`, `fix-round-verification-protocol`,
`clean-tree-verification-protocol`, `multi-repo-pr-submission`,
`work-order-commit-review`, `adversarial-infra-crosscheck`,
`discriminating-test-design`, `agent-conversation-recording`.
Reference them; do not restate them. (Flagship instance of the canonical
cross-agent skills effort, umbrella issue #46.)
