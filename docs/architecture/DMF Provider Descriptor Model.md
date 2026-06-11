# DMF Provider Descriptor Model

**Status:** Architecture reference for
[ADR-0026 (Provider Descriptors)](../decisions/0026-provider-descriptors.md).
**Date:** 2026-05-20
**Repos in scope:** `dmf-infra` (descriptor source), `dmf-env`
(rendered per-env `group_vars/all/*.yml`), `wizard-spike` (Python consumer,
later `dmf-wizard`), `dmf-cms` (future add-a-provider UI).

This document is the canonical reference for the Provider Descriptor schema.
Read [ADR-0026](../decisions/0026-provider-descriptors.md) for the *decision*;
this doc spells out the *shape*. Schema mutations land here as amendments,
not in the ADR.

---

## 1. Concept

A **Provider Descriptor** declares everything about one bootstrap-time
integration in one declarative file: the operator inputs to collect, the
secrets to ferry (by logical reference only), where those values land in
the SOPS bundle and OpenBao, what `vault_*` Ansible export var the wrapper
will produce, what `group_vars/all/<provider>.yml` file gets rendered into
the per-env inventory, and which Ansible roles assert on the bound vars.

Provider Descriptors are **not** the same as catalog entries
(ADR-0013 / [Function Catalog Model](DMF%20Function%20Catalog%20Model.md)).
The function catalog describes operator-launchable workloads with a
launch / teardown lifecycle. A Provider Descriptor describes a bootstrap
integration that is collected once during init and remains static for the
env's life. Different shape, different lifecycle, different consumers.

The descriptor answers the operator-facing question: *"what does this
provider need from me, and where does that information have to land for
the cluster to come up clean?"*

---

## 2. Storage and consumers

| Concern | Location |
|---|---|
| **Descriptor source** (the class) | `dmf-infra/k3s-lab-bootstrap/providers/<id>.yaml` |
| **Operator-supplied input values** (the instance) | Operator's local config files or wizard prompts; **never** committed |
| **Secret instance values, pre-OpenBao** | SOPS bundle at `${DMF_BOOTSTRAP_BUNDLE_DIR}/<env_id>.sops.yaml`, keyed at `<bundle_path>` |
| **Secret instance values, post-OpenBao** | OpenBao at `<vault_path>` with field `<vault_field>` |
| **Rendered per-env `group_vars` file** | `dmf-env/inventories/<env_id>/group_vars/all/<group_vars_file.path>` |
| **Runtime injection** | `dmf-env/bin/bootstrap-secrets.sh export-vars` writes a temp vars file with `<export_var>`; `bin/run-playbook.sh` passes it via `-e @file` |

Consumers:

| Consumer | What it does with the descriptor |
|---|---|
| Bash wizard (`dmf-env/bin/init-wizard.sh`) | Reads descriptors, drives prompts, writes bundle keys, renders `group_vars` file |
| Python wizard (`wizard-spike/` → `dmf-wizard/`) | Same, via pydantic validation + Jinja templating; library-shaped for reuse |
| `bootstrap-secrets.sh export-vars` / `seed-bao` | Reads descriptors to know which bundle keys → which `vault_*` export vars and which OpenBao paths |
| Ansible roles | Stay role-shaped; assert on `inventory_var` names. No descriptor awareness needed. |
| dmf-cms (future) | Imports the Python wizard package, reads descriptors, renders dynamic forms, writes to OpenBao + opens GitOps PRs |

---

## 3. Descriptor schema (v1)

