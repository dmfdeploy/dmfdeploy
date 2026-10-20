---
status: executed
date: 2026-04-26
---
# DMF Layer-1 OpenTofu Bootstrap Plan — 2026-04-26

> **Execution status (updated 2026-04-27):** Phase A skeleton + Phase B
> steps 6-7 are complete. `tofu plan` against the running Hetzner cluster
> reports **"No changes"**. State file lives at
> `<secure-store>/terraform-states/hetzner-arm/terraform.tfstate`.
> Remaining: §11 step 8 (cut-over) and §11 step 9 (destroy/recreate
> rehearsal). For the next-session pickup prompt see
> `Projects/DMF Layer-1 OpenTofu Phase B Cut-over Handoff 2026-04-27.md`
> (supersedes the 2026-04-26 implementation handoff).
>
> Module corrections discovered during step 6-7 import iteration (see
> handoff §5):
> - firewall name is `k3s-nodes` (plan §11.6 said `k3s-firewall`)
> - SSH key name is `k3s-hetzner` (plan §11.6 said `<operator>-k3s-hetzner`)
> - subnet `type = "server"` (legacy), not `"cloud"`
> - firewall has TCP/80 + TCP/443 from anywhere ("VIP traffic"); module
>   adds them so apply doesn't strip live ingress rules
> - Cloudflare records use relative `name` ("lab", "auth.lab"), not FQDN —
>   FQDN form would force destroy + recreate of live records
> - `hcloud_server` lifecycle ignores 5 client-side flags + `public_net`
>   block to suppress import-time reconciliation noise
> - `hcloud_server_network` uses static `for_each = toset(local.node_names)`
>   so import validates against an empty state
> - JuiceFS does not implement `flock(2)`; pass `-lock=false` on every
>   tofu write subcommand (see memory `project_tofu_juicefs_lock.md`)

> **Scope:** the *conservative* path discussed 2026-04-26. Replace
> `dmf-env/bin/provision-nodes.sh` (a shell script wrapping the
> `hcloud` CLI) with declarative OpenTofu resources for the Hetzner
> Layer-1 infrastructure. Ansible Layer 2 and Layer 3 playbooks stay
> exactly as they are. No changes to `lifecycle-provision.yml`, no
> changes to roles, no GitOps yet.

> **EBU alignment:** Layer 1 — Infrastructure (compute, network, storage,
> timing reference). White paper §Infrastructure §Orchestration explicitly
> mentions Terraform; OpenTofu is the OSS fork.

> **Companion docs:** `DMF EBU Mapping (2026-04-25).md`,
> `DMF Open Questions 2026-04-20.md` §EBU-3 (codegen),
> `dmf-env/manifests/hetzner-arm.yaml` (Resource Profile input).

---

## 1. Context & rationale

The current Layer-1 provisioning is a 350-line shell script
(`dmf-env/bin/provision-nodes.sh`) that imperatively calls
`hcloud server create`, `hcloud network create`, `hcloud ssh-key
upload`, then writes `inventories/hetzner-arm/hosts.ini` from the
captured outputs. It works, but it has the same brittleness profile
as any push-from-operator-host shell pipeline: no drift detection,
no idempotency guarantee at the resource level (only at the script
level), no plan-before-apply, no audit trail beyond the operator's
shell history, and IP addresses are baked into hosts.ini by hand
after a recreate.

The Resource Profile manifest landed 2026-04-26 already declares the
*intent* — `manifests/hetzner-arm.yaml` says exactly which Hetzner
server type, region, network CIDR, SSH allow-list, etc. The missing
piece is a declarative renderer that turns that intent into actual
Hetzner resources.

OpenTofu fits the gap. The `hetznercloud/hcloud` provider exposes
every resource the shell script touches, plus drift detection,
plan-before-apply, and a state file that can be a single source of
truth for "what currently exists in nbg1 under this account." The
Cloudflare provider can pick up the DNS records that today are managed
by hand. Both are well-maintained and OSS-friendly.

