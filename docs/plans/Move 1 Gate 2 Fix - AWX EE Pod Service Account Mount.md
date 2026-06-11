---
status: superseded
date: 2026-05-05
superseded_by: "Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md"
---
# Move 1 Gate 2 Fix: AWX Execution Environment Pod Service Account Mount
> **Superseded by** [Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md](Move%201%20Gate%202%20-%20Pivot%20to%20Path%20A%20for%20Catalog%20Launchers%202026-05-06.md) — see frontmatter.

> **SUPERSEDED 2026-05-23** by ADR-0025 Lane B. Catalog launcher pod placement
> is now handled by an AWX Container Group plus target-namespace RBAC, not the
> historical `spec.ee_pod_spec_override`/SA-mount fragment below.
>
> **⚠️ SUPERSEDED (2026-05-06)** — by [`Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md`](Move%201%20Gate%202%20-%20Pivot%20to%20Path%20A%20for%20Catalog%20Launchers%202026-05-06.md).
>
> The in-cluster SA-mount approach proved infeasible in the project's experiment phase: the implementation surface area (custom EE image, SA + RBAC, `InstanceGroup.pod_spec_override` serialization, JT EE wiring, K8S_AUTH_* env plumbing) was large and the failure modes were silent — see ~20 iterative commits in `dmf-runbooks` that never converged.
>
> Catalog launchers now use the same execution model the layer playbooks already use per ADR-0016 Path A: SSH to the k3s control node, `become: true`, `KUBECONFIG=/etc/rancher/k3s/k3s.yaml`, `kubernetes.core.k8s` reads the config natively. ADR-0012's Configure-vs-Provision stage split is unaffected. Validated end-to-end by AWX job 285 (`media-launch-nmos-cpp`, dmf-runbooks commit `e86ae24`).
>
> The SA / pod_spec_override work is preserved below only as historical context.
> ADR-0025's Container Group path is the current implementation.
>
> This document remains for historical context — what was tried, why it didn't fit, what we learned.

---

**Status:** Implementation help doc for next agent  
**Date:** 2026-05-06  
**Blocker:** NMOS-CPP launch jobs fail at kubeconfig read stage (in-cluster SA token not mounted)  
**Error signature:** `file not found: /var/run/secrets/kubernetes.io/serviceaccount/token`

---

## The Problem

When `media-launch-nmos-cpp` job runs in AWX, the playbook tries to read the in-cluster service account files:

```yaml
- name: Include nmos-cpp role (configure stage)
  ansible.builtin.include_role:
    name: nmos-cpp
```

The `nmos-cpp` role tries to read the token and CA:

```yaml
- name: Get in-cluster service account token
  ansible.builtin.slurp:
    src: /var/run/secrets/kubernetes.io/serviceaccount/token
  register: k8s_token
```

**Result:** `fatal: [localhost]: FAILED! => {"msg": "file not found: /var/run/secrets/kubernetes.io/serviceaccount/token"}`

**Root cause:** The AWX execution environment pod doesn't have the Kubernetes service account volume mounted. By default, Kubernetes auto-mounts the service account into pods, but AWX operator pod specs may override this or not set it explicitly.

---

## The Fix: Three-Part Implementation

### Part 1: Create Service Account with RBAC (dmf-infra)

**File:** `k3s-lab-bootstrap/roles/stack/operator/awx/tasks/service-account.yml` (create new)

