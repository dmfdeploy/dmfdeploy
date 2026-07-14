---
name: dmf-init-manage-playbook
description: Use dmf-init to restore a DMF sandbox env from a /tmp backup and iterate on ONE playbook via the Manage API (restore → lock → rerun-playbook → stream), without a full from-scratch bootstrap. For agents working on a single playbook/role (e.g. an Authentik blueprint, a vertical-security play) who need to re-apply and verify against the live env. Covers launch, restore, the repo-checkout-advance gotcha, streaming, source-of-truth verification, and teardown. Env slug rotates; current sandbox id under /tmp/dmf-init-montest.
type: operational-procedure
scope: live-env
owner: operator
review_by: '2027-01-14'
---

# DMF-init: restore-from-backup + manage playbook runs

**Scope:** the **local sandbox** lifecycle, where `dmf-init` runs as a localhost
process (not a container) and an env was bootstrapped by the e2e harness under a
tmpfs-style data root in `/tmp`. This is the path an agent uses to **re-apply and
verify ONE playbook** against an existing env without paying for a full
`reset → bootstrap` (~55 min). Two transports exist:

- **Mode A — dmf-init Manage API (this skill's focus).** When the env's on-disk
  state is gone/stale, or you specifically want the sanctioned `dmf-init` path:
  launch dmf-init, **restore from the dual-remote `/tmp` backup**, then drive
  `lock → rerun-playbook` over HTTP.
- **Mode B — direct `run-playbook.sh`.** When the env was *just* bootstrapped and
  its state is live on disk under `$DATA_ROOT` (e.g. straight after an e2e run),
  you can skip the restore and call the wrapper directly (see §7). Same repo
  rules and verification apply.

The canonical reference is `dmf-init/test/e2e/` (the harness drives the very same
`/api/...` endpoints) and `dmf-init/src/dmf_init/main.py` (route definitions).

---

## 🛑 §0 Secrets discipline (read first)

Same hard rules as `dmf-cluster-access` / `dmf-openbao-unseal`. Specific to this flow:

1. **The restore passphrase is a secret.** Put it in a **payload file**, never in
   `curl` argv (`ps`-readable). For the fixed sandbox operator the passphrase is the
   known test fixture `montest-test-pass` (already tracked in
   `dmf-init/test/e2e/profile.montest.env`) — for any non-sandbox env treat it as a
   real secret and source it out-of-band.
2. **Never `cat` the env's secret material** — `…/envs/<env>/openbao-keys.json`,
   `…/runs/<env>/age/keys.txt`, the decrypted bundle. Reference the *paths*; let the
   tooling read them.
3. The dmf-init **launch token** is printed to the app log; it's loopback + single-use
   and fine to use within the session, but don't paste it anywhere persistent.
4. Treat any session that restored an env as holding live credentials for that env;
   rotate per the cluster-access rules if it was a real (non-sandbox) env.

---

## 1. Orientation — the moving parts

| Thing | Sandbox default | Notes |
|---|---|---|
| Data root | `/tmp/dmf-init-montest` | `DMF_DATA_ROOT`. Holds `envs/<env>/`, `runs/<env>/`, `repos/`. |
| Repo source | `/tmp/dmf-init-reposrc` | `DMF_REPO_BASE_URL=file://…`. **Symlinks to your working clones** (`…/dmf-infra.git -> ~/repos/dmfdeploy/dmf-infra/.git`). |
| Backups | `/tmp/backups/a`, `/tmp/backups/b` | Dual-remote. Artifacts: `backups/dmf-backup-<env>-<UTCstamp>.tar.age`. |
| Bind port | `8091` | `DMF_BIND_PORT`. Loopback only. |
| Operator | `montest-op` / `montest@dmf.test` | Passphrase `montest-test-pass`. |
| Env id | rotates (`xxxx-xxxx`) | Discover with `ls /tmp/dmf-init-montest/envs/` and `limactl list` (VM `dmf-sandbox`). |
| Age key | `…/runs/<env>/age/keys.txt` | NOT the sops default — for any `SOPS_AGE_KEY_FILE` use this. |
| Cluster SSH | `"$USER"@<vm-ip>` | guest user = your `$USER`; key `…/envs/<env>/ssh/sandbox-node.key`; `sudo k3s kubectl …`. |

These sandbox paths come from `dmf-init/test/e2e/profile.montest.env`. Don't hard-code
the env id — read it.

> **Commit before you run.** Fetched repos clone from **committed** `.git` only, and
> the reposrc symlinks point at your working clone. An uncommitted fix is invisible
> to every restore/bootstrap. Commit on `main` first (push is the operator's call).

---

## 2. Find the backup and discover the env

```bash
ls /tmp/dmf-init-montest/envs/                       # the env id(s)
ls -lt /tmp/backups/a/backups/                       # newest dmf-backup-<env>-*.tar.age
limactl list | grep dmf-sandbox                      # VM up? note nothing else
```

Pick the **newest** `dmf-backup-<env>-<stamp>.tar.age`. It exists in both
`/tmp/backups/a` and `/tmp/backups/b` (dual-remote).

---

## 3. Launch dmf-init (loopback :8091)

```bash
cd ~/repos/dmfdeploy/dmf-init
DMF_DATA_ROOT=/tmp/dmf-init-montest \
DMF_REPO_BASE_URL=file:///tmp/dmf-init-reposrc \
DMF_BIND_PORT=8091 \
DMF_SESSION_TTL_SECONDS=14400 \
uv run python -m dmf_init.main >/tmp/dmf-init-manage.log 2>&1 &
```

Wait for health and grab the **launch token**:

```bash
until curl -fsS -m2 http://127.0.0.1:8091/healthz >/dev/null 2>&1; do sleep 1; done
TOKEN=$(sed -n 's/^launch token: //p' /tmp/dmf-init-manage.log | head -1); echo "$TOKEN"
```

Establish a session cookie:

```bash
COOKIE=/tmp/dmf-init-manage.cookies; rm -f "$COOKIE"
curl -fsS -L -c "$COOKIE" "http://127.0.0.1:8091/?token=${TOKEN}" >/dev/null
```

---

## 4. Restore the env from the /tmp backup

Build the payload as a **file** (keeps the passphrase out of argv). `dest_remotes`
must be **exactly two**. Local backups use rclone `type: alias`.

```bash
ENV=<env-id>                          # e.g. gn0f-iteu
ARTIFACT=dmf-backup-${ENV}-<stamp>.tar.age
cat > /tmp/manage-restore.json <<JSON
{
  "source_remote": {"name":"backup-a","type":"alias","options":{"remote":"/tmp/backups/a"},"destination_prefix":"backups"},
  "source_artifact": "${ARTIFACT}",
  "passphrase": "montest-test-pass",
  "dest_remotes": [
    {"name":"backup-a","type":"alias","options":{"remote":"/tmp/backups/a"},"destination_prefix":"backups"},
    {"name":"backup-b","type":"alias","options":{"remote":"/tmp/backups/b"},"destination_prefix":"backups"}
  ]
}
JSON

curl -sS -b "$COOKIE" -H 'content-type: application/json' \
  -d @/tmp/manage-restore.json \
  http://127.0.0.1:8091/api/manage/restore | tee /tmp/restore.json
```

Success looks like `{"session_id":"…","env_id":"<env>","checkpoint":N,"verified":true,
"age_key_path":"…","render_dir":"…","repos":[…]}`. **Capture the session id**:

```bash
SID=$(python3 -c 'import json;print(json.load(open("/tmp/restore.json"))["session_id"])')
```

> The restore re-materialises `envs/<env>/`, `runs/<env>/age/keys.txt`, the answers
> file, and **checks out each repo at the backup's pinned SHA** (see §6 — you will
> usually need to advance one).

(Optional) prove the env is healthy without changing anything — `doctor` streams like
any run:

```bash
RID=$(curl -sS -b "$COOKIE" -H 'content-type: application/json' -d "{\"session_id\":\"$SID\"}" \
  http://127.0.0.1:8091/api/manage/doctor | python3 -c 'import json,sys;print(json.load(sys.stdin)["run_id"])')
curl -sS -N -b "$COOKIE" "http://127.0.0.1:8091/api/bootstrap/stream/$RID"
```

---

## 5. Acquire the manage lock

`lock/acquire` runs a **drift check** against the env bundle and takes a TTL lock.
(The drift check is on the env *bundle*, not repo HEAD — so advancing a repo checkout
in §6 is drift-safe.)

```bash
curl -sS -b "$COOKIE" -H 'content-type: application/json' -d "{\"session_id\":\"$SID\"}" \
  http://127.0.0.1:8091/api/manage/lock/acquire
```

`{"held":true,…}` = good. Re-run it any time; `action/start` re-validates the lock and
tells you to re-acquire if it lapsed.

---

## 6. ⚠️ Advance the repo checkout to YOUR commit (the #1 gotcha)

Restore pins each repo at the **backup's** SHA — *not* your new work. `rerun-playbook`
uses the checkout **as-is** (it does NOT re-pin), so point it at your commit. The
reposrc symlinks to your working clone, so a committed change is fetchable:

```bash
REPO=dmf-infra                                   # the repo your playbook lives in
WORK_SHA=$(git -C ~/repos/dmfdeploy/$REPO rev-parse HEAD)   # your committed fix on main
git -C /tmp/dmf-init-montest/repos/$REPO fetch origin
git -C /tmp/dmf-init-montest/repos/$REPO checkout "$WORK_SHA"
# sanity: confirm your change is in the checked-out file
grep -n '<something unique to your change>' \
  /tmp/dmf-init-montest/repos/$REPO/k3s-lab-bootstrap/.../your-file
```

If the checkout refuses due to a dirty tracked file, inspect the diff first; if it's a
redundant edit already present in your target commit, `git checkout -- <file>` then retry.

---

## 7. Run the playbook

`params.playbook` is **relative to `$DATA_ROOT/repos`**. Allowed actions:
`rerun-playbook | upgrade-in-place | rotate | teardown`.

```bash
PB="dmf-infra/k3s-lab-bootstrap/playbooks/vertical-security/110-authentik.yml"
RID=$(curl -sS -b "$COOKIE" -H 'content-type: application/json' \
  -d "{\"session_id\":\"$SID\",\"action\":\"rerun-playbook\",\"params\":{\"playbook\":\"$PB\"}}" \
  http://127.0.0.1:8091/api/manage/action/start | python3 -c 'import json,sys;print(json.load(sys.stdin)["run_id"])')

# stream NDJSON to a file and watch the recap
curl -sS -N -b "$COOKIE" "http://127.0.0.1:8091/api/bootstrap/stream/$RID" > /tmp/run.ndjson
grep -E 'PLAY RECAP|ok=[0-9]+.*changed|failed=[1-9]|step_complete|"event":"(complete|error)"' /tmp/run.ndjson | tail
```

**Mode B (no restore, live on-disk env)** — same playbook, direct wrapper:

```bash
cd ~/repos/dmfdeploy/dmf-env
DMF_DATA_ROOT=/tmp/dmf-init-montest \
SOPS_AGE_KEY_FILE=/tmp/dmf-init-montest/runs/$ENV/age/keys.txt \
RUNBOOK_TIMEOUT=5400 \
bin/run-playbook.sh "$ENV" /tmp/dmf-init-montest/repos/$PB
```

---

## 8. Verify at the source of truth (NOT the playbook recap)

A green `PLAY RECAP` only means Ansible's tasks ran — it does **not** prove the app
reconciled (see Authentik gotchas below). Check the actual cluster state. Example for
an Authentik blueprint change via `ak shell`:

```bash
KEY=/tmp/dmf-init-montest/envs/$ENV/ssh/sandbox-node.key
cat > /tmp/q.py <<'PY'
from authentik.flows.models import FlowStageBinding, Flow
f = Flow.objects.get(slug="dmf-bootstrap-passkey-enrollment")
for b in FlowStageBinding.objects.filter(target=f).order_by("order"):
    print(b.order, type(b.stage).__name__, b.stage.name)
PY
cat /tmp/q.py | ssh -i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "$USER"@<vm-ip> "sudo k3s kubectl -n authentik exec -i deploy/authentik-server -- ak shell" \
  | grep -vE 'Warning: Permanently'
```

For a passkey-flow change you can also drive Authentik's flow-executor API to see the
first stage component (`*.dmf.test` resolves to the VM via the LAN wildcard, no
`/etc/hosts` edit): seed the session at `/if/flow/<slug>/?itoken=…`, then
`GET /api/v3/flows/executor/<slug>/?query=itoken%3D<itoken>` with `-L` and a cookie jar.

---

## 9. Teardown

```bash
curl -sS -b "$COOKIE" -H 'content-type: application/json' -d "{\"session_id\":\"$SID\"}" \
  http://127.0.0.1:8091/api/manage/lock/release   # 409 "acquire first" = already released, fine
pkill -f 'dmf_init.main'                            # stop the loopback server
limactl list | grep dmf-sandbox                     # leave the VM RUNNING (it's the live env)
```

Leave the Lima env VM up; only stop the dmf-init process.

---

## Gotchas (all observed live)

- **Commit-on-`main` or it's invisible.** Reposrc clones committed state only.
- **Restore pins the backup SHA** → always do §6 before running your change.
- **Authentik blueprints don't prune.** Removing a stage/binding from the YAML leaves
  the object in the DB; add `state: absent` tombstones to delete on existing envs
  (no-op on fresh).
- **Authentik ConfigMap propagation race (~60s).** The blueprint mounts via the
  `authentik-blueprints` ConfigMap; the playbook updates the CM then triggers an
  apply *before* kubelet refreshes the pod's mounted file, so the **first** post-change
  run reconciles stale content. Run the playbook **twice** (or wait ~60s). The 2nd run
  typically shows fewer `changed=` (the delta landed).
- **Setting `pending_user` from a policy** needs `request.context["flow_plan"].context[...]`,
  not `request.context[...]` (the policy context is a copy). Same memory note.
- **Don't `--keep`-leak processes.** The e2e cleanup trap kills helper PIDs (dmf-init,
  ssh-agent, tunnels) but never the VM; if you launched dmf-init yourself, `pkill` it (§9).
- **env id rotates** — re-read it every session; never hard-code last session's slug.
