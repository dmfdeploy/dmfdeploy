---
status: executed
date: 2026-05-25
---
# DMF OSS v0.1 WP3 - In-Cluster Platform Services

> **⚠️ RE-SCOPED (2026-05-25): split / trimmed by profile.** Under
> [WP0](DMF%20OSS%20v0.1%20WP0%20Release%20Contract%20and%20Profile%20Matrix%202026-05-25.md) /
> [ADR-0031](../decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md):
> - **`sandbox-single-node` (the gate):** **no Headscale requirement**
>   (sandbox-local comms on one node). **ntfy is optional / lightweight / stub**
>   depending on whether the CMS/alert path actually needs it for the gate. **No
>   SNS.** Monitoring trimmed. See [WP1S](DMF%20OSS%20v0.1%20WP1S%20Single-Node%20Sandbox%20Lane%202026-05-25.md).
> - **`aws-arm64-multi-node` (secondary):** the full content below applies —
>   in-cluster **Headscale** wired to **Authentik/OIDC** at `hs.<base_domain>`,
>   in-cluster **ntfy** at `ntfy.<base_domain>`, and **SNS** as an optional
>   out-of-band alert/step-up path. Headscale stays **mandatory for this lane.**
> - DMF Console stays **passkey-only** ([ADR-0015](../decisions/0015-dmf-console-passkey-only.md)); SNS/OTP is never console login.
>
> Read the Headscale / SNS / ntfy-ingress sections below as **AWS-lane work**,
> not sandbox gate work.

**Status:** Active — split/trim by profile (sandbox-trim / AWS-full)
**Date:** 2026-05-25
**Anchor:** [WP0 Release Contract & Profile Matrix](DMF%20OSS%20v0.1%20WP0%20Release%20Contract%20and%20Profile%20Matrix%202026-05-25.md)
**Parent mission (superseded):** [DMF OSS v0.1 Release Mission 2026-05-25.md](DMF%20OSS%20v0.1%20Release%20Mission%202026-05-25.md)
**Outcome:** Release-required platform services are provided by the cluster —
**sandbox trims Headscale + heavy ntfy/SNS; AWS gets in-cluster Headscale/OIDC,
ntfy, and SNS.**

---

## 1. Problem

Two current platform dependencies are not self-contained:

- ntfy is consumed through external/public URLs.
- Headscale is assumed as an external server while nodes join Tailscale early
  in the bootstrap sequence.
- There is no AWS SNS alert path for provider-native out-of-band messaging.

For v0.1, ntfy should be brought into the cluster and AWS SNS should provide
an out-of-band message path. Headscale is mandatory, must be brought into the
cluster, and must use Authentik/OIDC for human authentication. This requires
moving node Tailscale join later than its current early pre-seed position.

---

## 2. Goals

1. Deploy ntfy in-cluster for release notifications.
2. Provision and consume AWS SNS for out-of-band platform/security alerts.
3. Rewire Authentik/passkey, MFA/OTP, and Alertmanager notification producers
   to use the approved ntfy/SNS paths.
4. Deploy Headscale in-cluster after base cluster readiness.
5. Wire Headscale to Authentik/OIDC for human login and authorization.
6. Move Tailscale client join after Headscale is reachable.
7. Replace external Headscale cleanup with in-cluster administration.
8. Update playbook sequencing so platform services are ordered by real
   dependency, not historical placement.

---

## 3. Non-Goals

- Building a full notification preferences system.
- Supporting public ntfy.sh as a release dependency.
- Replacing all monitoring/alerting.
- Solving AWS provider work; that is WP1.

---

## 4. Current State

Relevant files:

- `dmf-infra/k3s-lab-bootstrap/playbooks/321-tailscale.yml`
- `dmf-infra/k3s-lab-bootstrap/playbooks/322-headscale-cleanup.yml`
- `dmf-infra/k3s-lab-bootstrap/roles/base/tailscale/tasks/main.yml`
- `dmf-infra/k3s-lab-bootstrap/roles/base/prometheus/defaults/main.yml`
- `dmf-infra/k3s-lab-bootstrap/roles/base/prometheus/tasks/main.yml`
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/defaults/main.yml`
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/tasks/main.yml`
- `dmf-infra/k3s-lab-bootstrap/bootstrap-provision-pre-seed.yml`
- `dmf-infra/k3s-lab-bootstrap/bootstrap-provision-post-seed.yml`

Observed gaps:

- No ntfy role/chart/deployment exists.
- No SNS topic/subscription path exists for release alerts or OTP delivery.
- Authentik defaults still allow public ntfy topic URLs.
- Prometheus uses an ntfy bridge but points at configured external URLs.
- Tailscale client setup currently runs before the cluster could host
  Headscale.
- Headscale cleanup assumes SSH to an external Headscale host.
- Headscale is not currently integrated with Authentik/OIDC in the release
  path.

---

## 5. ntfy Implementation Phases

### Phase 1 - ntfy role/chart

- Add a `stack/operator/ntfy` role or Helm integration.
- Create namespace, deployment/stateful workload, service, persistence, and
  ingress.
- Expose ntfy at `ntfy.<base_domain>` for browser/mobile/external subscribers.
- Decide topic/auth posture for v0.1.
- Configure retention and resource limits.

