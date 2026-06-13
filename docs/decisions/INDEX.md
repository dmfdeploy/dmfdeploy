# Architecture Decision Records (ADRs)

Cross-cutting decisions that apply across the DMF Platform. ADRs are the
**architectural** form of project rules; skills (`.claude/skills/`) are the
**operational** form. ADRs change rarely; skills change with the workflow.

Every agent working in any DMF repo should read the relevant ADRs before making
changes that touch their domain. New ADRs are added when a decision blocks
multiple repos or implies an enforcement mechanism (script, CI gate, skill).

## Start here

New here — human or cold-start agent? You do **not** need all 41 ADRs. Read these
**core** decisions (marked ★ in the Index below), in order — each is summarised by
its binding **Rule**; open the full ADR only when you need the *why*. Everything
else is reference. (How the record evolved and what reversed is told in
[../JOURNEY.md](../JOURNEY.md); what remains open is curated in
[../OPEN-QUESTIONS.md](../OPEN-QUESTIONS.md).)

1. **[ADR-0003 — EBU V2.0 taxonomy](0003-ebu-v2-taxonomy.md)** — the vocabulary
   everything else is named in. *Rule: every playbook, role, and doc uses the EBU
   DMF V2.0 taxonomy (6 layers, 4 verticals, 6 lifecycle stages); playbook numbers
   encode layer + lifecycle.*
2. **[architectural-commitments-v1](architectural-commitments-v1.md)** — the
   current operating stance (2026-06-06): what is frozen, what v0.1 claims, the
   work-selection rule. Individual ADRs are now read *against* this.
3. **[ADR-0013 — Media function catalog model](0013-media-function-catalog-model.md)**
   — the platform's heart. *Rule: a media function = a YAML manifest (intent)
   joined to a NetBox runtime tag (lifecycle state); dmf-cms shows the join and
   drives Configure/Finalise via AWX.*
4. **[ADR-0025 — In-cluster Ansible; catalog as Helm](0025-ansible-in-cluster-pods-and-catalog-helm.md)**
   — how intent becomes running workloads. *Rule: `media-*` launchers run in
   AWX-spawned in-cluster EE pods (never SSH-to-node); functions deploy as Helm
   charts from in-cluster Zot.*
5. **[ADR-0028 — Identity and authority chain](0028-identity-and-authority-chain.md)**
   — the identity model. *Rule: humans use passkeys (Authentik); emergency admins
   are sealed in OpenBao; machines use scoped service accounts; every automated
   action records the requesting human.*
6. **[ADR-0008 — OpenBao secrets architecture](0008-openbao-secrets-architecture.md)**
   — how secrets flow. *Rule: cluster-runtime secrets live in OpenBao and reach
   pods via ESO (AppRole); break-glass material stays outside the runtime path.*
7. **[ADR-0035 — Operator-local self-contained envs](0035-operator-local-self-contained-envs.md)**
   — the reproducibility boundary. *Rule: every env is operator-local under
   `~/.dmfdeploy/envs/<env>/` (nothing per-env committed); dmf-env is generic
   tooling.*
8. **[ADR-0036 — dmf-init thin control container](0036-dmf-init-thin-control-container.md)**
   — Day-0 bootstrap. *Rule: dmf-init bakes only tools + the app; playbooks are
   cloned at a selected ref at runtime and app images pulled at bootstrap —
   nothing baked.*

