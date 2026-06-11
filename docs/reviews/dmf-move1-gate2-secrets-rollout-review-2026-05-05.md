# Move 1 Gate 2 — Secrets & Playbook Rollout Review

> **Outcome 2026-05-06:** Path A pivot landed; the recommendations in this review
> are consistent with the secrets/playbook posture that shipped. See
> [`docs/plans/Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md`](../plans/Move%201%20Gate%202%20-%20Pivot%20to%20Path%20A%20for%20Catalog%20Launchers%202026-05-06.md).

**Date:** 2026-05-05
**Reviewer:** Claude (Opus 4.7, umbrella session)
**Scope:** Read-only review of the in-flight Gate 2 work — commit history, dirty
working tree in `dmf-infra`, the trials-and-tribulations doc, and conformance
to ADR-0007/0008/0010 + the Secret Ownership plan.
**For:** the agent currently driving Gate 2 (693-awx-integration → AWX UI launch).

This is a checkpoint, not a verdict. The diagnostics in
`docs/plans/Move 1 Gate 2 — Trials and Tribulations 2026-05-05.md` are good. But
the working tree currently encodes one logical contradiction and a couple of
hygiene gaps that should be resolved before another 693 run. This doc lists them
specifically so they can be fixed (or consciously deferred) in one pass.

---

## Inputs reviewed

- `docs/plans/Move 1 Gate 2 — AWX Integration + Launch NMOS.md` (gate plan)
- `docs/plans/Move 1 Gate 2 — Trials and Tribulations 2026-05-05.md` (run notes, 9 issues)
- `dmf-infra` commits: `61ea9c8` (move1-gate2 feature) and the 5 dirty files on top of it
- `dmf-infra` working-tree diffs:
  - `k3s-lab-bootstrap/ansible.cfg`
  - `k3s-lab-bootstrap/playbooks/693-awx-integration.yml`
  - `k3s-lab-bootstrap/roles/base/cluster-ready/tasks/main.yml`
  - `k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml`
  - `k3s-lab-bootstrap/roles/stack/operator/forgejo-bootstrap/tasks/main.yml`
- ADR-0007 (secrets never in argv/env/tmp/transcripts)
- ADR-0008 (OpenBao + ESO + AppRole shim)
- ADR-0010 (`bin/run-playbook.sh` is the only sanctioned entry point)
- `docs/plans/DMF Secret Ownership and OpenBao Migration Plan.md`

---

## Verdict snapshot

| Area | State |
|---|---|
| ADR-0010 entry-point use (`bin/run-playbook.sh`) | ✅ followed |
| ADR-0007 secret transport in pre-existing tasks | ✅ clean (stdin pipe pattern + `no_log: true`) |
| ADR-0008 OpenBao read/write paths | ✅ canonical (`secret/apps/forgejo/runtime`, etc.) |
| ADR-0007 `no_log: true` on **new** Forgejo API tasks | ❌ missing — see Issue R1 |
| Repo-creation guard logical consistency | ❌ contradicts the trials doc — see Issue R2 |
| `become: true` strategy | ⚠️ workaround, will recur — see Issue R3 |
| 692 password-rotation idempotency | ⚠️ real footgun — see Issue R4 |
| Working-tree commit hygiene | ⚠️ 5 interrelated files, doc/diff drift — see Issue R5 |
| Verification proof for the fixes | ⚠️ no clean end-to-end 693 run on record yet |

---

## Issues, ranked by what blocks the next 693 run

### R1 — Missing `no_log: true` on three new Forgejo API tasks (ADR-0007 §2)

**File:** `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml`
**Tasks added in the dirty diff (around lines 704–744):**

- `Check if dmf-runbooks repo exists in Forgejo`
- `Create dmf-runbooks repo in Forgejo if missing`
- `Ensure playbooks directory structure exists for dmf-runbooks`

Each of these carries `Authorization: token {{ awx_integration_forgejo_token }}`
in headers. None set `no_log: true`. Compare with the existing OpenBao-read tasks
above (e.g. `Read Forgejo runtime token from in-cluster OpenBao` at line 230) which
do set it.

**Why it matters:** ADR-0007 §2 says secrets should never end up in transcripts or
log files. The wrapper logs every run to `/tmp/dmf-playbook-logs/<name>-<timestamp>.log`
(ADR-0010). On a verbose or failed run, the header value is rendered to stderr and
into that log. Treat any past run with these tasks as having leaked the svc token
to a local log; rotate per ADR-0007 §6 if so.