```yaml
---
schema_version: 1                    # int, required; bump on breaking changes

id: <slug>                           # required; [a-z0-9-]+
name: "<human label>"                # required
kind: <vpn|dns|vps|storage|tls|identity|registry|...>  # required; open vocabulary
applies_to_profiles:                 # required; non-empty subset of:
  - cloud                            #   cloud / flypack-offline / flypack-online
  - flypack-offline
  - flypack-online
optional: <true|false>               # required; if true, role MUST skip when inputs absent

inputs:                              # required; may be empty
  - name: <local_name>               # required; the wizard's logical key
    prompt: "<question text>"        # required for required=true inputs
    type: <string|url|int|bool|enum> # required
    enum_values: [...]               # required when type=enum
    required: <true|false>           # default false
    default: <literal or Jinja>      # optional
    advanced: <true|false>           # default false; advanced=true means "don't prompt by default"
    inventory_var: <ansible_var>     # required; the role-side input name

secrets:                             # required; may be empty
  - name: <local_name>               # required
    prompt: "<question text>"        # required
    bundle_path: <dotted.path>       # required; key in the SOPS bundle YAML
    vault_path: <kv-v2-path>         # required; e.g. secret/platform/tailscale
    vault_field: <field>             # required; e.g. authkey
    export_var: <vault_*_name>       # required; the var the wrapper injects
    inventory_var: <ansible_var>     # required; the role-side input name
    indirection: "{{ <export_var> | default('') }}"   # required; literal Jinja for the group_vars file

group_vars_file:                     # required
  path: "group_vars/all/<file>.yml"  # required; relative to inventories/<env_id>/
  template: |                        # required; Jinja2 body — see §3.3
    ---
    # Generated from providers/<id>.yaml (ADR-0026).
    # Do not edit by hand.
    ...

roles_consuming:                     # required; non-empty
  - <role_path>                      # e.g. dmf-infra/k3s-lab-bootstrap/roles/base/tailscale

secret_rotation:                     # optional
  owner: <operator|reconciler|none>
  cadence: <e.g. yearly|on-demand>
```

### 3.1 Validation rules (MUST)

The schema doc is normative. A descriptor that violates any of the
following is invalid:

1. **No secret literals.** No field anywhere in the descriptor may carry
   a literal secret value (authkey, token, password, AK/SK). Secrets are
   declared by `bundle_path` + `vault_path` only. This is the ADR-0007
   tripwire.
2. **Every `secrets[]` entry MUST carry both `bundle_path` and
   `vault_path`.** Pre-OpenBao bootstrap reads from the bundle;
   post-OpenBao runtime reads from vault. Both tiers must be addressable.
3. **`inventory_var` names MUST be globally unique** across all descriptors
   for an env. (Future: the loader enforces this by static scan.)
4. **`indirection` MUST reference `export_var`** as the only variable, with
   `default('')` (or `default(<safe-default>)`). This keeps role assertions
   honest — empty string fails the role's own `length > 0` check.
5. **`group_vars_file.path` MUST start with `group_vars/all/`.** Other
   group_vars groupings are out of scope for v1.
6. **`applies_to_profiles[]` MUST be non-empty** and a subset of the
   three known profiles. If a descriptor doesn't apply to a profile,
   the wizard skips it and the per-env file is not rendered.

### 3.3 Template rendering convention

The `group_vars_file.template` body is Jinja2, rendered by the
descriptor-loader with **strict undefined** mode and exactly two
namespaces in scope:

1. **Inputs as top-level variables.** Every `inputs[].name` is available
   as a Jinja variable carrying the operator-supplied value (or the
   `default` if supplied and not overridden).
2. **A `secrets` dict.** For each `secrets[].name`, the dotted accessor
   `secrets.<name>.indirection` evaluates to the **literal indirection
   string** declared on that secret (e.g. `{{ vault_tailscale_authkey |
   default('') }}`). The renderer does not re-evaluate the string —
   it's emitted verbatim into the output file, where Ansible's own
   Jinja evaluates it at playbook time.

This eliminates the two-pass-Jinja escaping problem: descriptor
authors never write `{% raw %}`/`{% endraw %}` blocks or nested
`{{ '{{ ... }}' }}` constructs. They write `{{ input_name }}` for
substituted values and `{{ secrets.<name>.indirection }}` for
secret bindings, full stop.

Anything outside those two namespaces (`{{ vault_x }}` written
directly) raises a render error. Use `secrets.<name>.indirection`.

### 3.4 Field reference

| Field | Type | Required | Notes |
|---|---|---|---|
| `schema_version` | int | yes | v1 today; bump on breaking changes |
| `id` | string | yes | `[a-z0-9-]+`; filename matches `<id>.yaml` |
| `name` | string | yes | Human-readable, shown by wizard prompts and dmf-cms UI |
| `kind` | string | yes | Open vocabulary; consumers may filter by kind |
| `applies_to_profiles[]` | list[string] | yes | Subset of `cloud` / `flypack-offline` / `flypack-online` |
| `optional` | bool | yes | If true, role MUST skip when inputs absent |
| `inputs[]` | list[Input] | yes (may be empty) | Operator-typed; mapped to `inventory_var` |
| `secrets[]` | list[Secret] | yes (may be empty) | Logical references; never literal values |
| `group_vars_file` | object | yes | `path` + `template` |
| `roles_consuming[]` | list[string] | yes | Repo-relative role paths |
| `secret_rotation` | object | no | `{ owner, cadence }`; audit clarity |

