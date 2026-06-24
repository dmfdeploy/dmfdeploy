# Open questions — Aliyun Frankfurt rollout

**Date:** 2026-05-08
**Source:** Review `docs/reviews/dmf-aliyun-frankfurt-readiness-review-2026-05-08.md` §10
**Updated:** 2026-05-08 — answers added based on operator input + code archaeology

---

## Q1: AppRole role_id scope (Review S2)

Both `hetzner-arm` and `aliyun-frankfurt` inventories carry `openbao_role_id: <openbao-role-id-netbox>`. Two interpretations:

| Option | Description |
|---|---|
| **A. Shared role** | One AppRole `dmf-infra` with a policy covering both `secret/data/k3s-hetzner/*` AND `secret/data/k3s-aliyun/*`. Same role_id, different secret_ids per env. Simpler. |
| **B. Separate role** | Mint a new AppRole for aliyun with policy scoped only to `secret/data/k3s-aliyun/*`. More isolation, per-environment blast-radius containment. |

### **Decision: B — Separate role + separate OpenBao instance per env.**

**Evidence:**

1. **`bin/bootstrap-operator-approle.sh:55`** takes a `scope` arg defaulting to `k3s-hetzner` and uses it as "the first path segment under secret/data/". The script comment at line 40 confirms this is the policy boundary. The hetzner role_id `<openbao-role-id-netbox>` therefore has policy scoped to `secret/data/k3s-hetzner/*` only — it cannot read `secret/data/k3s-aliyun/*`.
2. **`manifests/aliyun-frankfurt.yaml:133`** declares `key_root: secret/k3s-aliyun` — explicitly env-segregated.
3. **Per-env breakglass dirs** (`<secure-store>/openbao-breakglass/hetzner-lab/` vs `aliyun-frankfurt/`) and per-env keychain services (`openbao-approle-dmf-infra` vs `openbao-aliyun-frankfurt`) confirm the design intent is *per-env OpenBao instances*, not a shared one.

The current `<openbao-role-id-netbox>` value in `aliyun-frankfurt/openbao_secrets.yml` is a **copy-paste bug**, not intentional sharing. It would not work in practice (policy denies reads on `secret/data/k3s-aliyun/*`).

**Sub-issue uncovered while answering:** `openbao_url: "https://<wg-mesh-ip>:8200"` is identical in both inventories. This cannot be right if each env has its own OpenBao — the aliyun cluster's OpenBao needs a different endpoint reachable from the operator (likely a different Tailscale IP, or the cluster's public ingress at `https://aliyun.<lan-host>/...`). Flag as **Phase A item #7a** below.

**Action items folded into Phase A #7:**
- After aliyun cluster bootstrap reaches "OpenBao installed + initialized" (rollout step 5), run:
  ```bash
  bin/bootstrap-operator-approle.sh dmf-infra openbao-aliyun-frankfurt secret-id k3s-aliyun
  ```
  This mints a new AppRole on the *aliyun* OpenBao with `secret/data/k3s-aliyun/*` policy and updates `dmf-env/inventories/aliyun-frankfurt/group_vars/all/openbao_secrets.yml:openbao_role_id` in place.
- Before that step runs, fix `openbao_url` to point at the aliyun OpenBao's reachable endpoint (Tailscale IP of one of the aliyun nodes, populated after `321-tailscale.yml` registers them).

---

## Q2: Unseal flow ownership

`bin/unseal-openbao.sh` (skill `dmf-openbao-unseal`) is hetzner-arm-specific. Two paths:

| Option | Description |
|---|---|
| **A. Parametrize** | Add `--env` / positional env arg so the script reads breakglass shares from the env-specific JuiceFS path. |
| **B. Fork** | Create `bin/unseal-openbao-aliyun.sh` following the same Shamir flow. |

### **Decision: A — Parametrize.**

**Evidence:** `bin/unseal-openbao.sh` lines 42–47 already make all three location-specific values overridable via env vars:

```bash
SSH_TARGET="${OPENBAO_SSH_TARGET:-k3s-admin@<node-public-ip>}"
SHARE_DIR="${OPENBAO_SHARE_DIR:-<secure-store>/openbao-breakglass/hetzner-lab}"
SHARE_KEYCHAIN_NAME="${OPENBAO_KEYCHAIN_SERVICE:-openbao-breakglass-share-3}"
```

…so 80% of parametrization is already there. The remaining work is small.

**Implementation sketch:**

1. Accept positional `<env>` (default `hetzner-arm` for back-compat) → match the convention used by `tf-apply.sh` and `run-playbook.sh`.
2. When `<env>` is provided, set defaults from the manifest:
   - `SSH_TARGET` ← derived from `inventories/<env>/hosts.ini` (the `[k3s_control]` host) or a new `<env>` block in a small lookup. Operator can keep override via `OPENBAO_SSH_TARGET`.
   - `SHARE_DIR` ← `<secure-store>/openbao-breakglass/<env>/` (matches `manifests/<env>.yaml:secrets.breakglass.automation_json` parent dir).
   - `SHARE_KEYCHAIN_NAME` ← from `inventories/<env>/group_vars/all/openbao.yml:openbao_keychain_service` *of the breakglass keychain*, not the AppRole one. **Note:** the manifest's `share_distribution[].location: macos-keychain` for share 3 currently maps to a keychain entry that the operator creates manually after `bao operator init`. The aliyun-frankfurt keychain service for share 3 is not yet documented; recommend `openbao-breakglass-aliyun-frankfurt-share-3` as the convention.