## 2. EBU model alignment

| EBU concept | Today | After this plan |
|---|---|---|
| Layer 1 — Infrastructure | shell script + `hcloud` CLI | OpenTofu module, declarative state |
| Vertical — Orchestration | Ansible (Layer 2+3) + ESO (in-cluster) | + OpenTofu (Layer 1) |
| Resource Profile (Design) | `manifests/hetzner-arm.yaml` declares intent; not yet read by anything | Read by OpenTofu via `yamldecode()` |
| Lifecycle — Provision | Ansible `lifecycle-provision.yml` only | `tofu apply` runs *before* Ansible; Ansible imports unchanged |

The Layer-1 work was deliberately not in `lifecycle-provision.yml`
(only Layer 2+ are imported there) — so adding OpenTofu doesn't break
the existing orchestrator. It slots in as an out-of-band step before
`bin/run-playbook.sh` is invoked, the same way `provision-nodes.sh`
does today.

## 3. Target state (architecture)

```
operator host
    │
    │  1. Edit manifests/hetzner-arm.yaml (Resource Profile)
    │  2. cd terraform/hetzner-arm && tofu plan
    │  3. tofu apply       ──▶  Hetzner API
    │                              creates servers / network / firewall / SSH key / LB
    │                              writes Cloudflare DNS records
    │                              outputs JSON: server IPs, network CIDR, SSH user
    │
    │  4. tofu output      ──▶  inventories/hetzner-arm/hosts.ini   (rendered)
    │
    │  5. bin/run-playbook.sh ../dmf-infra/k3s-lab-bootstrap/site.yml
    │                              Ansible reads inventory, runs Layer 2 → Layer 3 → verticals → Layer 6
    │                              (lifecycle-provision.yml unchanged)
```

Three loops the operator drives:

| Loop | Frequency | Tool | What it touches |
|---|---|---|---|
| **Provision Layer 1** | Rarely (rebuild, scale, re-region) | `tofu apply` | Hetzner + Cloudflare |
| **Render inventory** | Auto, after `tofu apply` | `tofu output` → templated `hosts.ini` | dmf-env |
| **Configure Layer 2+** | Per-deploy | `bin/run-playbook.sh site.yml` | Ansible playbooks |

## 4. What stays in Ansible (explicitly scoped out)

- **Layer 2 — Host Platform**: `200-baseline.yml`, `210-harden.yml`, `219-host-verify.yml` — unchanged. OS package install, hardening, fail2ban, k3s-admin user, sshd config — all stay in Ansible.
- **Layer 3 — Container Platform**: `300-k3s.yml` and everything else — unchanged. k3s install via the existing role, ingress, cert-manager, longhorn, etc.
- **All verticals and Layer 6** — unchanged.
- **Cloud-init handoff** — explicitly NOT in this plan. The conservative path keeps the SSH-key-only handoff (OpenTofu uploads SSH key + creates server with that key; Ansible connects as root, then provisions k3s-admin via the harden role). Cloud-init merging into the provision step is a follow-up.

## 5. Directory layout

New files added to `dmf-env`:

```
dmf-env/
├── manifests/
│   └── hetzner-arm.yaml          # already exists; this drives tofu
├── terraform/                    # NEW
│   ├── README.md                 # NEW — usage + state backend doc
│   ├── modules/
│   │   └── hetzner-cluster/      # reusable module (one per provider, eventually)
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       ├── versions.tf
│   │       └── templates/
│   │           └── hosts.ini.tftpl
│   └── hetzner-arm/              # one root module per environment
│       ├── main.tf               # reads ../../manifests/hetzner-arm.yaml; calls module
│       ├── outputs.tf
│       ├── versions.tf
│       ├── terraform.tfstate     # gitignored — see §6
│       └── .terraform.lock.hcl   # committed
└── bin/
    ├── tf-apply.sh               # NEW — wraps tofu apply with the right env loading
    ├── tf-render-inventory.sh    # NEW — runs `tofu output -json` and templates hosts.ini
    └── provision-nodes.sh        # KEPT for now, marked deprecated; removed after first green tofu apply
```