```yaml
---
# AWX execution environment pod service account + RBAC
# Allows launcher jobs to create/manage Kubernetes resources

- name: Create awx-runner service account
  kubernetes.core.k8s:
    kubeconfig: /etc/rancher/k3s/k3s.yaml
    state: present
    definition:
      apiVersion: v1
      kind: ServiceAccount
      metadata:
        name: awx-runner-sa
        namespace: "{{ awx_namespace }}"
        labels:
          app.kubernetes.io/name: awx
          app.kubernetes.io/component: runner

- name: Create cluster role for awx-runner (catalog job execution)
  kubernetes.core.k8s:
    kubeconfig: /etc/rancher/k3s/k3s.yaml
    state: present
    definition:
      apiVersion: rbac.authorization.k8s.io/v1
      kind: ClusterRole
      metadata:
        name: awx-runner-catalog
        labels:
          app.kubernetes.io/name: awx
          app.kubernetes.io/component: runner
      rules:
        # Permissions for catalog entry lifecycle (Provision/Configure/Finalise)
        - apiGroups: [""]
          resources: ["namespaces", "configmaps", "persistentvolumeclaims"]
          verbs: ["create", "get", "list", "watch", "patch", "update"]
        - apiGroups: ["apps"]
          resources: ["deployments", "statefulsets"]
          verbs: ["create", "get", "list", "watch", "patch", "update", "delete"]
        - apiGroups: [""]
          resources: ["services"]
          verbs: ["create", "get", "list", "watch", "patch", "update", "delete"]
        # Permissions for pod exec (for OpenBao reads, NetBox API via pod proxies)
        - apiGroups: [""]
          resources: ["pods"]
          verbs: ["get", "list", "watch"]
        - apiGroups: [""]
          resources: ["pods/exec"]
          verbs: ["create"]

- name: Bind awx-runner to catalog role
  kubernetes.core.k8s:
    kubeconfig: /etc/rancher/k3s/k3s.yaml
    state: present
    definition:
      apiVersion: rbac.authorization.k8s.io/v1
      kind: ClusterRoleBinding
      metadata:
        name: awx-runner-catalog
        labels:
          app.kubernetes.io/name: awx
          app.kubernetes.io/component: runner
      roleRef:
        apiGroup: rbac.authorization.k8s.io
        kind: ClusterRole
        name: awx-runner-catalog
      subjects:
        - kind: ServiceAccount
          name: awx-runner-sa
          namespace: "{{ awx_namespace }}"
```

**Integration:** Add to `roles/stack/operator/awx/tasks/main.yml`:

```yaml
- name: Configure AWX runner service account
  ansible.builtin.include_tasks: service-account.yml
```

### Part 2: Configure AWX Operator Pod Spec Override (dmf-infra)

**File:** `k3s-lab-bootstrap/roles/stack/operator/awx/defaults/main.yml` (add)

```yaml
# AWX execution environment pod spec overrides
awx_ee_pod_spec_override: |
  {
    "serviceAccountName": "awx-runner-sa",
    "automountServiceAccountToken": true,
    "containers": [
      {
        "name": "awx-ee",
        "volumeMounts": [
          {
            "name": "sa-token",
            "mountPath": "/var/run/secrets/kubernetes.io/serviceaccount",
            "readOnly": true
          }
        ]
      }
    ],
    "volumes": [
      {
        "name": "sa-token",
        "projected": {
          "sources": [
            {
              "serviceAccountToken": {
                "audience": "https://kubernetes.default.svc.cluster.local",
                "expirationSeconds": 3600,
                "path": "token"
              }
            },
            {
              "configMap": {
                "name": "kube-root-ca.crt",
                "items": [
                  {
                    "key": "ca.crt",
                    "path": "ca.crt"
                  }
                ]
              }
            },
            {
              "downwardAPI": {
                "items": [
                  {
                    "path": "namespace",
                    "fieldRef": {
                      "apiVersion": "v1",
                      "fieldPath": "metadata.namespace"
                    }
                  }
                ]
              }
            }
          ]
        }
      }
    ]
  }
```

**File:** `k3s-lab-bootstrap/roles/stack/operator/awx/templates/awx-instance.yml.j2` (add to spec)

```yaml
  # Execution environment pod configuration for catalog jobs
  ee_pod_spec_override: {{ awx_ee_pod_spec_override | to_json }}
```

### Part 3: Verify Job Template Configuration (dmf-infra)

**File:** `k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml` (update around line 450+)

Ensure job template creation includes:

```yaml
- name: Create media-launch-nmos-cpp job template
  ansible.builtin.uri:
    url: "{{ awx_url }}/api/v2/job_templates/"
    method: POST
    headers:
      Authorization: "Bearer {{ awx_token }}"
      Content-Type: "application/json"
    body_format: json
    body:
      name: media-launch-nmos-cpp
      description: "NMOS-CPP configure launcher (catalog entry)"
      project: "{{ dmf_runbooks_project.id }}"
      playbook: launch-nmos-cpp.yml
      inventory: "{{ awx_localhost_inventory.id }}"
      execution_environment: "{{ default_ee.id }}"  # ← Use the default EE (which now has pod spec)
      extra_vars: |
        {
          "nmos_stage": "configure",
          "netbox_api_token": "{{ vault_netbox_api_token }}"
        }
      verbosity: 1
      ask_tags_on_launch: false
  register: media_launch_job_template
  changed_when: media_launch_job_template.status == 201
```

---

## Acceptance Criteria

**Before:** Job fails at "file not found: /var/run/secrets/kubernetes.io/serviceaccount/token"

**After:** Job succeeds through to NetBox API call (may fail on netbox_api_token if not yet fixed, but kubeconfig generation passes)

**Verification:**

```bash
# 1. Check service account exists
kubectl get sa -n awx | grep awx-runner-sa

# 2. Check RBAC role binding
kubectl get rolebinding,clusterrolebinding | grep awx-runner

# 3. Launch job from AWX UI
# Settings > Jobs > media-launch-nmos-cpp > Launch
# Check job log for:
#   - "TASK [nmos-cpp : Ensure registry PVC exists]" (not skipped)
#   - No "file not found" errors
#   - Reaches the Kubernetes module tasks

# 4. Optional: kubectl exec into a pod and verify SA mount
kubectl exec -it -n awx deploy/awx-task -- sh
ls -la /var/run/secrets/kubernetes.io/serviceaccount/
cat /var/run/secrets/kubernetes.io/serviceaccount/token | wc -c  # should be >100 chars
```

---

## ADR References

- **ADR-0014** — AWX multi-project layout, roles_path configuration
- **ADR-0012** — Lifecycle stages (Configure stage invokes catalog launchers)
- **ADR-0013** — Catalog model (NetBox integration requires Kubernetes API access from jobs)

---

## Known Risks

1. **RBAC scope** — The role above grants cluster-wide permissions. For multi-cluster, consider namespaced roles + binding-per-namespace.

2. **Service account token TTL** — The projected token has 1-hour expiry. For long-running jobs (>1hr), this may cause mid-flight auth failures. Monitor first, increase TTL if needed.

3. **Pod spec override syntax** — The JSON format is AWX operator-specific. If AWX version changes, pod spec override field names may diverge. Check operator CRD on upgrade.

---

## Implementation Checklist

- [ ] Create `service-account.yml` in awx role
- [ ] Add service-account.yml include to awx/tasks/main.yml
- [ ] Add `awx_ee_pod_spec_override` to awx/defaults/main.yml
- [ ] Update awx-instance.yml.j2 to include ee_pod_spec_override
- [ ] Verify job template config uses default EE
- [ ] Run 640-awx.yml to apply changes (this will trigger AWX operator reconciliation)
- [ ] Test launch from AWX UI
- [ ] Check job log for kubeconfig generation success
- [ ] If netbox_api_token undefined error appears next, that's the Part 1 fix from the sanity check

---

## References

- **AWX Operator CRD:** https://github.com/ansible/awx-operator/blob/devel/roles/awx/templates/awx-instance.yml
- **Kubernetes Service Account Documentation:** https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/
- **AWX Job Template Execution:** docs/plans/dmf-platform-move-1-task-2026-05-04.md § "Step 5: Launch media-launch-nmos-cpp from AWX UI"

---

**Next agent:** After this fix lands, the job will likely fail on `netbox_api_token` undefined (captured in the sanity check doc). That's expected — fix this service account mount issue first, then move to the Part 2 fix (netbox_api_token extra_vars).
