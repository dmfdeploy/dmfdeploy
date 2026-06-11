---
status: superseded
date: 2026-05-14
superseded_by: "DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md"
---
# DMF In-Cluster Ansible Runner Pod — Implementation Plan
> **Superseded by** [DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md](DMF%20Cluster-Internal%20Ansible%20Execution%20and%20Catalog%20Helm%20Pivot%20Plan%202026-05-19.md) — see frontmatter.

> **2026-05-19 — converged into a broader plan.**
> This plan is now **Lane C** of the
> [DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19](./DMF%20Cluster-Internal%20Ansible%20Execution%20and%20Catalog%20Helm%20Pivot%20Plan%202026-05-19.md).
> Phases 2–4 below remain as specified. The only anchor flip is the EE
> image reference: once Lane A of the 2026-05-19 plan ships, point
> `ansible_runner_image` at the Zot-hosted EE
> (`zot.zot.svc.cluster.local:5000/dmf/awx-ee:<tag>`) instead of
> `quay.io/ansible/awx-ee:latest`. §10.5 (post-spike "Hosting in
> cluster-internal Zot") is now landed earlier as Lane A of the
> 2026-05-19 plan rather than a post-spike follow-on.

**Date:** 2026-05-14
**Status:** Phase 1 done · Phases 2–4 pending · Spike target: playbook 698
**Related ADRs:** ADR-0010, ADR-0012, ADR-0016, ADR-0023, **ADR-0025 (2026-05-19)**
**Related plans:** *DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md* (parent); *DMF App Admin Account Drift Audit and Realignment Plan 2026-05-14.md*; *DMF Internal Service DNS Migration Survey 2026-05-14.md*

---

## 0. How to use this document

A fresh agent picks this up cold. By the end of §3 you should understand
*why* the runner pod exists; by §6 you should know exactly *what to build
and in what order*; by §8 you should know *which failure modes already
ate hours and how to avoid repeating them*. Read top-to-bottom on first
pass; treat §6 as the work plan.

Estimated remaining effort to finish the spike (Phases 2–4): one focused
session, 3–4 hours of design + code + iteration against the live
`aliyun-123` cluster.

---

## 1. Boot ritual (do this before touching anything)

This work spans the **umbrella** + **`dmf-infra`** + **`dmf-env`** repos.
The umbrella's `CLAUDE.md` has the canonical boot ritual; the abbreviated
version:

1. `cd "$DMFDEPLOY_UMBRELLA" && git fetch && git pull`
2. `bin/generate-status.sh` — refresh STATUS.md; read it
3. Read the most recent file in `docs/handoffs/`
4. Skim `docs/decisions/INDEX.md` — note ADRs relevant to your task
   (this work specifically: ADR-0010, ADR-0012, ADR-0016, ADR-0023)
5. `git status` in each sub-repo you'll touch. **Ask the operator before
   modifying any sub-repo with dirty (uncommitted) state** — that's
   in-progress work from another session/agent.

For cluster operations + secrets-adjacent work, read §0 of the relevant
skill **first**:

- `.claude/skills/dmf-cluster-access/SKILL.md` — read §0 Secrets
  Discipline + §3 read-only ops. The runner-pod work touches the cluster
  authoritatively; this skill is your contract.
- `.claude/skills/dmf-openbao-unseal/SKILL.md` — read §0 if you need to
  unseal OpenBao to test. Don't improvise.
- The `agent-bridge` skill (`~/.claude/skills/agent-bridge/`) — used to
  coordinate with sibling qwen agents during long-running work. See §2.4
  below.

---

## 2. Required reading (in order)

These are the load-bearing prior artifacts. Skim each before §6.

### 2.1 ADR-0023 — Internal service DNS for cross-app wiring

`docs/decisions/0023-internal-service-dns-for-cross-app-wiring.md`

The architectural principle this entire workstream realizes: cross-app
HTTP wiring at runtime uses cluster-internal service DNS, not public
URLs. The ADR's §Scope distinguishes pod-to-pod calls (in scope) from
ansible-from-control-node calls (out of scope today). §Future direction
explicitly references this implementation plan.

**Key insight:** the runner pod collapses the §Scope caveat. Once
configure-stage ansible runs in-cluster, internal DNS works everywhere,
and the caller-location distinction is dead.

### 2.2 ADR-0010 — `bin/run-playbook.sh` as the sanctioned ansible entry point

`docs/decisions/0010-run-playbook-as-sanctioned-entry.md`

Says the operator wrapper is THE entry point for ansible runs. Direct
`ansible-playbook` is forbidden. The runner-pod work **must not break**
this — instead, it extends `run-playbook.sh` to dispatch by playbook
stage: provision-stage stays on the existing SSH path; configure-stage
pivots to kubectl-exec-into-pod transport.

### 2.3 ADR-0012 — Configure stage distinct from provision

`docs/decisions/0012-configure-stage-distinct-from-provision.md`

Establishes the lifecycle split. This work completes that split at the
runtime layer too: provision runs from the operator workstation
(unchanged), configure runs from inside the cluster.

### 2.4 agent-bridge usage

If you coordinate with sibling agents (qwen-left, qwen-right, codex)
during long monitoring or parallel work, use agent-bridge — do NOT relay
through the operator.

```bash
# List configured panes
~/.claude/skills/agent-bridge/bin/agent-bridge list

# Send a message — single-line
~/.claude/skills/agent-bridge/bin/agent-bridge send qwen-right -- '<message>'

# Send via stdin for multi-line
~/.claude/skills/agent-bridge/bin/agent-bridge send qwen-right - <<'EOF'
<multi-line>
EOF

# Read recent output
~/.claude/skills/agent-bridge/bin/agent-bridge read qwen-right --lines 80
```

Your bridge name is `claude-bottom` (or whichever pane the operator runs
you in — check with `agent-bridge list`). Per memory convention:
**always `/clear` qwen before dispatching a fresh task**, and **always
ask the recipient to reply via agent-bridge** so the bridge notifies
back asynchronously rather than requiring polling.

---

## 3. Why this exists — problem statement

### 3.1 Today's failure mode (concrete)

The bootstrap-configure chain (`playbooks/bootstrap-configure.yml`)
consists of import_playbook entries that wire dmf-cms tokens to live
apps (Authentik, AWX, NetBox, Forgejo). Today's 2026-05-13/14 session
ran 11 attempts before reaching `PLAY RECAP failed=0` end-to-end. Eleven
distinct walls were debugged, including:

| Wall | Root cause | Fix |
|---|---|---|
| 1 | NetBox sync `until` compared dict to string | `dmf-infra@685b32b` (status.value) |
| 2 | uri task hung on TCP, no timeout | `dmf-infra@46a57a7` (block/rescue + timeout:30) |
| 3 | NetBox sync used wrong Forgejo DNS name | `dmf-infra@07d0e00` (forgejo-http) |
| 4 | forgejo-svc user inactive | `dmf-infra@1d9d1eb` (active:true in PATCH) |
| 5 | NetBox DataSource still had placeholder URL | `dmf-infra@7b006ee` (PATCH source_url) |
| 6 | Drift: NetBox admin = `admin`, role default = `dmfadmin` | `-e netbox_sot_admin_username=admin` |
| 7 | Drift: AWX admin = `<user>`, password mismatch | `-e awx_integration_admin_user=<user>` + in-pod `awx-manage update_password` |
| 8 | Drift: Forgejo admin = `<user>` | `-e forgejo_admin_username=<user>` |
| 9 | librenms_host undefined (LibreNMS not deployed) | `dmf-infra@3e7a9d0` (default('')) |
| 10 | Variable-name fragmentation: 697 uses `awx_admin_user`, 698 uses `cms_forgejo_admin_user` etc. | More `-e` flags |
| 11 | 698 uri tasks default to placeholder dmf.example.com | `dmf-infra@37dbb56` (derive from `*_host`); revealed caller-location problem |

### 3.2 The structural pattern under those failures

Several of the 11 walls were *symptoms of the same disease*: configure-stage
ansible runs from outside the cluster, which forces every cross-app HTTP
call to go through:

1. External DNS for the env's domain
2. cert-manager + Let's Encrypt cert chain
3. MetalLB VIP announcement
4. Traefik/nginx-ingress routing
5. Public TLS handshake (currently weakened with `validate_certs: false`)

…instead of just hitting the in-cluster service object. And the override
list to coordinate the env-specific hostnames has grown to **six `-e`
flags**.

### 3.3 What we want instead

Move configure-stage ansible **inside the cluster**. Specifically: spawn
a one-shot Kubernetes Job that runs `ansible-playbook` inside a pod, with
CoreDNS available and `*.svc.cluster.local` reachable. Once that's in
place:

- Cross-app HTTP defaults flip to `http://<svc>.<ns>.svc.cluster.local:<port>` everywhere
- ADR-0023's §Scope caveat collapses
- `-e cms_*_api_url=...` overrides disappear entirely
- Operator workstation coupling drops (no more "is JuiceFS mounted? is
  the SSH key available?")

### 3.4 What stays the same

- `bin/run-playbook.sh` remains the entry point (ADR-0010 holds)
- Provision-stage (Layers 1–3: OpenTofu, base, k3s) stays on the SSH
  path — the cluster doesn't exist yet during those layers
- AWX is still the long-running ansible execution engine for ongoing
  operations. The runner pod is for *bootstrap-configure*, not for
  user-triggered jobs.

---

## 4. Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│  Operator workstation                                              │
│                                                                    │
│  bin/run-playbook.sh aliyun-123 <playbook> [-e ...]                │
│    │                                                               │
│    ├─ (provision-stage playbook → SSH + ansible, unchanged)        │
│    │                                                               │
│    └─ (configure-stage → kubectl path)                             │
│        │                                                           │
│        ├─ kubectl create secret openbao-breakglass-<runid>         │
│        │      from breakglass JSON on the operator's JuiceFS       │
│        ├─ kubectl cp dmf-infra-tarball pod:/workspace/             │
│        ├─ kubectl create -f runner-job-<runid>.yaml                │
│        ├─ kubectl logs -f job/runner-<runid>  (tee to log file)    │
│        └─ trap: kubectl delete secret + job (always)               │
└────────────────────────────────────────────────────────────────────┘
                              │ kubectl over Tailscale or SSH bastion
                              ▼
┌────────────────────────────────────────────────────────────────────┐
│  Kubernetes cluster                                                │
│                                                                    │
│  Namespace: dmf-bootstrap                                          │
│    ServiceAccount: ansible-runner (cluster-admin RBAC, spike)      │
│    Secret: openbao-breakglass-<runid>  (mounted into Job pod)      │
│    Job: runner-<runid>                                             │
│      └─ Pod                                                        │
│          ├─ Image: quay.io/ansible/awx-ee:latest                   │
│          ├─ /workspace: code tarball (initContainer extracts)      │
│          ├─ /etc/openbao-breakglass/keys.json (mounted Secret)     │
│          ├─ /var/run/secrets/.../token (auto-projected SA token)   │
│          └─ Command: ansible-playbook -i .../<env>                  │
│                       /workspace/k3s-lab-bootstrap/playbooks/      │
│                       <target>.yml                                 │
│                       --extra-vars '@/etc/.../vars.json'           │
│                                                                    │
│    Cross-app HTTP calls inside pod resolve via CoreDNS:            │
│      ✓ http://netbox.netbox.svc.cluster.local:80/api/              │
│      ✓ http://forgejo-http.forgejo.svc.cluster.local:3000/...      │
│      ✓ http://awx-service.awx.svc.cluster.local:80/api/v2/...      │
└────────────────────────────────────────────────────────────────────┘
```

### 4.1 Approved decisions (already baked into Phase 1)

| Decision | Choice | Rationale |
|---|---|---|
| Lifecycle | **Kubernetes Job** (one per playbook run) | Clean per-run state; matches `kubectl logs` ergonomics; mirrors AWX EE |
| Code distribution | **kubectl cp tarball** | No Forgejo dependency (Forgejo may not be up yet); operator working tree is source of truth |
| Image | **`quay.io/ansible/awx-ee:latest`** (spike) | Has ansible, kubectl, helm, python kubernetes.core; trusted upstream |
| Secrets | **Mounted Secret with breakglass JSON** | Reuses today's breakglass model; deleted by trap |
| RBAC | **cluster-admin** (spike); narrow post-spike | Spike proves model; narrowing is a known follow-up |
| Namespace | **`dmf-bootstrap`** | Isolates from app namespaces; cleanup-safe |
| Operator UX | **`bin/run-playbook.sh` dispatches by stage** | Doesn't break ADR-0010 |

---

## 5. Current state (2026-05-14)

### 5.1 Phase 1 — DONE (`dmf-infra@ff36ee8`)

| File | Purpose |
|---|---|
| `roles/stack/operator/ansible-runner/defaults/main.yml` | Variable surface: namespace, SA, ClusterRole, image |
| `roles/stack/operator/ansible-runner/tasks/main.yml` | Idempotent apply of the SA + RBAC manifest; assertion-based verification |
| `roles/stack/operator/ansible-runner/templates/runner-sa.yaml.j2` | Namespace + ServiceAccount + ClusterRoleBinding manifest |
| `roles/stack/operator/ansible-runner/README.md` | Variable docs + scope reminder |
| `playbooks/050-ansible-runner.yml` | One-shot install playbook (numeric prefix `050` to run early in configure-stage) |

This is the infrastructure that every per-run Job will reference. Test
that this layer works (Verification §7.1) before starting Phase 2.

### 5.2 Phases 2–4 — REMAINING

- **Phase 2:** Job template + operator wrapper (`bin/run-playbook-in-cluster.sh`)
- **Phase 3:** `openbao-session` role gets a `mounted-secret` mode
- **Phase 4:** End-to-end test on playbook 698; revert `dmf-infra@37dbb56` to use internal DNS again

---

## 6. Implementation — phase by phase

### 6.1 Phase 2 — Job template + operator wrapper

This is the meat of the spike. Two artifacts:

#### 6.1.1 Job template: `roles/stack/operator/ansible-runner/templates/runner-job.yaml.j2`

Rendered by the operator-side wrapper (NOT by ansible — the wrapper has
the per-run variables). Skeleton:

```yaml
---
apiVersion: batch/v1
kind: Job
metadata:
  name: runner-{{ runid }}
  namespace: {{ ansible_runner_namespace | default('dmf-bootstrap') }}
  labels:
    app.kubernetes.io/name: ansible-runner
    dmf.run/id: "{{ runid }}"
    dmf.run/playbook: "{{ playbook_basename }}"
    dmf.run/env: "{{ env_name }}"
spec:
  completions: 1
  parallelism: 1
  backoffLimit: 0          # don't retry — operator decides
  ttlSecondsAfterFinished: 600   # auto-clean 10min after exit
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ansible-runner
        dmf.run/id: "{{ runid }}"
    spec:
      serviceAccountName: {{ ansible_runner_service_account | default('ansible-runner') }}
      restartPolicy: Never
      initContainers:
        - name: extract-workspace
          image: busybox:1.36
          command:
            - sh
            - -c
            - |
              set -e
              cd /workspace
              tar -xzf /workspace-input/code.tar.gz
              chown -R 1000:1000 /workspace
          volumeMounts:
            - { name: workspace, mountPath: /workspace }
            - { name: workspace-input, mountPath: /workspace-input, readOnly: true }
      containers:
        - name: ansible
          image: {{ ansible_runner_image | default('quay.io/ansible/awx-ee:latest') }}
          imagePullPolicy: {{ ansible_runner_image_pull_policy | default('IfNotPresent') }}
          workingDir: /workspace/k3s-lab-bootstrap
          command:
            - ansible-playbook
            - -i
            - inventories/{{ env_name }}
            - -e
            - "@/etc/dmf-runner-vars/vars.json"
            - playbooks/{{ playbook_basename }}
            {% if extra_args %}
            {% for arg in extra_args %}
            - "{{ arg }}"
            {% endfor %}
            {% endif %}
          env:
            - name: ANSIBLE_CONFIG
              value: /workspace/k3s-lab-bootstrap/ansible.cfg
            - name: HOME
              value: /tmp
            - name: ANSIBLE_HOST_KEY_CHECKING
              value: "False"
          volumeMounts:
            - { name: workspace, mountPath: /workspace }
            - { name: runner-secret, mountPath: /etc/dmf-runner-vars, readOnly: true }
            - { name: breakglass, mountPath: /etc/openbao-breakglass, readOnly: true }
      volumes:
        - name: workspace
          emptyDir: {}
        - name: workspace-input
          configMap:
            name: runner-workspace-{{ runid }}
        - name: runner-secret
          secret:
            secretName: runner-vars-{{ runid }}
        - name: breakglass
          secret:
            secretName: runner-breakglass-{{ runid }}
```

**Gotcha: the tarball-via-ConfigMap doesn't work** for files >1MB (the
k8s ConfigMap size limit). The dmf-infra tarball will exceed this. Two
options:

- **a)** Switch the input from ConfigMap to an empty PVC, and `kubectl cp`
  the tarball INTO a temporary pod that mounts it, before the Job
  starts. Adds a step.
- **b)** Use a **single pod** (not a Job) created by the wrapper, then
  `kubectl cp` directly into the pod's filesystem AFTER it's running.
  Simpler. The wrapper waits for the pod, cp's the tarball, then triggers
  the playbook run via a second `kubectl exec`. Loses some Job ergonomics
  but is the path of least friction.

**Recommended for spike: option (b).** Pivot the manifest from `kind: Job`
to `kind: Pod` with a long-running entrypoint (`sleep infinity` initially);
wrapper does kubectl cp then kubectl exec. Adds an `expectedRunTime`
timeout cap. Revisit Job semantics post-spike with PVC-based code
distribution if needed.

If you take option (b), the manifest simplifies considerably — no
initContainer + ConfigMap dance.

#### 6.1.2 Operator wrapper: `dmf-env/bin/run-playbook-in-cluster.sh`

Mirrors `run-playbook.sh`'s shape so operator UX is consistent. Skeleton:

```bash
#!/usr/bin/env bash
# run-playbook-in-cluster.sh — execute an ansible playbook inside an
# in-cluster runner pod. Used for configure-stage playbooks per ADR-0023
# §Future direction. Provision-stage playbooks must still use
# bin/run-playbook.sh (ADR-0010 entry point — this wrapper is one of its
# branches).
#
# Usage:
#   bin/run-playbook-in-cluster.sh [ENV_NAME] <playbook> [ansible-playbook args...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
cd "$REPO_DIR"

# Arg parsing — same shape as run-playbook.sh
# (env detection, playbook resolution, ansible.cfg auto-discovery)
# ...

# Per-run identifier
RUNID="$(date -u +%Y%m%d-%H%M%S)-$(openssl rand -hex 3)"
NAMESPACE="dmf-bootstrap"
POD_NAME="runner-${RUNID}"

# Cleanup trap — runs on success, failure, SIGINT, exit
cleanup() {
  echo "==> Cleanup: deleting runner-${RUNID} resources" >&2
  kubectl -n "${NAMESPACE}" delete pod "${POD_NAME}" --ignore-not-found --wait=false >&2 || true
  kubectl -n "${NAMESPACE}" delete secret "runner-vars-${RUNID}" "runner-breakglass-${RUNID}" --ignore-not-found --wait=false >&2 || true
}
trap cleanup EXIT INT TERM

# Generate vars file (existing mechanism — reuses bootstrap-secrets.sh)
TMP_VARS_FILE="$(mktemp "${TMPDIR:-/tmp}/openbao-vars-${ENV_NAME}.XXXXXX")"
trap 'rm -f "$TMP_VARS_FILE"; cleanup' EXIT INT TERM
"$SCRIPT_DIR/bootstrap-secrets.sh" export-vars "$ENV_NAME" "$TMP_VARS_FILE"

# Resolve breakglass path from inventory (same logic as get-admin-cred.sh)
BREAKGLASS_FILE="$(parse_yaml_scalar inventories/${ENV_NAME}/group_vars/all/openbao_secrets.yml openbao_key_path).json"

# Create one-shot Secrets
kubectl -n "${NAMESPACE}" create secret generic "runner-vars-${RUNID}" \
  --from-file=vars.json="${TMP_VARS_FILE}"
kubectl -n "${NAMESPACE}" create secret generic "runner-breakglass-${RUNID}" \
  --from-file=keys.json="${BREAKGLASS_FILE}"

# Tarball the working tree
TARBALL="$(mktemp "${TMPDIR:-/tmp}/dmf-runner-code-${RUNID}.tar.gz")"
tar -C "$(dirname "${REPO_DIR}")" -czf "${TARBALL}" \
  dmf-infra/k3s-lab-bootstrap \
  dmf-env/inventories/${ENV_NAME}

# Render Job (or Pod, per §6.1.1 option b) and apply
# ... (template rendering with envsubst or python)
kubectl apply -f /tmp/runner-pod-${RUNID}.yaml
kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod/${POD_NAME} --timeout=60s

# Copy the tarball into the pod
kubectl -n "${NAMESPACE}" cp "${TARBALL}" "${POD_NAME}:/workspace/code.tar.gz"
kubectl -n "${NAMESPACE}" exec "${POD_NAME}" -- tar -C /workspace -xzf /workspace/code.tar.gz

# Execute the playbook, streaming logs
LOG_FILE="/tmp/dmf-playbook-logs/${PLAYBOOK_BASENAME}-${RUNID}.log"
mkdir -p "$(dirname "${LOG_FILE}")"

kubectl -n "${NAMESPACE}" exec "${POD_NAME}" -- \
  ansible-playbook \
    -i "/workspace/dmf-env/inventories/${ENV_NAME}" \
    -e "@/etc/dmf-runner-vars/vars.json" \
    "/workspace/dmf-infra/k3s-lab-bootstrap/playbooks/${PLAYBOOK_BASENAME}" \
    "$@" 2>&1 | tee "${LOG_FILE}"

RC=${PIPESTATUS[0]}
exit "${RC}"
```

**Gotchas:**

- `kubectl cp` is silent on permission errors when the destination
  filesystem is read-only or the tar binary inside the target is BusyBox
  (different flag set). Test on `awx-ee` image first.
- `kubectl exec ... -- ansible-playbook ...` doesn't allocate a TTY by
  default; ansible output should be fine without one.
- The `-e @file` pattern requires the vars file to be readable by the
  ansible-playbook UID inside the container. The `awx-ee` image runs as
  UID 1000; the mounted Secret default mode is 0644 which is readable —
  no chmod needed.

#### 6.1.3 Dispatch in `bin/run-playbook.sh`

Add a stage-detection branch. Configure-stage playbooks are those under
`playbooks/050-*`, `playbooks/600-*`, and `playbooks/69*-*` (the operator
configure chain). Provision-stage is `site.yml`, `lifecycle-provision.yml`,
`playbooks/0**-*` (excluding 050), `playbooks/1**-*`, `playbooks/2**-*`,
`playbooks/3**-*`, `playbooks/4**-*`.

Approach: detect by playbook path matching a known prefix list; fall
through to existing SSH-based path otherwise. Until the runner-pod work
is fully baked, **default to provision-stage path** (i.e. only invoke
the runner-pod transport when the playbook explicitly opts in). Reduces
blast radius during the spike.

A minimal opt-in: introduce env variable `DMF_RUNNER_TRANSPORT=in-cluster`
and let the wrapper switch based on it. Once stable, flip to auto-dispatch
by playbook-prefix.

### 6.2 Phase 3 — `openbao-session` mounted-secret mode

`roles/common/openbao-session/tasks/main.yml` currently reads the
breakglass JSON via `lookup('file', openbao_session_breakglass_file)`
delegated to `localhost` (the operator's machine). Inside the runner
pod, "localhost" IS the pod — and the breakglass JSON is mounted as a
Secret at a known path.

Add a `openbao_session_breakglass_source` variable (default: `localhost`,
runner-pod sets: `mounted`):

```yaml
- name: Load OpenBao break-glass JSON from operator host (localhost mode)
  ansible.builtin.set_fact:
    _openbao_session_breakglass: >-
      {{ lookup('file', openbao_session_breakglass_file) | from_json }}
  delegate_to: localhost
  become: false
  no_log: true
  when: openbao_session_breakglass_source | default('localhost') == 'localhost'

- name: Load OpenBao break-glass JSON from in-pod mount (mounted mode)
  ansible.builtin.set_fact:
    _openbao_session_breakglass: >-
      {{ lookup('file', '/etc/openbao-breakglass/keys.json') | from_json }}
  become: false
  no_log: true
  when: openbao_session_breakglass_source | default('localhost') == 'mounted'
```

The runner-pod's `dmf-env/inventories/<env>/group_vars/all/main.yml`
override (or `-e` from the wrapper) sets
`openbao_session_breakglass_source: mounted`.

### 6.3 Phase 4 — end-to-end test on playbook 698

1. **Install the runner foundation:**
   ```bash
   bin/run-playbook.sh aliyun-123 \
     ../dmf-infra/k3s-lab-bootstrap/playbooks/050-ansible-runner.yml
   ```
   Verify: `kubectl -n dmf-bootstrap get sa,clusterrolebinding`

2. **Revert `dmf-infra@37dbb56`** (the `*_host`-derivation correction):
   restore the internal-DNS defaults in 698 since the caller will now be
   in-pod. **Don't commit yet** — leave as a working-tree change until
   the in-cluster run passes.

3. **Run 698 via the new wrapper:**
   ```bash
   DMF_RUNNER_TRANSPORT=in-cluster \
     bin/run-playbook.sh aliyun-123 \
     ../dmf-infra/k3s-lab-bootstrap/playbooks/698-cms-netbox-forgejo-tokens.yml \
     -e netbox_sot_admin_username=admin \
     -e forgejo_admin_username=<user> \
     -e awx_admin_user=<user> \
     -e cms_forgejo_admin_user=<user>
   ```
   (Note: the drift-related `-e` flags persist — those are App Admin
   Drift Audit territory, separate from this spike. The
   `cms_*_api_url=...` flags are GONE — that's the spike's signal of
   success.)

4. **Watch `kubectl logs -f` stream** — confirm in-pod DNS resolves
   `*.svc.cluster.local`, confirm `PLAY RECAP failed=0`.

5. **If clean:** commit the revert of `37dbb56` with a message linking
   to this plan.

6. **Cleanup verification:** `kubectl -n dmf-bootstrap get all` should
   show only the persistent SA/RBAC after the wrapper exits.

---

## 7. Verification gates

Each phase has a hard gate before the next phase begins.

### 7.1 Phase 1 gate (already passed)

```bash
# Apply runner foundation
bin/run-playbook.sh aliyun-123 \
  ../dmf-infra/k3s-lab-bootstrap/playbooks/050-ansible-runner.yml

# Expect:
#   ok=N changed=M unreachable=0 failed=0
# Then verify:
ssh -i ~/.ssh/id_ed25519_k3s_aliyun k3s-admin@<control-node-ip> \
  "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n dmf-bootstrap get sa,clusterrolebinding | grep ansible-runner"
```

Note: this gate **has not actually been run yet** as of 2026-05-14 (Phase 1
landed in code but not deployed). Re-running the install playbook is
the first concrete action of Phase 2.

### 7.2 Phase 2 gate

- Wrapper script runs and creates a Pod that reaches `Running`
- Tarball cp succeeds; `/workspace/dmf-infra/k3s-lab-bootstrap/` exists in pod
- `kubectl exec` runs `ansible-playbook --version` successfully inside pod
- Cleanup trap removes Pod + both Secrets on wrapper exit (success, failure, SIGINT)

### 7.3 Phase 3 gate

- A trivial test playbook that includes `openbao-session` role with
  `openbao_session_breakglass_source: mounted` succeeds inside the
  runner pod
- The pod's stdout never prints the breakglass JSON contents (no_log
  preserved)

### 7.4 Phase 4 gate (spike success criterion)

- `bin/run-playbook.sh aliyun-123 .../698-cms-netbox-forgejo-tokens.yml`
  via in-cluster transport reaches `PLAY RECAP failed=0`
- Command line contains **no** `-e cms_*_api_url=...` flags
- The revert of `dmf-infra@37dbb56` is committed and verified — defaults
  in 698 are now `http://<svc>.<ns>.svc.cluster.local:<port>`
- `kubectl -n dmf-bootstrap get all` shows clean state (only persistent SA/RBAC)
- Compare to a control run: same playbook via the SSH path with the full
  override list. Both reach `failed=0` for the same logical work. Command
  line diff is the selling point.

---

## 8. Failure modes seen — do not repeat

### 8.1 The `dmf.example.com` placeholder is a trap

Per CLAUDE.md scrub convention, `dmf.example.com` is the fictitious
domain used in public-repo prose. Multiple playbook defaults still use
it as a fallback URL — they fail with NXDOMAIN when the env's `*_host`
override isn't set. Fix at the role default level using the
`*_host`-derivation pattern, not by hand-coding the env's real domain.

### 8.2 ALLOWED_HOSTS / nginx host-header rejection

When switching to internal service DNS, the target app must accept the
internal hostname as a valid `Host:` header. Verified-passing on
aliyun-123 as of 2026-05-14:

- NetBox `netbox.netbox.svc.cluster.local:80/api/` → 200
- Forgejo `forgejo-http.forgejo.svc.cluster.local:3000/api/...` → 401 (auth-aware)
- AWX `awx-service.awx.svc.cluster.local:80/api/v2/ping/` → 200

If you target a new app, **run the in-pod probe first** before changing
the default. Pattern:

```bash
ssh -i ~/.ssh/id_ed25519_k3s_<env> k3s-admin@<ip> \
  "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n <ns> \
    exec deploy/<deploy> -- sh -c 'curl -sS -o /dev/null -w %{http_code} \
    --max-time 3 http://<svc>.<ns>.svc.cluster.local:<port>/<path>'"
```

A `400` "Invalid HTTP_HOST header" means ALLOWED_HOSTS doesn't include
the internal hostname. Fix the app's chart values (add the internal
hostname to ALLOWED_HOSTS or use a wildcard) before migrating.

### 8.3 Forgejo's service name is `forgejo-http`, not `forgejo`

Standard Helm chart pattern: the HTTP-protocol service appends `-http`
to the fullname. Yesterday's `dmf-infra@07d0e00` fixed this for the
NetBox→Forgejo sync.

### 8.4 NetBox API returns `status` as a dict, not a string

`{'value': 'failed', 'label': 'Failed'}` not `"failed"`. Comparisons
must use `.status.value`, not `.status`. Fixed in `dmf-infra@685b32b`.

### 8.5 `ansible.builtin.uri` has no implicit timeout

Default behaviour: if TCP stalls, the call hangs indefinitely. `until`
loops never fire because they only evaluate AFTER each call returns.
Always set `timeout: 30` (or env-appropriate value). Fixed in
`dmf-infra@46a57a7` for one specific task; pattern is generally applicable.

### 8.6 `no_log: true` censors USEFUL diagnostic too

If a task fails with `no_log: true`, the error is hidden. Use a
`block:/rescue:` pattern: try with `no_log`, on failure run a sanitized
debug task that prints fields you've vetted as safe. Example in
`dmf-infra@46a57a7`.

### 8.7 Variable-name fragmentation across playbooks

Same logical identity gets different variable names across playbooks
(`awx_admin_user` in 697 vs `awx_integration_admin_user` in 693 vs
`cms_forgejo_admin_user` in 698 etc.). When migrating a playbook, grep
the role+playbook tree for ALL references to the relevant identity
before assuming one `-e` flag covers it. See the App Admin Drift Audit
plan §5.4 for the full matrix.

### 8.8 In-pod `python` may be `python3`

Some app pods (AWX EE included) don't symlink `python` → `python3`. When
running a python one-liner via `kubectl exec`, use `python3` explicitly,
or check the pod first.

### 8.9 base64 decoding leaves a trailing newline

`base64 -d` of a k8s Secret value adds `\n` to the end. Either `tr -d
'\n'` or `printf '%s'` to strip when piping into a command that expects
a clean password.

### 8.10 Pre-commit gitleaks rules apply to dmf-infra

The `dmf-operator-identity` rule flags occurrences of the operator
username (and similar) in committed files. Don't reference operator-specific
paths in dmf-infra code or docs. Use neutral phrasing or generic
placeholders like `<user>` (per the convention in the umbrella's
`bin/scrub-public-repos.sh`). The umbrella repo has more permissive
rules — env-specific hostnames are OK
there (per existing audit docs); dmf-infra still uses `<placeholder>`
patterns.

---

## 9. Do's and Don'ts

### Do

- ✅ Use `bin/run-playbook.sh` as the entry point. ADR-0010 holds.
- ✅ Test internal-DNS reachability via in-pod probe before migrating a default.
- ✅ Commit each phase as a focused, scoped commit. Use the `feat(ansible-runner): Phase N — ...` message pattern.
- ✅ Run `ansible-playbook --syntax-check -i inventories/example/hosts.ini <playbook>` before commit.
- ✅ Use `block:/rescue:` for any task that should give diagnostics on failure under `no_log`.
- ✅ Always set `timeout:` on `uri:` tasks.
- ✅ For multi-line passwords or secrets, use stdin + `read PW` inside the consuming command. Never argv.
- ✅ Coordinate with sibling agents via `agent-bridge`. Ask the recipient to reply via bridge so notifications fire.

### Don't

- ❌ Don't invoke `ansible-playbook` directly. ADR-0010.
- ❌ Don't echo secrets to stdout (visible in agent transcripts). Use length + sha256 prefix for comparisons.
- ❌ Don't copy `/etc/rancher/k3s/k3s.yaml` off the control node (dmf-cluster-access skill §0.4).
- ❌ Don't paste OpenBao Shamir share values anywhere — `dmf-openbao-unseal` skill is the only sanctioned path.
- ❌ Don't bake `dmf.example.com` placeholders into runtime config; use the `*_host` derivation pattern (until configure-stage moves in-cluster, after which switch to internal DNS).
- ❌ Don't bypass pre-commit hooks (`--no-verify`). If gitleaks fires, the leak is real — scrub the content.
- ❌ Don't break the override list for App Admin Drift unintentionally. Those `-e` flags address a SEPARATE concern (live cluster ≠ playbook source-of-truth on admin user/password) and persist regardless of the runner-pod migration. See App Admin Drift Audit plan.
- ❌ Don't widen the runner-pod's RBAC beyond `cluster-admin` (spike). And remember to narrow it post-spike.

---

## 10. Post-spike work (out of scope for this implementation, but on the runway)

When Phase 4 gate passes:

### 10.1 ADR cascade

- **New ADR-0025** — "Configure-stage ansible runs in an in-cluster
  ephemeral runner pod." Status: Accepted. References ADR-0010 (entry
  point), ADR-0012 (lifecycle split), ADR-0023 (internal DNS realised).