After these, browse the full Index below; for a topic, read its **canonical**
ADR(s) first ([Theme clusters](#theme-clusters--canonical-pointer)) and the
matching [digest](digests/).

## Format

Each ADR is a numbered markdown file. Status is one of:
- **Accepted** — current rule, follow it
- **Superseded** — fully replaced by a later ADR (link forward)
- **Partially superseded** — a later ADR is canonical for *part* of the scope; this
  one is still authoritative for the rest (name the successor and the split)
- **Deprecated** — no longer applies; preserved for history
- **Proposed** — under discussion, not yet adopted

Numbering is monotonic; **reserved numbers, if any, are annotated as such** (so an
unwritten reserved slot is not mistaken for a gap). No semantic meaning to the number.

**Supersession links are reciprocal.** When ADR-X supersedes/amends ADR-Y, X carries
`**Supersedes/amends:** ADR-Y` and Y carries the matching `**Superseded-by:**` (or
`**Partially superseded by:**` / `**Largely superseded by:**`) line. Both the file's
status line and its Index row below should name the canonical successor so current
truth is visible without opening the file.

## Index

**★ = core** — newcomer must-read; see [Start here](#start-here).

| # | Title | Status | Domain |
|---|---|---|---|
| [0001](0001-umbrella-as-docs-home.md) | Umbrella as docs home; component repos remain independent gits | Accepted (amended 2026-06-11 — components are siblings of the umbrella, not nested) | structure |
| [0002](0002-two-repo-model.md) | Two-repo model: generic playbooks + private inventory | Accepted | structure |
| [0003](0003-ebu-v2-taxonomy.md) | ★ EBU DMF V2.0 layer/vertical/lifecycle taxonomy | Accepted | vocabulary |
| [0004](0004-experiment-phase-stance.md) | Experiment phase, not hardening (until thesis-killers fall) | Accepted — **stance superseded for committed core by [architectural-commitments-v1](architectural-commitments-v1.md)** (gate fired 2026-06-04) | strategic |
| [0005](0005-version-as-single-source-of-truth.md) | dmf-cms VERSION file is the single source of truth | Accepted | dmf-cms |
| [0006](0006-cluster-is-the-truth.md) | The cluster is the truth, not local kubectl | Accepted | operations |
| [0007](0007-secrets-never-in-argv.md) | Secrets never in argv, env, /tmp, or AI transcripts | Accepted | security |
| [0008](0008-openbao-secrets-architecture.md) | ★ OpenBao + ESO + AppRole shim as secrets architecture | Accepted | security |
| [0009](0009-shamir-dr-model.md) | 5-share Shamir, 3-of-5 threshold, distributed across 5 locations | Accepted | DR |
| [0010](0010-run-playbook-as-sanctioned-entry.md) | `bin/run-playbook.sh` is the only sanctioned ansible entry point | Accepted | operations |
| [0011](0011-auto-unseal-tradeoff.md) | Auto-unseal trades Shamir defense-in-depth for operational tolerability | Accepted (with known tradeoff) | security |
| [0012](0012-configure-stage-distinct-from-provision.md) | Configure is a distinct lifecycle stage from Provision | Accepted | lifecycle |
| [0013](0013-media-function-catalog-model.md) | ★ Media function catalog model — YAML intent + NetBox runtime tag | Accepted | architecture |
| [0014](0014-awx-project-layout.md) | AWX project layout — hybrid (launchers + mirrored source repos) | Accepted | operations |
| [0015](0015-dmf-console-passkey-only.md) | DMF Console uses passkey-only OIDC authentication flow | Accepted | security |
| [0016](0016-awx-control-node-ssh-via-cloud-init-and-openbao.md) | AWX↔control-node SSH via cloud-init pubkey + OpenBao privkey (Path A) | **Partially superseded by ADR-0025** (canonical for `media-*` JTs; still authoritative for AWX→infrastructure plays) | operations |
| [0017](0017-mxl-intra-host-data-plane.md) | MXL is an intra-host data plane; multi-node media graphs use ST 2110/NDI/SRT bridges | Accepted | architecture |
| [0018](0018-self-managed-k3s-not-ack.md) | Stay self-managed k3s on every cloud — do not adopt ACK or other managed Kubernetes | Accepted | strategic |
| [0019](0019-tailscale-cgnat-vs-cloud-internal-services.md) | Tailscale CGNAT range overlaps Aliyun internal services — install a per-cloud allow rule above `ts-input` | Accepted | networking |
| [0020](0020-deployment-scope-and-regulatory-posture.md) | Deployment scope and regulatory posture — three named modes (OSS self-host / managed `dmfdeploy.io` / flypack) | Accepted (Mode A); Proposed (Mode B, C) | strategic / compliance |
| [0021](0021-openbao-approle-reconciler-identity.md) | OpenBao AppRole reconciliation uses a dedicated bootstrap identity | Accepted | security |
| [0022](0022-flypack-online-thin-edge-agent.md) | Flypack-online profile is a thin local edge agent paired to a cloud DMF hub | Proposed | architecture |
| [0023](0023-internal-service-dns-for-cross-app-wiring.md) | Cross-app HTTP wiring uses cluster-internal service DNS, not public URLs | Accepted | architecture / networking |
| [0024](0024-two-identity-admin-model.md) | Two-identity admin model + live-state read for K8s-Secret-backed admins | Accepted — **largely superseded by ADR-0028** (Identity & Authority Chain); §3 sanctioned exceptions preserved | operations |
| [0025](0025-ansible-in-cluster-pods-and-catalog-helm.md) | ★ Ansible runs in in-cluster pods using a Zot-hosted EE image; catalog functions deploy as Helm charts | Accepted | architecture / operations |
| [0026](0026-provider-descriptors.md) | Provider Descriptors as single source of truth for bootstrap integrations (one YAML per provider, read by wizard + roles + dmf-cms) | Proposed | architecture / operations |
| [0027](0027-catalog-instance-vs-definition-separation.md) | Separate catalog-entry, installation, and runtime-instance layers for media functions (defer reconciler until second catalog function) | Proposed (deferred) — **amended by ADR-0037** (instance layer in NetBox + AWX, not a CRD) | architecture |
| [0028](0028-identity-and-authority-chain.md) | ★ DMF Identity and Authority Chain — slogan, 5 contract statements, 8 decisions, sanctioned exceptions; supersedes ADR-0024 §Alternatives generalisation deferral | Accepted | architecture / security |
| [0029](0029-tiered-unseal-posture.md) | Tiered Unseal Posture (OSS) — three deploy-time tiers (quorum / operator / self-recovering) over an HA-bao+raft baseline + unseal kiosk; reframes ADR-0011 auto-unseal as "Tier 3, explicitly chosen". **Framework/posture only — implementation deferred** | Accepted (posture) | security |
| [0030](0030-console-i18n-and-airgap-posture.md) | Console i18n + air-gap/China posture — en/zh-Hans/zh-Hant co-equal, PO catalogs via self-hosted Forgejo+Weblate, self-hosted fonts + offline MT, fully self-contained runtime; re-opens Radix→React Aria | Proposed | architecture / ux |
| [0031](0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md) | OSS v0.1 release-profile matrix — canonical workflow contract with two lanes: `sandbox-single-node` (release gate) + `aws-arm64-multi-node` (parallel, eligible-if-ready); live Hetzner lab (`g2r6-foa9`) explicitly preserved as reference, not release. Original AWS-only draft preserved at §Historical | Accepted | release / provider / security |
| [0032](0032-catalog-launcher-scoped-netbox-writer.md) | Catalog launchers mutate NetBox via a scoped writer service account (`dmf-catalog-svc`), never the admin token; lifecycle tags pre-created at bootstrap. Refines ADR-0028 C3 (least-privilege machine identity) | Accepted | security / operations |
| [0033](0033-zot-scoped-machine-write-service-account.md) | Zot machine-write ops (seed/mirror) use a scoped native service account (`zot-svc`, push-only), never the `admin`/break-glass htpasswd user; `admin` demoted to dormant break-glass. Refines ADR-0028 C3+C4; sibling of ADR-0032 | Accepted | security / operations |
| [0034](0034-internal-ansible-collection-source.md) | No public Ansible Galaxy at runtime — collections resolve from internal **Forgejo git mirrors** (`type: git` in `requirements.yml`, pinned) + hermetic EE; Zot-OCI deferred until `ansible-galaxy` OCI matures. Honors ADR-0030 air-gap + ADR-0031 self-contained gate | Accepted | architecture / supply-chain |
| [0035](0035-operator-local-self-contained-envs.md) | ★ Every env (cloud + sandbox) is fully operator-local under `~/.dmfdeploy/envs/<env>/`; dmf-env becomes generic (scripts + `terraform/modules/` + one generic per-provider root + neutral tasks). Per-env SSH keys (privkey in the sops bundle); wizard does everything up to — not including — `tofu apply`; first-class teardown/remove. Extends ADR-0031 | Accepted | architecture / env-lifecycle |
| [0036](0036-dmf-init-thin-control-container.md) | ★ dmf-init is a **thin control-plane container**: bakes only the tool layer + the FastAPI/React app; **clones playbooks (dmf-env/dmf-infra/dmf-runbooks) at an operator-selected ref at runtime** into tmpfs (creds runtime-only, never baked); app images pulled from GHCR+upstream at bootstrap (mirrored to Zot by 630), **never baked**. Image is release-agnostic + public-safe; version coupling = the runtime-selected ref (recorded in the backup manifest). Air-gap (portable image bundle) deferred | Accepted | architecture / dmf-init |
| [0037](0037-media-workloads-netbox-instance-inventory.md) | Media Workloads = a NetBox-driven **Media Function instance inventory** (count + placement), scoped to a media-engineers group + tenant/site; **flows stay runtime-only** (never in NetBox); AWX reconciles cleared intent; k3s schedules. Amends ADR-0027 (instance layer in NetBox + AWX, not a CRD + operator) | Accepted (model); impl in flight | architecture |
| [0038](0038-netbox-driven-dynamic-monitoring.md) | NetBox-driven dynamic monitoring with a two-lane contract, standalone PromSD adapter, and continuous reconcile between NetBox and Kubernetes | Accepted | architecture / operations |
| [0039](0039-environment-identity-netbox-site-cluster.md) | An env's identity in NetBox is the per-env **Site + Cluster** plus the `dmf_env_id`/`dmf_env_label`/`dmf_provider`/`dmf_architecture` **custom fields** (written by born-inventory); consumers scope by Site/Cluster (or `cf_dmf_env_id`) and reach leaves by FK. **No per-env tag** (env ids rotate → tag sprawl; redundant; non-enforcing). The generic `dmf-day0` tag is env-agnostic | Accepted | architecture / console |
| [0040](0040-public-tls-tiering-and-dmfdeploy-io-psl.md) | Public-TLS tiering (own-domain / local-CA / dmfdeploy.io) to remove the CA-trust step: why sslip.io+LE fails (not on PSL → shared rate-limit), the PKI dead-ends (can't self-issue from a wildcard leaf / no public sub-CA), and the dmfdeploy.io **PSL design** (per-env registered domain = own LE bucket + site isolation; Cloudflare zone + DNS-01; broker vs acme-dns). Open hardening: attestation-gated issuance + hardware-inaccessible keys (reputation, not secrecy) | **Accepted** — OSS ships Tiers 1+2 only; dmfdeploy.io/Tier-3 **deferred to a future managed-service model**, kept separate to protect domain reputation | architecture / security / TLS |
| [0041](0041-release-and-contribution-model.md) | DMF Release and Contribution Model — GitHub-canonical-forward, DCO, retire Forgejo to archive, resolved external-contributor flow | Accepted | release / governance |
## Commitments

- ★ [architectural-commitments-v1](architectural-commitments-v1.md) (2026-06-06) — closes
  the ADR-0004 commit gate; freezes the v0.1 architecture (single-node/Flypack, AWX
  actuator, NetBox-tag lifecycle, dmf-init installer, public-safe split, rebuild-only)
  and names the explicit non-goals (federation, HA/cloud claim, Argo hybrid, in-place
  upgrade, media-v2). Not a numbered ADR — it's the standing commitment record that
  individual ADRs are now read *against*.

## Theme clusters & canonical pointer

Several ADRs accreted into clusters where current truth is spread across multiple
partially-superseding docs. When in doubt, **read the canonical ADR(s) first**; the
rest are history or context behind them.

| Cluster | Canonical — read this | History / context behind it |
|---|---|---|
| **Identity & authority** | **ADR-0028** (Identity & Authority Chain) · [digest](digests/identity-and-authority.md) | 0015 (passkey-only), 0021 (AppRole reconciler id), 0024 (largely superseded → 0028), 0032 (scoped NetBox writer) |
| **Catalog & execution** | **ADR-0013** (catalog model) + **ADR-0025** (in-cluster Helm) + **ADR-0038** (dynamic monitoring contract / PromSD bridge) · [digest](digests/catalog-and-execution.md) | 0014 (AWX layout), 0016 (Path A — partially superseded → 0025), 0027 (instance/definition split, deferred → amended by 0037), 0037 (Media Workloads — instances in NetBox), 0038 (monitoring contract and adapter) |
| **Secrets / unseal** | **ADR-0029** (tiered posture, directional) + **ADR-0009** (Shamir DR) · [digest](digests/secrets-and-unseal.md) | 0008 (OpenBao/ESO arch), 0011 (auto-unseal = today's Tier 3), 0031 (AWS-KMS = Tier 3 sub-variant) |
| **Deployment scope / release** | **ADR-0031** (OSS v0.1 release matrix) · [digest](digests/deployment-scope-and-release.md) | 0004 (experiment stance), 0018 (self-managed k3s), 0020 (three modes), 0022 (flypack-online), 0026 (provider descriptors, proposed) |

> Note: "canonical" means *the doc that states current truth for that scope* — it does
> not delete the others. Superseded ADRs are preserved for their decision history.

## Open decision debt (Proposed ADRs — not yet adopted)

Triaged 2026-06-04. These carry `Status: Proposed` and dangle without a forcing
function. Listed so they are not silently overlooked; **resolving them is an
operator decision**, not a hygiene task.

| ADR | Topic | Next step / note |
|---|---|---|
| 0020 (Mode B/C) | Managed `dmfdeploy.io` + flypack modes | Mode A is Accepted; B/C stay Proposed until a managed-service or flypack customer forces them. |
| 0022 | Flypack-online thin edge agent | Depends on a flypack customer; parked. |
| 0026 | Provider descriptors (one YAML/provider) | **Same problem, two sides:** the `init-wizard.sh` "provider-aware defaults" hardening stub (TODOS §init-wizard) is exactly what 0026 would formalize. Adopt 0026 ⇄ implement the wizard provider table together, or neither. |
| 0030 | Console i18n + air-gap posture | Re-opens Radix→React Aria; defer until i18n is on the console roadmap. |

## Portfolio reviews

- [DMF ADR Portfolio Review 2026-05-27](../reviews/DMF%20ADR%20Portfolio%20Review%202026-05-27.md)
  — cross-ADR review: contradictions, staleness, over-fragmentation, and
  suggested organizing actions. **CLOSED 2026-06-12** — §2/§6 applied
  (2026-05-30), §5 cosmetic nits fixed (2026-06-12); one standing
  enforcement-gap item noted.

## Adding an ADR

1. Copy `0000-template.md` to `NNNN-short-title.md` with the next number.
2. Fill in the four sections (context, decision, consequences, alternatives).
3. Add a row to the table above.
4. Commit. Update any skills or CLAUDE.md files that should reference the new ADR.

If an ADR supersedes an earlier one, set the earlier one's status to **Superseded**
and link forward; do not delete it.
