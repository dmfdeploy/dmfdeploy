# DMF Platform Deploy Quickstart

**Status:** Operator-facing runbook. Canonical deployment procedure for any
dmf-env environment (e.g. `hetzner-arm`, `aliyun`).
Assumes the bring-up incorporates every fix through
`docs/plans/DMF Bootstrap Pre-Seed Blocker Fix Implementation Plan 2026-05-09.md`
§§1–21 (in `main` as of 2026-05-10).

**Intent model:** `docs/processes/README.md` (BPMN 2.0). Read that for *why*;
this file is the *how* — copy-pasteable commands, no narration.

**Resets:** see the *Reset checklist* at the end of the implementation plan
for the inverse procedure (tear-down, Cloudflare/Headscale/operator-side
cleanup) before a fresh attempt against an already-initialised cluster.

---

## TL;DR — full bring-up in one screen

Sections below explain each step in detail. This is the bare command
sequence for environment `<env>` (substitute your actual env name —
`hetzner-arm`, `aliyun`, etc.).

The **preferred greenfield path is the interactive
`bin/init-wizard.sh`** — it collects every unique-non-generable input
in one pass, auto-generates passwords/tokens, and writes the encrypted
bundle + manifest + inventory + Terraform tfvars + appends the SOPS
recipient rule. Refuses to run if the bundle already exists.

The legacy `bin/bootstrap-secrets.sh init` is still available for
piecemeal per-field setup against an existing bundle — see §0.1.

```bash
export DMF_BOOTSTRAP_BUNDLE_DIR=<secure-store>/dmf-bootstrap
cd <umbrella-path>/dmf-env

# Substitute your environment name for <env> throughout (e.g. hetzner-arm, aliyun)
ENV=aliyun

# 1. First-time: greenfield wizard — collects identity, base domain,
#    provider tokens, B2 keys, optional Tailscale/Headscale; generates
#    passwords + cluster token; writes bundle + manifest + inventory +
#    tfvars; appends recipient rule to dmf-env/.sops.yaml.
#    (Refuses if ${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>.sops.yaml already
#    exists — move existing manifest/inventory aside if needed.)
bin/init-wizard.sh
bin/bootstrap-secrets.sh doctor "${ENV}"     # sanity-check the bundle

# 2. Create + configure object-storage buckets (Backblaze B2 native API).
#    Idempotent; reads bucket names from the manifest + creds from the
#    wizard-rendered object-storage.tfvars.
bin/b2-buckets.sh ensure "${ENV}"

# 3. Layer 1 — provision infra (tofu apply)
#    (-lock=false: local-backend state on JuiceFS-via-SMB lacks POSIX locking)
bin/tf-apply.sh "${ENV}" apply -auto-approve -lock=false

# 4. Pre-seed — k3s, hardening, CCM, Traefik, Tailscale, Longhorn, Zot, OpenBao
RUNBOOK_TIMEOUT=5400 bin/run-playbook.sh "${ENV}" \
    ../dmf-infra/k3s-lab-bootstrap/bootstrap-provision-pre-seed.yml

# 5. Push the bundle into OpenBao at secret/platform/* and secret/apps/*/
bin/bootstrap-secrets.sh seed-bao "${ENV}"

# 6. Export Phase 1 audit inventory vars (audit_log_aws_*) for the
#    host-cron audit archival + resilience-verify Track B.
bin/bootstrap-secrets.sh export-vars "${ENV}"

# 7. Post-seed — Authentik + Layer 6 apps + vertical-resilience track
RUNBOOK_TIMEOUT=5400 bin/run-playbook.sh "${ENV}" \
    ../dmf-infra/k3s-lab-bootstrap/bootstrap-provision-post-seed.yml

# 8. Configure — cross-app wiring (OIDC graph, NetBox SoT, CMS logout redirect, …)
RUNBOOK_TIMEOUT=5400 bin/run-playbook.sh "${ENV}" \
    ../dmf-infra/k3s-lab-bootstrap/bootstrap-configure.yml

# 9. Verify (cluster + OpenBao + resilience round-trip)
bin/unseal-openbao.sh "${ENV}" --status
bin/run-playbook.sh "${ENV}" \
    ../dmf-infra/k3s-lab-bootstrap/bootstrap-verify.yml \
    --tags vertical-resilience \
    -e resilience_verify_soak_prewarm=true
```

