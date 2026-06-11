# Identity and authority — Canonical Digest

**Scope:** How human identities, machine identities, custody, and audit attribution are governed across the DMF Platform.
**Canonical ADR(s):** [ADR-0028](../0028-identity-and-authority-chain.md)
**Last refreshed:** 2026-06-09

> This digest states the **current consolidated truth** for this topic so a reader
> does not have to reverse-engineer it from multiple partially-superseding ADRs.
> The numbered ADRs remain authoritative source; this digest points at them.

## Current truth

- Authentik is the sole human identity authority in steady state. *"Authentik is the sole human identity authority in steady state."* (ADR-0028 C1)
- OpenBao is the custody layer for steady-state secrets; physical recovery kits are disaster custody. *"OpenBao is the custody layer for steady-state secrets; physical recovery kits are disaster custody."* (ADR-0028 C2)
- Native service accounts are allowed only for machine-to-machine work and must be scoped, named, documented, and stored in OpenBao. Token ownership binds to the authenticating principal, not to a description field. *"A machine token must be minted while authenticated as the scoped service identity. Token/credential ownership binds to the authenticating principal."* (ADR-0028 C3.1)
- No routine operation may require use of a break-glass account. *"No routine operation may require use of a break-glass account."* (ADR-0028 C4)
- Every DMF-initiated automated action must carry actor, role, request id, and reason metadata. *"Every DMF-initiated automated action must carry actor, role, request id, and reason metadata, even when the downstream app executes under a service account."* (ADR-0028 C5)
- Three sanctioned exceptions to "no local accounts except break-glass" exist: Authentik `akadmin`, Zot `admin` (htpasswd format), Grafana `admin` (Helm chart default). The AWX shadow superuser is explicitly not a sanctioned exception. (ADR-0028 §Sanctioned exceptions)
- Attribution strength for the experiment phase is strong dmf-cms attestation: the immutable request log inside dmf-cms is the source of truth; actor/role/request_id/reason propagate to AWX `extra_vars`, NetBox change-request custom fields, Forgejo commit footer metadata, OpenBao audit context tags, and Kubernetes audit annotations. Cryptographic binding is deferred. (ADR-0028 "Attribution strength for experiment phase")
- Bootstrap convergence audit gate (D2): a bootstrap run is not complete until temporary bootstrap authority has been sealed, rotated, or explicitly recorded as retained. (ADR-0028 D2)
- DMF Console uses passkey-only authentication via the `dmf-passkey-login` flow. *"The DMF Console OIDC provider uses the dedicated dmf-passkey-login flow as its authentication_flow."* (ADR-0015 Decision). This was extended to brand-wide passkey-first (ADR-0015 Amendment 2026-05-29).
- OpenBao AppRole reconciliation uses a dedicated `approle-reconciler` bootstrap identity for `object-storage-*` AppRoles, preserving separation of duties between ACL policy reconciliation, AppRole reconciliation, and app-secret administration. (ADR-0021 Decision)
- Catalog launchers mutate NetBox via a scoped writer service account (`dmf-catalog-svc`), never the admin token. (ADR-0032 Decision, refining ADR-0028 C3)

## History / context behind it

| ADR | Role today | Superseded / amended by |
|---|---|---|
| 0015 | DMF Console passkey-only, extended to brand-wide passkey-first | — |
| 0021 | AppRole reconciliation uses dedicated bootstrap identity | — |
| 0024 | Two-identity admin model + sanctioned exceptions | **Largely superseded by ADR-0028**; §3 sanctioned exceptions preserved and re-confirmed |
| 0028 | Identity & Authority Chain — canonical, binding architecture | — |
| 0032 | Catalog launchers use scoped NetBox writer | — |

## Open items in this cluster

- None. All ADRs in this cluster are Accepted. The multi-user model remains explicitly deferred (ADR-0028 Consequences).
