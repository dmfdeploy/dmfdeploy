---
status: executed
date: 2026-05-19
---
# Init Wizard — disambiguate env_id, provider, architecture, label

## Context

The init wizard (`dmf-env/bin/init-wizard.sh`) currently asks the operator
for a single freeform string — `env_name` — that has accreted three
unrelated jobs:

1. **Identifier** for everything path-shaped: bundle filename, inventory
   directory, terraform root, OpenBao break-glass dir, B2 bucket suffix,
   keychain service, NetBox cluster name.
2. **Provider hint** baked into the string (`hetzner-arm`, `aliyun-123`).
3. **Architecture hint** baked into the string (`-arm`).

Today's two example envs prove the problem: `hetzner-arm` mixes provider
and arch into the path; `aliyun-123` mixes provider and an instance serial.
Provider is *also* prompted separately (`init-wizard.sh:526`) but only ends
up in tfvars filenames and a manifest prose `description` — it is not a
structured field on the manifest, in NetBox, or in inventory vars.
Architecture is never prompted at all; the wizard hardcodes `cpu_kind=arm64`
for both providers (`init-wizard.sh:335,338`).

Base URL is already cleanly separated from `env_name` via a distinct
`BASE_DOMAIN` prompt (`init-wizard.sh:534`) — no change needed there;
this plan confirms and preserves that separation.

The change: split the single string into four orthogonal concerns, make
the **identifier** auto-generated and opaque, and surface
provider/architecture/label as first-class fields wherever an operator
might want to filter, group, or report (NetBox, manifest, inventory vars).

## Schema (the four concerns)

| Field | Shape | Generated? | Used as path? | Visible in NetBox? |
|---|---|---|---|---|
| `env_id` | `[a-z0-9]{4}-[a-z0-9]{4}` (e.g. `nb1k-7q3m`) | wizard auto-generates | **yes — the only path identifier** | yes (cluster name + custom field) |
| `env_label` | free text, optional (e.g. `production-lab`) | operator-supplied, may be empty | no — never in a path | yes (site display name + custom field) |
| `provider` | enum `hetzner` \| `aliyun` (NetBox enum also allows `aws`) | operator-selected | no | yes (custom field, plus device manufacturer) |
| `architecture` | enum `arm64` \| `amd64` | operator-selected | no | yes (custom field) |

Existing envs (`hetzner-arm`, `aliyun-123`) are out of scope per the
scope answer — they continue using `env_name` as their id with no
structured provider/arch fields. New envs use the new schema. Born-inventory
defaults must therefore fall back gracefully when the new fields are absent.

## Where each identifier appears — and where it must NOT

### `env_id` (opaque slug — the path identifier)

Keep using a slug at all these sites — only rename the variable from
`env_name` to `env_id`:

- `dmf-env/inventories/<env_id>/` — wrapper paths (`init-wizard.sh:399,476,594`)
- `${DMF_BOOTSTRAP_BUNDLE_DIR}/<env_id>.sops.yaml` — encrypted bundle (`init-wizard.sh:279,514`)
- `${DMF_BOOTSTRAP_BUNDLE_DIR}/<env_id>/{hetzner,aliyun,object-storage}.tfvars` (`init-wizard.sh:293,307`)
- `dmf-env/terraform/<env_id>/` — terraform root module (`init-wizard.sh:625`)
- `dmf-env/manifests/<env_id>.yaml` — resource profile (`init-wizard.sh:332,523`)
- `${OPENBAO_BREAKGLASS_DIR}/<env_id>/openbao-keys-automation` (`init-wizard.sh:485`)
- `openbao-breakglass-share-3-<env_id>` — keychain service (`init-wizard.sh:488`)
- `${OPENBAO_USB_BASE}/<env_id>` (`init-wizard.sh:491`)
- `dmf-{audit,openbao-snapshots,app-backups}-<env_id>` — B2 buckets (`init-wizard.sh:382,386,390`)
- `.sops.yaml` recipient `path_regex: '.*/<env_id>\.sops\.yaml$'` (`init-wizard.sh:166-176`)
- NetBox **cluster name** stays the slug (`born-inventory/defaults/main.yml:9`)

### `env_id` must NOT appear in

- Manifest `description` prose (currently `init-wizard.sh:354`).
- NetBox **site name** (currently `"DMF {{ env_name }}"` at `born-inventory/defaults/main.yml:5`).
- Any user-visible label where `env_label` is the better choice.

### `env_label` (human-readable, optional)