For reruns, append `-e baseline_update_apt_cache=false` to each
`run-playbook.sh` invocation (skips a redundant apt cache refresh that
otherwise hangs while the previous Tailscale apt source is still pinned).

---

## 0. Operator pre-flight

Everything below uses `<env>` as a placeholder — substitute your actual
environment name (`hetzner-arm`, `aliyun`, etc.) in every command.
Assumes you are at the umbrella root with all three repos checked out and pulled.

```bash
cd <repos>/dmfdeploy
git fetch && git pull
( cd dmf-env && git fetch && git pull )
( cd dmf-infra && git fetch && git pull )
```

Required local state (the OpenBao role hard-fails if any is missing on a
fresh init):

| Need | Where | Why |
|---|---|---|
| JuiceFS mounted at `<volumes>/secure` | macOS Finder | break-glass shares 1+2 + automation file |
| USB stick `OPENBAO_A` plugged in (mounts at `/Volumes/OPENBAO_A`) | physical | break-glass shares 4+5 |
| macOS login Keychain unlocked, `security` CLI write-authorised | terminal session | break-glass share 3 |
| Aliyun creds in `~/.secure/aliyun/.ay-dmfdeploy` | mode `0400` | tofu provider auth |
| Cloudflare DNS API token in `~/.config/cf/dns.txt` | mode `0400` | DNS reconcile in `321-tailscale.yml` |
| Pre-Bao bootstrap bundle at `<secure-store>/dmf-bootstrap/` | JuiceFS | `bootstrap-secrets.sh` env exports + `seed-bao` |

```bash
export DMF_BOOTSTRAP_BUNDLE_DIR=<secure-store>/dmf-bootstrap
```

If you are bringing up over a previously-initialised cluster, run the *Reset
checklist* in the implementation plan first — otherwise the role's rerun
path will preload stale break-glass material that does not match the new
OpenBao instance.

### 0.1 Initialise the encrypted bootstrap bundle

The bundle is a SOPS-encrypted YAML at
`$DMF_BOOTSTRAP_BUNDLE_DIR/<env>.sops.yaml` — outside any git tree —
holding the operator-side seed values that pre-seed and seed-bao depend
on.

**For greenfield envs, prefer `bin/init-wizard.sh`** (§TL;DR step 1).
The wizard collects every unique-non-generable input in one interactive
pass, generates passwords/tokens, and writes the bundle + manifest +
inventory + Terraform tfvars + SOPS recipient rule. Refuses to run if a
bundle for the named env already exists — protects against accidentally
rotating passwords ESO is already wired against.

The `bin/bootstrap-secrets.sh init <env>` path documented below is for
piecemeal per-field setup against an existing bundle (re-init flow,
adding a field to a long-lived env). On first run it creates the file;
on subsequent runs it only prompts for fields that are still empty.

**Field set:** `init` prompts for **base_domain** — the root domain for
all platform URLs (e.g. `<lan-host>`). If an existing inventory
`group_vars` file is found, its `cert_manager_cluster_domain` is
suggested as the default.

Prereqs (one-time, machine-wide):

```bash
brew install sops age                                          # if missing
mkdir -p ~/.config/sops/age
[ -f ~/.config/sops/age/keys.txt ] || age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
age-keygen -y ~/.config/sops/age/keys.txt                      # public key — must be in dmf-env/.sops.yaml
```

If you generated a fresh age key, paste the public key into
`dmf-env/.sops.yaml` under the matching `path_regex` block before running
`init` (the script refuses to write a bundle the operator cannot decrypt).

