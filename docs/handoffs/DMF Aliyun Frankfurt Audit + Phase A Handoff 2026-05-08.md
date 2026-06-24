# DMF Aliyun Frankfurt — Audit + Phase A Handoff

**Date:** 2026-05-08 (late afternoon)
**Audience:** Next session picking up the aliyun rollout, or any agent landing in this workspace cold.
**Co-authors this session:** Claude (audit + review docs), Qwen-Coder (Phase A implementation).
**Prior handoff:** [`DMF Bootstrap Implementation Progress Handoff 2026-05-08.md`](DMF%20Bootstrap%20Implementation%20Progress%20Handoff%202026-05-08.md) — earlier today; Tier 1 bootstrap split landing.

---

## TL;DR

- A new **`aliyun-frankfurt`** environment was scaffolded (Tofu + inventory + manifest) and audited.
- **Four blockers + 11 security findings** caught during audit. Documented in [`docs/reviews/dmf-aliyun-frankfurt-readiness-review-2026-05-08.md`](../reviews/dmf-aliyun-frankfurt-readiness-review-2026-05-08.md).
- **Phase A blockers all cleared** by Qwen-Coder during this session (`dmf-infra@033d438`, `dmf-env@31f6a78`).
- **No live ECS yet** — operator confirmed "no rush." First Tofu apply against Aliyun is still pending operator decision.
- **Future-direction note** captured for per-resource provider+pricing chooser ([`docs/plans/dmf-multi-provider-resource-selection-future-direction-2026-05-08.md`](../plans/dmf-multi-provider-resource-selection-future-direction-2026-05-08.md)) — explicitly out of scope today.

---

## What landed

### dmf-env

| Commit | What |
|---|---|
| `cbccf8b` (14:43) | Aliyun Frankfurt scaffold — manifest, Tofu module, inventory group_vars, `tf-apply.sh` Alicloud branch, `tf-destroy.sh` guard, `.sops.yaml` recipient block, `terraform/README.md` rewrite for both envs. |
| `806b6bd` (16:06) | Phase A #6 — `.sops.yaml` populated with real age pubkey (`age1x0gntu7fy3vu7uh4mdgvl2n52wwfmd35wulh0g620ce964stj9rqnhjc8z`); both hetzner-arm and aliyun-frankfurt blocks updated, TODOs removed. |
| `31f6a78` (15:55) | Phase A items #2–#5, #7 from the readiness review:<br>• `bootstrap-secrets.sh` env-aware schema validation (hcloud OR alicloud), `cmd_init` reads `~/.secure/aliyun/.ay-dmfdeploy`, `cmd_seed_bao` writes `secret/platform/alicloud`, `cmd_export_vars` emits `vault_alicloud_*`, doctor/status display alicloud fields.<br>• `run-playbook.sh` swapped from `export-openbao-vars.sh` to `bootstrap-secrets.sh export-vars` (provider-agnostic).<br>• `tasks/aliyun_slb.yml` real Alicloud CCM install (secret, manifest, deployment patch, readiness wait, providerID patch) — no longer a stub.<br>• `terraform/modules/aliyun-cluster/main.tf` Cloudflare A-records guarded behind `count = local.has_slb ? 1 : 0` for two-pass apply.<br>• `terraform/aliyun-frankfurt/outputs.tf` adds `vswitch_id` for CCM.<br>• `inventories/aliyun-frankfurt/group_vars/all/openbao_secrets.yml` removes the copy-paste role_id and `openbao_url` (placeholders + post-bootstrap instructions).<br>• `inventories/.../main.yml` adds `alicloud_ccm_region` and `alicloud_ccm_vswitch_id` for CCM tasks. |

### dmf-infra

| Commit | What |
|---|---|
| `033d438` (15:55) | Phase A item #1 — `playbooks/219-host-verify.yml` hcloud block (7 tasks) gated `when: cluster_ingress_provider_tasks is search('hetzner_ccm')`. Summary section uses `default([])` to skip safely when vars are undefined. |

### dmfdeploy (umbrella)

| Commit | What |
|---|---|
| `9b6d6f6` | Review doc, questions doc with resolved decisions, future-direction note, STATUS.md regenerated. |
| (uncommitted as of this handoff) | STATUS.md HUMAN-START updated to reflect today's work; this handoff file; `docs/INDEX.md` refreshed to include all 2026-05 additions. |

### Memory

A project memory was added: `project_multi_provider_resource_selection.md` — flags the long-term direction so future agents don't preempt or duplicate the work.

---

## Open questions resolved this session

