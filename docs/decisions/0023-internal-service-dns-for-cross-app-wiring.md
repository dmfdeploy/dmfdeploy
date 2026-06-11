# ADR-0023: Cross-app HTTP wiring uses cluster-internal service DNS, not public URLs

**Status:** Accepted
**Date:** 2026-05-14
**Deciders:** @<handle> (decided during the 2026-05-13/14 bootstrap-configure debugging session)
**Related:** ADR-0006 (cluster is the truth), ADR-0010 (run-playbook as sanctioned entry), ADR-0019 (Tailscale CGNAT vs cloud-internal services), commit `dmf-infra@3457513` (first application), `docs/plans/DMF App Admin Account Drift Audit and Realignment Plan 2026-05-14.md`.

## Context

Multiple `bootstrap-configure.yml` runs on 2026-05-13/14 failed with
public-URL DNS resolution and connectivity issues:

- Run 5 / `691-netbox-sot`: NetBox datasource pointed at `forgejo.dmf.example.com`
  (the prose placeholder per CLAUDE.md scrub convention) — never resolved.
  Fixed by `dmf-infra@7b006ee` (PATCH `source_url` to internal service DNS).
- Run 9 / `697-cms-awx-token`: worked, but only because `awx_host` happened to
  be defined in the env inventory; the role default would have hit the
  same `dmf.example.com` trap.
- Run 10 / `698-cms-netbox-forgejo-tokens`: defaults `cms_netbox_api_url |
  default('https://netbox.dmf.example.com')` and `cms_forgejo_api_url |
  default('https://forgejo.dmf.example.com')` — NXDOMAIN on the public default.

Beyond DNS, public URLs at bootstrap time depend on a full chain that
isn't yet warm:

1. External DNS A/CNAME records for the env's domain
2. cert-manager has issued a valid Let's Encrypt cert
3. MetalLB has announced the ingress VIP
4. Traefik/nginx-ingress is healthy and has the route
5. Any L4/L7 firewall allows the public→ingress path

The cross-app wiring in question (CMS → NetBox, CMS → Forgejo, NetBox
→ Forgejo via datasource sync, etc.) is **app-to-app, both endpoints inside
the cluster**. There is no architectural reason to route this traffic
through the external boundary. Doing so creates artificial ordering
constraints (external surface must be built before bootstrap completes)
and accumulates per-env URL configuration that cluster-internal DNS makes
unnecessary.

The internal-DNS path (`<svc>.<ns>.svc.cluster.local:<port>`) is:

- Resolved by CoreDNS — works the moment the service object exists
- Independent of external DNS, certs, ingress, MetalLB, public domain
- Identical across every env — no per-env URL override needed
- Already the working pattern in places (NetBox→Forgejo datasource sync
  uses `forgejo-http.forgejo.svc.cluster.local:3000` after fix `07d0e00`)

Today's read-only survey on `aliyun-123` confirmed that the affected apps
accept internal hostnames (NetBox `ALLOWED_HOSTS` permissive; AWX nginx
permissive; Forgejo unproblematic):

- `http://netbox.netbox.svc.cluster.local:80/api/` → 200
- `http://forgejo-http.forgejo.svc.cluster.local:3000/api/...` → 401 (auth-aware)
- `http://awx-service.awx.svc.cluster.local:80/api/v2/ping/` → 200

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

## Scope (amended 2026-05-14 after run-11 caller-location discovery)

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

## Future direction

The caller-location split exists only because configure-stage ansible
runs on the control-node target instead of inside the cluster. A
companion workstream (planning in a follow-up session, 2026-05-14)
will design an **in-cluster ansible execution pod** that runs all
configure-stage playbooks from within the cluster. Once that lands:

- Configure-stage `uri:` tasks resolve DNS via CoreDNS → internal
  service DNS works everywhere
- The Scope table above collapses to "internal everywhere, public
  only for user-facing flows"
- The `*_host`-derivation pattern in ADR-0023-applying code becomes
  a transitional artifact; defaults can switch to `http://<svc>.<ns>
  .svc.cluster.local:<port>` uniformly

That migration is **not blocked on** the current `*_host` pattern —
they coexist cleanly. When the runner-pod lands, defaults flip in a
follow-up commit per file.

### 2026-05-19 update — realisation in progress under ADR-0025

The in-cluster ansible execution pod is now being delivered as **Lane C** of
the converged plan
[`docs/plans/DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md`](../plans/DMF%20Cluster-Internal%20Ansible%20Execution%20and%20Catalog%20Helm%20Pivot%20Plan%202026-05-19.md).
The pod shares its EE image with the AWX-driven catalog-launcher pods
(Lane B), so the caller-location split collapses for both bootstrap-configure
and catalog-launch transports simultaneously. The Scope table will be
simplified to "internal everywhere; public only for user-facing flows" when
Lane C Phase 4 gate passes. Tracked as a follow-up amendment to this ADR.

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

## Alternatives considered

1. **Continue public-URL defaults.** Status quo. Failure mode is the
   2026-05-13/14 session: fragile, requires per-env DNS coordination,
   accumulates `-e` flags. Rejected.

2. **Tailscale MagicDNS / private DNS overlay.** Still external from
   the cluster's perspective; adds operator setup burden; doesn't help
   during bootstrap before Tailscale is wired. ADR-0019 already documents
   Tailscale's role for *operator* access, not app↔app traffic.

3. **Raw ClusterIPs.** Brittle — ClusterIPs change on service re-create
   and aren't stable across envs. k8s service DNS is the right
   abstraction; ClusterIP is implementation detail.

4. **Service mesh (linkerd/istio) with mTLS.** Architecturally cleaner
   for production but too much surface for the experiment phase
   (ADR-0004). Internal plain-HTTP via service DNS is the right
   stop-gap until a service-mesh decision is made.

## Enforcement

- ADR principle. Reviews on `dmf-infra` playbook/role changes flag any
  new HTTP default referencing `dmf.example.com` or a `*_host` external
  variable for cross-app wiring.
- Survey + migration tracked in
  `docs/plans/DMF Internal Service DNS Migration Survey 2026-05-14.md`
  — produces a per-file diff inventory of remaining public-URL
  cross-app defaults to migrate.
- Future-state: a lint check in `bin/scrub-public-repos.sh` or pre-commit
  that flags `https?://.*\.dmf\.example\.com.*` defaults inside playbook
  `url:` lines (only when the playbook is doing cross-app wiring, not
  user-facing). Discipline-only until then.
- Touchpoint in roles/playbook reviews: when a new cross-app HTTP
  default is added, the reviewer asks "is this user-facing or app-to-app?"
  and points at this ADR for the app-to-app answer.
