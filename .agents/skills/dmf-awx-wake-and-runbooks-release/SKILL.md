---
name: dmf-awx-wake-and-runbooks-release
description: Wake AWX correctly before any playbook that talks to its API, and ship a dmf-runbooks change all the way to a cluster (tag → Forgejo mirror → AWX project pin → 693 → verify). Encodes the four traps that make this look like it worked when it did not. Use before running 693/640 or any AWX-API playbook, and for every dmf-runbooks release.
type: operational-procedure
scope: cross-repo
owner: operator
review_by: '2027-02-18'
---

# AWX wake + dmf-runbooks release

Two procedures that always travel together: a dmf-runbooks change only reaches a
cluster through AWX, and every step that touches AWX needs it awake first.

**Every trap below cost real time and every one of them looks like success at
the moment it fails.** That is the point of this file.

---

## §0 Read first — the five traps

1. **`kubectl scale` does NOT wake AWX.** `awx-operator` reconciles
   `awx-task`/`awx-web` against the AWX custom resource and reverts a manual
   scale. It will read `1/1` for a minute — long enough for a readiness check
   to pass — and be back at `0/0` before your playbook's first API call.
2. **A converged playbook run cannot keep AWX awake.** The idle-reaper counts
   only AWX **mutations** (activity-stream entries) as activity, with a grace
   period (default 300s). A re-apply that reports `changed=0` mutates nothing,
   so it goes quiet and gets slept out from under itself mid-run. **The
   safest-looking case — a no-op re-apply — is the one that fails.**
3. **`| tail` masks the exit code.** `playbook ... | tail -30` reports *tail's*
   exit status. A failed run reads as success. Redirect to a file instead and
   record the real code.
4. **`count: 0` from the AWX API is not absence.** Console/service tokens are
   RBAC-scoped and return zero for objects they cannot see. Never read it as
   "the object does not exist" — verify on disk instead (§4).
5. **A second `/ensure-awake` returns 200 and renews nothing.** The wake window
   lives on an owner-scoped Lease; a later caller is a different holder, so it
   waits for readiness and returns the existing lease untouched. Both outcomes
   are HTTP 200 and differ only in the response *body*. A repeated-call
   keep-alive therefore does not hold AWX open (§1).

---

## §1 Waking AWX — the sanctioned way, no secret handling

The wake credential already lives in the **console pod**, so you never need to
retrieve it from OpenBao. Have the pod call the helper with its own env vars —
the identical call the console makes on a provision click:

```bash
kubectl -n dmf-cms exec deploy/dmf-cms -- python3 -c "
import os, urllib.request
url = os.environ['DMF_CONSOLE_AWX_AUTOSCALE_HELPER_URL'].rstrip('/') + '/ensure-awake'
req = urllib.request.Request(url, data=b'{}', method='POST')
req.add_header('Authorization', 'Bearer ' + os.environ['DMF_CONSOLE_AWX_AUTOSCALE_BEARER_TOKEN'])
req.add_header('Content-Type', 'application/json')
print(urllib.request.urlopen(req, timeout=300).read().decode())
"
# -> {"ok":true,"detail":"awake and ready"}
```

The token is never printed and never enters `argv`, so **no rotation is
required afterwards** — unlike retrieving it from OpenBao, which would make
this session compromised for that secret's lifetime.

`/ensure-awake` is single-flight: it is safe to call repeatedly, and it is how
you wake AWX. It is **not** a keep-alive — see below.

### Holding it awake for a long run

**A repeated `/ensure-awake` loop does NOT extend the window. Do not use one.**

The helper holds an owner-scoped `coordination.k8s.io/Lease` carrying
`min_awake_until`. The holder identity is per-request
(`awx-autoscale-<pid>-<thread>`), so a *later* call is a different holder, and
`create_or_update` acquires **only if the lease is expired or already ours** —
otherwise it returns the existing lease **unchanged** and merely waits for
readiness. `min_awake_until` is never pushed out.

It is structurally useless rather than mistuned: the Lease is written with
`leaseDurationSeconds = MAX_STARTUP_WAIT + GRACE_PERIOD` (defaults 1200 + 300 =
**1500s**), so any keep-alive interval short enough to matter falls inside an
active lease and takes the non-holder path every time.

**How to tell which path you got** — log the response *body*, not just the
status code:

- `{"ok":true,"detail":"awake and ready"}` — you were the holder; the window
  was written.
- `{"ok":true,"detail":"awake (holder ... woke)"}` — non-holder; **nothing was
  renewed**. Both are HTTP 200, so a status-only log cannot tell them apart.
  Confirm in the helper's audit log: `ensure_awake_non_holder`.

