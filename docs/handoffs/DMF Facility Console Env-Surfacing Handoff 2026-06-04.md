# DMF Facility Console — Born-Inventoried Env Surfacing Handoff (2026-06-04)

**What:** while scoping NetBox-driven monitoring, the operator asked whether the dmf-cms
**Facility** page could show the **born-inventoried `<env>`**, and whether all env
resources should be **tagged** in NetBox. This session ran a read-only survey, settled the
modelling question, and produced a **dmf-cms-only work package** for a later session.
**This session committed docs only — no code, no component-repo edits** (kept independent
of the in-flight monitoring effort and clear of dmf-cms, which other agents may be
editing).

**Headline:** the env is **already** a first-class NetBox object — a per-env **Site** +
**Cluster** carrying `dmf_env_id`/`dmf_env_label`/`dmf_provider`/`dmf_architecture` custom
fields (written by `dmf-born-inventory`). **No per-env tag exists and none should be
added** — env ids rotate (tag sprawl), the info is redundant with Site/Cluster + FK, and
tags enforce nothing. The only gap is that **dmf-cms queries NetBox unscoped and ignores
`dmf_env_id`**, and only renders `dcim.device` (the lone `dmf-traefik` LB) — the k3s
nodes are `virtualization.virtual-machine`s it never queries. Fix is purely in the console
query/UI layer.

---

## What was produced (committed, umbrella `docs/` only)

1. **ADR-0039** — `docs/decisions/0039-environment-identity-netbox-site-cluster.md`:
   env identity = Site + Cluster `dmf_env_id` custom field; **no per-env tag**; consumers
   scope by Site/Cluster (or `cf_dmf_env_id`) and reach leaves by FK. INDEX.md updated.
2. **Work package** —
   `docs/plans/DMF Facility Console — Born-Inventoried Env Surfacing Plan 2026-06-04.md`:
   the single-session, dmf-cms-only implementation spec (backend `netbox.py` +
   `main.py /api/facility/env`; frontend `Facility.tsx` env card + Nodes table).
3. **This handoff.**

## Survey facts (for the implementer)

- Born-inventory writes per env:
  `dmf-infra/k3s-lab-bootstrap/roles/common/dmf-born-inventory/tasks/main.yml` +
  `defaults/main.yml` → Site `DMF <label/id>`, Cluster `<env_id>`, four `dmf_*` custom
  fields (on `dcim.site` + `virtualization.cluster`), shared Tenant `DMF`, generic
  **env-agnostic** `dmf-day0` tag. Apps registered as `ipam.Service` linked to the LB
  device (`tasks/app-service.yml`).
- dmf-cms Facility today: `Facility.tsx` → `/api/facility/{summary,devices}` →
  `netbox.list_sites()` (`?brief=1` — **brief strips custom_fields**) / `list_devices()`,
  both unscoped. `dcim/devices` ≈ just the LB; nodes (VMs) and services not shown.

## For the next agent — caveats (read before starting)

- **Scope is dmf-cms only.** Do **not** modify `dmf-born-inventory` or any dmf-infra file —
  the env model already exists, and the monitoring effort (ADR-0038, WP1/WP7) owns the
  born-inventory / netbox-sot files. Adding `dmf_env_id` to `ipam.Service`/`dcim.device`
  is a *deferred* option in ADR-0039, not this WP.
- **No per-env tag** (ADR-0039).
- **dmf-cms build is the gated path** — skill `dmf-cms-build-and-release` +
  `dmf-cms/docs/DEVELOPMENT-AND-BUILD-RULES.md` (VERSION → GHCR → Zot 630 → deploy 650).
  Never by hand.
- **`git status` dmf-cms first; ask the operator if it is dirty** (shared checkout,
  possibly mid-edit by another agent). Land on `main`.
- **Verification needs the live env in `STATUS.md`** (no cluster was up this session).
  Local pre-verify = backend unit test on a NetBox fixture + `pnpm build`.

## Open questions deferred to implementation
- Should `/api/facility/env` be engineer/admin-gated (`user.role`) or any-authenticated-
  user (current Facility behaviour)? — WP leaves it `_require_user` unless the operator
  asks to tighten.
- Include a services list/count on the env card, or counts only? — WP makes services
  optional.