**Action:** Add `no_log: true` to all three new tasks. (If R2 below is resolved by
removing the guard entirely, only the third task survives and still needs the flag.)

---

### R2 — The Forgejo repo-creation guard contradicts its own conclusion

**File:** same — `awx-integration/tasks/main.yml`, lines 704–728 in the dirty diff.

The trials doc, Issue #6, ends with:

> "Hit another snag: The Forgejo service token doesn't have `write:user` scope
> needed for `/user/repos`. So this approach won't work — repo creation must use
> admin auth (which 692 does with `force_basic_auth`).
> **Lesson:** The awx-integration role's repo creation guard is a nice-to-have
> but can't work with the service token. The canonical repo creation path is
> 692-forgejo-bootstrap with admin basic auth."

…yet the working tree still contains the guard. Confirm via
`forgejo-bootstrap/defaults/main.yml:40-43`:

```yaml
forgejo_svc_token_scopes:
  - read:user
  - read:repository
  - write:repository
```

`POST /user/repos` requires `write:user`, which the svc token deliberately lacks.
The guard will return 403 (or 404 because the create call itself fails) on every
fresh-cluster run. On warm reruns it short-circuits via the existence check, which
is why nobody has noticed in repeat tests.

**Decision required (one of):**

1. **Revert the guard.** Trust 692 to own repo creation. `forgejo_repos` already
   includes `dmf-runbooks` (`forgejo-bootstrap/defaults/main.yml:50`). The
   operational rule becomes: when adding a repo to `forgejo_repos`, re-run 692
   before 693. This is what the trials doc concluded.
2. **Widen `forgejo_svc_token_scopes` to include `write:user`.** Deliberate
   blast-radius decision — the svc token currently sees per-repo writes; adding
   `write:user` lets it create *and delete* user repos. If you choose this,
   document why in an ADR appendix and not just in code.

Either way: do not leave the current "guard exists but cannot succeed" state in
the tree. Pick one.

---

### R3 — `become: true` is being sprinkled per-task; the role-level fix is cleaner

**Files:**
- `roles/base/cluster-ready/tasks/main.yml` (7 tasks, dirty diff)
- `roles/stack/operator/forgejo-bootstrap/tasks/main.yml` (3 tasks, dirty diff)
- `playbooks/693-awx-integration.yml` (added at play level — ✅ correct level)

The trials doc Issue #3 already names the better pattern:

> "Consider a shared pattern (e.g., `become: true` at play level for all 69x
> playbooks, or a role-level `become: true` in `roles/base/cluster-ready/meta/main.yml`)."

The agent correctly applied play-level `become: true` to the 693 playbook. For the
roles, per-task sprinkling means every new `kubernetes.core.*` task added later
will hit the same trap and the same edit will need to be repeated. It also
inflates the diff in a way that obscures real changes.

**Action (recommended, not blocking):**
- Add `become: true` to `roles/base/cluster-ready/meta/main.yml` (role default
  for *all* tasks in the role) — or to the role's `tasks/main.yml` block-level
  if metafiles aren't supported in this Ansible version.
- Same for the `forgejo-bootstrap` role section that touches k3s.yaml.
- Then revert the per-task `become: true` lines.

If you decide per-task is preferable for explicitness, document the rule in the
role's README so future contributors know it's deliberate.

**Self-induced regression risk:** Issue #8 (the `longhorn-csi-csi-plugin` typo
introduced during the bulk per-task edit) is exactly the failure mode the role-level
fix avoids — fewer touched lines, fewer chances to miskey.

---

### R4 — Issue #9 (forgejo-svc password rotation) needs a code fix, not a comment

**File:** `roles/stack/operator/forgejo-bootstrap/tasks/main.yml` and surroundings.
**Trials doc Issue #9 says:**

> "The 'Update Forgejo service user password' task runs unconditionally. […] When
> re-running 692, be aware that it rotates the forgejo-svc password. Any
> downstream consumers (AWX SCM credentials, mirror configs) may need to be
> updated."

The current "fix" is a note in the trials doc. That's not idempotent and it's not
something the next agent will remember. Concrete failure path:

1. 692 starts, generates new password, updates Forgejo, persists to OpenBao.
2. Run interrupted (SIGINT, OpenBao seal, network blip, runtime cap from
   ADR-0010).
