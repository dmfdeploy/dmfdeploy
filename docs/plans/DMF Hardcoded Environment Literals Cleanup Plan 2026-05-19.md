---
status: executed
date: 2026-05-19
---
# Hardcoded Environment Literals Cleanup — dmf-infra + dmf-runbooks

Date: 2026-05-19
Source review: [`docs/reviews/dmf-infra-runbooks-hardcoded-env-literals-review-2026-05-19.md`](../reviews/dmf-infra-runbooks-hardcoded-env-literals-review-2026-05-19.md)

## Context

The 2026-05-19 sanitized scan of `dmf-infra/k3s-lab-bootstrap/{playbooks,roles}`
and `dmf-runbooks/{playbooks,roles}` surfaced 9 places where
environment-specific literals (private IPs, operator-specific DNS, operator
workstation paths, legacy env IDs, provider-private metadata endpoints) leak
into generic public roles. All 9 were re-verified against the current source
on the same date — every finding still applies.

This plan resolves them in 4 PR-sized waves, ordered by blast radius. Each
wave is self-contained and lands independently.

Out-of-scope, intentionally:
- Existing `hetzner-arm` and `aliyun-123` env behavior must remain
  byte-identical after the cleanup (graceful fallbacks where required).
- No new infrastructure work — this is purely lifting literals from generic
  code into private inventory or asserting them as required inputs.
- No re-architecting of ADR-0025 catalog launchers; the launcher map fix
  (Wave 2) is the smallest change that removes the public-repo leak even if
  the launcher itself is later replaced by in-cluster Helm.

## Wave 1 — Public-domain hygiene (P0-b, P2-d)

Smallest, lowest-risk PR. Unblocks public-repo publication and removes the
two operator-identity leaks from `dmf-infra` and `dmf-runbooks`.

### 1.1 Zot annotation key (P0-b)

File: `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/zot/tasks/main.yml:188`

Today the htpasswd-hash annotation key is namespaced under the operator's
custom lab domain (an operator-identity leak per the scrub policy). The
annotation is operator-private metadata used only to trigger pod rollout
on credential change — no external system reads it.

Change: replace the operator-specific DNS prefix with a placeholder pending
the canonical public DMF project domain decision. Interim replacement uses
the reserved `.local` TLD (RFC 6762), which avoids accidental DNS collision
and signals "placeholder pending decision" to readers:

```yaml
dmfdeploy.local/htpasswd-hash: "{{ zot_admin_htpasswd_line | hash('sha256') }}"
```

Add a one-line comment in the role pointing at the open decision. File a
follow-up entry in `docs/agentic/decisions-open.md`: "Public DMF project
DNS namespace for annotation/label prefixes."

Verification: `kubectl rollout restart deploy/zot -n zot` still cycles pods
when the htpasswd line changes (the annotation hash on the pod template is
what triggers rollout — the key prefix is irrelevant to k8s).

### 1.2 NMOS README + push script (P2-d)

Files:
- `dmf-runbooks/roles/nmos-cpp/README.md:60-150`
- `dmf-runbooks/roles/nmos-cpp/scripts/push-nmos-images.sh:14-28`

README edits:
- Replace tilde-relative operator workstation paths to the dmfdeploy
  umbrella with `$DMFDEPLOY_UMBRELLA/...` throughout (matches the boot
  ritual in `dmfdeploy/CLAUDE.md`).
- Replace the environment-specific Zot ingress hostname (currently a
  concrete operator subdomain) with `<env-registry-host>` and add a
  one-line pointer: "set from your env's `cluster_ingress_external_url`
  or the inventory `zot_external_host`."
- The `registry.dmf.example.com/...` tags in the build example are already
  using the canonical public example domain — leave those.

`push-nmos-images.sh` edits:
- Replace operator workstation paths in the Usage comment with the
  umbrella-relative form (`$DMFDEPLOY_UMBRELLA/dmf-runbooks/...`).
- Line 28's `docker build -t registry.dmf.example.com/...` is the public
  example domain (acceptable per repo convention), but the tag is still
  hardcoded — promote `REGISTRY_HOST="${REGISTRY_HOST:-registry.dmf.example.com}"`
  to the top of the script so an operator can override without editing.
