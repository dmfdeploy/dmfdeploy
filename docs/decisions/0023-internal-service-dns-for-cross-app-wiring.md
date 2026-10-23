# ADR-0023: Cross-app HTTP wiring uses cluster-internal service DNS by default, instead of public URLs

**Status:** Accepted
**Date:** 2026-05-14
**Deciders:** @<handle> (decided during the 2026-05-13/14 bootstrap-configure debugging session)
**Related:** ADR-0006 (cluster is the truth), ADR-0010 (run-playbook as sanctioned entry), ADR-0019 (Tailscale CGNAT vs cloud-internal services), commit `dmf-infra@3457513` (first application), `docs/plans/DMF App Admin Account Drift Audit and Realignment Plan 2026-05-14.md`.

**Rule:** Cross-app HTTP wiring uses cluster-internal service DNS by default. A public URL is not the default for cross-app wiring.

## Context

Multiple `bootstrap-configure.yml` runs on 2026-05-13/14 failed with
public-URL DNS resolution and connectivity issues.

Problem statement and evidence: see the [archive record](../archive/decisions/0023-internal-service-dns-for-cross-app-wiring.md).

## Decision

**Cross-app HTTP wiring uses cluster-internal service DNS by default.
A public URL is not the default for cross-app wiring.**

Concretely:

1. Any Ansible task, role default, or playbook that makes an HTTP call
   from one cluster app to another sets the URL default to
   `http://<svc>.<ns>.svc.cluster.local:<port>`: plain HTTP, internal
   service DNS, no `dmf.example.com` placeholders.
2. The per-env override knob (`<role>_api_url`, `<app>_internal_host`,
   etc.) remains, so an env can point to an external endpoint for
   testing or off-cluster validators. The **default works
   out-of-box** on any cluster where the services exist.
3. Public URLs (with TLS, ingress, valid cert) are reserved for
   **user-facing flows only**:
   - Browser UI links shown to humans
   - OIDC redirect URIs (must match what the IdP has registered)
   - Webhook callbacks that originate outside the cluster
   - Anything documented in the apps' UI/UX

### Scope (amended 2026-05-14 after run-11 caller-location discovery)

The principle applies to **calls whose caller runs inside the cluster**.
Concretely:

| Caller location | URL needed | ADR-0023 applies? |
|---|---|---|
| **Pod-to-pod runtime**: a pod making an HTTP call to another pod's service (for example dmf-cms to the NetBox API at runtime; NetBox worker to Forgejo for datasource sync) | Internal service DNS | **Yes. Use `http://<svc>.<ns>.svc.cluster.local:<port>`** |
| **Ansible `uri:` / `kubernetes.core.*` running from a control-node target**: provisioning tasks invoked by `bin/run-playbook.sh` against `k3s_control[0]` (for example the 691-699 chain) | Public URL via ingress | **No. These tasks resolve DNS via the node's `/etc/resolv.conf`, which has no path to CoreDNS. They need `https://<public-host>` derived from the env's `*_host` var.** |
| **Anything outside the cluster network**: operator browser, off-cluster validators, webhook senders | Public URL | **No. Out of architectural scope** |

When in doubt, the test is: **who actually opens the TCP
connection?** That caller's location decides which URL the default
should use.

## Consequences

**Positive:** env-independent defaults, and bootstrap works before cert-manager, ingress and MetalLB are warm.

**Negative**
- ALLOWED_HOSTS / nginx host-header settings must accept the internal
  hostname (verified for NetBox/AWX/Forgejo on aliyun-123; future apps
  must be checked at install time)
- Risk of an internal URL leaking into a user-facing render. It is easy to
  catch in review, but a real anti-pattern to watch for
- For off-cluster validators (for example a remote SoT validator hitting NetBox),
  the override path must remain functional and documented

### Enforcement

- discipline only: no automated check enforces this rule. Reviews on `dmf-infra`
  playbook/role changes flag any new HTTP default referencing `dmf.example.com`
  or a `*_host` external variable for cross-app wiring. The reviewer asks "is
  this user-facing or app-to-app?" and points at this ADR for the app-to-app
  answer.

## Status

Accepted

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0023-internal-service-dns-for-cross-app-wiring.md).