3. AWX SCM credential / dmf-cms still hold the old password. Project sync fails.
4. Re-run 692. Password rotates *again*. Two rotations, no propagation, neither
   the cluster nor the breakglass file matches what's in Forgejo.

**Action:** Make the password update conditional on actual mismatch. The check
already exists in spirit (`forgejo_svc_password | length == 0` triggers
generation); the *update* should only fire when the in-cluster Forgejo password
demonstrably differs from the one we hold. Or: make the task fully idempotent by
unconditionally setting password to a value already known-good in OpenBao.

This is a real ADR-0008 alignment issue — OpenBao should be authoritative; 692
should converge to it, not drift from it.

---

### R5 — Working-tree commit hygiene + doc/diff drift

- 5 files dirty in `dmf-infra`. They span 3 concerns: roles_path,
  `become: true`, and the repo-creation guard. Three commits would bisect more
  cleanly than one WIP.
- The trials doc summary table lists the `forgejo-bootstrap` change as
  "(pending)". The diff already contains it. The doc is stale.
- The trials doc Issue #2 says "Added `become: true` to every k8s_info task in
  cluster-ready/tasks/main.yml (8 tasks)". The diff shows 7. Either the doc is
  off-by-one or one task was missed.

**Action:** Reconcile the trials doc with the actual diff before committing, then
split into 2–3 logical commits. Helps the next agent (which may be a fresh
session of you) not chase phantom changes.

---

### R6 — No verification proof yet

The Gate 2 plan's success criteria (lines 261–274 of the gate doc) are still
unchecked. The trials doc says fixes were applied but doesn't include the
PLAY RECAP from a clean 693 run, nor any of the post-Step-5 verification queries
(NetBox tag flip, registry endpoint, ConfigMap presence).

**Action:** After R1+R2 are resolved, run 693 end-to-end through
`bin/run-playbook.sh hetzner-arm …` and capture:
- The wrapper's log path (`/tmp/dmf-playbook-logs/693-awx-integration-*.log`)
- `kubectl get all -n nmos`
- The NetBox tag query (Step 6.3 of gate plan)

Append the result to the trials doc as a final "10. Closure" section so the next
session has authoritative confirmation that Gate 2 passed.

---

## Things the agent got right (worth keeping)

- **ADR-0010 compliance:** ran via `bin/run-playbook.sh hetzner-arm …`, didn't
  bypass the wrapper.
- **ADR-0007 transport pattern preserved:** the existing `printf '%s\n' "$VAR" |
  kubectl exec -i ... sh -c 'IFS= read -r X'` pattern was not regressed. New
  edits added `become: true` only — no secrets moved into argv or env arguments
  to bao/curl.
- **OpenBao token revoked after use** in `awx-integration` (line 263 onward)
  — `bao token revoke -self` after the source-token reads. This is a model the
  rest of the codebase should adopt where it doesn't already.
- **Removing `cluster-ready` from 693:** correct. ADR-0012 supports the idea
  that not every play is a cluster-touching play; awx-integration is API-only
  (apart from one OpenBao pod discover, which can stand alone).
- **Diagnostics doc itself:** the 9-item structure with symptom / root cause /
  fix / lesson is the right shape. Carry that pattern forward into Move 2.

---

## Suggested order of operations

1. Resolve R2 (decide: revert guard *or* widen scopes).
2. If guard stays in any form, fix R1 (`no_log: true`).
3. Fix R3 (role-level `become: true`) — optional but lowers future cost.
4. Reconcile R5 (doc vs diff), commit in 2–3 logical chunks.
5. Run 693 end-to-end, capture R6 evidence.
6. Defer R4 (692 idempotency) into a follow-up commit *after* Gate 2 passes —
   it's a real bug but blocking Gate 2 on it stretches scope.

---

## References

- ADR-0007: `docs/decisions/0007-secrets-never-in-argv.md`
- ADR-0008: `docs/decisions/0008-openbao-secrets-architecture.md`
- ADR-0010: `docs/decisions/0010-run-playbook-as-sanctioned-entry.md`
- ADR-0014: `docs/decisions/0014-awx-project-layout.md`
- Secret Ownership: `docs/plans/DMF Secret Ownership and OpenBao Migration Plan.md`
- Gate plan: `docs/plans/Move 1 Gate 2 — AWX Integration + Launch NMOS.md`
- Trials doc: `docs/plans/Move 1 Gate 2 — Trials and Tribulations 2026-05-05.md`
- Reference impl for stdin secret transport: `dmf-env/bin/unseal-openbao.sh`
