# DMF Path Y Option A Redeploy — Mid-Flight Handoff (2026-05-05)

You are resuming a security incident response and cluster redeploy in progress. The previous agent did most of the prep work; you are picking up mid-Phase 7.

## Context: what happened

A real ed25519 SSH private key was committed to the **public** `dmf-infra` repo (in PEM-encoded form via an Ansible Machine credential helper). Per ADR-0007, the user authorized **Path Y** (full cluster redeploy) with **Path A** as the chosen execution model for AWX↔control-node SSH. All decision rationale is locked in **ADR-0016** at `docs/decisions/0016-awx-control-node-ssh-via-cloud-init-and-openbao.md`.

**Path A**: pubkey rendered into Hetzner cloud-init `ssh_authorized_keys` for `k3s-admin`; privkey lives in OpenBao at `secret/apps/awx/control_node_ssh`; AWX EE pod reads it at runtime to SSH-and-`run-playbook.sh` against the control node.

## Phase status

| # | Phase | Status |
|---|---|---|
| 1 | dmf-infra history rewrite (clean head `e8696f5`, force-pushed forgejo-lab) | done |
| 1b | ADR-0016 created + INDEX.md updated | done |
| 2 | Backup-decision audit | done |
| 3 | Force-update forgejo-lab mirror | done |
| 4 | `tofu destroy hetzner-arm` (manual LB cleanup via Hetzner API after subnet hung) | done |
| 5 | OpenBao re-init ceremony (5-share Shamir, ADR-0009) | **pending — operator-led, do not auto-trigger** |
| 6 | Generate new AWX↔control-node keypair, plumb in Tofu | done |
| 7 | `tofu apply` + bootstrap playbook | **IN PROGRESS** |
| 8 | Reintroduce AWX credential creation in awx-integration role | pending |
| 9 | Re-run Gate 2 with corrected SSH plumbing | pending |
| 10 | Shred local privkey + incident closure | pending |

## Where Phase 7 stands right now

- **Tofu state**: 10 core resources applied (3 nodes, network, subnet, firewall, SSH key, server-network attachments). Cloudflare records + `local_file.hosts_ini` were applied in a separate targeted run after.
- **Bootstrap playbook**: running via `bin/run-playbook.sh hetzner-arm ../dmf-infra/k3s-lab-bootstrap/site.yml`. Latest log: **most recent file in `/tmp/dmf-playbook-logs/`** (use `ls -t /tmp/dmf-playbook-logs/*.log | head -1`). Last observed: progressing through `300-k3s` (k3s install on first control plane node). User said "agent will take it from here."
- **Keypair**: pubkey at `~/.config/dmf/awx-control-node.pub`, privkey at `<secure-store>/awx-control-node.privkey` (JuiceFS at-rest encrypted; do **not** copy or `cat` it).
- **OpenBao breakglass**: pre-redeploy files renamed to `*.pre-redeploy-2026-05-05`, keychain `share-3` deleted. The cluster will trigger fresh auto-init when OpenBao bootstraps; the user does the operator-led 5-share Shamir ceremony in Phase 5 — **do not run this for them**.

## Repo fixes already applied (uncommitted in dmf-infra)

The previous agent fixed unprefixed Ansible role references that broke playbook resolution. Files modified:

- `playbooks/210-harden.yml`, `playbooks/301-k3s-verify.yml`: prefixed with `base/`
- `playbooks/310-ingress-public.yml`, `playbooks/320-cert-manager.yml`: prefixed with `base/`
- `playbooks/331-registry-zot.yml`, `600-landing-page.yml`, `610-netbox.yml`, `620-forgejo.yml`, `640-awx.yml`, `650-dmf-cms.yml`, `691-netbox-sot.yml`, `692-forgejo-bootstrap.yml`, `693-awx-integration.yml`: prefixed with `stack/operator/`
- `playbooks/vertical-monitoring/{100-prometheus,120-grafana,130-promtail}.yml`: prefixed with `base/`
- `playbooks/vertical-monitoring/110-loki.yml`: prefixed with `stack/operator/`
- `playbooks/vertical-monitoring/140-librenms.yml`: prefixed with `modules/infra-monitoring/`
- `playbooks/vertical-orchestration/100-eso.yml`: prefixed with `base/`
- `playbooks/vertical-security/{100-openbao,110-authentik,191-zot-oidc}.yml`: prefixed with `stack/operator/`
- All `cluster-ready` references across 15 playbooks: prefixed with `base/`
- `playbooks/219-host-verify.yml`: relaxed `failed_when` on cluster-domain DNS dig (don't fail on empty stdout — DNS doesn't exist yet on first bootstrap)
- `playbooks/698-cms-netbox-forgejo-tokens.yml:223-224`: removed duplicate `no_log: false` line
- `playbooks/200-baseline.yml`: replaced deprecated `ansible_architecture` with `ansible_facts["architecture"]`