- **ADR-0010 amendment** — note the runner-pod transport pivot for
  configure-stage. Status remains Accepted; no supersession.
- **ADR-0023 simplification** — drop the §Scope caveat about
  control-node callers (it no longer applies once configure-stage moves
  in); §Future direction becomes "Realised by ADR-0025".

### 10.2 RBAC narrowing

The `cluster-admin` ClusterRoleBinding is spike-only. Post-spike, replace
with a Role/ClusterRole that grants exactly what the configure-stage
playbooks need:

- get/create/patch on `configmaps` and `secrets` in target namespaces
  (`netbox`, `awx`, `forgejo`, `authentik`, `cms`, `openbao`, `zot`, ...)
- get/list/watch on `pods`, `services`, `deployments` cluster-wide (for
  health checks)
- CRDs: `awx.ansible.com/awxs/*`, `bao.openbao.io/*` (etc.)

Build this list by capturing the AuditPolicy events of a spike run and
deriving the minimal grant set.

### 10.3 Migration of remaining configure-stage playbooks

Per the spike plan's §Migration path, order:

1. ✅ 698-cms-netbox-forgejo-tokens (spike target)
2. 697-cms-awx-token
3. 696-cms-authentik-api (mostly kubectl-exec; trivial)
4. 691-netbox-sot
5. 692-forgejo-bootstrap
6. 693-awx-integration
7. 694-born-inventory
8. 699-cms-smoke-test
9. 600-series

