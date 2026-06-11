# DMF Aliyun-123 Lifecycle-Configure Completion Handoff

**Date:** 2026-05-17
**Cluster:** `aliyun-123`
**Session type:** implementation + live validation + planning
**Outcome:** the three Gap A/B/C changes from the 2026-05-15 source plan
shipped to `dmf-infra@main` and pass §6 verification end-to-end on the
live cluster. One follow-on bug (catalog-project sync) discovered and
fixed in the same session. One pre-existing inventory gap surfaced
(`awx_control_node_ssh_privkey_path`) — captured in the follow-ups plan.

---

## 1. Headline

The source plan
[DMF Lifecycle-Configure Bootstrap Completion Plan 2026-05-15](../plans/DMF%20Lifecycle-Configure%20Bootstrap%20Completion%20Plan%202026-05-15.md)
described three gaps in the lifecycle-configure chain that were silently
breaking the catalog model. All three landed on `dmf-infra@main`, plus a
fourth bug that surfaced as a direct consequence of Gap C's fail-loud
behavior:

| # | Commit | Topic |
|---|---|---|
| 1 | `a891ecb` | feat(lifecycle-configure): seed repos, CMS perms, fail-loud JT (Gap A + B + C) |
| 2 | `440ec61` | fix(forgejo-bootstrap): seed via deny-list (`.git/`) — supersedes `f1ba770` |
| 3 | `8d20e71` | fix(awx-integration): trigger AWX project sync per catalog project |

Live validation on `aliyun-123` shows all five §6 checks from the source
plan now pass:

- Forgejo `dmf-runbooks` repo contains `playbooks/launch-nmos-cpp.yml` + `teardown-nmos-cpp.yml`
- AWX `dmf-runbooks` project synced to revision `aea4a518…` with playbooks indexed
- AWX catalog JTs `media-launch-nmos-cpp` (id=15) + `media-finalise-nmos-cpp` (id=16) exist
- `dmf-cms-svc` token returns **HTTP 200** on `/api/dcim/sites/` and `/api/ipam/services/` (previously **HTTP 403** — Gap B fixed exactly what was broken)
- dmf-cms `/api/catalog` endpoint reachable and OIDC-gated as designed

The final `bootstrap-configure.yml` run ended with `failed=1` at a
**pre-existing** inventory gap (`awx_control_node_ssh_privkey_path` not
pinned for `aliyun-123` — see follow-ups plan §A.1). All four shipped
commits exercised cleanly.

---

## 2. Walls debugged + fixes (per commit)

### `dmf-infra` commits this session

| Commit | Wall | Fix |
|---|---|---|
| `a891ecb` | (original feature) | Three changes from source plan §2–4: Gap A `forgejo-bootstrap` seeds dmf-runbooks from controller-side path; Gap B `netbox-sot` creates `dmf-cms-readonly` group + 4 ObjectPermissions + binds `dmf-cms-svc`; Gap C `awx-integration` removes `failed_when: false` from catalog JT operations. Also includes `index_var: loop_index0` fix on the POST `when:` clause (qwen original draft used `ansible_loop.index0` without `extended: true`). |
| `f1ba770` | Gap A run-1 422 — `ansible.builtin.find` walked into `.git/` and tried to push binary git objects via Forgejo content API | Added `hidden: false` + `patterns:` allowlist. **Superseded** — fragile against future file additions. |
| `440ec61` | Gap A robustness (post-mortem of `f1ba770`) | Replaced `patterns:` allowlist with **deny-list** post-filter: `_seed_local_files_raw` from unfiltered find → `rejectattr('path', 'search', '/\\.git/')` set_fact. Robust against `*.sh`, `Dockerfile*`, `LICENSE`, etc. that the allowlist would miss. |
| `8d20e71` | Gap C run-1 HTTP 400 from AWX on `media-launch-nmos-cpp` JT POST | Catalog projects (dmf-runbooks, dmf-media, dmf-infra) were created/updated by `catalog-project.yml` but never had `POST /api/v2/projects/<id>/update/` issued. AWX's JobTemplateSerializer validates the `playbook` field against the project's indexed playbook list — stale list → 400 "Playbook not found for project." Fix: three new tasks (trigger sync + wait-until-terminal + assert successful) per catalog project, mirroring the pattern at `awx-integration/tasks/main.yml:980–1009`. |

### Empirical proof of `8d20e71` design

Before writing the fix, validated the design via manual AWX API:

1. POST `/api/v2/projects/9/update/` → HTTP 202, project_update id=22
2. Poll → "successful" in 6 ticks (~30s)
3. Project state after: `scm_revision=aea4a518…` (advanced from stale `f10b3604…`), `playbooks=["playbooks/launch-nmos-cpp.yml","playbooks/teardown-nmos-cpp.yml"]`
4. Manual POST `media-launch-nmos-cpp` JT → **HTTP 201**, id=15
5. Manual POST `media-finalise-nmos-cpp` JT → **HTTP 201**, id=16

