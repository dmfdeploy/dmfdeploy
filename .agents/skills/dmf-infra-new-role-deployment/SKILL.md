---
name: dmf-infra-new-role-deployment
description: Pattern for deploying a new monitoring/stack component to the k3s cluster via Ansible roles in dmf-infra — study sibling → mirror anatomy → static checks → parallel-safe commit
source: auto-skill
extracted_at: '2026-06-01T09:00:00.000Z'
---

# dmf-infra — New Component Role Deployment Pattern

When deploying a new component (exporter, adapter, service) to the k3s
cluster via dmf-infra Ansible roles, follow this workflow. Validated
against WP2 (blackbox-exporter) and WP4-B (dmf-promsd adapter).

## §0 — Study First (never write from scratch)

Find the **closest sibling role** by deployment mechanism:

| Mechanism | Study this role | Path prefix |
|---|---|---|
| Helm chart from public registry (prometheus-community, grafana, etc.) | `k3s-lab-bootstrap/roles/base/prometheus/` | `roles/base/<component>/` |
| Inline k8s manifests (no Helm chart) | `k3s-lab-bootstrap/roles/stack/operator/authentik/` (ESO pattern) or `cms/` | `roles/stack/operator/<component>/` |
| Custom Helm chart with values templating | `k3s-lab-bootstrap/roles/stack/operator/cms/` | `roles/stack/<layer>/<component>/` |

Read all files: `tasks/main.yml`, `defaults/main.yml`,
`templates/*.j2`, and the corresponding vertical playbook
(`playbooks/vertical-*/` matching the component's domain).

## §1 — Role Anatomy (mirror exactly)

### Directory layout
```
roles/base/<component>/          # or roles/stack/<layer>/<component>/
├── defaults/main.yml            # All vars with defaults
├── tasks/main.yml               # Task sequence
└── templates/                   # Helm values or config templates
    └── values.yml.j2
```

### defaults/main.yml — var conventions
- Namespace: `<component>_namespace` (default from domain, e.g. `monitoring`)
- Image: `<component>_image_repository` (Zot path: `registry.<domain>/<name>`)
- Image tag: `<component>_image_tag` reads `<repo>/VERSION` via
  `lookup('file', playbook_dir ~ '/../../../<repo>/VERSION') | trim`
- Resources: `<component>_resources` with requests/limits (sandbox-sized)
- ESO: `<component>_eso_*` for ExternalSecret refs
- NetBox/internal svc: `<component>_netbox_url` =
  `"http://netbox.<netbox_namespace>.svc.cluster.local"` (ADR-0023)

### tasks/main.yml — task sequence patterns

**For Helm-based roles** (blackbox, prometheus, loki, promtail):
1. Create namespace (`kubernetes.core.k8s`)
2. Add Helm repo (`kubernetes.core.helm_repository`)
3. Template values to `/tmp/<component>-values.yml`
4. Deploy via Helm (`kubernetes.core.helm` with wait)
5. Wait for rollout (`k3s kubectl rollout status deployment/<name>`)
6. Cleanup temp values file

**For inline manifest roles** (dmf-promsd, ESO secrets):
1. Create namespace
2. Create ExternalSecret (if needed)
3. Deploy Deployment (`kubernetes.core.k8s`)
4. Create Service
5. Wait for rollout

### Playbook pattern (`playbooks/vertical-*/`)
```yaml
- name: Deploy <component>
  hosts: k3s_control
  become: true
  gather_facts: false
  roles:
    - base/cluster-ready
    - <path/to/component>
```

### Playbook numbering
- `vertical-monitoring/`: 100s (100-prometheus, 110-loki, 120-grafana, 130-promtail, 140-librenms, 150-blackbox, 160-promsd)
- `vertical-security/`, `vertical-orchestration/`: follow existing numbers

## §2 — Zot Seed (for custom images)

If the component has a Docker image that needs to be in the cluster-internal
Zot registry, update `playbooks/630-zot-seed-platform.yml`:

1. Add `<component>_image_tag` var (reads `../<repo>/VERSION` like `dmf_cms_image_tag`)
2. Append to `zot_seed_images` list:
   ```yaml
   - name: <component>
     tag: "{{ <component>_image_tag }}"
     zot_repo: "{{ zot_registry_host }}/<component>"
   ```
3. Source = `ghcr.io/dmfdeploy/<component>` (canonical public source)

## §3 — ESO ExternalSecret Pattern (for OpenBao-backed secrets)

When a component needs a secret from OpenBao:
```yaml
- name: Create <component> ExternalSecret
  kubernetes.core.k8s:
    kubeconfig: /etc/rancher/k3s/k3s.yaml
    state: present
    definition:
      apiVersion: external-secrets.io/v1beta1
      kind: ExternalSecret
      metadata:
        name: <component>-<purpose>
        namespace: {{ <component>_namespace }}
      spec:
        refreshInterval: 1h
        secretStoreRef:
          name: openbao
          kind: ClusterSecretStore
        target:
          name: <component>-<purpose>
          creationPolicy: Owner
        data:
          - secretKey: <k8s_key>
            remoteRef:
              key: "secret/apps/<source>/runtime"
              property: "<openbao_property>"
  no_log: true
```

## §4 — Static Checks (no live cluster)

Before committing:
```bash
# Syntax check
cd k3s-lab-bootstrap
ansible-playbook --syntax-check -i localhost, playbooks/vertical-*/<N>-<name>.yml

# YAML validation (defaults parse via ansible)
ansible localhost -m include_vars -a "file=roles/.../defaults/main.yml"

# Render values.yml.j2 mentally or with a dummy render to confirm valid YAML
```

Expected output: `[WARNING]: Could not match supplied host pattern` is normal
(localhost isn't in the real inventory); `playbook: ...` confirms clean parse.

## §5 — Parallel Commit Safety

When multiple agents work in the same repo simultaneously:
- **NEVER** use `git add -A` or `git add .`
- **ALWAYS** use explicit paths: `git add path/to/file1 path/to/file2 ...`
- Verify with `git diff --cached --stat` before committing
- Conventional commit message: `feat(<domain>): <summary>`

## §6 — Image Sourcing Investigation

When deciding whether a component needs a Zot image override:
1. Check how the closest sibling role sources its images
2. **Helm charts from prometheus-community/grafana** pull images directly
   from public registries (no `imagePullSecrets`, no Zot override needed)
3. Only custom in-house images (dmf-cms, dmf-promsd, awx-ee) need Zot seeding
4. Report findings in commit message or handoff