Each migration drops more `-e cms_*_api_url=` flags from the override
list.

### 10.4 OpenBao k8s auth method

Eventually the runner-pod's SA should authenticate to OpenBao via the
k8s auth method (mounted SA token → OpenBao validates → issues client
token), eliminating the breakglass Secret mount. Out of scope for spike;
prerequisite is OpenBao's k8s-auth being configured (it likely is — check
ADR-0008 / OpenBao role).

### 10.5 Image refinement

`quay.io/ansible/awx-ee:latest` is fine for spike but heavy. Post-spike,
consider:

- Pinning to a specific digest (reproducibility)
- Building a slimmer custom image with just the collections actually used
- Hosting in the in-cluster Zot registry (closes the supply chain)
  — **landed earlier than expected as Lane A of the 2026-05-19 plan; this
  bullet is the trigger for the anchor flip noted at the top of this doc.**

---

## 11. Reference index

### 11.1 Skills (canonical procedures)

| Skill | When to read |
|---|---|
| `dmf-cluster-access` | Any cluster operation. §0 + §3 are required reading. |
| `dmf-openbao-unseal` | If OpenBao is sealed and you need to unseal to continue. |
| `dmf-cms-build-and-release` | Not directly relevant to this spike. |
| `agent-bridge` (in `~/.claude/skills/`) | Multi-agent coordination. |