3. Existing env-var overrides remain authoritative when set, so the existing hetzner-arm muscle memory still works.
4. Update skill `dmf-openbao-unseal` §0 to document the env arg.

**Why not fork:** two scripts diverge over time; the Shamir flow is identical across envs; the per-env values are already factored out. Forking would re-introduce the drift that ADR-0010 (sanctioned-entry wrappers) was designed to prevent.

**Timing:** does not block Phase A code-only fixes. Schedule for Phase B item #1, before first `bao operator init` against the aliyun cluster.

---

## Q3: Two-pass Tofu acceptable?

Alternative to guarding Cloudflare A-records behind SLB-length check: a separate `terraform/aliyun-frankfurt-dns/` workspace that runs after the cluster is up.

### **Decision: Two-pass guard (recommended).** Phase A #5 implements this.

**Why:** keeps everything in one workspace, one state file, one `tofu apply` mental model. The guard is a `count = length(...) > 0 ? 1 : 0` one-liner and the second pass is the same `bin/tf-apply.sh aliyun-frankfurt apply` command — no new workspace, no new state path, no new operator-script binding.

**Tradeoff accepted:** first pass produces a partial DNS state (records absent). Acceptable because:
- Tofu state still represents reality (no records yet ↔ count = 0 ↔ no resources to manage).
- Second pass after ingress playbook publishes A-records — Tofu treats them as `+ create`, not `~ update` of stale state.
- Idempotent on subsequent applies (records exist ↔ count = 1 ↔ no-op).

**Reject:** split workspace would require a second `bin/tf-apply.sh` env name, a second state file, cross-workspace dependency on the cluster output (data source against the first workspace's state) — strictly worse for a 5-line guard.

---

## Q4: Prefer fix-then-apply or apply-then-fix?

Implementing items 1-3 of Phase A is ~3h work; user may want to start ECS spend ASAP and patch in flight.

### **Decision: Fix-then-apply.** Confirmed by operator 2026-05-08: "no rush to start ecs."

**Order of operations:**

1. Land Phase A items 1-7 in their respective repos (`dmf-infra` for #1, `dmf-env` for #2-#7).
2. Run hetzner-arm regression (`bin/run-playbook.sh hetzner-arm ../dmf-infra/.../bootstrap-provision-pre-seed.yml --check`) to confirm Phase A changes don't break the working env.
3. Then proceed with §7 of the review (rollout procedure).
4. Phase B items can land alongside or after the rollout — none block the first apply.

---

## Resolution status

| Q | Decision | Status |
|---|---|---|
| Q1 | B — separate role per env; flag `openbao_url` copy-paste as Phase A #7a | ✅ Resolved 2026-05-08 |
| Q2 | A — parametrize `unseal-openbao.sh` (Phase B #1) | ✅ Resolved 2026-05-08 |
| Q3 | Two-pass Tofu guard (Phase A #5) | ✅ Resolved 2026-05-08 |
| Q4 | Fix-then-apply | ✅ Resolved 2026-05-08 by operator |

---

## New items surfaced while answering

These were not in the original §10 list but emerged from the answer evidence. Folded into the review's Phase A / Phase B as noted.

### N1: `openbao_url` is identical across envs (likely copy-paste bug)

`https://<wg-mesh-ip>:8200` appears in both `hetzner-arm` and `aliyun-frankfurt` openbao_secrets.yml. The hetzner inventory comment line 10 explicitly notes this is the hetzner cluster's OpenBao "via WireGuard wg2 tunnel." It cannot also be the aliyun cluster's OpenBao.

**Action:** Phase A #7a — after the aliyun cluster's `321-tailscale.yml` runs and assigns Tailscale IPs to the nodes, populate `inventories/aliyun-frankfurt/group_vars/all/openbao_secrets.yml:openbao_url` with the Tailscale IP of the aliyun control node (or whichever node hosts the OpenBao Service). Until then, the operator-side AppRole login from the operator's mac will resolve to the *hetzner* OpenBao, which doesn't have the aliyun policies.

### N2: Share-3 keychain service for aliyun not yet defined

`bin/unseal-openbao.sh:46` defaults to `openbao-breakglass-share-3` for hetzner. For aliyun, `manifests/aliyun-frankfurt.yaml:144-147` declares share 3 lives in `macos-keychain` but does not name the keychain service. Recommend convention `openbao-breakglass-<env>-share-3`.

**Action:** Phase B #1 (parametrization) names this convention. Operator must create the keychain entry after `bao operator init` and capturing share 3:

```bash
security add-generic-password \
  -s openbao-breakglass-aliyun-frankfurt-share-3 \
  -a share \
  -w   # prompts for the share value, never argv
```

### N3: Skill `dmf-openbao-unseal` §0 needs updating after Phase B #1

The skill's strict procedure currently encodes hetzner-arm assumptions. After parametrization, §0 must document the `<env>` positional arg and the per-env share-source defaults. Track as Phase B follow-up.

---

_Resolved: this doc is authoritative for the four questions plus the three new items above. Phase A and Phase B in the review are the implementation backlog._
