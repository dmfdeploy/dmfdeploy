---
status: active
date: 2026-05-25
---
# DMF OSS v0.1 WP1S — Single-Node Sandbox Lane

**Status:** Active — **first actionable work package** after WP0. **Phase 3 (AWX fit) + Phase 4 (catalog loop, machine path) PROVEN on `imc1-cyh4` 2026-05-29** (see §8.1). **Operator-confirmed end-to-end on `imc1-cyh4` 2026-05-29** (passkey browser → Console → AWX deploy/teardown). Remaining before a v0.1 tag: a formal non-maintainer fresh-clone replicability run.
**Date:** 2026-05-25
**Author:** Claude (planning sweep, under ADR-0031 framing)
**Anchor:** [WP0 Release Contract & Profile Matrix](DMF%20OSS%20v0.1%20WP0%20Release%20Contract%20and%20Profile%20Matrix%202026-05-25.md)
**Related ADR:** [ADR-0031](../decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md) (Profile 1, O1–O6)
**Profile:** `sandbox-single-node` — **the v0.1 release gate**

---

## 0. Why this is the center of gravity

`sandbox-single-node` is the profile that decides whether v0.1 can be tagged.
It is the default docs path and the immediate implementation center. If a choice
arises between polishing the AWS lane ([WP1A](DMF%20OSS%20v0.1%20WP1%20AWS%20Provider%20Profile%202026-05-25.md))
and making this lane concrete, **this lane wins**. AWS is not sequenced ahead of
it.

**Harness vs claim** (see [WP0 §1](DMF%20OSS%20v0.1%20WP0%20Release%20Contract%20and%20Profile%20Matrix%202026-05-25.md)):

- **First live implementation harness:** local Lima Debian 12 ARM64 VM on the
  maintainer's Mac, for rapid ARM64 iteration while still exercising the same
  Debian host bootstrap path as the release claim.
- **Release claim:** a **generic single-node ARM64 Debian host** — local VM,
  bare metal, or a cheap ARM VPS. The claim must hold on any of those, not just
  Lima. Lima is *how we build it first*, never *what we promise*.

---

## 1. Problem

The current bootstrap path assumes the maintainer's lab shape: multi-node
Hetzner, Longhorn replicated storage, Cloudflare DNS, Backblaze B2 backup
targets, external Headscale/Tailscale, and operator-Mac / JuiceFS / Keychain
unseal material. A contributor cannot replicate that cold. There is no
single-node, dependency-light path that a homelabber discovering the repo can
run on a laptop VM or a $5–$20 VPS.

The init wizard (`dmf-env/bin/init-wizard.sh`) currently offers `hetzner` and
`aws` providers only — there is **no sandbox / local provider path**.

---

## 2. Goals

1. A `sandbox-single-node` profile that bootstraps k3s + core platform services
   on one ARM64 Debian host with **no maintainer-specific credentials**.
2. Seeded admin can log in to the DMF Console via **passkey** ([ADR-0015](../decisions/0015-dmf-console-passkey-only.md)).
3. The reference catalog item (`nmos-cpp` registry + mock nodes, ADR-0031 O2)
   deploys, health-checks, transitions lifecycle state, and tears down — driven
   through dmf-cms → AWX.
4. Idempotent rerun from the same manifest; documented reset/teardown.
5. Local CA + explicit `dmf.test` host mappings for DNS/TLS (ADR-0031 O1).
6. Recommended local harness (`dmf-sandbox` Lima VM) documented, with the
   generic ARM64 Debian claim held distinct from it.

---

## 3. Recommended local harness

Two distinct harness modes. They are not interchangeable, and **only mode A
exercises the release bootstrap path.**

### Mode A — Lima Debian ARM64 VM (preferred WP1S harness)

For maintainer iteration, run a Lima Debian 12 ARM64 VM and bootstrap DMF's own
k3s onto it over SSH. This is what tests our host install (`300-k3s.yml`) and
ingress/cluster-ready roles while staying close to the release substrate.