### 11.2 Related plans

| Plan | Relationship |
|---|---|
| `DMF App Admin Account Drift Audit and Realignment Plan 2026-05-14.md` | Separate workstream; explains the drift-related `-e` overrides that persist regardless of the runner-pod migration |
| `DMF Internal Service DNS Migration Survey 2026-05-14.md` | The migration plan that this spike enables; tracks per-file internal-vs-public URL classification |

### 11.3 Related ADRs

| ADR | Topic |
|---|---|
| ADR-0006 | Cluster is the truth, not local kubectl |
| ADR-0010 | `bin/run-playbook.sh` is the sanctioned entry point |
| ADR-0012 | Configure stage distinct from provision stage |
| ADR-0016 | AWX↔control-node SSH via cloud-init pubkey + OpenBao privkey |
| ADR-0023 | Internal service DNS for cross-app wiring |

### 11.4 Today's session commits

`dmf-infra`:

| Commit | Topic |
|---|---|
| `46a57a7` | netbox-sot: block/rescue + timeout:30 on sync wait |
| `685b32b` | netbox-sot: compare `.status.value` not the dict |
| `07d0e00` | netbox-sot: correct Forgejo internal DNS name to `forgejo-http` |
| `1d9d1eb` | forgejo-bootstrap: PATCH includes `active: true` |
| `7b006ee` | netbox-sot: PATCH `source_url`; `default('...', true)` for empty host |
| `3e7a9d0` | dmf-born-inventory: `librenms_host \| default('')` |
| `3457513` | cms-tokens: defaults to internal service DNS (later corrected) |
| `37dbb56` | cms-tokens: derive defaults from `*_host` (control-node caller-location) |
| `ff36ee8` | **ansible-runner Phase 1 — foundation role + install playbook** |