The `modules/hetzner-cluster/` split is for the eventual case of
multiple Hetzner environments. For now it has exactly one caller
(`hetzner-arm/`).

## 6. State management

OpenTofu state is the source of truth for what exists. For the homelab:

- **Backend**: local file `terraform/hetzner-arm/terraform.tfstate`, stored on the JuiceFS mount (`<secure-store>/openbao-breakglass/.../terraform-states/hetzner-arm/`) via a `terraform { backend "local" { path = "..." } }` declaration.
- **Why JuiceFS not the repo**: state contains resolved IPs, account hints, and any output values — keep it off git.
- **Why local not remote**: a single operator, no concurrent applies. Remote backends (Terraform Cloud, S3, gitea-via-http) add ops surface for zero homelab benefit.
- **Recovery**: state file + the `manifests/<env>.yaml` together fully rebuild the environment. JuiceFS already has the breakglass backup discipline.
- **Lock file**: `.terraform.lock.hcl` IS committed — that pins provider versions, which we want under version control.

Gitignore additions (`dmf-env/.gitignore`):

```
terraform/*/terraform.tfstate
terraform/*/terraform.tfstate.backup
terraform/*/.terraform/
```

## 7. Provider configuration

`terraform/hetzner-arm/versions.tf`:

```hcl
terraform {
  required_version = ">= 1.7.0"   # OpenTofu's baseline

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.45"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
```

Provider tokens are NOT in the manifest. They come from OpenBao via
the same wrapper pattern Ansible uses. See §11 step 6.

## 8. Resources to declare

Mirror what `provision-nodes.sh` creates today, plus what's currently
managed by hand. Each resource maps directly to a field in
`manifests/hetzner-arm.yaml`.

| Resource | Maps to manifest field | Notes |
|---|---|---|
| `hcloud_ssh_key.k3s` | `spec.topology.admin_user` (key path) | Reads pubkey from `~/.ssh/id_ed25519_k3s_hetzner.pub` via `file()` |
| `hcloud_network.k3s_private` | `spec.provider.cloud.private_network` + `private_cidr` | One private network for the cluster |
| `hcloud_network_subnet.k3s_private` | derived | Subnet within the network |
| `hcloud_server.node[3]` | `spec.resource_profile.cluster_size` + `spec.provider.cloud.server_type` + `region` | `for_each` over a generated map of node names |
| `hcloud_server_network.node[3]` | derived | Attaches each server to the private subnet |
| `hcloud_firewall.k3s` | `spec.network.ssh_allow_ipv4` + `ssh_allow_ipv6` | Replaces `tasks/hetzner_firewall.yml` |
| `hcloud_firewall_attachment.k3s` | derived | Attaches firewall to all nodes |
| `cloudflare_record.cluster_apex` | `spec.domain.cluster_domain` + LB IP | A record `dmf.example.com` → LB IP |
| `cloudflare_record.cluster_auth` | `spec.domain.hosts.authentik` | A record `auth.dmf.example.com` → LB IP |
| `local_file.hosts_ini` | output | Renders `inventories/hetzner-arm/hosts.ini` from `templates/hosts.ini.tftpl` |

Explicitly NOT created by tofu:

- **`hcloud_load_balancer`** — kept reactive via Hetzner CCM (already works, not worth pre-creating). The CCM creates `dmf-traefik` when `310-ingress-public.yml` deploys the Service of type LoadBalancer. The wildcard DNS records still need an IP though — see §15 stretch.
- **Wildcard `*.dmf.example.com` Cloudflare record** — currently not needed (wildcard cert covers it without DNS). Leave as is.
- **Tailscale / Headscale** — Ansible Layer-3 task `321-tailscale.yml` handles. Could move to tofu later (`tailscale_tailnet_key`, `tailscale_acl`) but that's the medium-aggressive path.