```bash
# example shape; the exact Lima config lives outside the release claim
limactl start dmf-sandbox      # Debian 12, aarch64, 4 CPU, 10 GiB RAM, 60 GiB disk
# then bootstrap DMF's own k3s onto the VM over SSH (the release path)
```

- The VM should expose one routable node IP and keep SSH management simple.
  The live maintainer harness uses bridged networking plus the Lima management
  path; the cluster references the routable address, not a maintainer-private
  host path.
- Final release proof still requires a fresh **Debian ARM64** host (the §0
  claim). Treat the Lima VM as the fast iteration loop, not the gate.

### Mode B — Colima or managed local Kubernetes (optional smoke harness only)

`colima start --kubernetes` can give a fast in-cluster target for Helm /
in-cluster service smoke tests. It is **not** the release bootstrap proof and
**does not satisfy the sandbox gate**. If used, account for Traefik being
disabled by default unless config overrides it.

### Sizing (provisional)

- ARM64 is mandatory (matches the release node arch; all DMF-built images are
  `linux/arm64`).
- **~10 GiB / 4 CPU / 60 GiB is an initial target to validate, not a proven
  fit.** Live lab pod memory is ~12 GiB, and the sandbox only fits at all because
  of the §4 cuts (Longhorn, object backup, full monitoring). If AWX / Authentik /
  NetBox still thrash on first run, either raise the **maintainer harness** to
  ~12 GiB or trim monitoring further. Do not overclaim the footprint before the
  first green run; record the real number in WP5.
- This is a **harness convenience**, not the release contract. The same bootstrap
  must run on a plain Debian arm64 VM or VPS of equivalent size. Document both:
  "fast path (Lima Debian VM)" and "generic path (any ARM64 Debian host)."

---

## 4. Service shape

| Concern | Sandbox shape |
|---|---|
| Orchestrator | k3s, **single node** (server + agent on one host). |
| Ingress | Traefik on the normal **80/443** on the node IP via `single-node-servicelb` — **no MetalLB, no high NodePorts.** |
| Storage | k3s **`local-path`** provisioner. **No Longhorn.** |
| TLS / DNS | cert-manager with a **local CA** ClusterIssuer; explicit host mappings under **`dmf.test`** (e.g. `console.dmf.test`, `awx.dmf.test`). Installer/docs help the operator trust the CA. **Not** `.local`. |
| Secrets boot | OpenBao + ESO with **locally-generated** seed material; documented reset. No operator-Mac / JuiceFS / Keychain. |
| Identity | Authentik (seeded admin + role groups). |
| Console | dmf-cms (passkey login). |
| Automation | **AWX retained** (dmf-cms depends on it) — low concurrency, see §6. |
| Catalog supporting services | NetBox / Forgejo / Zot as needed for the catalog path. |
| Reference workload | `nmos-cpp` registry + mock nodes. |

### Kept

OpenBao/ESO · Authentik · dmf-cms · **AWX** · NetBox / Forgejo / Zot (as the
catalog path needs) · `nmos-cpp` reference deploy.

### Cut / trimmed

- **Longhorn** → `local-path`. The `longhorn`, `longhorn-backup-target`, and
  `longhorn-recurring-jobs` roles must become skippable on the sandbox profile.
- **Object-storage backups** → none. `object-storage-credentials` role skipped;
  reset/rerun is the recovery story.
- **Headscale / Tailscale** → none (sandbox-local comms on one node).
- **Full monitoring** → Prometheus/kube-prometheus-stack optional / trimmed.
- **AWS / SNS / KMS / Route53** → none (that is the [WP1A](DMF%20OSS%20v0.1%20WP1%20AWS%20Provider%20Profile%202026-05-25.md) lane).

### 4.1 Closed bootstrap gaps (k3s/ingress args)