`umbrella`:

| Commit | Topic |
|---|---|
| `67073e3` | docs(plans): fill aliyun-123 audit rows |
| `c1a9167` | docs(plans): record variable-fragmentation finding |
| `bfeb7f2` | docs(adr+plans): ADR-0023 + migration survey |
| `a9fc882` | docs(adr-0023+plan): add caller-location scope after run-11 discovery |

---

## 12. Glossary

- **Configure stage** — bootstrap lifecycle stage that wires the k3s
  cluster's apps together. Imports `playbooks/691-…` through
  `playbooks/699-…` in `bootstrap-configure.yml`. Provision stage runs
  before this and brings up the cluster itself.
- **Breakglass file** — JSON file on the operator's encrypted JuiceFS
  containing the OpenBao operator userpass credentials + Shamir share
  metadata. Used by `bin/run-playbook.sh` and `bin/get-admin-cred.sh`
  to bootstrap OpenBao access.
- **`bin/run-playbook.sh`** — operator's sanctioned ansible wrapper per
  ADR-0010. The new runner-pod transport becomes a branch in this
  wrapper, not a separate entry point.
- **Pod-to-pod / runtime call** — HTTP call made by a workload pod at
  runtime to another workload pod. CoreDNS resolves
  `*.svc.cluster.local`; ADR-0023 applies.
