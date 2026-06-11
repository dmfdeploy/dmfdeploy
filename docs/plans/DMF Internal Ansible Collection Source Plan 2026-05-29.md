---
status: draft
date: 2026-05-29
---
# DMF Internal Ansible Collection Source Plan (2026-05-29)

**Status:** PLAN — not yet implemented. Opened as the permanent follow-up to the
v0.1 EE-bake unblock (FIX 2 on `imc1-cyh4`).
**ADR:** [ADR-0034](../decisions/0034-internal-ansible-collection-source.md) — no public
Ansible Galaxy at runtime; internal collection source.
**Touches:** [ADR-0030](../decisions/0030-console-i18n-and-airgap-posture.md),
[ADR-0031](../decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md),
[ADR-0025](../decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md).

## 1. Problem

`project_update` in AWX runs `ansible-galaxy collection install -r
collections/requirements.yml`, which by default reaches
`https://galaxy.ansible.com`. On `imc1-cyh4` this timed out and cascaded
into a failed Console catalog deploy (job 29 → inventory sync 31 →
project update 32). Public Galaxy egress violates the ADR-0030 air-gap
posture and the ADR-0031 self-contained sandbox release gate.

## 2. Interim state (v0.1 unblock — already dispatched)

- `netbox.netbox` + all required collections baked into the `dmf/awx-ee` image.
- AWX **Organization Galaxy Credentials** set to internal/none so
  `project_update` cannot reach public Galaxy.
- `collections/requirements.yml` kept declarative + version-pinned.

This closes the gate but leaves the EE as the implicit source of truth.

## 3. Target (permanent)

Pick the internal collection source and wire it end to end:

### 3.1 Source mechanism — Forgejo-git (LOCKED 2026-05-29, ADR-0034)
Git-mirror each required collection into internal Forgejo (under e.g.
`mirrors/<collection>`), and reference them as git sources in
`requirements.yml`:
```yaml
collections:
  - name: https://forgejo.<domain>/mirrors/netbox.netbox.git
    type: git
    version: v3.23.0   # pin by tag or sha
```
`ansible-galaxy`'s git-source install contacts no galaxy server, works on
every ansible version, and `project_update` clones straight from internal
Forgejo. **Zot-OCI deferred** until `ansible-galaxy` OCI support is
first-class (see ADR-0034 §Decision).

### 3.2 Wiring
- AWX Organization Galaxy Credential → the chosen internal source.
- EE `ansible.cfg` / `ANSIBLE_GALAXY_SERVER_LIST` → internal source, with
  public Galaxy removed so a stray `requirements.yml` cannot reach out.
- `requirements.yml` declarative + digest/version pinned, resolving internally.
- Reconsider `scm_update_on_launch`: sync deliberately, not on every launch.

## 4. Acceptance

1. With egress to `galaxy.ansible.com` **blocked** at the node, a fresh
   `project_update` + the full Console catalog loop (deploy → health →
   lifecycle → teardown) succeed.
2. A new collection (or version bump) flows through the internal source +
   EE rebuild with no public Galaxy contact.
3. Release-gate check asserts no DMF runtime resolves collections from a
   public Galaxy endpoint (feeds the WP5 sandbox row).

## 5. Open items

- Confirm `ansible-galaxy` OCI maturity in the pinned ansible version
  (decides Zot-OCI vs Forgejo-git).
- Inventory the full collection set across all DMF projects/EEs (not just
  `netbox.netbox`).
- Decide whether the internal mirror is seeded at bootstrap (platform
  invariant) or maintained out-of-band.

## 6. Related

- `[[reference_sandbox_standalone_playbook_profile_gap]]`
- ADR-0034; the `imc1-cyh4` FIX 2 EE-bake unblock (interim).