**The procedure that actually works** is to widen the grace period for the
duration of the run, then put it back:

```bash
kubectl -n awx set env deploy/awx-autoscale AWX_AUTOSCALE_GRACE_PERIOD=5400
# ... run the long playbook ...
kubectl -n awx set env deploy/awx-autoscale AWX_AUTOSCALE_GRACE_PERIOD=300
```

Read the value back both times rather than trusting the write.

**Always revert it.** A long grace defeats the scale-to-zero behaviour the demo
narrative depends on — the presenter is meant to show AWX re-idling to zero. A
live `set env` is also not persisted: the next `awx-autoscale-deploy.yml` run
reverts it, so the cluster and the repo default silently disagree until then.

### Readiness is not `readyReplicas`

Check the API actually answers, not the deployment's replica count:

```bash
kubectl -n awx exec deploy/awx-web -c awx-web -- \
  python3 -c "import urllib.request;print(urllib.request.urlopen('http://127.0.0.1:8052/api/v2/ping/',timeout=8).status)"
```

---

## §2 Releasing dmf-runbooks

Releases are a VERSION-bump commit, then a tag on it — `main` is protected, so
the bump rides a PR.

1. Merge the change.
2. PR: `VERSION` → the new version, commit
   `chore(release): X.Y.Z — <summary> (Refs dmfdeploy/dmfdeploy#N)`.
3. After merge, tag the **merged** commit and push:
   `git tag -a vX.Y.Z -m "Release vX.Y.Z" <sha> && git push origin vX.Y.Z`.

Never tag before the bump merges: a rebase-merge gives the commit a new sha, so
a tag cut early points at a commit that never lands.

---

## §3 Getting it onto a cluster

AWX pins the dmf-runbooks project **by release tag**, and pulls from the
**cluster-internal Forgejo**, which is a *pull mirror* of the upstream repo. So
a tag pushed upstream is invisible to AWX until the mirror syncs.

1. **Sync the mirror.** The mirror has an interval (1h by default) and a
   *Synchronize now* button in the Forgejo UI. The API endpoint is
   `POST /repos/{owner}/{repo}/mirror-sync`, but its credential is in OpenBao —
   prefer the operator clicking the button over retrieving a secret for a step
   you will run twice.
2. **Bump the pin** — a PR in **dmf-infra**, not a flag:
   `k3s-lab-bootstrap/roles/stack/operator/awx-integration/defaults/main.yml`,
   the `dmf-runbooks` entry's `scm_branch`.
   Follow the convention in that file: each bump carries an inline **JT
   contract audit**. Run it, do not copy the previous one's conclusion —
   `git -C ../dmf-runbooks diff vOLD..vNEW -- '*/defaults/*'` plus a full
   `--stat`, and state explicitly whether any job-template registration or
   `extra_vars` surface changed. A non-empty defaults diff is not automatically
   JT-facing: role vars that are empty-defaulted and set from play-internal
   values are not `extra_vars`.
   **Do not open this PR before the tag exists** — it would point the next 693
   run anyone does at a tag that is not there.
3. **Wake AWX** (§1), then run 693:
   `bin/run-playbook.sh <env> ../dmf-infra/k3s-lab-bootstrap/playbooks/693-awx-integration.yml`
   Redirect to a file; do not pipe (trap 3).

---

## §4 Verify the pin actually moved

`changed=0` from 693 does **not** mean nothing happened — a previous partial run
may already have applied it. And the AWX API may answer `count: 0` for a
token that cannot see projects (trap 4). Verify against the project checkout on
disk, which needs no credential:

```bash
kubectl -n awx exec deploy/awx-task -c awx-task -- sh -c '
  ls -d /var/lib/awx/projects/*/                       # find the project dir
  cat /var/lib/awx/projects/_N__dmf_runbooks/VERSION
  git -C /var/lib/awx/projects/_N__dmf_runbooks describe --tags'
```

Both must read the version you just shipped. Grep the checkout for a symbol
your change introduced as a third, independent check that the code — not just
the tag — is present.

---

## §5 Only new work gets the change

A launcher change affects **newly provisioned** workloads only. Existing NetBox
records keep whatever the launcher wrote when they were created. If you are
verifying a launcher change, provision fresh — and be aware that a torn-down
workload may have had launcher-written tags stripped, so it is not a valid
subject either.

---

## Related

- `dmf-cms-build-and-release` — the console's own release path (630/650).
- `dmf-cluster-access` — §0 secrets discipline; the rule this file's §1 exists
  to satisfy.