The sandbox shape above is the *target*. The initial ServiceLB/local-path gaps
were closed during first acceptance; keep this section as the reasoning behind
those conditionals.

**Gap 1 — normal 80/443 ingress without MetalLB.**
`roles/base/ingress` originally supported only `cloud-native`, `metallb-l2`,
`metallb-bgp`, and `nodeport-only` (default `metallb-l2`). `nodeport-only`
gives high ports, which the operator explicitly wants to avoid. The sandbox
path now uses `single-node-servicelb`: `300-k3s.yml` does **not** disable k3s
ServiceLB for the sandbox profile, and Traefik's `LoadBalancer` Service binds
node 80/443.

**Gap 2 — `local-path` must actually exist.**
`300-k3s.yml` originally hardcoded `--disable=local-storage`, so the k3s-bundled
local-path provisioner was absent. The sandbox profile now keeps local-storage
enabled and verifies a default `local-path` StorageClass with a bound PVC.

Both changes are **profile-conditional** so the lab (Hetzner/MetalLB/Longhorn)
is unchanged while the sandbox gets ServiceLB + local-path.

### 4.2 Playbook / wrapper model

The sandbox lane should **not** copy the whole existing playbook tree. Use the
same atomic playbooks where possible, and add sandbox-specific wrappers that
select the sequence:

- **Keep shared atomic playbooks** for common capability installs:
  `300-k3s.yml`, `301-k3s-verify.yml`, `310-ingress-public.yml`,
  `320-cert-manager.yml`, `331-registry-zot.yml`, `610-netbox.yml`,
  `620-forgejo.yml`, `630-zot-seed-platform.yml`, `640-awx.yml`,
  `650-dmf-cms.yml`, and the 69x integration plays as they become sandbox-safe.
- **Add a sandbox wrapper sequence** rather than overloading the current lab
  wrappers as the first move. Proposed names:
  `bootstrap-sandbox-provision-pre-seed.yml`,
  `bootstrap-sandbox-provision-post-seed.yml`,
  `bootstrap-sandbox-configure.yml`, and `bootstrap-sandbox-verify.yml`. Exact
  names can change, but the sequence must be explicit and reviewable.
- **Leave the current bootstrap wrappers as the lab/reference path** until the
  sandbox is green. They represent the `g2r6-foa9` style flow and should not be
  broken while WP1S is being established.
- **Use profile capability variables**, not provider-name conditionals, for the
  shared playbooks and roles. Initial variables should look like:
  `dmf_release_profile: sandbox-single-node`,
  `dmf_storage_backend: local-path`,
  `dmf_ingress_mode: single-node-servicelb` (or `single-node-hostport` if
  chosen), `dmf_tls_mode: local-ca`, `dmf_object_storage_enabled: false`,
  `dmf_headscale_enabled: false`, `dmf_tailscale_enabled: false`,
  `dmf_monitoring_profile: minimal`, and
  `dmf_awx_profile: single-node-low-concurrency`.

The sandbox wrappers are responsible for omitting Longhorn, object-storage
backup roles, Headscale/Tailscale, heavy monitoring, and cloud-provider tasks.
The shared atomic playbooks are responsible only for honoring the capability
variables when they are included.

---

## 5. DNS / TLS posture (ADR-0031 O1)

- **Default (release gate):** local CA + generated `/etc/hosts` (or
  resolver) entries mapping `*.dmf.test` to the host. cert-manager issues from a
  self-signed CA ClusterIssuer; the installer prints the CA cert and the trust
  steps per-OS (the known footgun — make it a guided step, not a footnote).
- **Optional escape hatch:** contributors who already own a domain may supply
  DNS credentials and use ACME DNS-01 for production-shaped TLS. Not the gate.
- Do **not** use `.local` (mDNS/resolver ambiguity).

---

## 6. AWX resource posture

AWX is **kept** — it is load-bearing for the catalog/deploy loop that dmf-cms
drives. The goal is to make it *fit* on one node, not to remove or starve it.