## 9. Inventory rendering

`templates/hosts.ini.tftpl`:

```hcl
# Generated by OpenTofu — do not edit by hand.
# Source: manifests/hetzner-arm.yaml + terraform/hetzner-arm/*.tf
# Regenerate: bin/tf-render-inventory.sh hetzner-arm

[k3s]
%{ for node in nodes ~}
${node.name} ansible_host=${node.public_ip} k3s_node_ip=${node.private_ip} ansible_user=${admin_user}
%{ endfor ~}

[k3s_control]
${control_node}
```

Rendered via:

```hcl
resource "local_file" "hosts_ini" {
  filename = "${path.root}/../../inventories/hetzner-arm/hosts.ini"
  content  = templatefile("${path.module}/templates/hosts.ini.tftpl", {
    nodes        = [for s in hcloud_server.node : { name = s.name, public_ip = s.ipv4_address, private_ip = one([for n in s.network : n.ip]) }]
    admin_user   = "k3s-admin"   # from manifest
    control_node = "k3s-node-01" # from manifest spec.topology.control_plane.bootstrap_node
  })
  file_permission = "0644"
}
```

`bin/tf-render-inventory.sh` is a thin wrapper that runs `tofu apply
-target=local_file.hosts_ini` so the file regenerates without
re-touching upstream resources.

## 10. Resource Profile → tofu vars

The manifest is the higher-order source. To wire it in:

```hcl
locals {
  manifest = yamldecode(file("${path.module}/../../manifests/hetzner-arm.yaml"))
  spec     = local.manifest.spec
}

# Then reference everywhere:
#   local.spec.provider.cloud.server_type
#   local.spec.provider.cloud.region
#   local.spec.resource_profile.cluster_size
#   local.spec.network.ssh_allow_ipv4
#   ...
```

This means: edit the manifest → `tofu plan` shows the diff. The
manifest stays the canonical declaration; tofu is a renderer.

Tokens (the only secrets) come via env vars:

```bash
export TF_VAR_hcloud_token="$(read from openbao)"
export TF_VAR_cloudflare_api_token="$(read from openbao)"
tofu apply
```

`bin/tf-apply.sh` does the OpenBao read (matches the Ansible wrapper
pattern in `bin/export-openbao-vars.sh`) and execs `tofu` with the
env populated.

## 11. Implementation steps (numbered, executable)

1. **Create directory skeleton** (no resources yet).
   - `mkdir -p dmf-env/terraform/{modules/hetzner-cluster/templates,hetzner-arm}`
   - `terraform/README.md` — what this is, why local backend, JuiceFS path
   - `.gitignore` updates per §6

2. **Write the module** (`terraform/modules/hetzner-cluster/`).
   - `versions.tf` — provider pins
   - `variables.tf` — accepts the manifest spec as `var.spec` (object)
   - `main.tf` — the resources from §8
   - `outputs.tf` — exports node list, control node name, LB DNS target
   - `templates/hosts.ini.tftpl` — per §9

3. **Write the env root** (`terraform/hetzner-arm/`).
   - `main.tf` — `yamldecode` the manifest, instantiate the module, declare `local_file.hosts_ini`
   - `versions.tf` — provider config + state backend
   - `outputs.tf` — re-export node info for ad-hoc inspection

4. **Wrapper scripts** (`bin/`).
   - `tf-apply.sh` — OpenBao read → `TF_VAR_*` → `tofu apply`
   - `tf-render-inventory.sh` — `tofu apply -target=local_file.hosts_ini`

5. **OpenBao secret entries** (the only new secrets).
   - `secret/k3s-hetzner/credentials#hcloud_token` — already present (the Ansible wrapper reads it)
   - `secret/k3s-hetzner/credentials#cloudflare_dns_token` — already present
   - No new OpenBao paths needed; tofu and ansible read the same secrets.