Then init the bundle (using `ENV` from the TL;DR above):

```bash
cd <umbrella-path>/dmf-env
bin/bootstrap-secrets.sh init "${ENV}"
```

Fields the script will prompt for:

| Field | Source | Notes |
|---|---|---|
| `bootstrap_admin.username` / `email` | choose | becomes the seed admin in OpenBao + every Layer 6 app |
| `bootstrap_admin.password` | leave blank → autogenerated | written to `secret/platform/bootstrap_admin` by `seed-bao` |
| `cluster.k3s_token` | leave blank → autogenerated | written to `secret/platform/k3s/cluster` |
| `metadata.base_domain` | **required** — root domain for all platform URLs | e.g. `<lan-host>`; suggested from inventory `cert_manager_cluster_domain` if present |
| `providers.alicloud.access_key` / `secret_key` | Aliyun RAM user | also lives in `~/.secure/aliyun/.ay-dmfdeploy` for tofu — the bundle copy is for the in-cluster CCM |
| `providers.cloudflare.dns_token` | Cloudflare | DNS-01 cert challenges + `321-tailscale.yml` A-record reconcile |
| `providers.tailscale.authkey` | Headscale (`docker exec headscale headscale preauthkeys create -u <operator> --reusable --expiration 24h`) | auth key for joining the tailnet |
| `providers.hcloud.token` | optional | only if you also operate hetzner-arm |
| `notifications.*` | optional | leave blank for the experiment phase |

Sanity-check before moving on (decrypts and validates schema, no writes):

```bash
bin/bootstrap-secrets.sh doctor "${ENV}"
```

---

## 1. Layer 1 — Tofu apply

```bash
cd <umbrella-path>/dmf-env
bin/tf-apply.sh "${ENV}" apply -auto-approve -lock=false
```

`-lock=false` is required, not optional: the local backend in
`terraform/aliyun/versions.tf` keeps state under
`<secure-store>/terraform-states/aliyun/` which is JuiceFS mounted
via SMB. SMB on macOS does not reliably support the POSIX file-locking
calls Terraform's local backend uses, so leaving the lock on intermittently
hangs or fails the apply. Disabling it is safe in this single-operator
setup; teach yourself never to run two tofus in parallel against the same
env. Same flag applies to `tofu plan`, `destroy`, `state list`, etc.

Expected: ~1 minute, creates VPC + vSwitch + Security Group + key pair +
3× ECS instances + RAM role for the CCM. Generates
`inventories/aliyun/hosts.ini` and `inventories/aliyun/group_vars/all/tofu_outputs.yml`
on disk (these are intentionally not committed).

Sanity check:

```bash
bin/tf-apply.sh "${ENV}" output -lock=false
ssh -i ~/.ssh/id_ed25519_k3s_aliyun \
    -o StrictHostKeyChecking=accept-new \
    k3s-admin@$(awk '$1=="k3s-node-01"{for(i=2;i<=NF;i++)if($i~/^ansible_host=/){sub(/^ansible_host=/,"",$i);print $i;exit}}' inventories/aliyun/hosts.ini) \
    'uptime'
```

---

## 2. Layer 2+3+5 — Pre-seed provision

The 5400s (90 min) timeout absorbs cert-manager DNS-01, container-image
pulls (Longhorn, cert-manager, Zot, OpenBao), retry-loops on Aliyun's
slow-to-stabilise SLB, and the OpenBao init+unseal serialised work on
node-01.
`baseline_update_apt_cache=false` is for *reruns* only; on a fresh cluster
omit it so apt is refreshed exactly once.

```bash
cd <umbrella-path>/dmf-env
RUNBOOK_TIMEOUT=5400 bin/run-playbook.sh "${ENV}" \
    ../dmf-infra/k3s-lab-bootstrap/bootstrap-provision-pre-seed.yml
```

What this does in one pass:

1. Baseline + harden + kernel CVE mitigations (algif_aead, esp4, esp6, rxrpc)
2. k3s installs on all 3 nodes (control plane + etcd, no workers)
3. Aliyun CCM + private/public Traefik + cert-manager
4. Tailscale joins all 3 nodes; Cloudflare reconciles `*.<lan-host>` A records to the tailnet IPs
5. Longhorn storage class
6. Container platform: Zot registry (with Let's Encrypt cert via DNS-01)
7. **OpenBao** installed → `bao operator init` → shares written to JuiceFS / Keychain / USB / automation file → auto-unsealed → policies + AppRoles + ESO ClusterSecretStore wired
8. Container-platform verifier confirms in-cluster pulls from Zot

End state: bao is unsealed, ESO is up, but no app secrets exist yet.

Common gotchas (now fixed in `main`, listed for diagnosis):

- Hangs at `base/post-bootstrap-verify` or `base/kernel-cve-mitigations` →
  shouldn't recur (`ansible.cfg` `[ssh_connection]` + `usetty=False`).
- Hang at the breakglass save → shouldn't recur (role creates parent dir
  before save). If it does, USB or JuiceFS isn't mounted.
- 900s default timeout fires while waiting for Zot or another long-pull
  step → use `RUNBOOK_TIMEOUT=5400` as shown above.

---

## 3. Seed pre-Bao bundle into OpenBao

Pushes the bundle's bootstrap admin password, k3s join token, provider
tokens, and app-local compatibility copies into OpenBao at
`secret/platform/*` and `secret/apps/<app>/*`.

```bash
cd <umbrella-path>/dmf-env
bin/bootstrap-secrets.sh seed-bao "${ENV}"
```

The script SSHes to the first `k3s_control` host in
`inventories/<env>/hosts.ini` and runs `kubectl --kubeconfig
/etc/rancher/k3s/k3s.yaml exec -i ...` so secret values never traverse
operator-local kubectl context.

Sanity check via the unseal helper (same SSH path):

```bash
bin/unseal-openbao.sh "${ENV}" --status
```

Expect `sealed: false`.

---

## 4. Layer 6 — Post-seed provision

Installs Authentik + the rest of the vanilla Layer 6 apps. Asserts
`secret/platform/bootstrap_admin` and `secret/platform/k3s/cluster` exist
in OpenBao before any app install runs (the post-seed guard).

```bash
cd <umbrella-path>/dmf-env
RUNBOOK_TIMEOUT=5400 bin/run-playbook.sh "${ENV}" \
    ../dmf-infra/k3s-lab-bootstrap/bootstrap-provision-post-seed.yml
```

---

## 5. Configure — cross-app wiring

Authentik OIDC graph, NetBox SoT, Forgejo, AWX, Zot OIDC overlay,
dmf-cms wiring.

```bash
cd <umbrella-path>/dmf-env
RUNBOOK_TIMEOUT=5400 bin/run-playbook.sh "${ENV}" \
    ../dmf-infra/k3s-lab-bootstrap/bootstrap-configure.yml
```

---

## 6. Verify

```bash
# Cluster health from the control node
# SSH target from inventories/<env>/hosts.ini
ssh <ssh-target> 'sudo k3s kubectl get nodes,pods -A | head -40'

# OpenBao seal state
bin/unseal-openbao.sh "${ENV}" --status

# Public ingress (DNS-01 cert via Cloudflare)
curl -sI https://registry.<base-domain>/v2/ | head -3

# Public ingress (DNS-01 cert via Cloudflare)
curl -sI https://registry.<lan-host>/v2/ | head -3
```

Expected:

- All 3 nodes `Ready` with `control-plane,etcd,master` roles
- `kube-system` traefik + `traefik-private` traefik-private both have a
  `LoadBalancer` external IP
- OpenBao `sealed: false`
- Zot returns HTTP 200 with valid TLS

---

## 7. Reruns