- Low concurrency, enforced via the AWX CR's **`extra_settings`** block (the role
  template `roles/stack/operator/awx/templates/awx-instance.yml.j2` already has an
  `extra_settings:` map; these specific keys are **not** set today):
  - `SCHEDULE_MAX_JOBS: 1` — global cap on concurrently-scheduled jobs.
  - `DEFAULT_EXECUTION_QUEUE_MAX_CONCURRENT_JOBS: 1` — caps the container-group
    execution queue.
  - `DEFAULT_EXECUTION_QUEUE_MAX_FORKS` low — enforce as the **global AWX
    setting** (via `extra_settings`) and, belt-and-braces, as a **job-template
    default `forks`** on the catalog templates so a template can't override the
    intent upward.
- Use **`local-path` RWO** for AWX's PVCs.
- **Disable AWX backup CronJobs** in the sandbox profile.
- **Memory note:** idle AWX execution-environment pods are *not* the memory
  culprit; the cost is **running job EE pods**. Cap those through concurrency
  (above) and per-pod resource requests/limits, not by shrinking the AWX
  control/web/task footprint into instability.
- Do **not** try to starve AWX below realistic limits — under-provisioning it
  produces flaky catalog runs that look like platform bugs. Tune for "one job at
  a time, reliably," not "smallest possible footprint."

---

## 7. Implementation phases

### Phase 1 — Wizard sandbox provider/profile

- Add a `sandbox` (local / generic single-node) provider path to
  `dmf-env/bin/init-wizard.sh` alongside `hetzner` / `aws`.
- It must require **no** cloud credentials. Inputs: host address (or "local"),
  SSH reachability, generated opaque `dmf_env_id`, user subdomain label
  (`<label>.dmf.test`), sizing hints.
- Render a sandbox manifest + inventory with `provider: sandbox`,
  single-node group, `local-path` storage, local-CA TLS, no object-storage,
  no overlay mesh.

**Acceptance:** wizard produces a complete sandbox bundle with zero cloud creds.

### Phase 2 — Bootstrap profile switches

- Add the sandbox wrapper sequence described in §4.2 and make it the WP1S entry
  path for local harness testing.
- Make the Longhorn, object-storage-credentials, Headscale/Tailscale, and heavy
  monitoring roles **conditional** on capability variables so the sandbox
  wrappers skip them while lab/AWS wrappers can still include them.
- **Ingress (Gap 1):** keep the sandbox single-node ingress mode that gives
  Traefik 80/443 on the node IP without MetalLB and without high NodePorts by
  leaving k3s ServiceLB enabled for the sandbox profile.
- **Storage (Gap 2):** keep `300-k3s.yml` profile-conditional so the sandbox
  has the default `local-path` StorageClass while lab/cloud paths may keep their
  existing storage posture.
- Single-node k3s install; local-CA cert-manager issuer.
- See [WP2](DMF%20OSS%20v0.1%20WP2%20Bootstrap%20Independence%202026-05-25.md) for the sandbox-local OpenBao seed path (no operator-Mac).

**Acceptance:**
- `bootstrap-provision-*` complete on one ARM64 Debian host with no
  maintainer-specific inputs.
- Traefik answers on node **80/443** (no MetalLB, no high NodePort). *(Gap 1 closed in first acceptance.)*
- A PVC binds against a default `local-path` StorageClass. *(Gap 2 closed in first acceptance.)*
- The lab profile (MetalLB + Longhorn) is unchanged by the conditionals.

### Phase 3 — AWX fit

- Add the §6 concurrency knobs and `local-path` RWO to the AWX role under the
  sandbox profile; disable backup CronJobs.

**Acceptance:** AWX reaches Running and executes one job reliably on the sandbox node.

### Phase 4 — Console + catalog loop