Acceptance:

- ntfy is reachable at `ntfy.<base_domain>` and through internal service DNS
  for in-cluster producers.
- ntfy survives pod restart if persistence is enabled.

### Phase 2 - Producers

- Point Authentik enrollment/passkey notifications at in-cluster ntfy.
- Point Alertmanager ntfy bridge at in-cluster ntfy.
- Remove public `ntfy.sh` defaults from release inventory.
- Add smoke tests for publish and subscription behavior.

Acceptance:

- A passkey/invite notification can be published without external ntfy.
- Alertmanager can publish a test notification without external ntfy.

### Phase 3 - Sequence placement

- Place ntfy before Authentik if Authentik sends enrollment notifications.
- Place ntfy before Prometheus/Alertmanager bridge if alerts use it.
- Ensure SNS topic ARNs/region are available before producers are configured.
- Update `bootstrap-provision-post-seed.yml` or successor lifecycle file.

Acceptance:

- Playbook ordering reflects real producer/consumer dependencies.

---

## 6. AWS SNS Alert Path

SNS is provider-native rather than in-cluster, but it belongs in this package
because it is part of the platform notification contract.

Expected uses:

- Platform health alerts.
- Security-sensitive events such as admin role changes, failed MFA spikes, and
  OpenBao recovery actions.
- Optional OTP/SMS/email delivery for MFA fallback or step-up flows defined in
  WP4.

Implementation work:

- Consume SNS topic ARNs from WP1 outputs.
- Add inventory variables for alert topics and optional OTP topics.
- Wire Alertmanager or the ntfy bridge to publish to SNS where appropriate.
- Wire Authentik/CMS MFA delivery to SNS only through the policy approved in
  WP4.
- Add a smoke test that publishes a release test message.

Acceptance:

- A v0.1 install can deliver an out-of-band alert using AWS SNS.
- SNS is not used as the only admin authentication factor.

---

## 7. Headscale In-Cluster Requirement

Actions:

- Add a `stack/operator/headscale` role/chart.
- Deploy after k3s, ingress, cert-manager, storage, and the required secret
  substrate are healthy.
- Expose Headscale at `hs.<base_domain>`.
- Register Headscale as an Authentik/OIDC client.
- Map Authentik groups/claims to the allowed Headscale users or groups.
- Store Headscale OIDC client secret in OpenBao and deliver it through ESO.
- Generate or manage preauth keys in-cluster only where they are still needed
  for node join automation.
- Move node Tailscale client join after Headscale is reachable.
- Replace SSH-to-external cleanup with an in-cluster admin Job or API call.
- Add verification for OIDC login/config, node registration, and cleanup.

Acceptance:

- Headscale is not needed before it exists.
- Headscale is reachable at `hs.<base_domain>`.
- Headscale human authentication uses Authentik/OIDC, not a standalone local
  identity source.
- Node join occurs after in-cluster Headscale is healthy.
- The bootstrap sequence no longer requires an external Headscale host.
- A v0.1 install succeeds without pre-existing Headscale URL/auth key from
  outside the cluster.

---

## 8. Dependencies

- WP1 provides Route53/TLS assumptions for public service endpoints.
- WP1 provides SNS topics, IAM, and inventory outputs.
- **AWS ingress requires Traefik on fixed NodePorts (WP1 NLB decision,
  2026-05-25).** The WP1 AWS Terraform module
  (`dmf-env/terraform/modules/aws/cluster`) provisions an L4 NLB that forwards
  only the Traefik HTTP/HTTPS NodePorts (default 30080/30443, exposed as the
  module's `traefik_nodeports` output). k3s's default Traefik is a klipper
  ServiceLB; on the AWS profile the bootstrap/ingress role **must pin Traefik's
  Service to those fixed NodePorts** or external ingress breaks. This affects
  every `*.<base_domain>` host WP3 adds — `hs.<base_domain>` (Headscale) and
  `ntfy.<base_domain>` (ntfy) both reach the cluster over 443 → the HTTPS
  NodePort → Traefik. Verify the NodePort pinning before exposing WP3 services.
- WP2 provides the secret boot path consumed by ntfy/Auth/Headscale.
- WP4 may depend on ntfy for invite/signup notifications.
- WP4 defines the MFA policy for SNS-backed OTP use.
- WP4 defines the user/group model Headscale consumes through Authentik/OIDC.
- WP5 verifies in-cluster Headscale OIDC, registration, and cleanup.

---

## 9. Risks

- In-cluster Headscale can create a bootstrap loop if node access depends on
  Headscale before Headscale is deployed.
- Headscale OIDC group mapping can drift from CMS roles if it is not tied to
  the same Authentik group model.
- Notification auth can be underdesigned if all topics are public. Decide
  topic ACLs early.
- SMS OTP is weaker than passkeys/TOTP. Treat SNS SMS as fallback or step-up
  delivery, not the whole admin security model.
- ntfy persistence may be overkill for transient invite links; decide what
  data actually needs durable storage.

---

## 10. Done Definition

WP3 is done when v0.1 uses in-cluster ntfy and AWS SNS for the approved
notification paths, and Headscale is implemented in-cluster with Authentik/OIDC
without a bootstrap loop.