- **Do not** require `$DMFDEPLOY_UMBRELLA` at runtime: the script already
  self-locates via `SCRIPT_DIR → REPO_ROOT → UMBRELLA` (lines 20-23). The
  env-var convention is for README prose only; the script's runtime
  derivation stays intact for portability.

Verification: `bash -n push-nmos-images.sh` parses; manual smoke run with
`REGISTRY_HOST=registry.example.invalid` echos the right tag.

## Wave 2 — Catalog launcher NetBox custom-field fix (P0-a)

Removes the inline node-hostname-to-private-IP map from both NMOS launchers
by sourcing the private IP from a NetBox custom field. Implements the TODO
already written into the launchers.

### 2.1 NetBox schema change (dmf-env)

Add a `k3s_node_ip` custom field on the **`virtualization.virtualmachine`**
content type (not `dcim.device`).

Verified at review time: `dmf-born-inventory/tasks/node.yml` creates and
updates k3s nodes exclusively via `/virtualization/virtual-machines/` (lines
4, 14, 38, 409). They are VMs in NetBox, not devices. The AWX NetBox
dynamic inventory plugin must therefore also be configured to source
virtual machines — confirm `device_query_filters` / `vm_query_filters` on
the inventory source emit the k3s VMs before the compose rule will fire.

- Type: text (IPv4 string, no CIDR)
- Required: no (optional — only set on k3s control/worker VMs)
- Label: "k3s node private IP"
- Description: "Private subnet IP used for cluster-egress SSH from
  AWX/runner pods. Required for catalog launcher SSH to bypass cloud
  firewall blocking egress to public node IPs."

Seeding path: extend `dmf-infra/k3s-lab-bootstrap/roles/common/dmf-born-inventory/tasks/node.yml`
to set the `k3s_node_ip` custom field on each VM PATCH/POST body at
born-inventory time, sourced from the inventory host var of the same name
(already asserted at `playbooks/219-host-verify.yml:223-228`).

### 2.2 AWX inventory-source compose rule (dmf-infra)

File: `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/`
(NetBox dynamic inventory source config — exact file determined at impl time).

Add to the inventory source's `compose:` block:
```yaml
compose:
  ansible_host: custom_fields.k3s_node_ip | default(primary_ip4 | regex_replace('/.*$', ''), true)
```

Notes on this expression:
- **No `ansible.utils.ipaddr`** — that collection is not guaranteed to be
  present in the AWX project's collections (typically only `netbox.netbox`
  is installed there). `regex_replace` is `ansible.builtin` and available
  everywhere.
- The netbox.netbox dynamic inventory plugin emits `primary_ip4` as a
  string with CIDR (e.g. `"<node-private-ip>/<prefix>"`); the
  `regex_replace('/.*$', '')` strips the prefix length.
- The `true` 2nd arg to `default()` triggers the fallback when
  `k3s_node_ip` is empty or null (not just undefined), so VMs with an
  empty custom field still fall through to `primary_ip4` cleanly.
- Validate the actual emitted shape (`primary_ip4` vs `primary_ip4.address`)
  against a real inventory sync before finalizing — netbox.netbox versions
  differ on this. If the plugin emits `.address`, swap to
  `primary_ip4.address | regex_replace('/.*$', '')`.

### 2.3 Strip the launcher set_fact (dmf-runbooks)

Files: `playbooks/launch-nmos-cpp.yml`, `playbooks/teardown-nmos-cpp.yml`

Remove lines 19-35 (the TODO comment + `set_fact: ansible_host: …` block).
AWX now delivers the correct `ansible_host` from inventory.

Verification:
1. `dmf-infra` PR lands first (NetBox custom field on the VM content type
   + AWX inventory source compose rule + born-inventory seeding).
2. Re-run `661-awx-integration.yml` (or whatever publishes the inventory
   source) against the live env.
3. Sync NetBox inventory in AWX; spot-check that the k3s control-plane VM
   shows the correct private IP as `ansible_host` in job-template variable
   preview.
4. Then `dmf-runbooks` PR lands and the `media-launch-nmos-cpp` JT runs green.