These are not yet committed. **Verify they're sane before commit** — these were rapid fixes in service of unblocking the playbook, not a deliberate cleanup.

## What to do next

1. **Monitor the running bootstrap.** Use `tail -100 $(ls -t /tmp/dmf-playbook-logs/*.log | head -1)` repeatedly. Watch for `PLAY RECAP` (success) or `fatal:` / `FAILED` lines. Don't poll in tight loops — give it minutes between checks.
2. **If the bootstrap fails on another role-resolution or playbook bug**, fix the playbook in `dmf-infra/k3s-lab-bootstrap/` and re-run from `dmf-env`:
   ```bash
   cd <umbrella-path>/dmf-env
   RUNBOOK_TIMEOUT=3600 bin/run-playbook.sh hetzner-arm ../dmf-infra/k3s-lab-bootstrap/site.yml
   ```
   The user runs the playbook directly in their terminal — **do not** invoke it via Bash yourself, output is huge. Tell them the exact command and ask them to paste back any error you need.
3. **After bootstrap reaches the `lifecycle-finalise` stage**, the CCM-managed `dmf-traefik` LB should exist. Run a full `bin/tf-apply.sh hetzner-arm apply -auto-approve -lock=false` to create the Cloudflare A records that previously couldn't resolve.
4. **Phase 5 (OpenBao re-init) is operator-led.** When the user is ready, walk them through the 5-share Shamir ceremony per ADR-0009, but **never** generate or store shares yourself. The auto-init script triggered by the openbao role will produce shares; the operator must record them and write back the unseal token to keychain.
5. **Phase 8 (reintroduce AWX credential creation)** is the part you'll likely build. The pattern from ADR-0016:
   - Read privkey: `bao kv get -format=json secret/apps/awx/control_node_ssh` via `kubectl exec` into the openbao pod
   - Pipe via `printf '%s' | kubectl exec -i awx-pod -- ...` to create AWX Machine credential — never via argv, env vars, /tmp files, or stdout (ADR-0007).
   - All this lives in `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/`.

## Critical guardrails

- **Never `cat`, `echo`, or print** `<secure-store>/awx-control-node.privkey` or any OpenBao share/token. ADR-0007 § 6 — if you do, the user has to redeploy again.
- **Never commit** anything containing `BEGIN OPENSSH PRIVATE KEY` markers. Add a pre-commit hook check if you touch awx-integration.
- **Don't auto-`tofu destroy`** under any circumstance. Path Y is done; we're rebuilding, not tearing down again.
- **Don't auto-run** `git push --force` to either the GitHub or forgejo-lab mirror. The user already did the force-push.
- The `dmfdeploy` umbrella is at `<umbrella-path>/`. Read `STATUS.md` and the most recent file in `docs/handoffs/` before doing anything cross-cutting.

## Key file references

- `docs/decisions/0016-awx-control-node-ssh-via-cloud-init-and-openbao.md` — Path A decision
- `docs/decisions/0007-secret-discipline.md` — never-print rules
- `docs/decisions/0009-openbao-shamir-recovery.md` — 5-share recovery model
- `docs/reviews/dmf-move1-gate2-ssh-credential-incident-2026-05-05.md` — incident writeup
- `dmf-env/bin/generate-awx-control-node-keypair.sh` — keypair generator
- `dmf-env/terraform/modules/hetzner-cluster/templates/user-data.yml.tftpl` — cloud-init template
- `dmf-env/terraform/modules/hetzner-cluster/variables.tf` — `awx_control_node_ssh_pubkey_path` variable

Pick up by checking the latest log file. Keep responses terse — the user is watching this run live.
