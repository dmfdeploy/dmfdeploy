# DMF Agentic Harness — Autonomous Decisions Log

> **⚠️ Status: HISTORICAL (mothballed 2026-06-04).** The harness ran K1–K4 + K5
> ticks on 2026-05-12 (through tick 16) and has been unused since. This log is
> frozen; the live backlog is [`TODOS.md`](../../TODOS.md). Preserved for
> provenance.

> **Authority**: Append-only retrospective log of choices the orchestrator
> resolved without surfacing to the operator. Operator audits on return; can
> ack (no action) or revert (revert commit + log entry).
>
> **Distinct from**: [`decisions-open.md`](decisions-open.md) (forward queue —
> ADR-worthy gates awaiting operator action). This file is the *retrospective*
> half; that one is the *prospective* half.
>
> **Classification rubric**: A choice was logged here (instead of surfaced)
> when NONE of Constitution Rule 5 (a–e) held — i.e., the choice did not
> change a public surface, did not touch multiple repos, did not contradict
> or supersede an ADR, did not remove an option already considered in a plan
> doc, and did not cross a skill-guarded boundary.
>
> **Budget context**: Per-tick ≤ 1 entry. Per-shift ≤ 10 entries before the
> harness soft-pauses with a §"Autonomous decisions taken" summary block in
> the active handoff (Constitution Rule 14).
>
> **Source spec**:
> [`DMF Agentic Harness Plan`](../plans/DMF%20Agentic%20Harness%20Plan%202026-05-11.md)
> §Layer 3 "Autonomous decision routing".

---

## Format

One line per decision:

```
<ISO-timestamp> | <task-id> | <one-line decision> | <rationale ≤140ch> | <commit-sha or file-path>
```

Field rules:

- `<ISO-timestamp>`: `YYYY-MM-DDTHH:MM:SSZ` UTC.
- `<task-id>`: matches a `backlog.yaml` id, or `oneshot:<short-slug>` if the
  decision arose outside a tracked task.
- `<one-line decision>`: imperative voice, ≤80 chars. E.g. "set scratch
  emptyDir sizeLimit to 25Gi".
- `<rationale ≤140ch>`: why this option over alternatives. Brevity is the
  point — operator scans the column; long context lives in the commit body.
- `<commit-sha or file-path>`: where the change landed. Commit SHA is
  preferred (clickable in git log); use a file path when the change is
  configuration that hasn't committed yet.

Operator response convention:

- Lines start at the column 1 with the ISO timestamp.
- Operator notes go on the next line, indented two spaces, prefixed by
  `ack:` or `revert:` and a brief rationale.

---

## Entries

2026-05-12T08:50:00Z | k2-build | new sibling script bin/agentic/install-agentic-hooks.sh instead of extending bin/install-hooks.sh | canonical plan said "extension" but install-hooks.sh is single-responsibility (sets hooksPath); per-repo hook deployment is a separate concern; rubric (a-e) none apply | docs/agentic/install-agentic-hooks.sh
  ack/revert: pending operator review

2026-05-12T11:24:00Z | rel-p0-umbrella | add hosts.ini to umbrella .gitignore §6 baseline block | source plan §6 baseline lists hosts.ini; umbrella .gitignore was missing it; pure file-pattern hygiene fix, rubric (a-e) none apply | umbrella@31ee1e2
  ack/revert: pending operator review

2026-05-12T12:14:00Z | rel-p0-dmf-cms | add hosts.ini to dmf-cms .gitignore §6 baseline block | same gap as umbrella; qwen propagated the fix per source plan §6 baseline; rubric (a-e) none apply | dmf-cms@686980c
  ack/revert: pending operator review

2026-05-12T12:14:30Z | tick-3 prep | commit dmf-cms WIP investigation→stash flow as orchestrator-driven action | operator authorized "investigate dirty state and solve" then chose stash; not in autonomy rubric per se but worth audit-trail noting; rubric (a) borderline (touches sub-repo state) but operator explicitly steered | dmf-cms stash@{0}
  ack/revert: pending operator review

2026-05-12T12:24:00Z | rel-p0-dmf-infra | add hosts.ini to dmf-infra .gitignore §6 baseline block | same gap pattern as umbrella + dmf-cms; rubric (a-e) none apply | dmf-infra@1551d27