Surfaces in display-only contexts, never in paths:

- Manifest `metadata.label:` field (new), used in `description` prose if non-empty.
- NetBox `dcim/sites` `display` / `name` becomes `"DMF <env_label>"` when set,
  falling back to `"DMF <env_id>"` when empty (`born-inventory/defaults/main.yml:5`).
- Site `description` field in NetBox.
- Wizard summary echo (`init-wizard.sh:582-596`).
- Inventory vars `group_vars/all/main.yml` (informational comment header only).

### `provider` (enum)

- Wizard prompt — already exists (`init-wizard.sh:526`); extend choices to
  `hetzner|aliyun|aws`. AWS keeps a stub tfvars-render path (no Terraform
  module yet) and the wizard explicitly notes the module is TBD in the
  next-steps echo — this keeps NetBox enum forward-compatible.
- Manifest `spec.provider:` (new, structured field — not just prose).
- Bundle metadata `provider:` (already there at `init-wizard.sh:200`).
- Inventory `group_vars/all/main.yml` — new `dmf_provider:` var, picked up
  by `topology.provider` for born-inventory.
- NetBox **Site custom field** `dmf_provider` (selection: hetzner|aliyun|aws).
- NetBox **manufacturer name** derived from provider (replaces hardcoded
  `"Hetzner"` at `born-inventory/defaults/main.yml:12`).

### `architecture` (enum)

- Wizard prompt — new, choices `arm64|amd64`. Replaces the hardcoded
  `cpu_kind` block at `init-wizard.sh:335-339`.
- Manifest `spec.resource_profile.per_host.cpu.kind:` (already exists,
  just stop hardcoding it; also promote to top-level
  `spec.architecture:` for easy filtering).
- Bundle metadata `architecture:` (new, alongside `provider`).
- Inventory `dmf_architecture:` var.
- NetBox **Site custom field** `dmf_architecture` (selection: arm64|amd64).
- Drives `private_iface` selection (currently provider-only at
  `init-wizard.sh:404`); revisit only if any provider has multiple SKUs
  with different NIC names — out of scope for this change.

### `base_domain` — confirmation only, no change

Already cleanly separated. Used in `external_base_url`, ingress hosts,
cert-manager domain, etc. (`init-wizard.sh:378,420-431`). No conflation
with env_id today; preserve.

## Files to modify

### `dmf-env/bin/init-wizard.sh` (primary surface)

- Add `gen_env_id()` helper near `gen_password`/`gen_token` (around line 100s).
  Use `LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 8` formatted as
  `${4}-${4}`. Collision check: refuse if
  `${DMF_BOOTSTRAP_BUNDLE_DIR}/<id>.sops.yaml` or
  `dmf-env/inventories/<id>/` exists — regenerate up to N=10 times.
- Replace operator `env_name` prompt at line 512 with:
  - auto-generate `env_id` and echo it ("Generated env id: nb1k-7q3m");
  - `prompt_default "Optional human label" ""` → `env_label`.
- Move `PROVIDER` prompt above the env_id echo for narrative flow; extend
  choices to `hetzner|aliyun|aws` (`init-wizard.sh:526`). For `aws`,
  set credential prompts to no-op stubs and add a TBD note.
- Add `prompt_choice "Architecture" arm64 amd64` → `ARCH`.
- Rewrite `render_manifest()` (`init-wizard.sh:330-395`) to emit:
  ```yaml
  metadata:
    name: ${env_id}
    label: ${env_label}        # may be empty
    provider: ${PROVIDER}
    architecture: ${ARCH}
    description: ${provider_human} ${ARCH} 3-node k3s cluster${label_suffix}
  spec:
    provider: ${PROVIDER}
    architecture: ${ARCH}
    resource_profile: ...
  ```
  Drop the `cpu_kind` hardcoding at lines 335,338; use `$ARCH`.
- `render_bundle()` (`init-wizard.sh:200`-ish): add `architecture:` and
  `label:` next to existing `provider:`/`base_domain:`.
- `render_inventory_main()` (`init-wizard.sh:397`): emit new vars at top:
  ```yaml
  dmf_env_id: <env_id>
  dmf_env_label: "<env_label>"
  dmf_provider: <provider>
  dmf_architecture: <architecture>
  ```