See [`docs/questions/aliyun-frankfurt-rollout-open-2026-05-08.md`](../questions/aliyun-frankfurt-rollout-open-2026-05-08.md).

| Q | Decision |
|---|---|
| Q1: AppRole role_id scope | **B — separate role per env.** Hetzner role_id (`<openbao-role-id-netbox>`) was a copy-paste leak into aliyun. Mint a new role on the *aliyun* OpenBao after bootstrap via `bin/bootstrap-operator-approle.sh dmf-infra openbao-aliyun-frankfurt secret-id k3s-aliyun`. |
| Q2: Unseal flow ownership | **A — parametrize `bin/unseal-openbao.sh`** (Phase B; not blocking first apply). Existing env vars already abstract location-specific values; add a positional `<env>` arg. |
| Q3: Two-pass Tofu | **Two-pass guard inside the same workspace.** Implemented in `31f6a78`. |
| Q4: Fix-then-apply | **Fix-then-apply.** Operator-confirmed "no rush to start ECS." |
| N1 (new): `openbao_url` copy-paste | Both inventories had `https://<wg-mesh-ip>:8200` (hetzner-only WireGuard endpoint). Aliyun must populate with its own Tailscale IP after `321-tailscale.yml` runs. Now a placeholder with post-bootstrap instructions in `openbao_secrets.yml`. |
| N2 (new): Share-3 keychain naming | Convention: `openbao-breakglass-<env>-share-3`. Operator creates after `bao operator init`. |
| N3 (new): Skill `dmf-openbao-unseal` §0 | Needs update after Phase B #1 lands. |

---

## What's still open (Phase B + tail)

None of these block the first aliyun apply. They are quality-of-life or post-rollout items.

1. **Parametrize `bin/unseal-openbao.sh`** for env arg (Q2/A). Existing `OPENBAO_SSH_TARGET` / `OPENBAO_SHARE_DIR` / `OPENBAO_KEYCHAIN_SERVICE` env vars already factor 80% of it; add positional `<env>` defaulting to `hetzner-arm` for back-compat.
2. **Implement `dmf-env/tasks/aliyun_security_group.yml`** for runtime drift reconciliation. Tofu module already declares the SG inline so this is non-blocking. Mirror `dmf-env/tasks/hetzner_firewall.yml`.
3. **Append aliyun section to `dmf-env/DEPLOYMENT.md`** (currently mentions only hetzner-arm).
4. **Update skill `dmf-openbao-unseal` §0** post-Phase B #1.
5. **Remove legacy `bootstrap.yml` `lookup('password', '/dev/null …')`** lines from both env inventories once `bootstrap-secrets.sh` is the canonical source.
6. **Retire `bin/export-openbao-vars.sh`** if no longer referenced (now superseded by `bootstrap-secrets.sh export-vars`).
7. **Confirm Tofu image** — `debian_13_4_arm64_20G_alibase_20260414.vhd` was queried 2026-05-08; Alicloud rotates image IDs, may need refresh before apply.

---

## Rollout procedure (summary; full version in review §7)

When the operator is ready to start ECS spend:

```bash
# 0. Boot ritual (every session)
cd <repos>/dmfdeploy && git fetch && git pull && bin/generate-status.sh

# 1. Operator-machine prerequisites
ls -la ~/.ssh/id_ed25519_k3s_aliyun{,.pub}              # ssh-keygen if missing
test -f ~/.secure/aliyun/.ay-dmfdeploy                   # ALIYUN_ACCESS_KEY_ID/SECRET, mode 0400
test -f ~/.config/cf/dns.txt                             # Cloudflare zone-edit token
test -f ~/.config/sops/age/keys.txt                      # age private key, mode 0600
age-keygen -y ~/.config/sops/age/keys.txt                # paste pubkey into dmf-env/.sops.yaml block (S1)

# 2. Pre-seed bundle
export DMF_BOOTSTRAP_BUNDLE_DIR=$HOME/secure/dmf-bootstrap
cd <umbrella-path>/dmf-env
bin/bootstrap-secrets.sh init aliyun-frankfurt
bin/bootstrap-secrets.sh doctor aliyun-frankfurt

# 3. Tofu pass 1 (infra; DNS guarded)
bin/tf-apply.sh aliyun-frankfurt init
bin/tf-apply.sh aliyun-frankfurt apply

# 4. Pre-seed provision (host hardening, k3s, OpenBao install, network policies, ESO)
bin/run-playbook.sh aliyun-frankfurt ../dmf-infra/k3s-lab-bootstrap/bootstrap-provision-pre-seed.yml \
    --tags bootstrap-preflight                            # smoke-test first
bin/run-playbook.sh aliyun-frankfurt ../dmf-infra/k3s-lab-bootstrap/bootstrap-provision-pre-seed.yml

# 5. Init OpenBao + distribute Shamir shares
#    (manual: bao operator init, save 5 shares per manifest's share_distribution)
bin/unseal-openbao.sh aliyun-frankfurt                    # post-Phase B #1; until then, manual

# 6. Mint aliyun-specific operator AppRole + seed secrets
bin/bootstrap-operator-approle.sh dmf-infra openbao-aliyun-frankfurt secret-id k3s-aliyun
bin/bootstrap-secrets.sh seed-bao aliyun-frankfurt
DMF_AWX_CONTROL_NODE_SSH_PATH=<secure-store>/awx-control-node.privkey \
  bin/bootstrap-secrets.sh seed-awx-control-node-ssh aliyun-frankfurt

# 7. Post-seed provision (apps + monitoring)
bin/run-playbook.sh aliyun-frankfurt ../dmf-infra/k3s-lab-bootstrap/bootstrap-provision-post-seed.yml

# 8. Tofu pass 2 (publish Cloudflare A-records now SLB exists)
bin/tf-apply.sh aliyun-frankfurt apply

# 9. Configure stage
bin/run-playbook.sh aliyun-frankfurt ../dmf-infra/k3s-lab-bootstrap/bootstrap-configure.yml

# 10. Verify
bin/run-playbook.sh aliyun-frankfurt ../dmf-infra/k3s-lab-bootstrap/bootstrap-verify.yml
curl -sS https://aliyun.<lan-host>/

# 11. Post-rollout: update STATUS.md HUMAN-START + write closure handoff
```

Full procedure with prerequisites and verification: [`docs/reviews/dmf-aliyun-frankfurt-readiness-review-2026-05-08.md`](../reviews/dmf-aliyun-frankfurt-readiness-review-2026-05-08.md) §7.

---

## Repo state at handoff

| Repo | HEAD | Working tree | Unpushed commits |
|---|---|---|---|
| dmfdeploy (umbrella) | `9b6d6f6` (this handoff + STATUS.md updates not yet committed) | dirty (STATUS.md, INDEX.md, this handoff) | 7 + the new ones |
| dmf-cms | `e9ffbd7` | clean | 1 |
| dmf-infra | `033d438` | clean | 3 |
| dmf-env | `31f6a78` | clean | 4 |
| dmf-central | `b210784` | clean | 1 |
| dmf-media | `2c2e2a6` | clean | 1 |
| dmf-runbooks | `c5707d2` | clean | 0 |

**Push status:** all the above remain unpushed. Operator decision when to push to public mirrors (per ADR/handoff `DMF Public Publish Readiness Handoff 2026-05-07.md`).

---

## How to resume

1. Run the boot ritual at the top of [`/CLAUDE.md`](../../CLAUDE.md).
2. Read [`STATUS.md`](../../STATUS.md) HUMAN-START.
3. Read this handoff.
4. If touching aliyun rollout:
   - Read [`docs/reviews/dmf-aliyun-frankfurt-readiness-review-2026-05-08.md`](../reviews/dmf-aliyun-frankfurt-readiness-review-2026-05-08.md).
   - Decide: rollout-now or Phase B housekeeping first.
5. If touching anything else: this handoff is informational only — your task probably has a more relevant prior handoff in [`docs/handoffs/`](.).

---

## Cross-references

- Review: [`docs/reviews/dmf-aliyun-frankfurt-readiness-review-2026-05-08.md`](../reviews/dmf-aliyun-frankfurt-readiness-review-2026-05-08.md)
- Questions: [`docs/questions/aliyun-frankfurt-rollout-open-2026-05-08.md`](../questions/aliyun-frankfurt-rollout-open-2026-05-08.md)
- Future direction: [`docs/plans/dmf-multi-provider-resource-selection-future-direction-2026-05-08.md`](../plans/dmf-multi-provider-resource-selection-future-direction-2026-05-08.md)
- Prior handoff: [`docs/handoffs/DMF Bootstrap Implementation Progress Handoff 2026-05-08.md`](DMF%20Bootstrap%20Implementation%20Progress%20Handoff%202026-05-08.md)
- Strategic frame: [`docs/reviews/dmf-platform-strategic-review-2026-04-30.md`](../reviews/dmf-platform-strategic-review-2026-04-30.md)
- ADRs touched: 0007 (secrets-never-in-argv), 0008 (openbao architecture), 0009 (Shamir DR), 0010 (sanctioned entry), 0012 (configure-stage distinct), 0016 (AWX SSH via cloud-init).