- Seeded admin passkey login to dmf-cms (per [WP4](DMF%20OSS%20v0.1%20WP4%20CMS%20User%20Administration%202026-05-25.md) trimmed scope).
- dmf-cms drives AWX to deploy `nmos-cpp` registry + mock nodes; health probe;
  lifecycle state transition; teardown.

**Acceptance:** the full workflow-contract loop (WP0 §3 steps 5–7) passes on the sandbox.

### Phase 5 — Idempotency + reset

- Rerun the bootstrap from the same manifest → only expected no-ops.
- Document and test a clean reset/teardown.

**Acceptance:** second run is idempotent; reset returns the host to a re-bootstrappable state.

### Phase 6 — Verification + docs

- Sandbox quickstart (Lima Debian fast path + generic ARM64 Debian path).
- CA trust steps per-OS.
- Feed the sandbox row of the [WP5](DMF%20OSS%20v0.1%20WP5%20Release%20Verification%20and%20Tagging%202026-05-25.md) verification matrix.

**Acceptance:** a contributor can follow the quickstart cold and pass the sandbox gate.

---

## 8. Verification (sandbox gate)

From a fresh clone, on a fresh ARM64 Debian single-node host:

1. Fresh bootstrap completes from public docs + public repos only.
2. Seeded admin **passkey** login to the DMF Console works.
3. dmf-cms can drive AWX.
4. `nmos-cpp` deploy → health → lifecycle transition → teardown.
5. Idempotent rerun (only expected no-ops).
6. Documented reset works.
7. No Longhorn; `local-path` in use. No object-storage backup dependency.
8. AWX runs at low concurrency without starving the node (resource sanity).
9. No maintainer-specific credentials or private inventory anywhere on the path.

This list is the source for the **sandbox row** of the WP5 matrix, and the
sandbox row **gates the v0.1 tag**.

### 8.1 Proven on `imc1-cyh4` (2026-05-29) — machine path + findings

A full cold rollout on a fresh Lima Debian VM + wizard env (`imc1-cyh4`,
throwaway identity `marty-mcfly` / `delorean.dmf.test`) exercised this gate.
**Machine path PASS:** items 1, 3, 4, 5, 7, 8, 9 verified — the `nmos-cpp`
catalog loop runs deploy → health → lifecycle → teardown **end-to-end,
offline, attributed to `dmf-cms-svc`** over multiple cycles. Item 2 (passkey
**browser** Console login) is **operator-confirmed (2026-05-29)**: the full
human → browser → Console → AWX deploy/teardown path works, attributed to
`dmf-cms-svc`. Item 6 (documented reset) is the one-`rm` teardown from the
consolidation work. **Net: gate functionally met on imc1-cyh4; the remaining
pre-tag item is a formal non-maintainer fresh-clone run.**

