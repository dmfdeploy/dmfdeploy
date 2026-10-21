# ADR-0011 archive: Auto-unseal trades Shamir defense-in-depth for operational tolerability

This file holds material moved out of [ADR-0011](../../decisions/0011-auto-unseal-tradeoff.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **A. HA bao with raft.** Run 3 bao replicas. Manual unseal needed only at
  first cluster boot or full simultaneous cluster restart; replicas
  auto-unseal from peers via the raft protocol. Materially better security
  (no automation file at all). Costs: ~half-day to set up, few hundred MB
  extra memory per replica, raft init/peer-discovery learning curve. Deferred
  per ADR-0004 — it's hardening, not thesis-killer work.
- **B. Initial-unseal-only on single-replica bao.** No automation file;
  every pod restart blocks until a human unseals. Operationally brutal for
  a lab cluster with frequent restarts; would force the operator into the
  loop multiple times per week. Rejected.
- **C. Cloud-KMS auto-unseal.** Bao supports AWS/GCP KMS for sealing the
  master. Trades local-only trust for cloud-vendor trust. Philosophical
  mismatch with a local-first lab; reconsider only if the deployment
  topology shifts to cloud-first.
- **D. macOS Keychain-resident automation file.** Move the automation JSON
  contents into a Keychain entry (or FileVault-protected sub-volume) that
  requires login session unlock. Narrows the attack window but does not
  fundamentally change the threat model — anything readable while the Mac
  is "logged in and operating" is still readable by malicious processes
  running as the user. Marginal gain, real complexity. Not recommended.

## Related

- **ADR-0029** — Tiered Unseal Posture; reframes this tradeoff as Tier 3
- **ADR-0031** — OSS v0.1 release matrix; AWS-KMS unseal = Tier 3 sub-variant 3a
- **ADR-0009** — 5-share Shamir, 3-of-5 threshold, distributed across 5 locations
- **ADR-0004** — Experiment phase, not hardening (defers HA bao migration)
- **ADR-0007** — Secrets never in argv (the discipline that makes the
  automation file's exposure surface as small as possible *given* the design)
- **ADR-0008** — OpenBao + ESO + AppRole shim secrets architecture
- `dmf-openbao-unseal` skill — the operator-facing manual breakglass path
  (which the Shamir model fully protects)
