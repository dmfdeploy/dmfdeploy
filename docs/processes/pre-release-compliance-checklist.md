# Pre-Release Compliance Checklist

**Status:** Operator checklist — companion to [Pre-Release Compliance Readiness Plan](../plans/DMF%20Pre-Release%20Compliance%20Readiness%20Plan%202026-05-11.md) and [ADR-0020](../decisions/0020-deployment-scope-and-regulatory-posture.md)
**Last reviewed:** 2026-05-11

> This is the *runnable* version of the readiness plan. Each row has a binary state: done or not done.
> If an item needs nuance, the readiness plan §2–§4 is the source of truth — this file is for tracking.
> Use [`docs/decisions/INDEX.md`](../decisions/INDEX.md) and the framework plan for control rationale.

## Purpose

Provide a single, auditable list the operator can run down before each of the three named go-live events (per [ADR-0020](../decisions/0020-deployment-scope-and-regulatory-posture.md)):

- **Tier A** — first push of `dmfdeploy/*` to `github.com`
- **Tier B** — first managed-service customer on `dmfdeploy.io`
- **Tier C** — first flypack ships to a customer site

Each tier strictly depends on the prior tier being complete.

## Scope

Cross-repo, covers the 7 publish targets — the `dmfdeploy` umbrella (`.`) plus the 6 public component repos (`dmf-cms`, `dmf-infra`, `dmf-central`, `dmf-media`, `dmf-runbooks`, `dmf-init`). The `dmf-env` repo is deliberately private; `dmf-promsd` is a component repo but not yet on the public-publish path (add it to the scripts' `PUBLIC_REPOS` + this scope when its GHCR/GitHub path is decided). Excludes external assurance (ISO 27001 / SOC 2 certification), customer-specific procurement deliverables, and operational alerting/SLO tuning — those follow Tier B by 6+ months.

## Actors / Roles

| Role | Responsibility |
|---|---|
| Operator (sole) | All items in this checklist until team grows. |
| External counsel | Tier B DPA / SCC / TIA review only — engaged at Tier B-3 |
| External auditor | Tier B SoA / ISO 27001 readiness review only — engaged 6+ months post-Tier-B |

## Trigger event

This checklist is run **before** each tier's go-live. Re-run it on any material change to the deployment topology, ADRs, or compliance framework references.

---

## Tier A — Before the first GitHub push

> Goal: anyone cloning `github.com/dmfdeploy/*` gets an honest, framework-shaped, security-respecting starting point with no attestation claims.

### A.1 — Scope decision is named

- [ ] [ADR-0020](../decisions/0020-deployment-scope-and-regulatory-posture.md) status = **Accepted** (not Proposed)
- [ ] Operator has confirmed the three-mode model is the intended posture
- [ ] Cluster-per-tenant constraint (ADR-0020 B.3) sanity-checked against unit-economics expectations

### A.2 — Release & Contribution Model Phases 0–2

Per [DMF Release and Contribution Model Implementation Plan](../plans/DMF%20Release%20and%20Contribution%20Model%20Implementation%20Plan%202026-05-11.md):

- [ ] LICENSE (Apache-2.0) at root of every public repo
- [ ] NOTICE at root of every public repo
- [ ] `## License` section in every public README
- [ ] VERSION file in every repo (`0.1.0` baseline for the 4 missing it)
- [ ] CONTRIBUTING.md in every public repo with MUST / MUST NOT bullets
- [ ] `.gitignore` baseline block in all 7 repos
- [ ] Per-repo gitleaks pre-commit hooks installed and tested with a deliberate-leak smoke
- [ ] `bin/check-public-repo-hygiene.sh` exists, runs, exits 0 on all 7 publish targets (umbrella + 6 public components)
- [ ] `bin/sync-to-github.sh` exists and `--dry-run` passes for every public repo

### A.3 — Mode A boundary documents

- [ ] `SELF-HOST-DISCLAIMER.md` at root of every public repo — one page; states "framework only, no attestation; operators carry their own regulatory obligations"; links to the framework plan
- [ ] Public-facing README of the umbrella repo names the three modes (ADR-0020) and points to which mode the OSS clone supports
- [ ] No file in any public repo references `dmfdeploy.io` as a required dependency (Mode A constraint per ADR-0020)
- [ ] `dmf-env` private repo confirmed off the GitHub org and protected by hook/script

### A.4 — Audit log architecture (Pivot 2)

- [ ] `docs/processes/audit-log-retention-policy.md` exists and states:
  - [ ] k3s API audit + security-relevant app audit (Loki streams labelled
        `job=k3s-audit` / `job=authentik-audit` / `job=*-security`) → 6 months
        hot in Loki; k3s API host file also → 12 months WORM in S3
  - [ ] Operator activity / general app logs (Loki default streams) → 30 days
        hot, no S3 archival (operational debugging, not forensic)
  - [ ] Metrics (Prometheus) → 30 days hot, no archival
  - [ ] Personal data handled per RoPA (forward link)
- [ ] Audit bucket has Object Lock enabled at creation
      (set by `dmf-env/bin/b2-buckets.sh ensure <env>`; verify with
      `bin/b2-buckets.sh show <env>` showing `Object Lock: enabled=True`
      on the audit row); per-upload `--object-lock-mode COMPLIANCE
      --object-lock-retain-until-date "+365d"` set by the
      `roles/base/audit-log-archival` cron
- [ ] Clock-sync stance documented (NTP today, PTP on roadmap for media plane)
- [ ] One smoke-test confirms archived audit log is unmodifiable for the retention period

### A.5 — Artifact-side supply chain (Pivot 3, bootstrap half)

- [ ] `roles/base/cosign-bootstrap` (or equivalent) generates and stores keypair in OpenBao
- [ ] At least one release-tagged image in Zot signed by cosign
- [ ] At least one image has an attached syft-generated SBOM in Zot
- [ ] Pin-by-digest policy documented for upstream image references (commitments v1 §B1 promoted from "principle" to "rule")

### A.6 — Supplier register stub

- [ ] `docs/inventory/supplier-register.md` (new) contains a table: upstream component | criticality tier (1=critical, 2=important, 3=optional) | CVE feed URL | last-checked date | escape-hatch
- [ ] Initial seed: k3s, Longhorn, OpenBao, Authentik, ESO, Traefik, cert-manager, Prometheus, Loki, Grafana, NetBox, AWX, Forgejo, Zot, sony/nmos-cpp

### A.7 — Recovery procedure exercised once

- [ ] Loss-of-Shamir-share recovery procedure documented (extends `dmf-openbao-unseal` skill with the loss-recovery branch)
- [ ] One dry-run rehearsal recorded in a handoff note
- [ ] Break-glass JSON location confirmed, mode 0600, outside git

### A.8 — Strongly recommended (publishable without, but adds confidence)

- [ ] DPIA stub for operator-identity-only processing (1-page CNIL-PIA-tool output)
- [ ] Backup/restore decision recorded — either an RPO/RTO claim or an explicit "no backup claim until Tier B"
- [ ] Aliyun-Frankfurt TIA stub (one paragraph; Schrems II analytic frame)
- [ ] Identity-leak sweep close-out check verified (per 2026-05-11 handoff)

### A.9 — Tier A acceptance

- [ ] `bin/check-public-repo-hygiene.sh` reports clean across all 7 publish targets (umbrella + 6 public components)
- [ ] `bin/sync-to-github.sh --dry-run` succeeds for the first repo to be pushed
- [ ] Operator has read this checklist top-to-bottom in the same session as the push

---

## Tier B — Before the first managed-service customer

> Goal: dmfdeploy.io can sign a DPA and onboard one customer without retrofitting.
> All Tier A items remain checked.

### B.1 — ADR-0020 architectural constraints enforced

- [ ] B.1 Shamir shares originate customer-side: bring-up ceremony documented and rehearsed once
- [ ] No Shamir share material crosses dmfdeploy.io systems, support tooling, logs, or agent transcripts
- [ ] ADR-0011 auto-unseal tradeoff closed for customer hubs: no operator-local automation file containing a Shamir quorum or root token is required for routine Mode B operation
- [ ] Replacement unseal design documented and rehearsed (HA OpenBao, customer-side ceremony, or equivalent customer-side quorum custody)
- [ ] B.2 OIDC/workload-identity federation working for at least one cloud provider
- [ ] Provider bootstrap paths that are not federation (for example Hetzner cloud-init seed) are documented as customer-side, ephemeral, and free of long-lived credentials at rest in dmfdeploy.io
- [ ] B.3 Cluster-per-tenant verified by a multi-cluster smoke test
- [ ] B.4 OSS-vs-managed boundary: one managed-only feature exists and provably requires a dmfdeploy.io API key

### B.2 — ISO 27001:2022 Statement of Applicability

- [ ] SoA drafted: every Annex A control (93 total) marked Applicable / Not Applicable with one-line rationale
- [ ] SoA format per ISO 27001 clause 6.1.3(d)
- [ ] Each Applicable control cross-references either a code artefact (role/playbook path) or a process document (runbook/handoff)
- [ ] Each Not Applicable control has a rationale that doesn't rely on "we're small" alone

### B.3 — GDPR controller/processor pack

- [ ] Mode B role matrix complete:
  - [ ] dmfdeploy.io is processor for customer-hub data processed on customer instructions
  - [ ] dmfdeploy.io is controller for its own account, billing, support, security-log, and vulnerability-intake data
- [ ] DPA template (SCC-aligned) drafted and reviewed by counsel
- [ ] RoPA (Records of Processing Activities) filled out for Mode B categories:
  - [ ] Operator identity (Authentik)
  - [ ] Audit logs (Loki, S3 archive)
  - [ ] Customer-uploaded config (NetBox, Forgejo)
  - [ ] Support data (incident tickets, screen-shares, terminal captures)
  - [ ] Vulnerability reports and security-contact data
  - [ ] Billing / commercial-contact data
- [ ] DPIA produced for the customer-hub bring-up flow (Art. 35)
- [ ] Privacy notice drafted for dmfdeploy.io controller-side data
- [ ] Lawful-basis table drafted for controller-side processing
- [ ] Lead supervisory authority / lead DPA stance recorded for cross-border processing
- [ ] Sub-processor list current (Hetzner, Aliyun, Cloudflare, any other transitive vendor)
- [ ] TIA written for every third-country vendor:
  - [ ] Aliyun (PRC NIL/DSL access risk; supplementary measures named)
  - [ ] Any other non-EEA vendor in the stack
- [ ] Data subject rights process (access / rectification / erasure) documented
- [ ] Breach decision tree separates dmfdeploy.io-as-processor customer notification from dmfdeploy.io-as-controller Art. 33 notification duties

### B.4 — Incident response runbook

In `docs/runbooks/incident-response.md`:

- [ ] Definition of "significant incident" per NIS2 Art. 23
- [ ] 24h early-warning template + recipient list (CSIRT / national authority per relevant Member State)
- [ ] 72h GDPR Art. 33 breach assessment + notification template
- [ ] Processor-side breach notice template to customer controller ("without undue delay")
- [ ] 1-month NIS2 final report template
- [ ] Out-of-band communication path (assume primary comms compromised)
- [ ] Forensics evidence-preservation playbook (WORM bucket access, log export, image snapshot)
- [ ] One tabletop exercise recorded in a handoff note

### B.5 — Backup / restore evidence

- [ ] Longhorn BackupTarget configured to an off-cluster object store
- [ ] OpenBao Raft snapshot scheduled (daily) + tested restore on a scratch cluster
- [ ] Authentik PG backup tested
- [ ] NetBox PG backup tested
- [ ] AWX PG backup tested
- [ ] Forgejo data backup tested
- [ ] One end-to-end DR rehearsal: cluster rebuild + secret reseed from break-glass + app restore — pass/fail recorded

### B.6 — Vulnerability management

Ties EBU R 160 to operations:

- [ ] `security@dmfdeploy.io` mailbox + published PGP/age public key
- [ ] CVE intake SLA: critical 7d, high 30d, medium 90d
- [ ] Trivy in CI: fail-on-merge for HIGH/CRITICAL (Release Plan Phase 4 promoted from "queued" to "blocking")
- [ ] Cosign signing enforced at Zot push (Pivot 3, CI half)
- [ ] Image SBOM verification on pull (admission controller)
- [ ] Kernel CVE mitigations role kept current with vendor advisories

### B.7 — Access review

- [ ] Quarterly access review procedure documented
- [ ] First review completed for:
  - [ ] Authentik groups + memberships
  - [ ] OpenBao policies + named identities
  - [ ] NetBox tokens
  - [ ] Kubernetes RBAC (Roles, RoleBindings, ServiceAccounts)
  - [ ] Cloud provider IAM (Hetzner, Aliyun)
- [ ] Output stored in `docs/audits/access-review-YYYY-MM-DD.md`

### B.8 — Configuration management baseline (ISO A.8.9)

- [ ] Ansible playbooks + Helm values declared source-of-truth in writing
- [ ] Kyverno (or equivalent) admission policies installed for:
  - [ ] No privileged containers (except small allowlist)
  - [ ] No `hostPath` mounts (except small allowlist)
  - [ ] Image signature required for production namespaces
  - [ ] Image SBOM required for production namespaces
- [ ] Drift-detection job runs against the cluster (extension of the existing `lifecycle-operate.yml` drift check)

### B.9 — SIEM-lite alerting

- [ ] Loki + Alertmanager rules for:
  - [ ] Root shell on any node
  - [ ] OpenBao seal/unseal event
  - [ ] Secret read by an unexpected identity
  - [ ] Ingress 4xx/5xx anomaly
  - [ ] Authentik failed-auth burst
  - [ ] Image pulled from unsigned source
- [ ] Alerts route to a paged channel that is monitored

### B.10 — Customer trust package v0.1

In `docs/trust-package/`:

- [ ] Architecture diagram (one-page)
- [ ] Security model summary (one-page from the framework plan)
- [ ] SoA (B.2)
- [ ] Privacy role matrix (B.3)
- [ ] Privacy notice for controller-side data (B.3)
- [ ] Sub-processor list (B.3)
- [ ] Supplier register (A.6 promoted from stub)
- [ ] DPA template (B.3)
- [ ] Customer-side Shamir custody / unseal summary (B.1)
- [ ] Incident response summary (B.4 summary, not full runbook)
- [ ] Vulnerability process summary (B.6 summary)
- [ ] Backup / DR posture summary (B.5)

### B.11 — Tier B acceptance

- [ ] One customer hub successfully onboarded end-to-end
- [ ] Customer signed the DPA without retrofit
- [ ] Privacy role matrix and controller-side privacy notice reviewed in the same session as the DPA
- [ ] Customer-side Shamir custody verified; no ADR-0011-style automation quorum remains in the managed hub path
- [ ] Customer's security questionnaire answered honestly from the trust package
- [ ] Tier C dependencies identified (if flypack is in the customer's scope, schedule Tier C work)

---

## Tier C — Before the first flypack ships

> Goal: a flypack can ship to a customer site and operate disconnected without becoming a portable breach risk.
> All Tier A and Tier B items remain checked.

### C.1 — Hardware reference platform

- [ ] One TPM 2.0 + secure-boot capable platform identified and bench-tested
- [ ] HSM2-class smart card (or equivalent) identified for share custody
- [ ] Tamper-evident enclosure design specified
- [ ] Procurement path documented

### C.2 — Per-flypack provisioning ceremony

In `docs/runbooks/flypack-provisioning.md`:

- [ ] Ephemeral identity issuance at first boot (no shared identity across packs)
- [ ] TPM-sealed disk-encryption keys (not recoverable from disk alone)
- [ ] Shamir share threshold inside the unit
- [ ] Recovery shares held by operator off-pack
- [ ] Factory-reset path
- [ ] Provisioning rehearsed once and recorded

### C.3 — Loss / theft / non-return procedure

Extending the Tier B incident runbook:

- [ ] Remote attestation revocation at dmfdeploy.io trust anchor
- [ ] Tamper-evidence inspection workflow on return
- [ ] 72h GDPR Art. 33 breach assessment trigger if seal broken or unit not returned
- [ ] Customer notification template
- [ ] One tabletop exercise recorded

### C.4 — Reconnect / offline-update story

- [ ] Customer-side relay design documented — flypack never initiates; relay polls
- [ ] Disconnect-by-default verified
- [ ] Offline patch path documented (USB stick / on-site engineer / customer relay)
- [ ] Update integrity verified (cosign + customer-held trust anchor)

### C.5 — EBU R 143 vendor acceptance

- [ ] EBU R 143 media-vendor security checklist completed for the assembled flypack
- [ ] Acceptance evidence stored in `docs/audits/flypack-r143-YYYY-MM-DD.md`

### C.6 — Physical-media controls (ISO A.7.10 / A.7.13 / A.7.14)

- [ ] Shipping-condition checks (tamper indicator, serial verification)
- [ ] Return-path security (RMA process with chain-of-custody)
- [ ] Secure-disposal procedure when retired (drives crypto-erased, TPM cleared, enclosure inspection)

### C.7 — Tier C acceptance

- [ ] One flypack shipped, operated in real production, and returned through the documented lifecycle
- [ ] No findings on return, or findings tracked through the Tier B incident process

---

## Exception paths

| Exception | Response |
|---|---|
| Tier A item unrecoverable (e.g. upstream license incompatible with Apache-2.0) | Stop the GitHub push. Resolve in framework plan amendment + ADR before re-running. |
| Tier B SoA control marked Applicable but no implementation exists | Either implement (preferred), accept-risk in writing (counsel sign-off), or descope the customer use case. |
| Tier B customer hub still needs ADR-0011-style operator-local auto-unseal material | Stop Tier B exit. Replace with customer-side quorum custody or explicitly descope managed service. |
| Tier B DR rehearsal fails | Stop Tier B exit. Root-cause + re-rehearse. Do not onboard customer on unproven restore. |
| Tier C flypack lost in transit before customer receipt | Trigger C.3 loss procedure. Cannot reuse the lost identity. Re-provision a replacement unit. |
| Customer requests a feature outside the named mode (e.g. Mode A user demands attestation) | Refer to ADR-0020. Do not extend the mode boundary informally. |

## Inputs

- ADR-0020 (deployment scope)
- The framework plan and its referenced standards
- Existing role/playbook coverage map (Plan §2)

## Outputs

- Tier A: a publishable OSS bundle on `github.com/dmfdeploy`
- Tier B: a signed-DPA customer hub on `dmfdeploy.io`
- Tier C: a deployed flypack returning through the documented lifecycle

## Systems touched

The cluster (k3s), OpenBao, Authentik, Loki, Forgejo, GitHub, the public S3 archive bucket, future cloud-provider IAM federations, future flypack hardware.

## Controls / approvals

- Tier A exit: operator-only (sole maintainer)
- Tier B exit: operator + external counsel for DPA/SCC/TIA and privacy role matrix
- Tier C exit: operator + EBU R 143 acceptance reviewer (may be operator if claiming self-acceptance)

## Related runbooks

- [DMF Bootstrap process](dmf-bootstrap.md)
- `docs/runbooks/incident-response.md` (created at Tier B)
- `docs/runbooks/flypack-provisioning.md` (created at Tier C)
- Skills `dmf-cluster-access`, `dmf-openbao-unseal`, `dmf-cms-build-and-release`