The pre-seed and post-seed playbooks are idempotent — safe to rerun any
stage without manual cleanup. Two flags help on reruns:

```bash
RUNBOOK_TIMEOUT=5400 bin/run-playbook.sh "${ENV}" \
    ../dmf-infra/k3s-lab-bootstrap/bootstrap-provision-pre-seed.yml \
    -e baseline_update_apt_cache=false
```

`baseline_update_apt_cache=false` skips a redundant apt cache refresh that
otherwise hangs while the previous Tailscale apt source is still pinned.

---

## 8. Manual unseal (after pod restart)

The OpenBao role's auto-unseal handles most cases. For an out-of-band pod
restart that the automation file does not cover (or when the file is
missing/stale), the operator runs the strict 3-share Shamir unseal:

```bash
cd <umbrella-path>/dmf-env
bin/unseal-openbao.sh "${ENV}"
```

The script derives `SHARE_DIR`, `SHARE_KEYCHAIN_NAME`, and `SSH_TARGET`
from `inventories/<env>/`. Share 1+2 read from JuiceFS, share 3 from the
login Keychain (service `openbao-breakglass-share-3-<env>`). USB shares
4+5 are not touched in the routine path.

---

## 9. Reset (teardown for fresh attempt)

See *Reset checklist* in
`docs/plans/DMF Bootstrap Pre-Seed Blocker Fix Implementation Plan 2026-05-09.md`
for the canonical sequence. Summary:

```bash
# 1. Drop the LoadBalancer Services so CCM deprovisions the SLBs
ssh -i ~/.ssh/id_ed25519_k3s_aliyun "$SSH" \
    'sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml \
     delete svc -n kube-system traefik --wait=false; \
     sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml \
     delete svc -n traefik-private traefik-private --wait=false'

# 2. If CCM is degraded and the SLBs do not deprovision, force-delete
#    via the Aliyun CLI after disabling DeleteProtection (DeleteProtection
#    enum value is `off`, not `non-protection`).
aliyun slb DescribeLoadBalancers --RegionId eu-central-1 \
    | jq -r '.LoadBalancers.LoadBalancer[].LoadBalancerId'
aliyun slb SetLoadBalancerDeleteProtection --RegionId eu-central-1 \
    --LoadBalancerId <id> --DeleteProtection off
aliyun slb DeleteLoadBalancer --RegionId eu-central-1 --LoadBalancerId <id>

# 3. Tofu destroy
bin/tf-apply.sh aliyun destroy -auto-approve -lock=false

# 4. Cloudflare A-record cleanup (delete records that point at the
#    Aliyun tailnet IPs that just went away)

# 5. Headscale node cleanup
ssh root@hs.<lan-host> 'docker exec headscale headscale nodes list' \
    | grep aliyun
ssh root@hs.<lan-host> 'docker exec headscale headscale nodes delete \
    --identifier <id> --force'

# 6. Operator-side state — should already be empty after a clean
#    run; verify in case of partial init
ls <secure-store>/openbao-breakglass/aliyun/   # must not exist
security find-generic-password -s openbao-breakglass-share-3-aliyun -a share  # must fail
ls /Volumes/OPENBAO_A/aliyun/                       # must not exist
```

---

## 10. References

- Intent model: `docs/processes/README.md` (BPMN 2.0)
- Implementation plan: `docs/plans/DMF Bootstrap Pre-Seed Blocker Fix Implementation Plan 2026-05-09.md`
- ADR-0008 secrets architecture: `docs/decisions/0008-openbao-secrets-architecture.md`
- ADR-0009 Shamir DR model: `docs/decisions/0009-shamir-dr-model.md`
- ADR-0011 auto-unseal tradeoff: `docs/decisions/0011-auto-unseal-tradeoff.md`
- Skill `dmf-openbao-unseal` (operator-facing manual breakglass)
- Skill `dmf-cluster-access` (cluster ops + read patterns)
