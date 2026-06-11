# DMF Infra + Runbooks Hardcoded Environment Literals Review

Date: 2026-05-19
Scope:
- `dmf-infra/k3s-lab-bootstrap/playbooks`
- `dmf-infra/k3s-lab-bootstrap/roles`
- `dmf-runbooks/playbooks`
- `dmf-runbooks/roles`
- selected repo docs and helper scripts referenced by those areas

This report is sanitized: concrete operator domains and concrete private-node
addresses are intentionally described by class rather than copied verbatim into
this tracked umbrella document.

## Method

The scan combined targeted `rg` probes with a helper classifier created outside
the repo. Invocation shape, with operator workstation paths redacted to the
umbrella convention:

```bash
python3 <scan-helper>.py \
  "$DMFDEPLOY_UMBRELLA/dmf-infra" \
  k3s-lab-bootstrap/playbooks \
  k3s-lab-bootstrap/roles

python3 <scan-helper>.py \
  "$DMFDEPLOY_UMBRELLA/dmf-runbooks" \
  playbooks roles README.md CLAUDE.md
```

The classifier buckets hits for:
- RFC1918/private and provider-private IPs
- public URLs/domains
- operator-specific domains/identifiers
- absolute workstation paths
- environment/provider names
- SSH key/user path hints

Loopback, bind-all addresses, Kubernetes service DNS, broad RFC1918 allowlists,
and `dmf.example.com` placeholders were treated as generally acceptable unless
they appeared in an environment-varying role default.

## Findings

### P0 - Environment-Varying Private Node Map In Runbooks

Files:
- `dmf-runbooks/playbooks/launch-nmos-cpp.yml:19-33`
- `dmf-runbooks/playbooks/teardown-nmos-cpp.yml:19-33`

Finding:
Both launcher playbooks contain a hardcoded private subnet comment and a
hostname-to-private-IP map for three k3s nodes. This is environment-specific
and is already known to break outside the original provider/network shape.

Impact:
Catalog launch/finalise jobs can target the wrong private addresses or fail
outright in any environment whose node names or private subnet differ.

Recommendation:
Remove the inline map. Populate node private IPs from inventory/NetBox, then
compose `ansible_host` from a source-of-truth field. The TODO in the files
already points at the correct direction: a `k3s_node_ip` custom field plus
AWX inventory-source `compose:`.

### P0 - Operator-Specific Domain In Kubernetes Annotation

