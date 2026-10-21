# ADR-0023: Cross-app HTTP wiring uses cluster-internal service DNS, not public URLs

**Status:** Accepted
**Date:** 2026-05-14
**Deciders:** @<handle> (decided during the 2026-05-13/14 bootstrap-configure debugging session)
**Related:** ADR-0006 (cluster is the truth), ADR-0010 (run-playbook as sanctioned entry), ADR-0019 (Tailscale CGNAT vs cloud-internal services), commit `dmf-infra@3457513` (first application), `docs/plans/DMF App Admin Account Drift Audit and Realignment Plan 2026-05-14.md`.

## Context

Multiple `bootstrap-configure.yml` runs on 2026-05-13/14 failed with
public-URL DNS resolution and connectivity issues:

Problem statement and evidence: see the [archive record](../archive/decisions/0023-internal-service-dns-for-cross-app-wiring.md).

The cross-app wiring in question (CMS → NetBox, CMS → Forgejo, NetBox
→ Forgejo via datasource sync, etc.) is **app-to-app, both endpoints inside
the cluster**. There is no architectural reason to route this traffic
through the external boundary. Doing so creates artificial ordering
constraints (external surface must be built before bootstrap completes)
and accumulates per-env URL configuration that cluster-internal DNS makes
unnecessary.

## Decision

**Cross-app HTTP wiring uses cluster-internal service DNS by default,
not public URLs.**

Concretely:

1. Any Ansible task, role default, or playbook that makes an HTTP call
   from one cluster app to another sets the URL default to
   `http://<svc>.<ns>.svc.cluster.local:<port>` — plain HTTP, internal
   service DNS, no `dmf.example.com` placeholders.
2. The per-env override knob (`<role>_api_url`, `<app>_internal_host`,
   etc.) remains, so an env can point to an external endpoint for
   testing or off-cluster validators. But the **default works
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
| **Pod-to-pod runtime** — a pod making an HTTP call to another pod's service (e.g. dmf-cms → NetBox API at runtime; NetBox worker → Forgejo for datasource sync) | Internal service DNS | **Yes — use `http://<svc>.<ns>.svc.cluster.local:<port>`** |
| **Ansible `uri:` / `kubernetes.core.*` running from a control-node target** — provisioning tasks invoked by `bin/run-playbook.sh` against `k3s_control[0]` (e.g. 691-699 chain) | Public URL via ingress | **No — these tasks resolve DNS via the node's `/etc/resolv.conf`, which has no path to CoreDNS. They need `https://<public-host>` derived from the env's `*_host` var.** |
| **Anything outside the cluster network** — operator browser, off-cluster validators, webhook senders | Public URL | **No — out of architectural scope** |

The bootstrap-configure chain today straddles the line: provisioning runs
from the control node (currently public-URL), but the values it *writes*
into k8s Secrets are consumed at runtime by in-cluster pods (internal-URL
preferred). When in doubt, the test is: **who actually opens the TCP
connection?** That caller's location decides which URL the default
should use.

## Consequences

**Positive**
- Env-independent defaults — no per-env `-e cms_*_api_url=...` overrides
- Bootstrap-time robust: works before cert-manager, ingress, MetalLB
  are warm
- Smaller public surface for app↔app traffic
- Faster — no external network hop, no TLS handshake
- New envs spin up without coordinating DNS for cross-app paths

**Negative**
- ALLOWED_HOSTS / nginx host-header settings must accept the internal
  hostname (verified for NetBox/AWX/Forgejo on aliyun-123; future apps
  must be checked at install time)
- Risk of an internal URL leaking into a user-facing render — easy to
  catch in review, but a real anti-pattern to watch for
- For off-cluster validators (e.g. a remote SoT validator hitting NetBox),
  the override path must remain functional and documented

**Neutral**
- Each role still exposes the `*_api_url` override knob; existing
  env-side overrides continue to work unchanged
- Existing internal-URL usages (e.g. `forgejo-http...` in netbox-sot)
  retroactively become "ADR-compliant" rather than special cases

### Enforcement

- ADR principle. Reviews on `dmf-infra` playbook/role changes flag any
  new HTTP default referencing `dmf.example.com` or a `*_host` external
  variable for cross-app wiring.
- Future-state: a lint check in `bin/scrub-public-repos.sh` or pre-commit
  that flags `https?://.*\.dmf\.example\.com.*` defaults inside playbook
  `url:` lines (only when the playbook is doing cross-app wiring, not
  user-facing). Discipline-only until then.
- Touchpoint in roles/playbook reviews: when a new cross-app HTTP
  default is added, the reviewer asks "is this user-facing or app-to-app?"
  and points at this ADR for the app-to-app answer.

## Status

Accepted

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0023-internal-service-dns-for-cross-app-wiring.md).