If step 3 fails, the launcher PR is held — public repo stays clean either
way (the launcher with the map is no worse than today).

## Wave 3 — Role defaults → required inventory inputs (P1-a, P1-b, P1-c, P2-a, P2-b)

Consistent pattern across 5 findings: remove the concrete fallback default,
add an `assert` task (or `vars: <key>: "{{ undef('required') }}"` shim) so
the playbook fails loud with a pointer to the inventory key.

For each of these, the existing hetzner-arm + aliyun-123 envs already set
the correct value in their private inventory — so the only behavioral change
for those envs is "explicit instead of implicit". A new env that forgets
the value now fails at plan time instead of silently shipping the
hetzner-arm literal.

### 3.1 `harden_private_cidr` (P1-a)

File: `dmf-infra/k3s-lab-bootstrap/roles/base/harden/defaults/main.yml:17-18`,
inherited at `roles/base/chrony/defaults/main.yml:34`.

- Drop the concrete `harden_private_cidr` default from
  `harden/defaults/main.yml` (currently a small `/28` literal).
- Add a top-of-role `assert` in `harden/tasks/main.yml`:
  ```yaml
  - name: Assert harden_private_cidr is set
    ansible.builtin.assert:
      that: harden_private_cidr is defined and harden_private_cidr | length > 0
      fail_msg: >
        harden_private_cidr must be set in inventory group_vars (the private
        cluster subnet for this environment). The harden + chrony roles
        trust this CIDR for intra-cluster traffic.
  ```
- Update `chrony_allow_cidr` to drop its `default(...)` fallback — now
  plain `"{{ harden_private_cidr }}"` since the assert guarantees it.
- Add `harden_private_cidr` to each env's `group_vars/all/main.yml` in
  `dmf-env` (existing envs — verify the value already in use before
  lifting it from the public default).

### 3.2 NetBox seed config-context (P1-b)

Files:
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo-bootstrap/templates/netbox-data/config-contexts/sites.yaml.j2:17-32`
- `…/templates/device-cisco-base.j2.j2:14`

Changes:
- `dns.servers` default: `[]` instead of two concrete private addresses.
- `syslog.servers` default: `[]` instead of a single-entry list with a
  concrete private address.
- `snmp.traps` default: `[]` instead of a single-entry list with a concrete
  private destination address.
- Cisco template `ip name-server` block: already loops over
  `site.config_context.data.dns.servers | default([])` after the seed change,
  no `ip name-server` lines rendered when empty — drop the concrete
  fallback list from its `default(...)` filter.

For environments that want DNS/syslog/SNMP populated, supply per-site
`dns_primary`, `dns_secondary`, `syslog_primary`, `snmp_trap_dest` etc. as
NetBox config-context overrides (existing override path is already wired —
this only removes the concrete fallback).

### 3.3 OpenBao USB path (P1-c)

Files:
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/defaults/main.yml:45-50`
- `…/tasks/main.yml:372-385`

Change `tasks/main.yml:374`:
```yaml
- name: Assert OPENBAO_A USB is mounted (holds recovery shares 4+5)
  ansible.builtin.stat:
    path: "{{ openbao_usb_dir }}"
```

And the fail_msg:
```yaml
fail_msg: >-
  USB 'OPENBAO_A' is not mounted at {{ openbao_usb_dir }}. Plug it in
  and re-run. OpenBao init writes shares 4 and 5 to this path.
```

Leave the role default for `openbao_usb_dir` unchanged for now (matches
the existing operator workflow) — the variable is already documented as
per-environment overridable. The bug is purely "ignores its own variable",
not "default is wrong."

Optional follow-up (not in this wave): switch the default to `""` and add
an assert that requires it to be set explicitly. Defer until a second env
actually uses a different mount path.

### 3.4 verify_ssh_key (P2-a)

File: `dmf-infra/k3s-lab-bootstrap/playbooks/219-host-verify.yml:29-30`

Today the play-vars block falls back to a provider-named key path under
`~/.ssh` when `ansible_ssh_private_key_file` is not defined.