File:
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/zot/tasks/main.yml:188`

Finding:
The Zot deployment uses an annotation key under an operator-specific DNS
namespace.

Impact:
This leaks a concrete operator domain into a public/generic role and violates
the repo rule that public repos avoid specific DNS.

Recommendation:
Use a generic annotation namespace, for example under `dmfdeploy.io` if that is
the intended public project domain, or a Kubernetes-safe project-local prefix
such as `dmfdeploy.dev` only if that domain is intentionally public.

### P1 - Hardcoded Private CIDR Defaults In Infra Roles

Files:
- `dmf-infra/k3s-lab-bootstrap/roles/base/harden/defaults/main.yml:17-18`
- `dmf-infra/k3s-lab-bootstrap/roles/base/chrony/defaults/main.yml:31-34`

Finding:
The hardening role defaults the private cluster CIDR to a concrete small
private subnet, and Chrony inherits that same default.

Impact:
The default can be wrong for any cloud/provider inventory with a different
private network. It also weakens the distinction between generic role defaults
and private environment inventory.

Recommendation:
Make `harden_private_cidr` required for configurations that need private
cluster trust, or derive it from a generic inventory variable such as
`k3s_private_cidr`/`cluster_private_cidr`. Avoid a concrete fallback in the
public role.

### P1 - NetBox Seed Config Contains Concrete Private Service Defaults

Files:
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo-bootstrap/templates/netbox-data/config-contexts/sites.yaml.j2:17-32`
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo-bootstrap/templates/netbox-data/templates/device-cisco-base.j2.j2:12-15`

Finding:
The NetBox seed config-context defaults include concrete private addresses for
DNS, syslog, and SNMP trap destinations. The Cisco template also has a concrete
private DNS fallback.

Impact:
Generated NetBox data and rendered device templates can silently contain
environment-specific addressing when an environment does not override every
value.

Recommendation:
Use empty lists or placeholder examples in seed config, and make per-site DNS,
syslog, and trap destinations explicit environment inventory inputs. For the
Cisco template, default to an empty list and render no `ip name-server` lines
unless values exist.

### P1 - OpenBao USB Path Bypasses Its Own Variable

Files:
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/defaults/main.yml:45-50`
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/tasks/main.yml:372-385`

Finding:
The OpenBao role defines `openbao_usb_dir`, but the init-time mount assertion
still checks a concrete macOS volume path directly.

Impact:
Operators using a different mount path or per-environment subdirectory will
still fail against the hardcoded path.

Recommendation:
Use `openbao_usb_dir` consistently in the `stat` task and failure message.
Consider making the default a neutral empty value that must be supplied by
private inventory for init workflows.

### P2 - Hetzner-Specific SSH Key Default In Host Verify

File:
- `dmf-infra/k3s-lab-bootstrap/playbooks/219-host-verify.yml:29-30`

Finding:
`verify_ssh_key` falls back to a provider-specific key name under `~/.ssh`.

Impact:
This makes the generic preflight provider-biased and can fail on other
environments unless inventory overrides the key.

Recommendation:
Require `ansible_ssh_private_key_file` or use a generic `verify_ssh_key`
inventory variable without a provider-specific fallback.

### P2 - Legacy Environment IDs In Born-Inventory Defaults

File:
- `dmf-infra/k3s-lab-bootstrap/roles/common/dmf-born-inventory/defaults/main.yml:4-18`

Finding:
The born-inventory role still falls back to a specific legacy environment ID
and comments reference legacy environments.

Impact:
The role can silently stamp new or incomplete environments with the wrong
identity. This area is already dirty/in-flight in the local worktree.

Recommendation:
Make `dmf_env_id` required for born-inventory writes, or default to an explicit
placeholder that fails validation before it reaches NetBox.

### P2 - Provider Metadata IP Literal

Files:
- `dmf-infra/k3s-lab-bootstrap/playbooks/300-k3s.yml:12-14`
- `dmf-infra/k3s-lab-bootstrap/roles/base/ingress-private/defaults/main.yml:13-16`

Finding:
Aliyun metadata/DNS provider-private ranges are present in comments/examples.

Impact:
These are provider-specific rather than operator-specific, so they are less
sensitive, but they still encode cloud behavior in generic infra code.

Recommendation:
Accept if the intent is provider documentation, or move the concrete metadata
endpoint examples into provider-specific inventory/docs. Avoid using them as
role defaults.

### P2 - Runbooks Docs Contain Operator Workstation Paths And Env-Specific Registry Host

Files:
- `dmf-runbooks/roles/nmos-cpp/README.md:76-146`
- `dmf-runbooks/roles/nmos-cpp/scripts/push-nmos-images.sh:14-16`

Finding:
The NMOS README and helper script comments use tilde-relative operator
workstation paths to the dmfdeploy umbrella.
The README also mentions an environment-specific Zot ingress host.

Impact:
Public docs describe one operator workstation layout and one private runtime
hostname.

Recommendation:
Rewrite examples to use `$DMFDEPLOY_UMBRELLA`, relative paths, and
`registry.dmf.example.com` or `<registry-host>` placeholders.

## Non-Issues / Acceptable Hits

The scan also found many literals that appear acceptable:
- `127.0.0.1` for local OpenBao commands and port-forwarded local services
- `0.0.0.0` for container bind/listen addresses
- Kubernetes service DNS such as `*.svc.cluster.local`
- broad private allowlists used by application defaults, such as RFC1918 CIDR
  ranges in NetBox proxy settings
- `dmf.example.com`, `example.com`, `local.invalid`, and `<placeholder>` style
  examples
- public project/package registries such as GHCR, Docker Hub, Quay, Helm chart
  repos, and upstream project docs

## Repo State At Review Time

- `dmf-infra` had pre-existing dirty changes in:
  - `k3s-lab-bootstrap/inventories/example/group_vars/all/main.yml`
  - `k3s-lab-bootstrap/roles/common/dmf-born-inventory/defaults/main.yml`
  - `k3s-lab-bootstrap/roles/common/dmf-born-inventory/tasks/main.yml`
- `dmf-runbooks` was clean.

No component repo files were modified during this review.