2026-05-12T12:33:00Z | rel-p0-dmf-central | add hosts.ini to dmf-central .gitignore §6 baseline block | same gap pattern propagating across all 6 public repos; rubric (a-e) none apply | dmf-central@c9ec871
  ack/revert: pending operator review

2026-05-12T12:43:00Z | rel-p0-dmf-media | add hosts.ini to dmf-media .gitignore §6 baseline block | 5th instance of same gap pattern; rubric (a-e) none apply | dmf-media@cf13bd3
  ack/revert: pending operator review

2026-05-12T12:52:00Z | rel-p0-dmf-runbooks | add hosts.ini to dmf-runbooks .gitignore §6 baseline block | 6th and final propagation; same shape as prior 5; rubric (a-e) none apply | dmf-runbooks@3852524
  ack/revert: pending operator review

2026-05-12T12:30:00Z | group-c-expansion | encode each Move 1 Piece as ONE backlog entry with file-acceptance + cluster_verify_optional note rather than splitting file/verify into 2 entries | source plan implies one Piece = one bounded scope; splitting doubles entry count for marginal clarity; cluster verification is operator-side regardless; rubric (a-e) none apply | umbrella@1d69332

2026-05-12T12:38:00Z | move1-audit | introduce `obviated` as terminal backlog status (distinct from `done`) for entries where Path A pivot eliminated the original Piece's applicability | operator authorized Option B which implies a status distinguishing "satisfied via Path A equivalent" from "no equivalent needed, original premise dropped"; cleaner audit trail; rubric (d) borderline (touches schema choice) but operator's strategy implied this need | (pending umbrella commit; backlog.yaml move1-p2 + p5)

2026-05-12T20:10:00Z | oneshot:aliyun-123-loki-sizing | shrink Loki to 5Gi/7d for aliyun-123 — no S3 chunk backend, no extended security retention | follows from ADR-0020 Mode A answered today; Mode B compliance (6mo security streams, 12mo WORM) deferred until a managed-service driver exists; experiment intent is to validate the stack on 80GB ECS disks, not exercise compliance retention; operator-confirmed in /loop session | dmf-env@aliyun-123/group_vars/all/main.yml (uncommitted)
  ack/revert: pending operator review
  ack/revert: pending operator review
  ack/revert: pending operator review

2026-05-19T22:00:00Z | oneshot:catalog-helm-convergence | collapse 2026-05-19 NMOS-only draft plan into the broader 2026-05-19 Catalog Helm + EE-as-runtime + runner-pod convergence plan, document-only PR | operator's plan-mode instruction "scan thoroughly to ensure docs are consistent and not diverging decision branches"; the NMOS-only first cut overlapped with the runner-pod plan on EE-build ownership and Stage 4b seeding; merging them into one canonical doc prevents the divergence. NEW ADR-0025 placeholder reserved (ADR-0024 preserved for prior App Admin drift reservation). Rubric (c) applies (touches ADR-0016/0012/0023 amendments) — surfaced for operator approval via ExitPlanMode before docs landed; this log records the choice to renumber 0024→0025 to respect prior reservation, which was orchestrator-resolved (rubric (e) borderline — schema-of-numbering choice, not architecturally load-bearing). | umbrella@(pending) — docs/plans/DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md + 14 file edits
  ack/revert: pending operator review

2026-05-19T23:30:00Z | batch:2026-05-19-defaults-ratification | operator ratified all 7 open decisions from the 2026-05-19 catalog Helm pivot with their recommended defaults (§8.1=A workstation Ansible play, §8.2=B defer skill, §8.3=A broad ADR-0025, §8.4=A operator workstation, §8.5=A NMOS arm64 images confirmed in Colima docker-build profile, §8.6=A anonymous read on dmf/*, §8.7=B SA-in-target-ns + AWX Container Group) | operator explicit instruction: "I now decide to go with the default answers, pls proceed with ur recommended approach and implement as you see fit"; not orchestrator-resolved, this is operator ratification recorded for audit trail | docs/agentic/decisions-open.md (all 7 Status: answered)
  ack/revert: operator-ratified

---

## See also

- Per-tick history (mechanical record of preflight/postflight/dispatch
  outcomes): [`loop-log.md`](loop-log.md).
- Issues opened during a run: [`issues.yaml`](issues.yaml) (mirror) and
  Forgejo `label:agent-opened` (canonical).
- Operator inbox for things this log is NOT supposed to absorb:
  [`decisions-open.md`](decisions-open.md).
