---
status: executed
date: 2026-06-01
executed: 2026-06-01
---
# DMF Hetzner CCM Upgrade Plan (2026-06-01)

**Status:** decision pending — operator chose "report only, I'll decide" on the
version strategy. No code changed yet. This doc is the self-contained context
for whoever picks up the actual bump.

**Hard deadline:** Hetzner removes the deprecated `server.datacenter` API field
**after July 2026** (operator email gives **30 June 2026** as the action-by
date). Any `hcloud-cloud-controller-manager` (hccm) ≤ **v1.30.0** will **panic
and crash within minutes** once the field is gone.

---

## 1. Why this exists (the trigger)

Hetzner emailed the operator (<operator-name>) flagging that project
**`k3s-infra-lab` (ID 14224671)** is sending API requests with an outdated
controller:

> User-Agent: `hcloud-cloud-controller/v1.26.0 hcloud-go/2.21.1`
> Please update … to at least **v1.30.1** … Once the API change takes effect,
> the controller will … crash within a few minutes. In this state hccm can no
> longer initialize new nodes, remove deleted nodes, or apply LoadBalancer
> changes via Service objects.

Cause: Hetzner is phasing out the `"datacenter"` API property in favor of
`"location"` for Primary IPs and Servers.
Changelog: https://docs.hetzner.cloud/changelog#2025-12-16-phasing-out-datacenters
Tracking issue: https://github.com/hetznercloud/hcloud-cloud-controller-manager/issues/1146#issuecomment-3919929223

`k3s-infra-lab` is the `hcloud_context` of the current live env **`g2r6-foa9`**.

---

## 2. Where it's pinned (exact files)

The Hetzner CCM is installed by an Ansible task that applies the official
static manifest by release-tagged URL. **One** version default governs all
Hetzner envs:

| File | Line | Content |
|---|---|---|
| `dmf-env/tasks/hetzner/ccm.yml` | 15 | `hcloud_ccm_version: "{{ hcloud_ccm_version \| default('v1.26.0') }}"` |
| `dmf-env/tasks/hetzner/ccm.yml` | 46 | applies `.../releases/download/{{ hcloud_ccm_version }}/ccm-networks.yaml` |

**No inventory overrides `hcloud_ccm_version`** — every Hetzner env inherits the
`v1.26.0` default. Envs wire the task in via `cluster_ingress_provider_tasks`:

- `dmf-env/inventories/g2r6-foa9/group_vars/all/main.yml:30` (current live env;
  `hcloud_context: "k3s-infra-lab"` at :12, `hcloud_ccm_network` at :36)
- `dmf-env/inventories/hetzner-arm/group_vars/all/main.yml:24` (template/profile)

The CCM manifest is applied **live, at playbook run time**, from the URL. So a
code change to the default does **not** retroactively change a running cluster —
it only takes effect on the next playbook re-run or fresh redeploy.

Aliyun envs are **unaffected** — they use a separate `alicloud` CCM in
`dmf-env/tasks/aliyun/ccm.yml`. This issue is Hetzner-only.

---

## 3. The version coupling (the non-obvious part)

hccm's version is **decoupled from Kubernetes versions**. The current cluster
runs **k3s `v1.30.6+k3s1`** (k8s 1.30), pinned at
`dmf-infra/k3s-lab-bootstrap/playbooks/300-k3s.yml:56` and `:153`. k8s 1.30 is
already **EOL upstream**.

hccm official compatibility matrix
(`docs/reference/version-policy.md` in the hccm repo, "With Networks support"):

| Kubernetes | Recommended hccm |
|---|---|
| 1.30 | **v1.26.0** ← current pin; matrix-correct for k8s 1.30, but below the fix floor |
| 1.31 | v1.29.2 |
| 1.32 | **v1.30.1** ← datacenter-fix floor |
| 1.33 – 1.36 | latest (currently **v1.31.1**) |

**The tension:** v1.26.0 is the *matrix-correct* hccm for our k8s 1.30, but it's
below the v1.30.1 floor that contains the datacenter fix. v1.30.1 is CI-tested
against **k8s 1.32**, not 1.30. hccm's version policy says EOL'd pairings aren't
necessarily broken — just unsupported and bug-fix-excluded. The CCM surface is
narrow (node lifecycle + LB reconciliation), so v1.30.1 will **very likely run
fine on k8s 1.30** — but the *clean* fix bumps k3s and hccm together.

