---
status: historical
date: 2026-05-22
---
# DMF g2r6-foa9 Configure-Verify Follow-Ups Plan

**Date:** 2026-05-22
**Trigger:** First successful `bootstrap-configure.yml` on `g2r6-foa9`
(PLAY RECAP `ok=651 changed=20 failed=0 rescued=0 ignored=0` at
log `/tmp/dmf-playbook-logs/bootstrap-configure-20260522-133918.log`).
**Status:** Open — items to be picked up after the two-identity admin
model PR2 lands (parallel session).

> The bootstrap-configure run succeeded but surfaced four non-fatal
> warnings and one architectural footprint that deserve explicit
> followup so they don't rot into "we always see those, ignore them"
> noise. Each item below is **non-blocking** for current cluster
> operation but should be resolved before the same code runs against a
> second env.

---

## A. Cosmetic: `dmf-born-inventory` template warnings — task-name interpolation outside loop scope

### Symptom

The run log shows four `[WARNING]: Encountered 1 template error.`
warnings, all from `roles/common/dmf-born-inventory/tasks/main.yml`:

```
Origin: roles/common/dmf-born-inventory/tasks/main.yml:510:13
TASK [common/dmf-born-inventory : Set DMF tenant id]
TASK [common/dmf-born-inventory : Look up DMF choice set << error 1 - 'item' is undefined >>]
TASK [common/dmf-born-inventory : Build DMF choice set id map (name -> id)]
TASK [common/dmf-born-inventory : Look up DMF custom field << error 1 - 'item' is undefined >>]
```

The task names contain `{{ item.name }}` or `{{ item.item.name }}`,
which Ansible attempts to resolve **at task-name display time** —
before the loop scope is established. Since `item` doesn't exist at
that moment, Jinja raises the templating error. The task bodies
themselves still execute correctly (the loop scope establishes `item`
before the body runs), and `loop_control.label` is already set on
each task, so per-iteration display is unaffected.

### Affected lines

| Line | Task name |
|---|---|
| `tasks/main.yml:510` | `Look up DMF choice set {{ item.name }}` |
| `tasks/main.yml:523` | `Create missing DMF choice set {{ item.item.name }}` |
| `tasks/main.yml:572` | `Look up DMF custom field {{ item.name }}` |
| `tasks/main.yml:585` | `Create missing DMF custom field {{ item.item.name }}` |

(Line 510 is the headline reference; the warning at line 540 / 553 are
echoes of the same task-name evaluation order; the four task names
above are the four root causes.)

### Fix

Two options, both single-commit:

1. **Drop the interpolation from the task name** — relies on
   `loop_control.label` (already present on lines 521/537/551/583) to
   show the per-iteration name in the play recap. Pattern:

   ```yaml
   - name: Look up DMF choice set
     ...
     loop: "{{ _dmf_choice_sets }}"
     loop_control:
       label: "{{ item.name }}"
   ```

2. **Move the dynamic name to a `name:` template variable** — keep a
   readable summary line but avoid the unscoped `item` reference.
   Slightly more verbose; cleaner for log scanning.

Recommend option 1 — minimum-diff, removes the warning at root, no
behaviour change.

### Why it's not blocking

- All four affected tasks complete successfully (post-run NetBox
  contains the expected choice sets and custom fields).
- The warnings are cosmetic at the Jinja-template layer.
- Cluster operation is unaffected.

### Followup commit

- File: `dmf-infra/k3s-lab-bootstrap/roles/common/dmf-born-inventory/tasks/main.yml`
- Scope: 4 task-name edits.
- Expected commit message: `fix(dmf-born-inventory): drop {{ item.name }} from task names (Jinja item-scope warning)`

---

## B. Architecture: in-cluster execution environment + Docker availability

### Question raised

> "What is the status of the in-cluster execution environment?
> Docker available?"

### Short answer

**No Docker on the cluster.** Docker daemon is not installed on any
g2r6-foa9 node. The cluster runs k3s, which embeds containerd as its
CRI. The in-cluster execution environment is the `ansible-runner` pod
(per ADR-0025) pulling a purpose-built AWX EE image from
cluster-internal Zot, executed by containerd.

### Where each piece runs

