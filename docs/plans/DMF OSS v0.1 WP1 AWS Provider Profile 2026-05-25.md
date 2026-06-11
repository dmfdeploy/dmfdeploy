---
status: historical
date: 2026-05-25
---
# DMF OSS v0.1 WP1A — AWS ARM64 Multi-Node Lane

> **⚠️ RE-SCOPED (2026-05-25): this is WP1A, a SECONDARY lane — not the v0.1
> gate.** Under [ADR-0031](../decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md)
> and [WP0](DMF%20OSS%20v0.1%20WP0%20Release%20Contract%20and%20Profile%20Matrix%202026-05-25.md):
> - `aws-arm64-multi-node` is **secondary, eligible-if-ready**. It ships in the
>   v0.1 tag only if it passes its gates **without delaying** the sandbox lane.
>   It **never gates** v0.1 and **must not be sequenced ahead of**
>   [WP1S (Single-Node Sandbox)](DMF%20OSS%20v0.1%20WP1S%20Single-Node%20Sandbox%20Lane%202026-05-25.md),
>   which is the release gate and center of gravity.
> - The original outcome line below ("AWS is the **only** supported v0.1
>   provider profile") is **void**. AWS is one lane of three, not the contract.
> - The Terraform skeleton (Phase 2 / §9) is **`tofu validate`-clean and
>   template-complete, NOT plan-proven.** A real `tofu plan`/apply requires an
>   explicit operator-named AWS profile/account, a real Route53 zone, and a
>   read-only preflight. Do not infer credentials or run an opportunistic plan.
> - Headscale (in-cluster, OIDC-wired, `hs.<base_domain>`) and ntfy
>   (`ntfy.<base_domain>`) remain **mandatory for this lane** — they are AWS-lane
>   requirements, not sandbox requirements.
> - DMF Console stays **passkey-only** ([ADR-0015](../decisions/0015-dmf-console-passkey-only.md)); SNS/OTP here is for out-of-band/step-up, never console login.
>
> The AWS/network/IAM/boot material below remains technically useful for this
> lane; only its release-gating status changed. Filename kept (`...WP1 AWS
> Provider Profile...`) for cross-link stability; the work package is **WP1A**.

**Status:** Active — secondary lane (eligible-if-ready, non-gating)
**Date:** 2026-05-25
**Anchor:** [WP0 Release Contract & Profile Matrix](DMF%20OSS%20v0.1%20WP0%20Release%20Contract%20and%20Profile%20Matrix%202026-05-25.md)
**Parent mission (superseded):** [DMF OSS v0.1 Release Mission 2026-05-25.md](DMF%20OSS%20v0.1%20Release%20Mission%202026-05-25.md)
**Outcome (re-scoped):** AWS ARM64 multi-node is a fully provisionable, verifiable
**secondary** v0.1 lane — compute, DNS (Route53), object storage (S3), SNS,
TLS DNS-01, KMS auto-unseal, in-cluster Headscale + ntfy — that ships only if it
passes its gates without delaying the sandbox release gate.

---

## 1. Problem

The current implementation still asks for or assumes multiple external
providers:

- Hetzner/Aliyun for compute.
- Cloudflare for DNS and cert-manager DNS-01.
- Backblaze B2 for object storage.
- External Headscale for private networking.
- Public ntfy.sh for notifications.

The init wizard already exposes `aws` as a provider option, but AWS is not
implemented as a full Terraform/bootstrap path. For v0.1 this needs to be a
real provider profile, not a placeholder.

---

## 2. Goals

> **Note:** the historical body below contains stale goal/scope statements from
> the AWS-only draft. **The banner at the top of this doc controls.** Item 1 is
> struck because AWS is a *secondary* lane, not the only v0.1 provider.

1. ~~Define AWS as the only supported v0.1 release provider.~~ **(VOID — AWS is
   the `aws-arm64-multi-node` secondary lane; the v0.1 gate is
   [WP1S](DMF%20OSS%20v0.1%20WP1S%20Single-Node%20Sandbox%20Lane%202026-05-25.md).)**
   Read this WP's goal as: *make AWS a fully provisionable, verifiable secondary
   lane that ships only if it passes without delaying the sandbox.*
2. Provision EC2-backed k3s infrastructure from Terraform/OpenTofu.
3. Provision Route53 records for the release domain.
4. Provision S3 buckets for audit/archive/snapshot/app-backup uses.
5. Provision SNS topics/subscriptions for platform alerts and optional
   OTP/SMS/email delivery.
6. Configure cert-manager to use Route53 DNS-01.
7. Make the init wizard collect only release-required provider inputs.
8. Remove Cloudflare/B2/Hetzner/Aliyun credentials from the v0.1 required path.
9. Add provider verification so drift is caught before release.

---

## 3. Non-Goals

- Supporting every AWS topology.
- Migrating existing Hetzner/Aliyun environments.
- Maintaining feature parity with legacy provider paths.
- Building a multi-provider abstraction beyond what v0.1 needs.
- Solving in-cluster Headscale or ntfy; those are WP3.
- Solving OpenBao boot independence; that is WP2, though it depends on AWS
  KMS/IAM outputs from this package.

---

## 4. Current State

Relevant files:

- `dmf-env/bin/init-wizard.sh`
- `dmf-env/bin/bootstrap-secrets.sh`
- `dmf-env/bin/b2-buckets.sh`
- `dmf-env/terraform/modules/hetzner`
- `dmf-env/terraform/modules/aliyun`
- `dmf-infra/k3s-lab-bootstrap/providers/tailscale.yaml`
- `dmf-infra/k3s-lab-bootstrap/roles/base/cert-manager/tasks/main.yml`
- `docs/decisions/0026-provider-descriptors.md`
- `docs/architecture/DMF Provider Descriptor Model.md`

Observed gaps:

- AWS provider selection exists in the wizard, but Terraform generation is
  explicitly missing.
- There is no AWS Terraform module for network, EC2, IAM, Route53, or S3.
- There is no AWS SNS alert or OTP delivery substrate.
- DNS publishing is Cloudflare-shaped.
- cert-manager only has the current Cloudflare/HTTP-01 release behavior.
- B2 bucket creation is a Backblaze-native script.
- Provider descriptors are still mostly conceptual; only Tailscale exists as
  an implemented descriptor.

---

## 5. Implementation Phases

### Phase 1 - Release provider contract (operator-confirmed 2026-05-25)

[ADR-0031](../decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md)
already serves as the "narrow v0.1 ADR" this phase originally called for; the
contract below is its WP1 operational expansion. Operator decisions and Codex
review constraints (both recorded 2026-05-25) are folded in. Conflicts with
ADR-0031/ADR-0018 are flagged inline and summarized in §1.10.

#### 1.1 Compute / architecture

- **ARM64 (AWS Graviton).** Rationale: the current lab is already ARM64
  (Hetzner CAX21) and the four DMF-built images are built `linux/arm64`.
- One Graviton general-purpose instance family for v0.1 (e.g. `m7g`/`t4g`
  class); do not enumerate a multi-family matrix.
- **Release gate (Codex):** an explicit **`linux/arm64` image-availability
  gate**. Every release-path container image must publish a `linux/arm64`
  manifest. Enumerate and verify the full set — DMF-built (`awx-ee`,
  `dmf-cms`, `nmos-cpp-registry`, `nmos-cpp-node` — already arm64) plus
  third-party (Authentik, NetBox, Forgejo, Zot, OpenBao, ESO, cert-manager,
  Traefik, kube-prometheus-stack + Alertmanager, ntfy, Headscale). WP5
  verification fails if any release image lacks an arm64 manifest. This gate
  is owned by WP5 but defined here because it is a precondition of choosing
  Graviton.
- **Architecture policy (operator + Codex, 2026-05-25) — ARM64 is the fixed
  v0.1 baseline, enforced as scheduling policy:**
  - All DMF-owned images are ARM64 today and stay ARM64; the **default
    release node pool is ARM64**. The cluster's default architecture does not
    change.
  - If an absolute AMD64 requirement ever appears, it is handled by adding
    **specifically labelled/tainted AMD64 nodes**, never by flipping the
    default cluster architecture.
  - Any such future AMD64 nodes must carry a node label and a taint; workloads
    that genuinely need AMD64 opt in explicitly via `nodeSelector`/affinity
    plus matching `tolerations`. This keeps core ARM64 workloads from drifting
    onto AMD64 nodes. v0.1 ships ARM64-only, but the scheduling discipline is
    encoded now so the door is one-way safe.

#### 1.2 Network topology

- **Public/private subnet split, single-AZ for v0.1.** The split is kept
  because future special MXL media nodes may need it; it is **not** expanded
  to multi-AZ/HA now (mission §7 risk — keep v0.1 minimal).
- Public subnet: NLB + a single NAT gateway.
- Private subnet: k3s nodes, no public IPs.
- S3 reached via a **VPC gateway endpoint** (free). KMS/SNS/Route53 and image
  egress (GHCR/Zot) go via NAT for v0.1; interface endpoints are deferred as
  cost/overbuild.

#### 1.3 Ingress / TLS

- External ingress: AWS **Network** Load Balancer (L4 TCP passthrough) in the
  public subnet, forwarding to Traefik. Traefik terminates TLS in-cluster;
  cert-manager issues certificates via **Route53 DNS-01**.
- **⚠️ Conflict flag (ADR-0031):** the operator said "AWS Load Balancer." An
  **ALB (L7) + ACM** would terminate TLS at the load balancer and make
  cert-manager Route53 DNS-01 redundant — that contradicts ADR-0031
  §Enforcement ("cert-manager release defaults must use Route53 DNS-01").
  **Resolution: use an NLB in passthrough mode, not an ALB**, so Traefik +
  cert-manager + DNS-01 remain the TLS authority. The operator's "Traefik
  still able to route in-cluster behind it" is satisfied exactly by NLB
  passthrough. **Confirmed (operator + Codex, 2026-05-25): NLB passthrough.**
  AWS owns the external L4 entrypoint; Traefik + cert-manager remain the
  in-cluster TLS/routing authority.
- LB/SG must leave room for the ports Headscale needs at `hs.<base_domain>`
  (443 for control plane + OIDC; embedded DERP over 443 for v0.1, avoiding
  extra UDP DERP ports). Detailed in WP3.

#### 1.4 Bootstrap reachability (new — surfaced by the subnet split)

- **⚠️ Conflict flag (ADR-0031):** private-subnet nodes combined with
  ADR-0031's rule that "node Tailscale join must move after Headscale is
  reachable" creates a chicken-and-egg — Ansible must reach the nodes to
  bootstrap them *before* Headscale/Tailscale exists, but private nodes have
  no public IP.
- **Resolution — confirmed (operator + Codex, 2026-05-25): AWS SSM Session
  Manager is the primary bootstrap exec/SSH path** — IAM-gated, no public SSH,
  no bastion, reaches private subnets, and dovetails with the node instance
  profile (§1.8). This removes the Headscale chicken-and-egg cleanly. The
  temporary public-subnet control node (SG locked to the operator IP) remains
  **fallback only**. WP1 provisions the SSM path: the
  `AmazonSSMManagedInstanceCore` permission set on the node profile, and —
  because Debian AMIs do **not** ship `amazon-ssm-agent` — cloud-init installs
  and enables the arm64 agent at boot. Two further prerequisites the Phase-2
  skeleton now carries (Codex review 2026-05-25): the `aws_ssm` Ansible
  connection plugin stages files through an **S3 transfer bucket**
  (`dmf-ssm-transfer-<env>`, created in WP1 Phase 2 — not deferred to Phase 4
  with the audit/snapshot/backup buckets, or Phase 2 could not run Ansible over
  SSM), and the node `metadata_options` use **IMDSv2 with hop limit 2** (see
  §1.8). VPC interface endpoints for SSM are deferred unless NAT egress proves
  insufficient.

#### 1.5 DNS

- Route53 hosted zone for `base_domain`. The zone may be pre-existing
  (operator-owned) or Terraform-created; record management is scoped to that
  zone. Release-required hostnames: `hs.<base_domain>` (Headscale),
  `ntfy.<base_domain>` (ntfy), plus existing console/app hosts.

#### 1.6 Object storage

- S3 buckets for audit archive / OpenBao snapshots / app backups (Phase 4),
  SSE-default on. Replaces Backblaze B2 on the release path.

#### 1.7 Out-of-band messaging

- SNS topics for platform/security alerts and optional OTP delivery (Phase 5).
  SNS/SMS is fallback or step-up only, never the sole admin factor.

#### 1.8 IAM model (two identities, least-privilege)

- **Bootstrap/provisioning identity** (operator-run `tofu`): EC2 + VPC + NAT +
  route tables, IAM (create the node role / instance profile), Route53, S3,
  SNS, and KMS create/alias/grant.
- **Node instance profile** (runtime, attached to the EC2 nodes):
  - KMS `Encrypt`/`Decrypt`/`GenerateDataKey`/`DescribeKey` on the OpenBao
    seal key **only** — auto-unseal via IMDS, consumed by WP2.
  - S3 read/write scoped to the release buckets.
  - SNS `Publish` scoped to the release topics.
  - Route53 `ChangeResourceRecordSets` on the zone (cert-manager DNS-01 uses
    ambient IMDS credentials — see §1.10 on why there is no IRSA).
- **Honest trade (per ADR-0031's documentation requirement):** k3s is not EKS,
  so there is **no IRSA / per-pod credential scoping**. Any pod scheduled on a
  node can assume the node profile via IMDS. v0.1 accepts node-level scoping;
  per-pod isolation (kube2iam / IRSA-on-k3s) is overbuild and deferred. IMDSv2
  is required, with **hop limit 2** — pods reach IMDS across an extra
  network-namespace hop, so hop limit 1 would break the very ambient-credential
  model this section relies on (OpenBao unseal, cert-manager DNS-01,
  Alertmanager→SNS). Hop limit 2 widens IMDS reachability to every pod on the
  node; that is the same node-level scoping trade, stated honestly here rather
  than hidden behind a tighter-looking-but-broken hop limit 1 (Codex review
  2026-05-25).

#### 1.9 Legacy provider prompts

- The wizard makes `aws` the default and only release path. Cloudflare / B2 /
  Hetzner / Aliyun prompts move behind an explicit non-release flag (e.g.
  `--experimental`) and are not shown on the v0.1 release path.

#### 1.10 ADR alignment / conflict summary

- **ADR-0018 (self-managed k3s, not EKS):** Graviton + self-managed k3s is
  fully compatible (the lab already runs self-managed k3s on ARM64). The
  no-EKS rule is *why* there is no IRSA, which drives the node-instance-profile
  IAM model in §1.8. **No conflict.**
- **ADR-0031 — architecture:** ADR-0031 does not pin an architecture, so ARM64
  is an allowed refinement. The new obligation it adds is the §1.1 arm64
  image-availability release gate.
- **ADR-0031 — load balancer:** resolved by choosing **NLB passthrough** over
  ALB+ACM specifically to preserve ADR-0031's cert-manager Route53 DNS-01
  enforcement (§1.3).
- **ADR-0031 — Headscale / ntfy / kiosk / KMS unseal:** `hs.<base_domain>`,
  `ntfy.<base_domain>`, kiosk-not-a-hard-gate, and KMS auto-unseal are all
  consistent and restated here so WP1's network/LB/IAM provisioning leaves
  room for them (LB ports for Headscale, KMS key + node-profile grant for
  WP2). **No conflict.**
- **Keeping `g2r6-foa9` (Hetzner) live as the lab:** explicitly sanctioned by
  ADR-0031 ("Non-AWS providers may remain in the repository as lab, legacy, or
  experimental paths"). AWS is built as a separate greenfield env. **No
  conflict.**

Acceptance:

- A reviewer can tell exactly which provider inputs are required for v0.1.
- Existing Cloudflare/B2/Hetzner/Aliyun paths are clearly marked non-release
  or experimental.
- The `linux/arm64` image-availability gate is enumerated and owned by WP5.
- The load-balancer decision is recorded as NLB-passthrough with its
  ADR-0031 DNS-01 rationale.
- The bootstrap-reachability mechanism for private-subnet nodes is named
  (SSM Session Manager, fallback bastion).

### Phase 2 - Terraform/OpenTofu AWS substrate

Add an AWS Terraform module that creates:

- VPC and subnets.
- Security groups.
- EC2 instances for the k3s nodes.
- IAM instance profile for node duties.
- SNS topics for platform/security alerts and optional OTP delivery.
- Optional EBS volume settings required by storage.
- Route53 zone lookup or creation strategy.
- Outputs needed by Ansible inventory generation.

Open decisions:

- One public subnet only vs public/private subnet split.
- Whether to use Elastic IPs or DNS-only addressing.
- Whether to introduce an AWS load balancer or keep k3s/Traefik exposure
  simple for v0.1.

Acceptance:

- `tofu plan` and `tofu apply` can produce an inventory-compatible AWS
  environment.
- Outputs are stable enough for `bin/run-playbook.sh`.

### Phase 3 - Route53 and cert-manager

- Replace release-path Cloudflare DNS records with Route53 records.
- Add cert-manager Route53 DNS-01 solver configuration.
- Store only the required AWS IAM/role data for DNS automation.
- Update verification to prove DNS and TLS are working.

Acceptance:

- A new environment obtains valid TLS certificates without a Cloudflare token.
- No release-path inventory var requires `cloudflare_*`.

### Phase 4 - S3 object storage

- Replace B2 buckets with S3 buckets for:
  - audit archive
  - OpenBao snapshots
  - app backups
- Enable encryption by default.
- Add lifecycle rules.
- Decide whether audit archive requires object lock in v0.1.
- Replace or bypass `b2-buckets.sh` for the release path.

Acceptance:

- A new environment can write/read release-required objects from S3.
- No release-path script requires B2 key material.

### Phase 5 - SNS alert and MFA delivery substrate

- Create SNS topics for platform alerts and security-sensitive events.
- Define topic/subscription conventions for release installs.
- Define SMS/email usage for OTP or MFA fallback, subject to the WP4 MFA
  policy.
- Grant only the minimal publish permissions needed by in-cluster producers.
- Expose SNS topic ARNs and region through inventory/bootstrap outputs.

Acceptance:

- A release install can publish a test platform alert through SNS.
- MFA/OTP delivery has a documented AWS-side substrate if enabled.
- SNS permissions do not require broad administrator credentials at runtime.

### Phase 6 - Init wizard and bootstrap bundle

- Make AWS the default and only release-supported provider.
- Remove release prompts for Cloudflare and B2.
- Capture SNS subscription targets or explicitly mark them as post-install
  admin configuration.
- Render AWS Terraform root config.
- Render AWS-specific inventory vars.
- Render bootstrap bundle metadata with provider `aws`.
- Add clear errors if an operator selects a non-release provider.

Acceptance:

- The wizard creates a complete AWS release environment bundle.
- The generated next steps do not mention Cloudflare, B2, Hetzner, or Aliyun
  for the v0.1 path.

### Phase 7 - Verification and docs

- Add a provider-profile verification play or role.
- Verify Route53, S3, and SNS as first-class AWS release resources.
- Update `STATUS.md` generation if it needs provider-specific reporting.
- Update release docs and README entrypoints.
- Add a "legacy providers" note so existing lab paths are not confused with
  the public release path.

Acceptance:

- WP5 can run a greenfield AWS install using only the documented AWS inputs.

---

## 6. Dependencies

- WP2 needs AWS IAM/KMS choices from this package.
- WP3 needs Route53/TLS assumptions for `ntfy.<base_domain>` and mandatory
  `hs.<base_domain>` ingress.
- WP5 needs the wizard and Terraform outputs to be stable.

---

## 7. Risks

- AWS IAM scope can sprawl if every service asks for broad credentials.
- Route53 hosted-zone ownership must be clear for OSS users.
- Object lock can be operationally surprising; include only if the release
  audit posture requires it.
- Multi-AZ/high-availability design can expand quickly. Keep v0.1 minimal.

---

## 8. Done Definition

WP1 is done when a fresh AWS environment can be provisioned and handed to the
existing bootstrap playbook sequence without any non-AWS provider credential.

---

## 9. Progress / Status (2026-05-25)

- **Phase 1 — provider contract: confirmed.** §1.1–1.10 above carry the
  operator + Codex decisions (ARM64/Graviton baseline + scheduling policy, NLB
  passthrough, SSM primary bootstrap, single-AZ public/private split, KMS
  auto-unseal, no-IRSA node-profile IAM). ADR-0031 is the binding ADR.
- **Phase 2 — Terraform substrate skeleton: landed, Codex-reviewed (no
  remaining objections).** `dmf-env/terraform/modules/aws/cluster/` — VPC +
  public/private subnets + NAT + S3 gateway endpoint, Graviton EC2 (no public
  IP, IMDSv2 hop-limit 2, SSM agent via cloud-init), node SG opening the
  Traefik NodePorts, NLB L4 passthrough, least-priv node IAM, KMS unseal key,
  SNS topics, Route53 zone lookup + two-phase alias records, and the
  `dmf-ssm-transfer-<env>` bucket required by the `aws_ssm` Ansible transport.
- **Phase 6 (partial) — reference root + sample manifest: landed.**
  `terraform/aws-sample/` + `manifests/aws-sample.yaml`. The full graph is
  **`tofu validate`-clean and template-complete, but NOT plan-proven.** A real
  `tofu plan` hits live AWS APIs (Debian-arm64 AMI lookup, `aws_route53_zone`,
  `aws_availability_zones`) and exposes cost-bearing intent (EC2/NAT/NLB/KMS/
  S3/SNS), so it requires an explicit operator-named account/profile + region.
  Do not infer credentials from the workstation or run an opportunistic live
  plan (Codex + claude-bottom, 2026-05-25).
- **Gating for plan/apply (when the operator wants it):**
  1. Operator names the AWS profile/account (e.g. `AWS_PROFILE=dmf-oss-dev`).
  2. Operator names the real Route53 zone / base domain, or confirms a
     disposable test zone (`example.com` in the sample is template-only).
  3. Read-only preflight first: STS caller identity, Route53 zone lookup,
     region/AZ availability, expected AMI lookup.
  4. `tofu plan` only (no apply) against a **copied real env root/manifest**,
     not `aws-sample`.
- **Scope caveat:** ADR-0031 is accepted with AWS as the secondary
  eligible-if-ready lane. The AWS root/apply stays the AWS-lane proof point and
  is **not** promoted to a hard v0.1 gate. The sandbox contract is defined first.
- **Component repo state:** the AWS module/root/manifest work described above
  lives in `dmf-env` and remains outside this umbrella docs commit unless
  committed separately in that repo.