The play runs on `hosts: localhost` and then loops `_ssh_checks` over
`groups.k3s`. A naive rewrite to
`verify_ssh_key: "{{ ansible_ssh_private_key_file | mandatory }}"` resolves
against **localhost's** hostvars, not the k3s hosts' — so the rewrite
would either fail when localhost has no key set, or quietly pick localhost's
unrelated key and miss the per-host inventory values. (Caught by codex
review on 2026-05-19.)

Correct change: introduce an explicit `verify_ssh_key` inventory variable
with no provider-named fallback. The preflight assumes a homogeneous
control plane (single key for all k3s nodes), which matches how the
playbook is used today.

Drop the current `vars:` line that synthesizes a fallback. Replace it
with an `assert` task at the top of `tasks:` so the playbook fails fast
with a clear message if inventory forgets the var:

```yaml
tasks:
  - name: Assert verify_ssh_key is set in inventory
    ansible.builtin.assert:
      that:
        - verify_ssh_key is defined
        - verify_ssh_key | length > 0
      fail_msg: >
        verify_ssh_key must be set in inventory group_vars (the SSH
        private key path used for k3s preflight SSH checks).
```

The remaining task references to `verify_ssh_key` (lines 138, 156, 162,
167) resolve directly from inventory after the assert passes — no
self-referential `lookup('vars', ...)` needed, which would either recurse
or shadow the inventory value at play-var precedence.

Set `verify_ssh_key` in each env's `group_vars/all/main.yml` to the
correct private key path. Document the new required var in the role
README.

Follow-up (not in this wave): if multi-key envs appear, switch to
loop-scoped per-host resolution via
`hostvars[item].ansible_ssh_private_key_file | mandatory` inside the SSH
check task. Track as a separate ADR/plan item only when needed.

### 3.5 Born-inventory legacy ID fallbacks (P2-b)

File: `dmf-infra/k3s-lab-bootstrap/roles/common/dmf-born-inventory/defaults/main.yml:14-30`

Two fallback chains both terminate at the same legacy environment-id
literal:
- `dmf_born_inventory_env_name` (legacy `env_name` chain, line 14-17)
- `dmf_born_inventory_env_id` (new `env_id` chain, line 27-30)

Per the [init-wizard env_id plan](DMF%20Init%20Wizard%20env_id%20Provider%20Architecture%20Split%20Plan%202026-05-19.md),
existing envs continue using the inventory directory name as their
identifier via `dmf_inventory_env_name` (injected by
`dmf-env/bin/run-playbook.sh`). The terminal legacy literal only fires if
both `dmf_env_id` AND `dmf_inventory_env_name` are unset — which can only
happen if the wrapper isn't used. In that case, silently stamping NetBox
with a legacy env id is the wrong failure.

Change both fallback chains to terminate at a noisy assert rather than the
literal:

```yaml
dmf_born_inventory_env_id: >-
  {{ dmf_env_id
     | default(topology.env_id
       | default(dmf_inventory_env_name | mandatory)) }}
```

(`mandatory` filter fails with a clear "Mandatory variable not defined"
message that surfaces the inventory-loading bug rather than masking it.)

Move the same pattern to `dmf_born_inventory_env_name`.

Verification: re-run `661-netbox-sot.yml` against each existing env — all
still resolve via `dmf_inventory_env_name` and produce identical NetBox
state. Run `ansible-playbook ... -e dmf_inventory_env_name=""` and confirm
it fails fast with the mandatory-variable error.

## Wave 4 — Provider metadata documentation cleanup (P2-c)

Smallest, mostly cosmetic. Two files contain Aliyun metadata IPs in
comments:

- `dmf-infra/k3s-lab-bootstrap/playbooks/300-k3s.yml:12-14` (comment block
  documenting the opt-in `k3s_provider_id_metadata_url` activation)
- `dmf-infra/k3s-lab-bootstrap/roles/base/ingress-private/defaults/main.yml:13-16`
  (comment explaining `ingress_private_force_helm_upgrade: false`)

Both are *documentation*, not active defaults. The reviewer flagged them
because they encode cloud-specific knowledge in generic infra code.

Two acceptable resolutions:

a) **Keep as comments, label them as provider examples.** Prepend `# Aliyun example —`
to each occurrence. Cheapest; preserves the operator-useful context.

b) **Move to a provider-specific docs section.** Create
`dmf-infra/docs/provider-notes/aliyun.md` and replace the comments with a
one-line pointer. Higher cost; aligns with the "providers documented
separately" pattern if more provider-specific notes accumulate later.

**Recommended:** (a) — the comments are immediately load-bearing for an
operator reading the playbook (the metadata URL is exactly what they'd
copy-paste into a new env's `group_vars`). Moving them to a separate doc
sacrifices that proximity for a small purity win. Reconsider if a third
provider's notes appear and the comment density grows.

## Sequencing + ownership

| Wave | Repo(s) touched | Depends on | Notes |
|---|---|---|---|
| 1 | dmf-infra, dmf-runbooks | none | Two independent PRs. Land in either order. |
| 2 | dmf-infra + dmf-env, then dmf-runbooks | none | Two-stage merge: infra+env first, runbooks second after AWX inventory re-sync verified. |
| 3 | dmf-infra + dmf-env | none | Single PR per repo. Verify each existing env still bootstraps cleanly after the inventory additions. |
| 4 | dmf-infra | none | Single small PR. Comment edits only. |

All four waves can land in parallel calendar-time if PR reviewers are
available; only Wave 2's internal two-stage sequence has a real ordering
constraint.

## Verification matrix

| Wave | Smoke test |
|---|---|
| 1.1 | Edit `zot_admin_password` in the env's inventory, rerun `vertical-security/600-zot.yml`; confirm pod rolls. |
| 1.2 | `bash -n push-nmos-images.sh`; render README in GitHub UI; `bin/scrub-public-repos.sh dmf-runbooks` is clean. |
| 2 | `media-launch-nmos-cpp` AWX JT runs green. NetBox VM for the k3s control-plane node shows `custom_fields.k3s_node_ip` set to the expected private address in the inventory variable preview. |
| 3.1 | `bin/run-playbook.sh <env> playbooks/210-harden.yml` succeeds. Removing the var from inventory fails loud with the assert message. |
| 3.2 | NetBox config-context for a fresh site renders with empty DNS/syslog/SNMP arrays. Cisco template renders without `ip name-server` lines. |
| 3.3 | Move USB volume to a non-default path, override `openbao_usb_dir`, init OpenBao on a fresh env — share write succeeds at the overridden path. |
| 3.4 | `bin/run-playbook.sh <env> playbooks/219-host-verify.yml` succeeds with `verify_ssh_key` set in inventory. Unset the inventory var → fails with mandatory-variable error. |
| 3.5 | NetBox cluster/site/manufacturer for each existing env are byte-identical before/after. Run without `dmf_inventory_env_name` → fails fast. |
| 4 | Visual diff of the comment edits. No runtime change. |

## Acceptance

The cleanup is complete when:

- `bin/scrub-public-repos.sh` passes on the umbrella + every public repo
  (no IDENTITY, TOPOLOGY, or SECRET hits in `dmf-infra` or `dmf-runbooks`).
- `gitleaks` pre-commit hook stays silent on each PR.
- A second-pass `rg` for residual private-CIDR or node-hostname-to-IP map
  patterns in `dmf-infra/k3s-lab-bootstrap/{playbooks,roles}` and
  `dmf-runbooks/{playbooks,roles}` returns no live-code hits (only
  provider-example comments or historical docs).
- `media-launch-nmos-cpp` AWX JT and the full `site.yml` bootstrap both
  succeed against a live env after all 4 waves merge.

## Open decisions to file separately

These surfaced during planning and are out of scope for this cleanup:

1. **Canonical public DMF project DNS namespace** for annotation/label
   prefixes (replaces the `dmfdeploy.local` placeholder from Wave 1.1).
   File into `docs/agentic/decisions-open.md`.
2. **Whether to require `openbao_usb_dir` explicitly** rather than
   defaulting to the current macOS USB volume mount path. Defer until a
   second env uses a different mount path.
3. **Provider-notes doc structure** — option (b) from Wave 4. Defer until
   a third provider's notes appear.