6. **Dry-run import** (no destructive changes).
   - Initialise: `cd terraform/hetzner-arm && tofu init`
   - **Import existing resources** (CRITICAL — first apply must NOT recreate the running cluster):
     - `tofu import 'module.cluster.hcloud_server.node["k3s-node-01"]' <id>`
     - same for nodes 02 + 03
     - `tofu import 'module.cluster.hcloud_network.k3s_private' <id>`
     - SSH key, firewall, network subnet
     - Cloudflare records (zone_id + record_id)
   - `tofu plan` — must show **no changes** if the module faithfully describes current state. If it shows changes, fix the module until plan is clean.

7. **First apply** (against current state — must be a no-op).
   - `tofu apply` — confirms idempotency on the running cluster
   - `tofu apply -target=local_file.hosts_ini` — generates the new `hosts.ini` and verifies it matches the existing committed one (diff should be empty after normalising)

8. **Cut-over** (deprecate `provision-nodes.sh`).
   - Add a deprecation banner to `provision-nodes.sh` pointing at `bin/tf-apply.sh`
   - Update `DEPLOYMENT.md` to describe the new Layer-1 step
   - Update `manifests/README.md` to note that the manifest now drives tofu
   - Update `DMF EBU Mapping (2026-04-25).md` Layer 1 row
   - Remove `tasks/hetzner_firewall.yml` from Ansible (replaced by `hcloud_firewall` resource)
   - Update `tasks/hetzner_ccm.yml` if it refers to firewall management (verify it doesn't)

9. **Tear-down rehearsal** (proves the loop is fully captured in tofu).
   - `tofu destroy -target=hcloud_server.node["k3s-node-03"]` (single node)
   - `tofu apply` — recreates it
   - SSH in, verify Ansible can re-converge (`bin/run-playbook.sh playbooks/300-k3s.yml`) — proves the boundary handoff works
   - This is the real verification, done on a non-critical node.

10. **Commit + push**.
    - One commit per logical step (skeleton, module, root, wrappers, deprecation).
    - Push to forgejo.

## 12. Verification

| Check | Command | Pass criteria |
|---|---|---|
| YAML reads | `tofu console <<< 'yamldecode(file("../../manifests/hetzner-arm.yaml"))'` | Returns the parsed object |
| Plan against current state (post-import) | `tofu plan` | "No changes" |
| Inventory render matches | `diff <(tofu output -raw hosts_ini) inventories/hetzner-arm/hosts.ini` | Empty |
| Single-node destroy + recreate | §11 step 9 | k3s rejoins; verify with `kubectl get nodes` |
| Drift detection | Manually delete the firewall in Hetzner console; run `tofu plan` | Plan shows the firewall as needing recreation |

## 13. Risks & rollback

| Risk | Likelihood | Mitigation |
|---|---|---|
| First `tofu apply` recreates a running server | Medium | The import step (§11.6) is mandatory and the rehearsal must be a no-op before any non-import apply runs |
| `local_file.hosts_ini` overwrites a hand-edited inventory | Low | The template emits the same format Ansible expects; first-apply diff is the gate |
| Provider version bump breaks plan | Low (mitigated) | `.terraform.lock.hcl` committed; provider versions pinned in `versions.tf` |
| State file lost (JuiceFS unavailable) | Medium | State can be re-imported from existing Hetzner resources via §11.6; document this in `terraform/README.md` |
| Cloudflare token has wider scope than needed | Low | Token is already present and scoped to DNS-only zone; no broadening required |
| Ansible Layer-2 fails to connect to a freshly tofu-provisioned host | Medium | Explicitly tested by §11.9 (single-node rehearsal); `harden_admin_pubkey` and `ansible_ssh_private_key_file` already point at the same key tofu uploads |

**Rollback**: until `provision-nodes.sh` is deleted, the rollback path
is "ignore tofu, run provision-nodes.sh against a torn-down cluster".
The state file is the only piece that becomes orphaned; re-importing
is straightforward.

## 14. Files to create / modify

**New (dmf-env):**
- `terraform/README.md`
- `terraform/modules/hetzner-cluster/{versions,variables,main,outputs}.tf`
- `terraform/modules/hetzner-cluster/templates/hosts.ini.tftpl`
- `terraform/hetzner-arm/{versions,main,outputs}.tf`
- `bin/tf-apply.sh`
- `bin/tf-render-inventory.sh`
- `.gitignore` additions

**Modified (dmf-env):**
- `bin/provision-nodes.sh` — deprecation banner only
- `DEPLOYMENT.md` — new Layer-1 step replaces "run provision-nodes.sh"
- `manifests/README.md` — note that manifest now drives `tofu`
- `tasks/hetzner_firewall.yml` — deleted (superseded by `hcloud_firewall` resource)

**Modified (operator note store):**
- `DMF EBU Mapping (2026-04-25).md` — Layer 1 row updated
- `DMF Open Questions 2026-04-20.md` — close §EBU-3 codegen sub-item for tofu
- `DMF Layer-1 OpenTofu Bootstrap Plan 2026-04-26.md` — this doc

**No change (dmf-infra):**
- `lifecycle-provision.yml` — Layer 1 was never imported here; nothing to change
- `playbooks/200-baseline.yml`, `210-harden.yml`, `300-k3s.yml`, etc. — all unchanged
- `roles/` — unchanged

## 15. Stretch goals (deferred, not in this plan)

These are NOT part of the conservative path. Listed so they don't leak in:

- **Cloud-init handoff** — let tofu's `user_data` provision the `k3s-admin` user + sshd config so Ansible has nothing to do at Layer 2 except install packages. Saves one round-trip but couples Ansible-tier work into tofu.
- **Pre-create the LB** — `hcloud_load_balancer` declared in tofu, then ingress role told to attach to it (instead of CCM creating it on Service apply). Predictable IP for DNS, but requires changing the ingress role.
- **Wildcard `*.dmf.example.com` Cloudflare record** — only useful if the `*` cert ever needed DNS-01 fallback for sub-zones; currently not needed.
- **Tailscale ACLs in tofu** — `tailscale_acl` resource. Move headscale config out of Ansible. Worth doing but separate scope.
- **Multi-environment** — second env (e.g. flypack-staging) under `terraform/<env>/` reusing the module. Trivial once the first env works; not in this plan.
- **`tofu plan` in CI** — gate all Layer-1 changes through PR review. Requires Forgejo Actions + secret store; defer until value is proven.

## 16. Decisions (locked 2026-04-26)

1. **State file location:** `<secure-store>/terraform-states/hetzner-arm/terraform.tfstate` — peer directory under `<secure-store>/`, separate from `openbao-breakglass/`. Infrastructure state lives next to (not inside) the secrets backup.
2. **Cloudflare records in tofu:** YES — apex (`dmf.example.com`) and auth (`auth.dmf.example.com`) A records are declared as `cloudflare_record` resources, using the existing OpenBao-stored DNS token.
3. **`provision-nodes.sh` cut-over:** keep with a deprecation banner for one cycle. Delete after the first successful tofu-driven destroy + recreate (§11 step 9) is verified end-to-end.
4. **`kube-hetzner` opinionated module:** not adopted. Revisit later if multi-cluster fleet work makes the opinionated module's MicroOS + bundled k3s install attractive. For now, write a thin Layer-1-only module that hands off cleanly to the existing Ansible playbooks.

---

**Status:** plan locked. Decisions resolved. Ready to begin §11 step 1.
Estimated end-to-end: ~1.5 days, gated on the import-and-no-op
verification in §11.6.