Findings surfaced + fixed (all gate-relevant):
- **sops cold-bootstrap** — `seed-bao` re-encrypt failed ("no matching creation
  rules found") on the new `~/.dmfdeploy/envs/` layout; fixed (dmf-env `3ab4e50`):
  `--config` to the per-env `.sops.yaml` + temp named to match the creation-rule.
- **Machine identity** — catalog jobs ran as `awx-break-glass` (AWX binds token
  ownership to the authenticating principal); fixed to mint **as** `dmf-cms-svc`
  (dmf-infra `64cd035`; codified ADR-0028 §C3.1).
- **Galaxy egress** — `project_update` fetched `netbox.netbox` from public
  galaxy.ansible.com → timeout (breaks self-containment); fixed by EE-bake +
  neutralized `requirements.yml` (dmf-infra `d2800a9`/`38d2db6`, EE
  `awx-ee:0.1.1`). Permanent internal source = [ADR-0034](../decisions/0034-internal-ansible-collection-source.md).
- **EE pin** — pin the DMF EE on the NetBox **inventory source**, not just the
  JTs (else `inventory_update` runs the default EE → "unknown plugin
  nb_inventory"). Footgun: 630 EE-tag fallback is decoupled from the role default.
- **Console double-launch** — deploy/teardown buttons re-enabled before the AWX
  job completed → a second click fired a duplicate job; **fixed in dmf-cms
  `0.9.2`** (backend `find_active_job_for_template` idempotency returns the
  in-flight job + frontend gates on the in-flight job id). Residual: a
  sub-second two-tab TOCTOU is unlocked (narrow; frontend closes single-session)
  — optional DB/advisory-lock follow-up only if real concurrency appears.
- **Deploy↔finalise race** (follow-up, not built) — deploy (JT `media-launch`)
  and finalise (JT `media-finalise`) are *different* templates, so the 0.9.2
  same-action dedup does NOT serialize them; firing them ~1s apart raced on
  imc1-cyh4 (jobs 92+96) into pods-up + tag `active` with a no-op finalise.
  Fix direction: per-catalog-entry cross-action lock. Not a path failure.

---

## 9. Current state (relevant files)

- `dmf-env/bin/init-wizard.sh` — provider prompts (`hetzner` / `aliyun` /
  `aws` only; **no final sandbox provider path yet**), provider tfvars
  rendering, host sizing vars. `bootstrap-secrets.sh` has a validated
  sandbox/local quick path, but the cloud-parity opaque env-id + inventory-dir
  creation belongs in `init-wizard.sh`.
- `dmf-infra/k3s-lab-bootstrap/playbooks/300-k3s.yml` — sandbox profile now
  keeps ServiceLB and local-storage enabled; lab profile remains unchanged.
- `dmf-infra/k3s-lab-bootstrap/roles/base/ingress` — includes the
  `single-node-servicelb` sandbox mode used for normal 80/443 without MetalLB.
- `dmf-infra/k3s-lab-bootstrap/bootstrap-provision-pre-seed.yml` /
  `bootstrap-provision-post-seed.yml` — lifecycle; Longhorn + storage ordering.
- `dmf-infra/k3s-lab-bootstrap/roles/base/longhorn` (+ `-backup-target`,
  `-recurring-jobs`) — make skippable on sandbox.
- `dmf-infra/k3s-lab-bootstrap/roles/base/object-storage-credentials` — skip on sandbox.
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx` — add §6 concurrency
  knobs via the existing `extra_settings` in `templates/awx-instance.yml.j2`.
- `dmf-infra/k3s-lab-bootstrap/roles/base/cert-manager` — local-CA ClusterIssuer for sandbox.

## 10. Dependencies

- [WP0](DMF%20OSS%20v0.1%20WP0%20Release%20Contract%20and%20Profile%20Matrix%202026-05-25.md) — scope, trims, gates (this profile's contract).
- [WP2](DMF%20OSS%20v0.1%20WP2%20Bootstrap%20Independence%202026-05-25.md) — sandbox-local OpenBao seed path (no operator-Mac).
- [WP3](DMF%20OSS%20v0.1%20WP3%20In-Cluster%20Platform%20Services%202026-05-25.md) — sandbox services trim (no Headscale; ntfy optional/stub).
- [WP4](DMF%20OSS%20v0.1%20WP4%20CMS%20User%20Administration%202026-05-25.md) — seeded admin passkey login + backend role guards (trimmed).
- [WP5](DMF%20OSS%20v0.1%20WP5%20Release%20Verification%20and%20Tagging%202026-05-25.md) — sandbox row of the verification matrix (gates the tag).
- [WP-LAB](DMF%20OSS%20v0.1%20WP-LAB%20g2r6-foa9%20Reference%20Delta%202026-05-25.md) — harvest known-good settings from the live lab.

## 11. Done definition

WP1S is done when a contributor, from a fresh clone on a generic ARM64 Debian
single-node host, can bootstrap the sandbox, log in as the seeded admin with a
passkey, deploy and tear down the `nmos-cpp` reference item through dmf-cms/AWX,
rerun idempotently, and reset — with no maintainer-specific credentials, no
Longhorn, and no object-storage backup dependency.
