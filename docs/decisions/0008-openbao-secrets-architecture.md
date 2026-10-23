# ADR-0008: OpenBao + ESO + AppRole shim as secrets architecture

**Status:** Accepted
**Date:** 2026-04-22 (formalized in `DMF Secret Ownership and OpenBao Migration Plan.md`)
**Deciders:** @<handle>
**Rule:** Cluster-runtime secrets live in OpenBao and reach pods via External Secrets Operator (AppRole auth); operator scripts inject bootstrap secrets via a temp vars file; break-glass material (Shamir shares, ops_admin) stays outside the runtime path.

## Context

The platform needs a secrets backend that handles three classes of secret with
different lifetimes and access patterns:

1. **Bootstrap-time secrets**: provider tokens (Hetzner, Cloudflare, Tailscale),
   k3s join token, initial admin passwords. Needed before the cluster exists.
2. **Runtime secrets**: app admin passwords, API tokens, OIDC client secrets.
   Needed inside the cluster, by Pods.
3. **Break-glass material**: OpenBao Shamir shares, ops_admin userpass.
   Needed only when normal flows fail.

Each class has different leakage tolerance and recovery semantics.

## Decision

**Cluster-runtime secrets** live in OpenBao at `https://openbao.dmf.example.com`.
Pods consume them via External Secrets Operator (ESO), which authenticates to
OpenBao via an AppRole role+secret pair stored in OpenBao itself (bootstrapped
once, then self-perpetuating).

**Operator-side scripts** (`dmf-env/bin/*.sh`) read provider tokens from
local files (`~/.config/hcloud/cli.toml`, `~/.config/cf/dns.txt`,
`~/.config/ts/authkey.txt`) and generate ephemeral seed secrets at first
bootstrap (k3s_token, app admin passwords). The wrapper writes a temp vars
file and injects it into Ansible via `-e @file`, then cleans up.

**Break-glass material** lives **outside** the runtime path:
- 5-share Shamir keys distributed across separate stores held by the
  maintainer (see ADR-0009)
- ops_admin userpass in the automation file at
  `<secure-store>/openbao-breakglass/<env>/openbao-keys-automation.json`

**No `community.hashi_vault` runtime dependency in Ansible.** The wrapper
exports vars before `ansible-playbook` starts; tasks reference `vault_*`
variables rather than calling out to OpenBao mid-run. This keeps the runtime
secret-resolution path small and testable.

## Consequences

- **Positive:** clear secret-tier classification. Each tier has a different
  storage location, leak-blast-radius, and recovery procedure.
- **Positive:** ESO is industry-standard; pods don't see OpenBao directly,
  only k8s Secrets that ESO syncs.
- **Positive:** operator side stays simple, with one wrapper script per task type
  (`run-playbook.sh`, `tf-apply.sh`).
- **Negative:** three distinct flows for secret retrieval (ESO at runtime,
  wrapper-shim at provision, break-glass file for emergencies). Operators
  must know which is right for which task.
- **Negative:** the AppRole bootstrap is a chicken-and-egg. The very first
  cluster bring-up needs a seeded ops_admin to write the AppRole. Initial OpenBao init resolves this by writing
  both Shamir shares and ops_admin to the break-glass automation file.

### Enforcement

`dmf-infra/k3s-lab-bootstrap/playbooks/verify-openbao-identity-model.yml` asserts the OpenBao identity model
and that the ESO chain reconciles. Nothing mechanical checks the secret tiers or the ban on a
`community.hashi_vault` runtime dependency; those rest on discipline. `DMF Secret Ownership and OpenBao Migration Plan.md`
(`docs/plans/`) is the canonical mapping, and each secret has a documented tier. The wrapper (`dmf-env/bin/run-playbook.sh`)
and `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/tasks/main.yml` are the reference implementations.
`dmf-cluster-access` skill §5.1 covers operator-side reads; `dmf-openbao-unseal` skill covers the break-glass path.

## Status

Accepted

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0008-openbao-secrets-architecture.md).