- **Control-node ansible call** — HTTP call made by an `ansible.builtin.uri:`
  task running on the ansible target host (the control-node VM). Today's
  resolver path is the node's `/etc/resolv.conf` — no CoreDNS. The
  runner-pod migration collapses this category.
- **ADR cascade** — set of ADR updates that follow a single decision
  ripple. Here: a new ADR captures the runner-pod decision; ADR-0023
  simplifies; ADR-0010 picks up an amendment note.
- **Spike** — a time-boxed proof of concept to validate that an approach
  works before committing to a full migration. Phase 4 gate is the
  spike's success criterion.

---

## 13. Open questions (track these; don't block on them)

1. **Tarball-via-ConfigMap vs Pod-with-kubectl-cp.** §6.1.1 recommends
   option (b) for spike simplicity. Validate before committing to a Job
   manifest design.
2. **Tailscale-vs-SSH for kubectl.** The wrapper needs cluster API access
   from the operator's mac. `dmf-cluster-access` skill documents both;
   wrapper should prefer Tailscale if available. Not blocking.
3. **OpenBao k8s auth migration timing.** Currently mounting breakglass
   Secret per-run. Future: SA-based auth. Don't conflate with spike.
4. **AuditPolicy capture for RBAC narrowing.** Required for post-spike
   RBAC tightening — capture during the first successful spike run.

---

## 14. Acceptance criteria (this implementation plan)

This plan is complete enough to hand off when:

- [ ] Phase 1 gate is verified by running `050-ansible-runner.yml` against `aliyun-123`
- [ ] Phase 2 artifacts (Job/Pod template + wrapper) are landed and verifiably create a runnable runner pod
- [ ] Phase 3 artifact (openbao-session mounted-secret mode) is landed and a smoke test confirms it
- [ ] Phase 4 gate is achieved: 698 runs end-to-end in-cluster with no `cms_*_api_url` overrides; internal-DNS defaults reverted on 698 are committed
- [ ] §11.4 commits table is updated through the spike
- [ ] ADR-0025 is drafted (post-spike, but plan tracks it)

When all six are checked, the spike concludes and the migration plan
(see §11.2) takes over for per-playbook rollout.