- Add `render_terraform_root()` — new function that templates
  `dmf-env/terraform/<env_id>/main.tf` from a per-(provider, arch) skeleton.
  Replaces the "operator must copy hetzner-arm or aliyun-123" prose at
  `init-wizard.sh:621-625`. Source templates live at
  `dmf-env/terraform/_templates/<provider>-<arch>/main.tf`. Out-of-table
  combinations error cleanly with a TBD message (e.g. aws-amd64 until that
  module exists).
- Rename every internal `env_name` to `env_id` for clarity (~30 occurrences).
  Search/replace within `init-wizard.sh` only.
- Summary block (`init-wizard.sh:582-596`) — print all four fields and
  call out which become paths.

### `dmf-infra/k3s-lab-bootstrap/roles/common/dmf-born-inventory/defaults/main.yml`

- Add the new vars (with legacy fallback so existing envs keep working):
  ```yaml
  dmf_born_inventory_env_id:        "{{ topology.env_id        | default(dmf_born_inventory_env_name) }}"
  dmf_born_inventory_env_label:     "{{ topology.env_label     | default('') }}"
  dmf_born_inventory_provider:      "{{ topology.provider      | default('') }}"
  dmf_born_inventory_architecture:  "{{ topology.architecture  | default('') }}"
  ```
- Rewrite `dmf_born_inventory_site_name` (`defaults/main.yml:5`):
  ```yaml
  dmf_born_inventory_site_name: >-
    DMF {{ dmf_born_inventory_env_label | default(dmf_born_inventory_env_id, true) }}
  ```
- `dmf_born_inventory_cluster_name` (`defaults/main.yml:9`) → use `env_id`
  (this is the structural identifier).
- Derive `dmf_born_inventory_manufacturer_name` from provider:
  ```yaml
  dmf_born_inventory_manufacturer_name: >-
    {{ {'hetzner':'Hetzner','aliyun':'Aliyun','aws':'AWS'}[dmf_born_inventory_provider]
       | default('Hetzner') }}
  ```
  (default keeps legacy `hetzner-arm`/`aliyun-123` working; they currently
  produce `"Hetzner"` regardless of provider — log a follow-up to fix that
  manually for `aliyun-123` outside this PR.)

### `dmf-infra/k3s-lab-bootstrap/roles/common/dmf-born-inventory/tasks/main.yml` (+ site task)

- Add a step that ensures NetBox custom field schemas exist for sites:
  - `dmf_env_id` (text)
  - `dmf_env_label` (text)
  - `dmf_provider` (selection: hetzner|aliyun|aws)
  - `dmf_architecture` (selection: arm64|amd64)
  Idempotent: lookup `/api/extras/custom-fields/?name=dmf_*`, POST when
  missing, PATCH when shape drifts.
- After the existing site upsert, PATCH `/api/dcim/sites/<id>/` with
  `custom_fields: {dmf_env_id, dmf_env_label, dmf_provider, dmf_architecture}`
  — skip the patch when the source var is empty (legacy envs).
- Same treatment for `Cluster` (custom fields on
  `virtualization.cluster`) so the four fields are queryable from either side.

### `dmf-env/inventories/example/group_vars/all/main.yml` (template)

- Add `dmf_env_id`, `dmf_env_label`, `dmf_provider`, `dmf_architecture`
  to the example so new operators see the schema even without running
  the wizard.

### New: `dmf-env/terraform/_templates/<provider>-<arch>/main.tf`

- Initial templates: `hetzner-arm64/`, `aliyun-arm64/` (mirror what
  `terraform/hetzner-arm/` and `terraform/aliyun-123/` look like today but
  parameterized on `env_id`). `aws-*` and `hetzner-amd64` deferred; the
  wizard errors with a TBD message if those combos are requested.

## What is intentionally NOT changing

- `BASE_DOMAIN` / ingress / cert-manager — already clean.
- OpenBao secret paths (`secret/apps/netbox/runtime`, etc.) — env-agnostic
  collision risk is real but out of scope; flag as a follow-up if multiple
  envs ever share one OpenBao instance.
- Existing `hetzner-arm` and `aliyun-123` directories, bundles, manifests,
  and NetBox records. Schema upgrade for legacy envs is a separate plan.
- Kubernetes namespaces (already fixed, not env-scoped).

## Verification

1. **Dry-run wizard locally** — comment out the `confirm` block, run
   `dmf-env/bin/init-wizard.sh`, supply test inputs, and inspect
   generated artifacts under a scratch `DMF_BOOTSTRAP_BUNDLE_DIR`:
   - `<scratch>/<env_id>.sops.yaml` decrypts cleanly via `sops -d`.
   - `manifests/<env_id>.yaml` has structured `provider`,
     `architecture`, optional `label`; `metadata.name == env_id`.
   - `inventories/<env_id>/group_vars/all/main.yml` has the four new vars.
   - `terraform/<env_id>/main.tf` is rendered (not a manual-copy stub).