Confirmed facts (checked 2026-06-01 against the hccm GitHub repo):
- Latest hccm release is **v1.31.1**.
- The `ccm-networks.yaml` asset is still published per-release, so the manifest
  URL scheme in `ccm.yml:46` still works unchanged for any target version.

---

## 4. Decision required (operator)

Pick a version path. All three are a **one-line change** to `ccm.yml:15`
(set/override `hcloud_ccm_version`), optionally plus a k3s bump in
`300-k3s.yml:56` and `:153`.

| # | Path | hccm | k3s | Tradeoff |
|---|---|---|---|---|
| 1 | **Minimal** | v1.30.1 | unchanged (1.30.6) | Smallest change, beats deadline. Off-matrix on k8s 1.30 (untested pairing, very likely fine). Leaves cluster on EOL k8s. |
| 2 | **Matrix-aligned** | v1.30.1 | 1.32.x | Supported pairing; moves k3s off EOL. Larger blast radius — k3s minor bump + full redeploy/validation. |
| 3 | **Most current** | v1.31.1 | 1.33+ | Longest-lived, matrix "latest". Biggest k3s jump, most validation churn. |

Recommendation if minimizing risk-now: **Path 1** to clear the deadline, with
Path 2/3 folded into a future planned k3s upgrade. Recommendation if the
g2r6 wipe+redeploy is imminent anyway: do **Path 2** as part of that redeploy
(one validation pass covers both bumps).

---

## 5. Live `g2r6-foa9` handling (decided)

Operator decision (2026-06-01): **leave g2r6 / tear it down.** g2r6 is throwaway,
mid-rehab with organic drift (see STATUS.md "Upgrade-in-place BLOCKED + g2r6
mid-rehab"), and slated for wipe+redeploy. It will be destroyed before the
deadline, so its *running* hccm version doesn't matter — **only the code default
does**, so the next env builds clean.

⚠️ If g2r6 (or any Hetzner env) is *not* torn down before 30 June 2026, it must
be patched in place: re-run the Hetzner CCM task against it after bumping the
version (the manifest re-applies idempotently). Otherwise hccm crashes and the
cluster loses node lifecycle + LoadBalancer reconciliation.

---

## 6. How to apply the fix (when the path is chosen)

1. Edit `dmf-env/tasks/hetzner/ccm.yml:15` — change the default
   `'v1.26.0'` → the chosen version (e.g. `'v1.30.1'`).
   - Alternative (cleaner if you want to keep the role default conservative):
     set `hcloud_ccm_version` per-env in the inventory `group_vars` instead.
2. (Paths 2/3 only) Edit `dmf-infra/k3s-lab-bootstrap/playbooks/300-k3s.yml:56`
   and `:153` — bump `k3s_version`. Validate k3s release args / channel.
3. Apply by re-running the deploy on the target env via
   `dmf-env/bin/run-playbook.sh <env-name>` (substitute the live env from
   STATUS.md), or via a fresh wipe+redeploy.
4. `dmf-env` is a shared checkout — verify `HEAD == main` and ask before
   touching dirty state (CLAUDE.md boot ritual step 5).

### Verification after apply
- `kubectl -n kube-system get deploy hcloud-cloud-controller-manager -o jsonpath='{.spec.template.spec.containers[0].image}'`
  → confirms the new tag is live.
- `kubectl -n kube-system logs deploy/hcloud-cloud-controller-manager | head`
  → no datacenter/location panics; CCM initialized.
- Confirm nodes have `spec.providerID: hcloud://<id>` (the task patches these;
  see `ccm.yml` "Patch nodes with Hetzner providerIDs").
- Confirm the Traefik LoadBalancer Service is reconciled (external IP present,
  targets registered) — that's the user-visible symptom if CCM is broken.
- After 30 June 2026 / once Hetzner removes the field: re-check CCM logs for
  crashes on any surviving env.

---

## 7. References

- hccm repo: https://github.com/hetznercloud/hcloud-cloud-controller-manager
- Version policy / compat matrix: `docs/reference/version-policy.md` in that repo
- Datacenter phase-out changelog: https://docs.hetzner.cloud/changelog#2025-12-16-phasing-out-datacenters
- Tracking issue #1146: https://github.com/hetznercloud/hcloud-cloud-controller-manager/issues/1146#issuecomment-3919929223
- Related DMF context: STATUS.md (g2r6 wipe+redeploy recommendation),
  `dmf-env/tasks/hetzner/ccm.yml`, `dmf-env/tasks/aliyun/ccm.yml` (unaffected).