| Component | Where it runs | Container runtime |
|---|---|---|
| **k3s nodes** | Hetzner CAX21 ARM64 (`g2r6-foa9-node-01..03`) | containerd (k3s-embedded) |
| **EE image build** | Operator workstation (macOS arm64) | Colima (Docker-compatible) — runs ansible-builder |
| **EE image push to Zot** | Operator workstation | skopeo (daemon-free) — refactored 2026-05-21 from the prior Docker-on-control-node antipattern |
| **EE image consumption** | In-cluster `ansible-runner` Pod + AWX-spawned launchers | containerd, image pulled from cluster-internal Zot |

### Authoritative source map

- **ADR-0025** — Cluster-internal Ansible execution + catalog Helm pivot. Defines the architecture.
- **`dmf-infra/k3s-lab-bootstrap/ee/`** — ansible-builder config (`execution-environment.yml`, `bindep.txt`, `requirements.txt`, `requirements.yml`).
- **`dmf-infra/k3s-lab-bootstrap/playbooks/630-zot-seed-platform.yml`** — Stage 4b: build EE image on workstation Colima + push to in-cluster Zot via skopeo. Wired into `bootstrap-provision-post-seed.yml` between 620 and 640. Idempotent (skips if image+tag already present in Zot).
- **`dmf-infra/k3s-lab-bootstrap/playbooks/050-ansible-runner.yml`** — deploys the runner Pod.
- **`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/ansible-runner/defaults/main.yml`** — Image default `registry.dmf.example.com/dmf/awx-ee:0.1.0` (cluster-internal Zot); fallback `ghcr.io/dmfdeploy/awx-ee:0.1.0` when Zot is not yet seeded.
- **`docs/plans/DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md`** — the planning record for ADR-0025.

### What that means operationally

- **No `docker` CLI on any cluster node.** Don't write playbooks that assume `docker run`, `docker exec`, etc. — they'll fail.
- **For shell-out-to-container needs on a cluster node**, use `crictl` (containerd CRI) or `kubectl exec` into a Pod. The dmf-infra CLAUDE.md and the NetBox-token playbook (`691-netbox-sot.yml`) both use `kubectl exec`, not docker.
- **The workstation needs Colima running** for any `630-zot-seed-platform.yml` re-run (EE rebuild/republish). `colima start --arch aarch64` if not running.
- **AWX-spawned catalog launchers** consume the same EE image, so any change to `ee/requirements.yml` (Ansible collections) etc. requires re-running 630 to republish.

### Open verification questions (not blocking)

- **Is the `ansible-runner` Deployment running on g2r6-foa9?** Not yet
  confirmed in this session (operator preference: avoid SSH onto the
  control node unless required). Verify on next operator-driven
  inspection:

  ```bash
  bin/run-playbook.sh g2r6-foa9 \
    ../dmf-infra/k3s-lab-bootstrap/playbooks/050-ansible-runner.yml --check
  ```

  Or, with kubeconfig exported on workstation:

  ```bash
  kubectl get deploy -A | grep -i ansible-runner
  kubectl get pods -n <ns> -l app=ansible-runner
  ```

- **Is the EE image present in cluster Zot?**

  ```bash
  curl -k -u <admin>:<password> https://zot.dmf.example.com/v2/dmf/awx-ee/tags/list
  ```

- **Does the in-cluster runner Pod successfully execute a sample playbook?** Smoke test deferred until catalog Helm pivot lands.

### Followup actions

None required for current operation. Open items above are
verifications, not fixes. Add to next `bootstrap-verify.yml` sweep
once `verify-oidc-admin-bridge.yml` lands (parallel PR2 work).

---

## C. Cross-session coordination (recorded for context)

This followup plan was authored after the successful run while the
two-identity admin model PR2 implementation was concurrently committing
in pane 2 (claude-bottom). PR2 scope landed:

- `roles/common/admin-identity-resolve/` helper role (created, with README).
- `awx-integration/tasks/main.yml` refactored to use the helper.
- `playbooks/697-cms-awx-token.yml` refactored to use the helper (supersedes the same-session PR1 set_fact at `dmf-infra@142f819`).
- `playbooks/verify-oidc-admin-bridge.yml` smoke test.
- `docs/decisions/0024-two-identity-admin-model.md` (Accepted, not Proposed — promotion criteria met).
- `docs/decisions/INDEX.md` row update.

Scope deltas vs the original handoff (operator-confirmed during PR2 implementation):

