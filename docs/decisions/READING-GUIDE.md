# ADR reading guide — new here? Start with these

The record holds 41 ADRs plus a standing commitment document. You do not need
them all. Read the eight below, in order — each layer assumes the one before it.
Everything else is reference via [INDEX.md](INDEX.md), and the four
[digests](digests/) consolidate current truth per topic cluster so you never
have to reverse-engineer it from partially-superseding ADRs.

| # | Read | Why it's load-bearing |
|---|---|---|
| 1 | [ADR-0003 — EBU DMF V2.0 taxonomy](0003-ebu-v2-taxonomy.md) | The vocabulary. Layers / verticals / lifecycle stages name every playbook, role, and doc in the estate. Nothing else parses without it. |
| 2 | [architectural-commitments-v1](architectural-commitments-v1.md) | The current operating stance (2026-06-06): what is frozen, what v0.1 claims, and the work-selection rule. Individual ADRs are now read *against* this. |
| 3 | [ADR-0013 — Media function catalog model](0013-media-function-catalog-model.md) | The platform's heart: catalog YAML as intent, NetBox tags as runtime lifecycle state, the console joining the two. |
| 4 | [ADR-0025 — Ansible in in-cluster pods; catalog functions as Helm charts](0025-ansible-in-cluster-pods-and-catalog-helm.md) | How catalog intent becomes running workloads: AWX-spawned execution-environment pods, cluster-local registry, Helm deploys. |
| 5 | [ADR-0028 — Identity and authority chain](0028-identity-and-authority-chain.md) | The canonical identity model: Authentik as sole human authority, scoped machine identities, break-glass discipline, attribution metadata. |
| 6 | [ADR-0008 — OpenBao secrets architecture](0008-openbao-secrets-architecture.md) | How secrets flow: OpenBao custody, External Secrets Operator projection, AppRole auth. ([ADR-0009](0009-shamir-dr-model.md)/[0029](0029-tiered-unseal-posture.md) layer custody + unseal posture on top.) |
| 7 | [ADR-0035 — Operator-local self-contained envs](0035-operator-local-self-contained-envs.md) | The reproducibility boundary: repos are generic, every environment's state is operator-local. Why the public tree contains no real topology. |
| 8 | [ADR-0036 — dmf-init thin control container](0036-dmf-init-thin-control-container.md) | Day-0: how a blank node becomes a facility — and why the installer image stays release-agnostic and public-safe. |

After these, go by topic, canonical digest first:

- **Identity & authority** → [digest](digests/identity-and-authority.md)
- **Catalog & execution** → [digest](digests/catalog-and-execution.md)
- **Secrets & unseal** → [digest](digests/secrets-and-unseal.md)
- **Deployment scope & release** (what v0.1 does and does not claim) → [digest](digests/deployment-scope-and-release.md)

How the record evolved — and which decisions were reversed and why — is told in
[../JOURNEY.md](../JOURNEY.md). What remains open is curated in
[../OPEN-QUESTIONS.md](../OPEN-QUESTIONS.md).
