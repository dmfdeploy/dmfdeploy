# ADR-0008: OpenBao + ESO + AppRole shim as secrets architecture

**Status:** Accepted
**Date:** 2026-04-22 (formalized in `DMF Secret Ownership and OpenBao Migration Plan.md`)
**Deciders:** @<handle>

## Context

The platform needs a secrets backend that handles three classes of secret with
different lifetimes and access patterns:

1. **Bootstrap-time secrets** — provider tokens (Hetzner, Cloudflare, Tailscale),
   k3s join token, initial admin passwords. Needed before the cluster exists.
2. **Runtime secrets** — app admin passwords, API tokens, OIDC client secrets.
   Needed inside the cluster, by Pods.
3. **Break-glass material** — OpenBao Shamir shares, ops_admin userpass.
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
- 5-share Shamir keys distributed across JuiceFS / macOS Keychain / USB
  (see ADR-0009)
- ops_admin userpass in the automation file at
  `<secure-store>/openbao-breakglass/hetzner-lab/openbao-keys-automation.json`

**No `community.hashi_vault` runtime dependency in Ansible.** The wrapper
exports vars before `ansible-playbook` starts; tasks reference `vault_*`
variables rather than calling out to OpenBao mid-run. This keeps the runtime
secret-resolution path small and testable.

## Consequences

- **Positive:** clear secret-tier classification. Each tier has a different
  storage location, leak-blast-radius, and recovery procedure.
- **Positive:** ESO is industry-standard; pods don't see OpenBao directly,
  only k8s Secrets that ESO syncs.
- **Positive:** operator side stays simple — one wrapper script per task type
  (`run-playbook.sh`, `tf-apply.sh`).
- **Negative:** three distinct flows for secret retrieval (ESO at runtime,
  wrapper-shim at provision, break-glass file for emergencies). Operators
  must know which is right for which task.
- **Negative:** the AppRole bootstrap is a chicken-and-egg — the very first
  cluster bring-up needs a seeded ops_admin to write the AppRole; resolved
  by initial OpenBao init writing both Shamir shares and ops_admin to the
  break-glass automation file.

## Alternatives considered

- **HashiCorp Vault directly.** OpenBao is the OSS fork; functionally
  equivalent for our needs and not gated on enterprise-edition features.
- **k8s Secrets only (no external store).** Loses the audit trail, the
  human-and-pod unified policy model, and break-glass-vs-runtime
  separation.
- **`community.hashi_vault` lookup at task time.** Runtime API dependency,
  more complex error paths during playbooks, and harder to test offline.
  Wrapper-shim approach is simpler.

## Enforcement

`DMF Secret Ownership and OpenBao Migration Plan.md` (`docs/plans/`) is the
canonical mapping. Each secret has a documented tier. The wrapper
(`bin/run-playbook.sh`) and the openbao role tasks/main.yml are the reference
implementations. `dmf-cluster-access` skill §5.1 covers operator-side reads;
`dmf-openbao-unseal` skill covers the break-glass path.