- NetBox and Forgejo role adoption **skipped** — both read their local admin from OpenBao (`secret/apps/<app>/admin` via `common/app-admin-facts`), not from a K8s Secret. The helper is K8s-Secret-specific and doesn't apply.
- `698-cms-netbox-forgejo-tokens.yml` **not refactored** — keeps the narrow PR1b fix at `dmf-infra@4f7f505` (same reasoning).
- Per-env opt-in flag plumbing for `aliyun-123` / `hetzner-arm` **skipped** — both clusters are retired.

The retired-cluster doc cleanup (CLAUDE.md, `.claude/skills/dmf-cluster-access/`, `dmf-openbao-unseal/` references to retired envs) is a separate followup, not part of this plan.

---

## D. Bootstrap bundle landed on workstation disk instead of encrypted USB volume

### Symptom

Operator expected the g2r6-foa9 bootstrap bundle (env-specific
secrets, SOPS-encrypted env file, age key, etc.) at
`/Volumes/<operator>/secure/dmf-bootstrap/` — the path their
`~/.config/dmf/env` exports as `DMF_BOOTSTRAP_BUNDLE_DIR` and the
path used as the encrypted secure-store across the platform. The
bundle was not there. Symptom surfaced when running
`bin/run-playbook.sh g2r6-foa9 ../dmf-infra/k3s-lab-bootstrap/playbooks/vertical-security/110-authentik.yml`
without overriding the env var — the wrapper errored on missing
bundle dir.

### Observed state (2026-05-22)

```
/Volumes/<operator>/secure/dmf-bootstrap/    ← matches ~/.config/dmf/env
├── aliyun/
├── aliyun-123/
├── hetzner-arm/                       (3 retired envs only)
└── *.sops.yaml

/Users/<operator>/secure/dmf-bootstrap/      ← workstation disk, NOT the configured path
├── g2r6-foa9/             (2026-05-21 09:20)
├── g2r6-foa9.sops.yaml    (2026-05-21 11:24)
├── z4ud-sy22/             (2026-05-20 14:47 — discarded env)
└── z4ud-sy22.sops.yaml
```

Both fresh envs created during this session (the discarded
`z4ud-sy22` and the active `g2r6-foa9`) landed on the workstation
disk, not the encrypted USB volume. All three retired envs are on
the USB volume.

### Likely root cause

When the wizard ran for both envs, the operator's USB volume at
`/Volumes/<operator>/secure/` was either:

- not mounted at the moment the wizard executed, OR
- mounted but `DMF_BOOTSTRAP_BUNDLE_DIR` was unset in that shell so
  the wizard fell back to a `$HOME/secure/dmf-bootstrap/` default.

Either way, the wizard wrote silently to the fallback location.
The error surfaced only later, when an unrelated playbook required
the bundle and read `DMF_BOOTSTRAP_BUNDLE_DIR` from
`~/.config/dmf/env`.

### Security tradeoff

`/Volumes/<operator>/secure/` is an encrypted USB volume — the platform's
intended secure-store. `/Users/<operator>/secure/` lives on the
workstation disk (FileVault-protected at the disk layer, but no
removable-media isolation). The split posture is a real difference:
the bootstrap bundle contains the OpenBao breakglass token,
SOPS-encrypted age key, and other materials whose compromise would
allow full takeover of the env's cluster.

### Remediation options

**Option 1 — move existing bundles onto the USB volume (preferred):**

```bash
# with /Volumes/<operator>/secure mounted
mv /Users/<operator>/secure/dmf-bootstrap/g2r6-foa9 \
   /Volumes/<operator>/secure/dmf-bootstrap/g2r6-foa9
mv /Users/<operator>/secure/dmf-bootstrap/g2r6-foa9.sops.yaml \
   /Volumes/<operator>/secure/dmf-bootstrap/g2r6-foa9.sops.yaml

# also delete the discarded z4ud-sy22 if not already removed
rm -rf /Users/<operator>/secure/dmf-bootstrap/z4ud-sy22 \
       /Users/<operator>/secure/dmf-bootstrap/z4ud-sy22.sops.yaml
```

After move, the existing `~/.config/dmf/env`
`DMF_BOOTSTRAP_BUNDLE_DIR=/Volumes/<operator>/secure/dmf-bootstrap` Just
Works.

