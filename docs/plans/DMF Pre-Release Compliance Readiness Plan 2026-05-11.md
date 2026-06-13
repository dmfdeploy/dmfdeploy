---
status: draft
date: 2026-05-11
---
# DMF Pre-Release Compliance Readiness Plan

**Status:** Draft
**Date:** 2026-05-11
**Pairs with:** [ADR-0020](../decisions/0020-deployment-scope-and-regulatory-posture.md) (deployment scope), [`dmf-infra/docs/security-compliance-framework-plan.md`](https://github.com/dmfdeploy/dmf-infra/blob/main/docs/security-compliance-framework-plan.md) (framework)
**Operational counterpart:** [`docs/processes/pre-release-compliance-checklist.md`](../processes/pre-release-compliance-checklist.md)
**Driver:** Senior-DevOps review 2026-05-11 — three architectural pivots cheap now / expensive later; multi-modal deployment posture (OSS / managed / flypack) requires tiered readiness gates rather than a single pre-release event.

---

## 1. Scope and framing

This plan exists because the framework plan answers *what controls* and the
release & contribution plan answers *how artefacts ship* — but neither
answers *what must be true before each named deployment mode is allowed to
exist in the world*.

Three deployment modes are defined in ADR-0020:

- **Mode A — OSS self-host** (`github.com/dmfdeploy/*`, Apache-2.0)
- **Mode B — Managed service** (`dmfdeploy.io`, customer hubs)
- **Mode C — Flypack** (portable offline kit)

Each has a distinct regulatory posture and therefore a distinct readiness
gate. This plan organises the work into **three tiers**, each gated. Work
not assigned to a tier is explicitly deferred.

### Standards basis

- **ISO/IEC 27001:2022** — 93 controls, 4 themes. The 2013 version's
  transition window closed 31 Oct 2025 per IAF MD 26; only the 2022
  controls apply going forward.
- **NIS2** — Directive (EU) 2022/2555 + Implementing Reg. (EU) 2024/2690
  (technical floor for managed service providers under Annex I §8).
- **GDPR** — Regulation (EU) 2016/679; Art. 25, 28, 30, 32, 33, 35
  primarily; EDPB Recs 01/2020 v2.0 for transfers; Guidelines 02/2024
  on Art. 48 (third-country lawful access). Mode B must treat
  dmfdeploy.io as processor for customer-hub data and controller for
  its own account, billing, support, security-log, and
  vulnerability-intake data.
- **EBU R 143** (media vendor cybersecurity) and **EBU R 160**
  (vulnerability management) — media-domain overlay.

### What this plan is not

- It is not a Statement of Applicability. That document is a Mode B
  deliverable produced at Tier B exit.
- It is not a substitute for legal counsel on customer claims. Counsel
  signs off on Mode B contractual language at Tier B exit.
- It is not a substitute for the framework plan's control register or
  evidence model — both are referenced, not duplicated.

---

## 2. Current coverage map — what already exists

Before listing gaps, name what's already done. This list is *also* the
"what to put in the trust package" inventory for Tier B.

### Controls implemented in code today

| Capability | Where | Maps to |
|---|---|---|
| Secrets at rest, Shamir 3-of-5, root-token-disposal | `roles/stack/operator/openbao/*`, ADR-0007/0008/0009 | ISO A.5.17, A.8.5, A.8.24; NIS2 21(2)(h)(i); GDPR Art. 32 key-mgmt |
| Passkey-only OIDC at the operator UI | Authentik blueprints, ADR-0015 | ISO A.5.16-18; NIS2 21(2)(i)(j); GDPR Art. 32 |
| Pod-level secret delivery via ESO read-only AppRole | `roles/base/external-secrets`, openbao security model | ISO A.8.5, A.8.24; NIS2 21(2)(h) |
| k3s API audit logging, 30-day rotation | `roles/base/k3s` (`k3s-audit-logging.conf.j2`) | ISO A.8.15; NIS2 21(2)(g) (partial — see Pivot 2) |
| S3 audit log archival path | `roles/base/audit-log-archival` | ISO A.8.15 (partial — needs object-lock) |
| Host hardening — SSH allowlist, fail2ban, nftables, non-root admin | `roles/base/harden` | ISO A.8.20, A.8.21; NIS2 21(2)(e) |
| Kernel CVE mitigations by named CVE list | `roles/base/kernel-cve-mitigations` | ISO A.8.8; NIS2 21(2)(e); EBU R 160 |
| TLS automation with cert-manager + DNS-01 wildcard | `roles/base/cert-manager` | ISO A.8.24; NIS2 21(2)(h); GDPR Art. 32 (transit) |
| Network policies (OpenBao default-deny + allowlist) | `roles/base/network-policies` | ISO A.8.22; NIS2 21(2)(j) |
| Cluster-readiness gate before app deploys | `roles/base/cluster-ready` | ISO A.8.9 (partial — config-mgmt baseline) |
| Source-side supply chain — gitleaks pre-commit, CODEOWNERS, scrub-public-repos | umbrella `.githooks/`, `bin/scrub-public-repos.sh` | ISO A.5.19, A.8.31; NIS2 21(2)(d) |
| ADR + handoff discipline | `docs/decisions/`, `docs/handoffs/` | ISO A.5.31, A.5.37 — documented information / operating procedures |
| Conventional Commits + Apache-2.0 + LICENSE/NOTICE (in-flight) | Release & Contribution Plan Phase 0 | ISO A.5.10, A.5.32; A.5.34 |

Important limitation: the Shamir row above is true for the current lab
and manual break-glass model, but ADR-0011 explicitly accepts an
experiment-phase auto-unseal path where an operator-local automation file
holds a quorum. That path is not a Mode B control. Tier B exit requires
closing or replacing it for customer hubs.

### Process in flight (Release & Contribution Model Phases 0–6)

- 3-layer gitleaks (pre-commit done in umbrella; per-repo + pre-receive + CI in flight)
- Branch protection + linear history + required reviews
- `bin/release.sh` + CHANGELOG generation per repo
- commitlint enforcement
- Trivy filesystem scan (Phase 4)

### Plans landed but not implemented

- LLM-restricted git pipeline (dev/testing/production token scoping)
- Forgejo-as-NetBox-external-datasource (delivered, awaiting validation)

This coverage is **stronger than typical pre-release**. The gaps below are
real but they are not "start from scratch"; they are "harden the edges and
name the boundaries before more apps generate state."

---

## 3. The three pivots (priority order)

These three are decided in this plan because deferring them gets
materially more expensive with every app added, log written, or image
pushed.

### Pivot 1 — Deployment scope is named (ADR-0020)

**Status:** ADR-0020 Proposed as of 2026-05-11; awaits promotion to
Accepted per the criteria listed in that ADR.

**Why now:** Every downstream control's applicability depends on which
mode it serves. Without naming the modes, "compliance work" is
infinite-scope.

**Action:** Promote ADR-0020. Tier A exit depends on it.

### Pivot 2 — Audit log architecture is lockable

**Status:** k3s audit log shipping locally with 30-day rotation; S3
archival role exists but uses a mutable bucket; Loki retention 168h;
Prometheus retention 6h.

**Why now:** Once Mode B onboards a single customer, retroactively
re-classifying historic operator logs (which are personal data once
operator accounts are real) is multi-day work. Once 6+ months of logs
exist without a retention policy, the policy decision becomes a
deletion exercise instead of a forward commitment.

**Action:**

- Enable S3 Object Lock on the audit bucket at bucket-creation time.
  (Implemented in Phase 2 via `dmf-env/bin/b2-buckets.sh` against B2;
  Terraform was attempted but pivoted away — see the Phase 2 handoff
  §2.6 for why.) Per-upload retention is set by the `audit-log-archival`
  role's cron via `--object-lock-mode COMPLIANCE
  --object-lock-retain-until-date "+365d"`.
- Add `docs/processes/audit-log-retention-policy.md`:
  - k3s API audit + security-relevant app audit (Loki streams labelled
    `job=k3s-audit`, `job=authentik-audit`, `job=*-security`) → **6 months
    hot in Loki**; k3s API host file additionally → **12 months WORM in S3**
  - Operator activity / general app logs (Loki default streams) → **30 days
    hot, no S3 archival** (operational debugging, not forensic)
  - Metrics / Prometheus → **30 days hot, no archival** (operational only)
  - Personal data in any audit stream → handled per RoPA, separate from
    bucket retention
- Document clock-sync stance (ISO A.8.17) — NTP discipline today, PTP
  on roadmap for the media plane.

**Tier:** Mostly Tier A (policy doc, WORM bucket), small slice into Tier B
(SIEM-lite alerting).

### Pivot 3 — Artifact-side supply-chain provenance

**Status:** Source-side excellent; artifact-side absent (no cosign, no
syft SBOM, no Trivy gate on images; Trivy fs-scan queued for release
plan Phase 4 but doesn't cover images in Zot).

**Why now:** Sony nmos-cpp pin-by-SHA is the principle (commitments v1
§B1) but enforcement is missing. NIS2 21(2)(d) + ISO A.8.9, A.8.28 will
require signed/SBOM'd images for any Mode B customer claim. There are
roughly 10 images today; bolting cosign onto a year-old registry with
50 images is materially harder than starting now.

**Action:**

- Add a `roles/base/cosign-bootstrap` role: generate a project keypair
  (key in OpenBao, public key in repo); install `cosign` on the build
  host; document the signing ceremony.
- Add `syft` SBOM generation to every `docker build` invocation in
  `dmf-runbooks/roles/nmos-cpp/` and `dmf-cms/` build pipelines; store
  SBOM in Zot alongside the image (Cosign-style attached attestation).
- Add Trivy image scan as a *post-push verify* step against Zot;
  fail-on `HIGH`/`CRITICAL` with an explicit allowlist for known/accepted.
- Document pin-by-digest policy for upstream image references.

**Tier:** Tier A (bootstrap + first image signed), Tier B (CI gate
enforcing).

---

## 4. Tiered readiness gates

### Tier A — Before the github push (Mode A go-live)

**Goal:** the OSS repos are *publishable* — anyone cloning gets an
honest, framework-shaped, security-respecting starting point with no
attestation claims.

**Required (no public push without these):**

1. **ADR-0020 promoted Accepted.** (Pivot 1)
2. **Release & Contribution Model Phases 0–2 complete** — LICENSE,
   NOTICE, VERSION, CONTRIBUTING, baseline `.gitignore`, per-repo
   gitleaks pre-commit, `bin/check-public-repo-hygiene.sh`,
   `bin/sync-to-github.sh` (already a planned hard gate).
3. **`SELF-HOST-DISCLAIMER.md` at each public-repo root** — one page,
   stating: this is framework + reference implementation; no compliance
   attestation; clone-and-self-host operators carry their own
   regulatory obligations; pointer to the framework plan.
4. **Audit-log retention policy documented** (Pivot 2.policy half).
5. **Cosign signing of release-tagged images bootstrapped** (Pivot 3
   bootstrap half) — even if not yet CI-enforced.
6. **Public-repo identity sweep complete + verified** (in flight per
   2026-05-11 handoff; just needs the close-out check).
7. **CODEOWNERS files in every public repo present and protect
   `.github/`, `bin/`, `docs/decisions/`** (already done — re-verify).
8. **`dmf-env` confirmed off the GitHub org and remains so by hook.**
9. **Supplier register stub** — single markdown table of upstream OSS
   components with criticality tier and CVE-feed subscription path
   (ISO A.5.19, NIS2 21(2)(d) — Mode A doesn't need full diligence,
   but the inventory must exist).
10. **Loss-of-secret-share recovery procedure documented and dry-run
    once** — references existing `dmf-openbao-unseal` skill; gap is
    just the loss-recovery branch.

**Strongly recommended (publishable without, but adds confidence):**

- DPIA stub for operator-identity-only processing — even Mode A self-host
  operators benefit from a template.
- Backup/restore decision recorded (RPO/RTO or "no claim until Tier B").
- Aliyun-Frankfurt TIA stub (one paragraph; Mode A operators using
  Aliyun should be aware).

**Out of scope for Tier A:**

- ISO 27001 Statement of Applicability, SoA gap analysis
- Customer trust package
- Multi-tenant billing, hub-orchestration UI
- Flypack-specific controls

### Tier B — Before managed-service v0.1 (Mode B go-live)

**Goal:** dmfdeploy.io can onboard one customer and answer their
security questionnaire honestly.

**Required (in addition to all Tier A items):**

1. **ADR-0020 Mode B constraints enforced architecturally:**
   - B.1 Shamir-shares-customer-side bring-up ceremony implemented and
     test-rehearsed once; no Shamir share material crosses dmfdeploy.io
     systems, support tooling, logs, or agent transcripts.
   - ADR-0011 auto-unseal tradeoff closed for customer hubs: no
     operator-local automation file containing a Shamir quorum or root
     token is required for routine Mode B operation. Accepted exits:
     HA OpenBao with manual initial unseal, customer-side unseal
     ceremony, or another design with equivalent customer-side quorum
     custody.
   - B.2 OIDC/workload-identity federation for at least one cloud
     provider. Hetzner cloud-init seed is a non-federated bootstrap
     path; it can satisfy the "no long-lived credential at rest in
     dmfdeploy.io" constraint only when customer-side, ephemeral, and
     documented as such.
   - B.3 Cluster-per-tenant verified by a multi-cluster smoke test.
   - B.4 OSS-vs-managed boundary enforced — pick one managed-only
     feature and prove it requires a dmfdeploy.io API key to function.
2. **ISO 27001:2022 Statement of Applicability drafted** — every Annex
   A control marked Applicable / Not Applicable with one-line
   rationale. Format per ISO 27001 clause 6.1.3(d).
3. **GDPR controller/processor pack:**
   - Role matrix covering every Mode B processing category:
     dmfdeploy.io as processor for customer-hub data; dmfdeploy.io as
     controller for its own account, billing, support, security-log, and
     vulnerability-intake data.
   - DPA template (Standard Contractual Clauses-aligned).
   - RoPA filled out for Mode B processing categories
     (operator identity, audit logs, customer-uploaded config, support
     data, vulnerability reports, billing/contact data).
   - DPIA for the bring-up flow (Art. 35).
   - Privacy notice and lawful-basis table for dmfdeploy.io's
     controller-side data.
   - Lead supervisory authority / lead DPA stance recorded for
     cross-border processing.
   - Breach decision tree distinguishing dmfdeploy.io-as-processor
     notification to the customer without undue delay from
     dmfdeploy.io-as-controller Art. 33 notification duties.
   - Sub-processor list (Hetzner, Aliyun, Cloudflare, any other
     transitive vendor).
   - Aliyun (or any third-country vendor) TIA with supplementary
     measures named (EU-only support, customer-held keys, contractual
     disclosure-disclosure clause).
4. **Incident response runbook** (in `docs/runbooks/`) covering:
   - Definition of "significant incident" per NIS2 Art. 23
   - 24h early-warning template + recipient list
   - 72h GDPR Art. 33 breach assessment + notification template
   - 1-month NIS2 final report template
   - Out-of-band communication path (assume primary comms compromised)
   - Forensics evidence-preservation playbook (WORM bucket access, log
     export, image snapshot)
5. **Backup/restore evidence:**
   - Longhorn BackupTarget configured to off-cluster object store
   - OpenBao Raft snapshot scheduled + tested restore on a scratch
     cluster
   - One full DR rehearsal (cluster rebuild + secret reseed from
     break-glass) — pass/fail recorded
6. **Vulnerability management process** (ties EBU R 160 to operations):
   - CVE intake channel (security@dmfdeploy.io with a published key)
   - SLA: critical 7d, high 30d, medium 90d (numbers up to operator)
   - Trivy in CI as **fail-on-merge** (Release Plan Phase 4 promotes
     from "queued" to "blocking")
   - Cosign signing **enforced** at Zot push (Pivot 3 CI half)
7. **Access review cadence + evidence:**
   - Quarterly review of Authentik groups, OpenBao policies, NetBox
     tokens, Kubernetes RBAC
   - Output stored alongside ADRs (read-only Forgejo or signed Git tag)
8. **Customer trust package v0.1** — architecture diagram, security
   model, SoA, privacy role matrix, privacy notice, sub-processor list,
   supplier register, DPA template, customer-side Shamir custody /
   unseal summary, incident response process summary, vulnerability
   process summary.
9. **Configuration management baseline (ISO A.8.9):**
   - Declare Ansible playbooks + Helm values as source-of-truth
   - Add Kyverno (or equivalent) admission policies for the highest-risk
     constraints (no privileged containers, no `hostPath` mounts in
     namespaces beyond a small allowlist, image-signature required)
10. **SIEM-lite alerting:** Loki + Alertmanager rules for high-priority
    audit events (root-shell, OpenBao seal, secret read by unexpected
    identity, ingress 4xx/5xx anomaly).

**Required to STOP doing at Tier B exit:**

- Treating Mode A and Mode B with identical handling of customer data
- Pushing unsigned images to Zot
- Mutable audit-log buckets
- ADR-0011-style operator-local automation quorum for customer hubs
- Long-lived cloud credentials at rest (except residual-risk-documented
  providers per ADR-0020 B.2)

### Tier C — Before flypack v0.1 (Mode C go-live)

**Goal:** a flypack can be shipped to a customer site and operate
disconnected without becoming a portable breach risk.

**Required (in addition to all Tier B items):**

1. **Reference hardware platform identified** (TPM 2.0 + secure boot
   minimum; HSM2-class smart card for share custody).
2. **Per-flypack provisioning ceremony documented and rehearsed:**
   ephemeral identity issuance, TPM-sealed disk-encryption keys,
   factory-reset path.
3. **Loss procedure** in incident response runbook:
   - Remote attestation revocation (the flypack's identity cert is
     revoked at the dmfdeploy.io trust anchor)
   - Tamper-evidence inspection workflow on return
   - 72h breach assessment trigger if seal broken or unit not returned
4. **Customer-side relay design** for optional re-connect to
   dmfdeploy.io — flypack does not initiate; relay polls. Disconnect by
   default; reconnect is a deliberate customer action.
5. **EBU R 143 vendor-systems acceptance** completed for the assembled
   flypack as a whole (R 143's media-vendor security checklist).
6. **Physical-media controls (ISO A.7.10, A.7.13, A.7.14):**
   shipping-condition checks, return-path security, secure-disposal
   procedure when a unit is retired.
7. **Documented stance on offline software update:** how patches reach
   a flypack at sea / in an OB-truck / in a field venue. (Answer must
   be honest; "operator brings a USB stick" is acceptable if
   documented.)

---

## 5. Dependency graph

```
ADR-0020 (Proposed → Accepted)
    │
    ├──→ Tier A (OSS public push)
    │       │
    │       ├──→ Release & Contribution Phases 0–2 (already in flight)
    │       ├──→ Audit-log retention policy doc
    │       ├──→ Cosign bootstrap
    │       ├──→ Supplier register stub
    │       └──→ SELF-HOST-DISCLAIMER + reference to framework plan
    │
    └──→ Tier B (managed v0.1)
            │
            ├──→ ADR-0020 B.1–B.4 architectural enforcement
            ├──→ Close ADR-0011 auto-unseal gap for customer hubs
            ├──→ SoA + DPA + DPIA + RoPA + TIA + privacy role matrix
            ├──→ Incident response runbook
            ├──→ Backup/restore evidence (one DR rehearsal)
            ├──→ Vuln mgmt SLA + CI cosign/Trivy enforcement
            ├──→ Customer trust package v0.1
            │
            └──→ Tier C (flypack v0.1)
                    ├──→ Reference hardware
                    ├──→ Per-pack provisioning ceremony
                    ├──→ Loss procedure
                    └──→ EBU R 143 acceptance
```

Tiers A and B can run partially in parallel; Tier B items that depend on
Tier A artefacts (SoA referencing the released image-signing pipeline)
must wait. Tier C strictly follows Tier B.

---

## 6. Effort estimate (rough)

| Tier | Net-new effort beyond what's already planned | Notes |
|---|---|---|
| Tier A | 2–3 sessions | Most of the work is already in the Release & Contribution Plan; this plan adds the disclaimer, policy doc, cosign bootstrap, supplier stub. |
| Tier B | 9–13 sessions | SoA + DPA + DPIA + TIA + incident runbook + DR rehearsal + Kyverno admission + Trivy gate + closing the ADR-0011 auto-unseal gap. The DR rehearsal and unseal redesign are the longest items. |
| Tier C | 5–8 sessions | Hardware-dependent; partly procurement + bench-testing. |

These estimates assume the operator is implementing; outside legal review
for DPA/SCC adds external time.

---

## 7. Acceptance criteria

- ADR-0020 is referenced from `dmf-infra/docs/security-compliance-framework-plan.md`'s
  amended §"Open Questions" / §"Pre-release gates" (this is the
  ratification check that the framework plan and ADR are in sync).
- `docs/processes/pre-release-compliance-checklist.md` mirrors §4 of this
  plan as a runnable checklist.
- Tier A acceptance = first GitHub repo push succeeds with all required
  items present (validated by `bin/check-public-repo-hygiene.sh` once
  that script is built per Release Plan Phase 2).
- Tier B acceptance = one customer hub successfully onboarded against a
  signed DPA, with the privacy role matrix complete, the trust package
  shared, customer-side Shamir custody verified, and a customer-side
  audit question set answered.
- Tier C acceptance = one flypack shipped, operated, and returned with
  no findings — or with findings tracked through the incident process.

---

## 8. Risks and decisions deferred

- **Aliyun stays in scope.** Decision required before Tier B exit on
  whether Aliyun-Frankfurt is supported as a Mode B target or restricted
  to Mode A self-host operators who accept the residual risk themselves.
  EDPB stance is unchanged: third-country-equivalent regardless of
  region.
- **Cluster-per-tenant economics** — ADR-0020 B.3 binds this. If unit
  economics force a change, ADR-0020 must be superseded; this plan's
  Tier B controls assume B.3.
- **ADR-0011 auto-unseal tradeoff** — acceptable for the lab, but
  incompatible with Mode B's customer-side Shamir custody claim. Tier B
  must retire, supersede, or scope it away from customer hubs before any
  managed-service onboarding.
- **SOC 2 / ISO 27017 / ISO 27018** — explicitly deferred until a
  customer triggers them. Framework plan §"Frameworks To Defer Unless
  Triggered" remains the source of truth.
- **Pod-to-pod mTLS / service mesh** — deferred. NetworkPolicy +
  Tailscale lane is sufficient until at least Tier B SoA review names
  it as a residual risk.
- **ISO 22301 BC certification** — deferred; Tier B's DR rehearsal +
  incident runbook + backup evidence provides functional continuity
  without the management-system overhead.

---

## 9. Done definition

- Tier A: every Mode A consumer (anyone who clones a GitHub repo) gets
  honest framework + no over-claim + no broken expectation. The
  framework plan + ADR-0020 + SELF-HOST-DISCLAIMER answer every
  reasonable security question a downstream operator would ask.
- Tier B: dmfdeploy.io can sign a DPA without retrofitting; its
  controller/processor duties are separated in writing; one customer hub
  is operational, customer-side-unsealed, and auditable end-to-end.
- Tier C: one flypack has shipped, served real production, and returned
  through the documented lifecycle.

The framework plan's Phase 4 ("external assurance" — ISO 27001
certification, SOC 2 Type II) is **out of scope for this plan** and
follows Tier B by 6+ months of stable operations.