**Input fields:** `name`, `prompt`, `type`, `enum_values` (when type=enum),
`required`, `default`, `advanced`, `inventory_var`.

**Secret fields:** `name`, `prompt`, `bundle_path`, `vault_path`,
`vault_field`, `export_var`, `inventory_var`, `indirection`.

See §3.3 for how `template` resolves input and secret references.

---

## 4. Lifecycle (when each field is read)

```
operator runs wizard
  │
  ▼
[wizard reads dmf-infra/k3s-lab-bootstrap/providers/*.yaml]
  │
  ├─► filters by applies_to_profiles ∩ chosen profile
  │
  ├─► prompts inputs[] (skipping advanced=true by default)
  │   └─► values typed by operator → wizard memory
  │
  ├─► prompts secrets[] (always; advanced flag does not apply)
  │   └─► values typed by operator → SOPS bundle at <bundle_path>
  │
  ├─► renders group_vars_file.template with input values
  │   └─► writes dmf-env/inventories/<env_id>/group_vars/all/<path>
  │
  └─► (later) bootstrap-secrets.sh seed-bao
      └─► reads bundle, writes to OpenBao at <vault_path>:<vault_field>

later: operator runs run-playbook.sh
  │
  ├─► bootstrap-secrets.sh export-vars
  │   └─► reads bundle/vault, writes <export_var> to temp vars file
  │
  ├─► ansible-playbook -e @temp-vars-file
  │   └─► temp vars file defines <export_var>
  │
  └─► group_vars/all/<file>.yml binds inventory_var = indirection
      └─► role asserts on inventory_var, runs cleanly
```

---

## 5. Reference descriptor

The canonical example is the Tailscale descriptor at
`dmf-infra/k3s-lab-bootstrap/providers/tailscale.yaml`, which lands
alongside this document and satisfies Promotion Criterion 1 of
ADR-0026.

Additional descriptors planned (each separate PRs, each one a check that
the schema survives the next integration without mutation):

| Provider | Likely `kind` | Notes |
|---|---|---|
| Cloudflare DNS | `dns` | `cert-manager` consumer; zone + DNS-01 API token |
| Hetzner Cloud | `vps` | CCM + LB consumer; hcloud token + context + LB annotations |
| Aliyun ECS | `vps` | Likely first schema-mutation candidate (RAM/STS optional fields) |
| Backblaze B2 | `storage` | Three buckets (audit / openbao-snapshots / app-backups); may need a `multi_secret` shape — defer until v2 |
| Headscale (control) | `vpn` | Distinct from Tailscale (node) descriptor; may merge if shapes converge |

---

## 6. Consumer contracts

Each consumer reads the descriptor differently. The descriptor is the
contract; the implementation is per-consumer.

### 6.1 Bash wizard (`dmf-env/bin/init-wizard.sh`)

- Loads all descriptors at startup.
- For the chosen profile, iterates: prompt → bundle key → group_vars
  render.
- Hard-fails if any required input is missing or any `inventory_var`
  collides with another descriptor's.
- Reader is shared infrastructure — likely `dmf-env/bin/lib/provider-descriptors.{sh,py}` —
  not inlined.

### 6.2 Python wizard (`wizard-spike/` → `dmf-wizard/`)

- pydantic `ProviderDescriptor` model + registry loader in
  `src/dmf_wizard/providers.py`.
- Step 6 (lane-conditional prompts) consumes descriptors instead of
  hand-coded prompt lists.
- Step 7 (real bash-script step bindings) uses `roles_consuming[]` to
  decide which playbooks must run after a descriptor's group_vars file is
  rendered.
- Round-trip test required: load → dump → reload → field-equal.

### 6.3 dmf-cms (future, post-bootstrap)

- New FastAPI route returns the descriptor catalog as JSON.
- React renders dynamic forms from the schema. `inputs[].type` drives
  form field types; `advanced=true` collapses into an "Advanced" disclosure.
- Submit handler writes secret to OpenBao directly (cluster is up),
  opens a GitOps PR against `dmf-env` adding the env block + rendered
  group_vars file.

---

## 7. Amendments

| Date | Change | Reason |
|---|---|---|
| 2026-05-20 | Schema v1 initial publication. | Adopted with ADR-0026. |