**Option 2 — switch the configured path to the workstation disk:**

Drop the USB requirement entirely. Edit `~/.config/dmf/env`:

```bash
export DMF_BOOTSTRAP_BUNDLE_DIR=$HOME/secure/dmf-bootstrap
```

Easier; loses the encrypted-volume property. Acceptable if the
operator decides FileVault is sufficient and removable-media
isolation isn't worth the operational overhead.

### Decision 2026-05-23 — Option 2 for the experiment phase

**Chosen:** Option 2 — switch the configured path to the workstation disk.

**Rationale.** During the experiment phase (per [ADR-0004](../decisions/0004-experiment-phase-stance.md))
the platform is optimised for *learning whether the architecture survives
contact with reality*, not for hardening. The operational overhead of
keeping the USB volume mounted at every wizard invocation — and the
silent-bifurcation failure mode it created on g2r6-foa9 — outweighs the
removable-media isolation benefit at this stage. FileVault remains the
disk-layer guarantee.

**Action required (operator-side, outside this repo):** edit
`~/.config/dmf/env`:

```bash
export DMF_BOOTSTRAP_BUNDLE_DIR=$HOME/secure/dmf-bootstrap
```

Optionally delete the discarded `z4ud-sy22` directory + `.sops.yaml` from
the workstation-disk location once the env-removal is otherwise clean.
The retired envs (`aliyun/`, `aliyun-123/`, `hetzner-arm/`) on the USB
volume can stay where they are — they are read-only history.

**Revisit gate.** This decision is for the experiment phase only. Restore
the encrypted-USB requirement (Option 1) when **any one** of the
following holds:

1. ADR-0020 Mode B (managed `dmfdeploy.io`) starts being implemented —
   removable-media isolation is part of the customer-facing trust story
   that Mode B has to make honestly. Even before Mode B's promotion,
   any genuine third-party / paying-customer pilot using this
   workstation as the bootstrap origin is an immediate trigger.
2. The platform exits experiment phase (ADR-0004 is superseded or
   amended).
3. The bootstrap bundle contents grow to include any material whose
   loss-by-disk-theft (post-FileVault-unlock state, e.g. RAM image of
   an unlocked machine, lent device, etc.) would be a meaningfully
   worse outcome than its loss-by-USB-theft equivalent.

When the gate fires, the wizard-hardening items below become hard
prerequisites, not improvements.

### Wizard hardening (separate followup — still wanted under Option 2)

The fall-through is silent today — that's the underlying root cause.
Option 2 makes item #1 less load-bearing day-to-day (the configured
path now matches the wizard's silent fallback) but item #2 is still
valuable for the future-revisit case: if the operator ever mounts the
USB and runs the wizard, the silent re-bifurcation re-emerges.

1. **Fail-fast if `DMF_BOOTSTRAP_BUNDLE_DIR` is unset.** Refuse to
   pick a default. Forces the operator to confirm the target dir
   per wizard invocation.
2. **Warn-or-fail if the resolved dir is under `$HOME` but a
   `/Volumes/*/dmf-bootstrap/` exists.** Auto-detect the
   configuration mismatch (operator typically has a single secure
   location; if both exist, surface the inconsistency).

Implementation: a short check at the top of the wizard, before any
state writes. Belongs in `dmf-env`, not the umbrella.

### Tracking

- Decision: Option 2, 2026-05-23 (this section).
- Operator-side `~/.config/dmf/env` edit: tracked here, executed
  out-of-band.
- Wizard hardening: separate small commit in `dmf-env`, not blocking.
- Future revisit: gated on the triggers above; record any retrigger
  event in STATUS operator notes so the decision context isn't lost.

---

## E. Out of scope for this plan

- ADR-0024 PR2 lifecycle (covered by the parallel session).
- The PR2 smoke-test playbook itself (covered by the parallel session).
- Larger refactor of `dmf-born-inventory` (e.g., splitting into multiple roles, generalising the choice-set / custom-field block) — deferred until the role gains additional callers.
- Catalog Helm pivot lifecycle (separate active plan: `DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md`).
- Full review of every operator path that reads `DMF_BOOTSTRAP_BUNDLE_DIR` — the wizard fail-fast in §D covers the write path; consumers (run-playbook.sh, get-passkey-enrollment-url.sh, etc.) already error clearly when the dir is missing.
