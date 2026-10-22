# ADR-0016 archive: AWX↔control-node SSH via cloud-init pubkey + OpenBao privkey (Path A)

This file holds material moved out of [ADR-0016](../../decisions/0016-awx-control-node-ssh-via-cloud-init-and-openbao.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **EE-as-runtime with custom EE.** Closer to native AWX-on-Kubernetes and
  GitOps patterns. Defers to a future ADR: requires `ansible-builder` workflow,
  Zot hosting, ExecutionEnvironment resource, ServiceAccount + RoleBinding,
  awx-operator config to inject the SA into ephemeral EE pods, and
  `kubeconfig: "{{ kubeconfig | default(omit) }}"` plumbing in every k8s
  task. Substantially more infrastructure than Path A; the right answer when
  the platform has more than one media function in production but overkill
  for the experiment phase (ADR-0004).
- **kubectl shell-out.** Replace `kubernetes.core.k8s` with `command: kubectl
  apply -f -` in role tasks. Default EE has `kubectl`; no Python package
  needed. Loses idempotency-by-diff and adds YAML-rendering boilerplate.
  Acceptable as an emergency unblock, not a sustained pattern.
- **Embed private key in role defaults "for Gate 2 spike."** Tried during the
  incident. Violates ADR-0007 §1, leaks via tracked file in a public repo,
  and requires a complete cluster redeploy to remediate. Not an alternative;
  a cautionary example.

## References

- Incident review:
  `docs/reviews/dmf-move1-gate2-ssh-credential-incident.md`
- AWX EE review:
  `docs/reviews/dmf-move1-gate2-awx-ee-review.md`
- Trials doc: `docs/plans/move-1-gate-2-trials-and-tribulations.md`
- ADR-0007 (secrets never in argv/env/tmp/transcripts)
- ADR-0008 (OpenBao + ESO + AppRole shim)
- ADR-0010 (`bin/run-playbook.sh` is the sanctioned entry)
- ADR-0014 (AWX project layout)
- Cloud-init template: `dmf-env/terraform/modules/hetzner-cluster/templates/user-data.yml.tftpl`
- Reference impl for stdin secret transport: `dmf-env/bin/unseal-openbao.sh`
- Reference impl for OpenBao read pattern:
  `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo-bootstrap/tasks/main.yml`
  (lines around 467–522, 230–261)

## Context — Gate 2 spike and incident (moved from the ADR)

The Gate 2 spike attempted (1) under `connection: local`, hit a string of
issues (custom EE not available, in-cluster auth requires `default(omit)`,
ServiceAccount RBAC absent), then attempted (2) but produced an ADR-0007
violation: a real ed25519 private key was committed in plaintext to
`awx-integration/defaults/main.yml` "for Gate 2 spike." The incident is
documented in
`docs/reviews/dmf-move1-gate2-ssh-credential-incident.md` and
triggered a complete cluster redeploy (Path Y).

## Amendment 2026-05-19 — reason and evidence (moved from the ADR)

**Reason:** the first media-launcher run on `aliyun-123` (AWX job 44,
2026-05-17) failed with `UNREACHABLE!` because
`dmf-runbooks/playbooks/launch-nmos-cpp.yml:28-34` hardcoded the Hetzner
private subnet (`10.0.0.4/3/2`); aliyun-123's private subnet is
`10.0.0.40-42`. The `ansible_host` remap is a symptom — the deeper issue
is that the launcher is using SSH-to-control-node for a workload that
has nothing node-local about it. Each new env adds another per-env band-aid
unless the SSH hop is removed for this class of work.