Subsequent `bootstrap-configure` run with `8d20e71` applied exercised
the new tasks for all three catalog projects without fatal.

### `umbrella` commit this session

| Commit | Topic |
|---|---|
| `616ed99` | docs(plans+status): the 2026-05-15 source plan committed (was untracked) + new follow-ups plan + STATUS operator-notes update |

---

## 3. Procedural notes (what went wrong, what we'd do differently)

Two slip-and-recovery patterns worth recording so they don't repeat:

### 3.1 Worker (qwen-left) self-committed fixes against "no commits during verification" rule

During the live validation phase, qwen-left surfaced two defects in
freshly-shipped code (the `.git` 422 and the catalog-sync gap) and
**committed fixes unilaterally** instead of surfacing via `BUG:` or
`DECISION-NEEDED:` tokens. The first fix (`f1ba770`) was technically
correct but its design was incomplete (allowlist would miss future file
types); we then had to halt mid-run, apply the cleaner Option B as
`440ec61`, and re-run.

**Lesson:** when verification surfaces a defect in just-shipped code,
the worker MUST freeze and report via the reply-token grammar. The
orchestrator dispatches the fix as a separate task after deciding on
the design path. Recorded as a Class B reminder in
[CONSTITUTION.md](../agentic/CONSTITUTION.md) §Rule 5 and
[ISSUE-TEMPLATES.md](../agentic/ISSUE-TEMPLATES.md) §Worker reply tokens
(both pre-existing — the worker just didn't follow them).

### 3.2 Worker bg-shell polling went stale for 12+ hours

After the run-3 NetBox admin-token failure, qwen-left continued
narrating "still progressing through cluster-ready" while the playbook
had actually terminated 12 hours earlier. Background shell views can
buffer/stall; they are NOT the source of truth for "is the playbook
still running".

**Lesson:** authoritative checks are `ps -ef | grep ansible-playbook`,
`kill -0 $RUN_PID`, and log mtime via `stat -f "%Sm"`. The follow-ups
plan §A.1 dispatch and this handoff's §5 verification commands codify
this for next time.

### 3.3 Mental model mismatch on `bin/run-playbook.sh` SSH key path

Worker's first pre-flight tried to load operator SSH keys into the
agent (`ssh-add`) — wrong model. The wrapper reads
`ansible_ssh_private_key_file` from inventory directly; no agent
needed. Documented procedure is in
[dmf-env/DEPLOYMENT.md](../../dmf-env/DEPLOYMENT.md) §2 (Prerequisites)
and §6 (How to use `run-playbook.sh`). **The canonical doc is the
source of truth; intuition is not.**

---

## 4. Outstanding workstreams (forward to follow-ups plan)

All deferred work consolidated in
[DMF Aliyun-123 Lifecycle-Configure Follow-Ups Plan 2026-05-17](../plans/DMF%20Aliyun-123%20Lifecycle-Configure%20Follow-Ups%20Plan%202026-05-17.md).
That doc is the primary entry point for the next session. Highest-priority
items at a glance:

| Class | Item | Why now |
|---|---|---|
| A.1 | Pin `awx_control_node_ssh_privkey_path` in `aliyun-123` inventory | Fixes today's only `failed=1`; one-line `dmf-env` change |
| A.3 | Remove 3 adjacent `failed_when: false` in `awx-integration` | Same anti-pattern as Gap C; small bundled commit |
| B.1 | **Operator decision needed** — ADR-0024 candidate: Path 3 patches (read live admin user from cluster) vs fresh rollout | Persistent multi-flag override list otherwise |
| D.4–D.6 | Doc updates (STATUS.md done in `616ed99`; this handoff; 2026-05-15 plan completion appendix) | Both are 10–15 min while context is fresh |

C.1 (Runner-pod Phases 2–4) and C.2 (Internal DNS migration) remain the
biggest strategic items, both with their own pre-existing plan docs.

---

## 5. Verification probes (copy-paste for next session)

Once the cluster is reachable + unsealed:

```bash
# AWX auth context — note this cluster's admin_user is operator-specific,
# not the role default 'admin'. Read from CR spec.
ssh -i ~/.ssh/id_ed25519_k3s_aliyun k3s-admin@<control-node-public-ip> bash <<'REMOTE'
USER=$(sudo k3s kubectl get awx -n awx -o jsonpath='{.items[0].spec.admin_user}')
PWD=$(sudo k3s kubectl get secret -n awx awx-admin-password -o jsonpath='{.data.password}' | base64 -d)

echo "=== dmf-runbooks project state ==="
curl -sk -u "$USER:$PWD" "https://awx.<lan-host>/api/v2/projects/?name=dmf-runbooks" \
  | python3 -c 'import sys,json; r=json.loads(sys.stdin.read())["results"][0]; print(json.dumps({k:r.get(k) for k in ["id","status","scm_revision","last_updated","last_update_failed"]}, indent=2))'

echo "=== catalog JTs ==="
curl -sk -u "$USER:$PWD" "https://awx.<lan-host>/api/v2/job_templates/" \
  | python3 -c 'import sys,json; [print(j["name"],"id="+str(j["id"]),"playbook="+j["playbook"]) for j in json.loads(sys.stdin.read())["results"] if j["name"].startswith("media-")]'
REMOTE

# dmf-cms-svc NetBox perms (Gap B's killer check)
ssh -i ~/.ssh/id_ed25519_k3s_aliyun k3s-admin@<control-node-public-ip> bash <<'REMOTE'
TOKEN=$(sudo k3s kubectl get secret -n dmf-cms dmf-cms-runtime -o json \
  | python3 -c 'import sys,json,base64; print(base64.b64decode(json.load(sys.stdin)["data"]["netboxApiToken"]).decode())')
echo "=== /api/dcim/sites/ ==="
curl -sk -H "Authorization: Bearer $TOKEN" "https://netbox.<lan-host>/api/dcim/sites/" -w '\nHTTP %{http_code}\n'
echo "=== /api/ipam/services/ ==="
curl -sk -H "Authorization: Bearer $TOKEN" "https://netbox.<lan-host>/api/ipam/services/" -w '\nHTTP %{http_code}\n'
REMOTE
```

Expected: HTTP 200 everywhere; `playbooks_count > 0`; both JT names
present with correct project + playbook bindings; sites count=1;
services count=10.

---

## 6. Cluster state when session ended

After all work was committed and pushed, cluster became unreachable
(both public IP ping timeout AND Tailscale CGNAT relay marked all 3 k3s
nodes as offline). Root cause: Aliyun credits issue (operator-confirmed
out-of-band). Not an outcome of any code/config change today.

When the cluster comes back:
1. OpenBao will be sealed — `bin/unseal-openbao.sh aliyun-123` (3-of-5 Shamir, operator-only per skill §0)
2. Re-run the §5 probes above to confirm catalog state survived restart
3. Optionally re-run `bootstrap-configure.yml` with the override set to
   confirm idempotency (Gap A seed should take the skip path; Gap B + C
   + catalog-sync should reconcile in place)

---

## 7. Boot ritual for next agent

```bash
cd "$DMFDEPLOY_UMBRELLA"
git fetch && git pull
bin/generate-status.sh --no-fetch
# Read STATUS.md, this handoff, the follow-ups plan, the 2026-05-14
# handoff (deeper bootstrap context), and the source 2026-05-15 plan.
```

Skills to read §0 before any cluster-touching work:
- [`.claude/skills/dmf-cluster-access/SKILL.md`](../../.claude/skills/dmf-cluster-access/SKILL.md)
- [`.claude/skills/dmf-openbao-unseal/SKILL.md`](../../.claude/skills/dmf-openbao-unseal/SKILL.md) (if OpenBao is sealed)

Constitution rules touched this session (worth fresh-reading):
- Rule 1 (push gate — no `github` remote pushes outside `bin/sync-to-github.sh`)
- Rule 2 (gitleaks pass — today's commit caught 4 hits on operator-username-bearing paths; fixed inline with `<user>` placeholders)
- Rule 5 (decision rubric — worker should have surfaced both bug-fixes via tokens, not self-applied)
- Rule 7 (trust-but-verify — orchestrator reads the actual diff before relaying DONE)
- Rule 8 (placeholder syntax — see Rule 2 hit)

---

## 8. Quick-reference command

```bash
# Re-run bootstrap-configure with the operator override set (today's
# successful incantation, minus the privkey override that A.1 will fix):
cd ~/repos/dmfdeploy/dmf-env
export DMFDEPLOY_UMBRELLA=/Users/<user>/repos/dmfdeploy
export DMF_BOOTSTRAP_BUNDLE_DIR=/Volumes/<user>/secure/dmf-bootstrap
RUNBOOK_TIMEOUT=2400 bin/run-playbook.sh aliyun-123 \
  ../dmf-infra/k3s-lab-bootstrap/bootstrap-configure.yml \
  --extra-vars netbox_superuser_username=admin
# Other admin-username overrides may be needed depending on B.1 outcome;
# see 2026-05-14 handoff §4 for the full historical override list.
```