2. **Born-inventory regression on hetzner-arm** — re-run
   `playbooks/694-born-inventory.yml` on the live cluster. Site name
   must still be `"DMF hetzner-arm"` (legacy fallback), cluster name
   `hetzner-arm`, no custom-field patches attempted because the source
   vars are empty. Confirm via NetBox API: `GET /api/dcim/sites/?name=DMF%20hetzner-arm`.
3. **New-env NetBox shape (paper test, no real cloud)** — point
   born-inventory at a stub topology with `env_id=nb1k-7q3m`,
   `env_label="production-lab"`, `provider=hetzner`,
   `architecture=arm64`. Site name = `"DMF production-lab"`,
   cluster name = `nb1k-7q3m`, custom fields populated.
4. **Schema doc** — extend
   `dmf-env/inventories/example/group_vars/all/main.yml` and add a
   short paragraph to `docs/architecture/DMF Platform Plan.md`
   (§8c multi-env) describing the four-field schema.
5. **Lint** — `shellcheck dmf-env/bin/init-wizard.sh`,
   `ansible-lint dmf-infra/k3s-lab-bootstrap/roles/common/dmf-born-inventory/`.

## Follow-ups (logged separately, not in this change)

- Migrate `hetzner-arm` and `aliyun-123` to the new schema (rename or
  alias; patch NetBox custom fields retroactively).
- AWS terraform module + provider credential prompts.
- Per-env OpenBao secret path namespacing (multi-env-in-one-instance).
- Aliyun manufacturer in legacy NetBox record (currently misreports as
  Hetzner via the hardcoded default).

## Implementation note (2026-05-19, after Codex review)

The plan above describes the full target shape. Two items in the
"Files to modify" section were intentionally **deferred** in the
shipped change, both based on operator direction during review:

### Deferred: `render_terraform_root` + `terraform/_templates/<provider>-<arch>/`

The shipped wizard still emits next-steps prose pointing the operator
at an existing terraform root (`hetzner-arm`, `aliyun-123`) to copy as
a starting template. Rationale for the defer:

- `terraform/hetzner-arm/` and `terraform/aliyun-123/` contain
  `.terraform/` (provider cache), `.terraform.lock.hcl`, and
  `terraform.tfstate.*.backup` files. A copy-template renderer would
  propagate state cruft unless it carefully allow-lists `main.tf`,
  `outputs.tf`, `versions.tf` and rewrites the env-name placeholders.
- `terraform/aliyun-123/main.tf` carries provider-specific blocks
  currently under active development (RAM/STS module wiring,
  `tofu_outputs.yml` codegen). A frozen `_templates/` tree would
  diverge from the source root quickly.
- The wizard's collision check in `gen_env_id` already prevents
  writing into an existing `terraform/<id>/` dir, so the operator's
  manual `cp -r` step is safe.

Reopen this when the aliyun cluster lifecycle stabilises and the
template set is bounded to a small allow-list (main.tf + outputs.tf
+ versions.tf with `__ENV_ID__` placeholders).

### Partial: NetBox custom-field drift reconciliation

Choice sets and `select`-typed `dmf_provider` / `dmf_architecture`
fields **are** shipped (yesterday's text-typed version was the
first-day deviation that this follow-up corrected). What is **not**
shipped is PATCH-on-drift: if an existing NetBox install already has
`dmf_provider` as type `text` (from a Day-1 of this schema), the role
emits a warning and leaves the field as-is rather than mutating its
shape. Reason: NetBox 4 custom-field type changes can require
backing-data migration and PATCHing live state from a bootstrap role
is a sharp edge we'd rather not auto-fire.

The operator's manual remediation when a drift warning appears:
delete the existing custom field via the NetBox UI; the next role
run will recreate it with the correct shape (no site/cluster data
is lost — the custom-field values are PATCHed back on the same run).

### Honoured

All other items in "Files to modify" are implemented as specified:
wizard prompt restructure, manifest + bundle + inventory structured
fields, born-inventory defaults with legacy fallback (extended via
`dmf_inventory_env_name` from `run-playbook.sh` after the Codex
review), idempotent custom-field creation, site + cluster PATCH,
provider-aware bootstrap-secrets, architecture doc §8c.1 update.
