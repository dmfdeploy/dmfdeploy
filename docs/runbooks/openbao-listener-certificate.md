# OpenBao Listener Certificate

**Status:** Operator-facing runbook. Procedure to move an environment from the
self-signed OpenBao certificate to the OpenBao CA, to renew the OpenBao
certificate, and to renew the CA.

**Audience:** the human operator. Agents may run the read-only checks. Run the
plays with the operator's go-ahead.

## When to run this procedure

- **Move an existing environment.** The environment was installed before the
  OpenBao CA existed, so OpenBao still serves a self-signed certificate. A new
  install needs no move.
- **Renew the OpenBao certificate.** cert-manager has renewed the `openbao`
  Certificate, or you forced a renewal, and the running pods still serve the old
  certificate. Until the OpenBao upgrade in
  [#902](https://github.com/dmfdeploy/dmfdeploy/issues/902) reloads the
  certificate by itself, the reload happens when `320-cert-manager.yml` runs.
- **Renew the CA.** The root Certificate is near its renewal window or its
  expiry.

For the design, see the dmf-infra document
[OpenBao Bootstrap And Security Model](https://github.com/dmfdeploy/dmf-infra/blob/main/docs/openbao-bootstrap-security-model.md),
section "Certificate Authority For OpenBao TLS".

## How the pieces fit

A CA in the `openbao` namespace signs the certificate that OpenBao serves. The
Secret `openbao-tls` holds the certificate and the CA's `ca.crt`. Clients trust
the CA, never the certificate, so a renewal of the certificate changes nothing
that a client trusts. A running OpenBao server reads its listener certificate at
startup and on `SIGHUP`, and `320-cert-manager.yml` sends the `SIGHUP` to each
running pod after each issuance.

## Prerequisites

- OpenBao is unsealed on `<env>`. If it is sealed, follow the
  [`dmf-openbao-unseal`](../../.agents/skills/dmf-openbao-unseal/SKILL.md)
  procedure first.
- `kubectl` reaches `<env>` (see the
  [`dmf-cluster-access`](../../.agents/skills/dmf-cluster-access/SKILL.md)
  skill).
- You run the plays from `dmf-env` with `bin/run-playbook.sh <env> <playbook>`,
  from a checkout of dmf-infra at `origin/main`.
- For a move on a Raft cluster, an `ops-admin` token in `OPENBAO_GUARD_TOKEN`
  for the restart play. Keep it out of the command line and the transcript
  ([ADR-0007](../decisions/0007-secrets-never-in-argv.md)).

All playbook paths below are under `dmf-infra/k3s-lab-bootstrap/playbooks/`.

## A. Move an environment from the self-signed certificate to the CA

Run the plays in this order.

1. Run `320-cert-manager.yml`. It creates the CA, issues the `openbao`
   certificate from it, proves the issuance, and reloads every running OpenBao
   pod. The play stops at the first pod that fails its check.

   Until a pod reloads, its CLI can fail with an `x509` error, because the old
   pods point `BAO_CACERT` at the certificate file, and that file now holds the
   new certificate. The reload clears the error.
2. Run `vertical-orchestration/100-eso.yml`. It puts the CA certificate in the
   main `ClusterSecretStore`.
3. If object storage is on, run
   `vertical-resilience/100-object-storage-credentials.yml`. It puts the CA
   certificate in the per-class stores.
4. Run `vertical-security/100-openbao.yml`. It waits for a Secret that the CA
   issued, then applies the new configuration and pod spec (`ca.crt` for
   `BAO_CACERT` and for `retry_join`).
   - A single replica restarts by itself and comes back sealed. The role
     unseals it.
   - A Raft cluster uses the OnDelete update strategy, so nothing restarts.
     Restart one pod at a time with `vertical-security/103-openbao-restart-pod.yml`,
     standbys first and the leader last, and unseal each pod before the next:

     ```bash
     # <pod> is openbao-0, openbao-1, ...; OPENBAO_GUARD_TOKEN is set in the shell.
     bin/run-playbook.sh <env> \
       ../dmf-infra/k3s-lab-bootstrap/playbooks/vertical-security/103-openbao-restart-pod.yml \
       -e openbao_restart_pod_name=<pod>
     ```

     In the sandbox lane only, add `-e openbao_restart_unseal_from_automation_file=true`
     to unseal from the automation file. Otherwise unseal with the shares, as the
     [`dmf-openbao-unseal`](../../.agents/skills/dmf-openbao-unseal/SKILL.md)
     skill describes.

The stores report not ready between step 1 and steps 2 and 3, because they still
hold the old self-signed certificate. The ExternalSecrets keep their last values
meanwhile. Run steps 2 and 3 right after step 1. They do not need the new pod
spec.

### Verify the move

1. Each pod trusts the CA:

   ```bash
   kubectl -n openbao exec <pod> -- printenv BAO_CACERT
   ```

   The output is `/openbao/config/tls/ca.crt`.
2. Every pod is unsealed, and all pods report the same Raft index (compare the
   `Raft Committed Index` lines of `bao status` in each pod).
3. The `ClusterSecretStore` is valid:

   ```bash
   kubectl get clustersecretstore
   ```

   Every store shows `Valid`.
4. The ExternalSecrets are synced:

   ```bash
   kubectl get externalsecret -A
   ```

   Every row shows `SecretSynced`.

## B. Renew the OpenBao certificate

cert-manager renews the `openbao` Certificate on its own schedule, and the
kubelet writes the new files into each pod within about a minute. A running
server keeps its old certificate until it reloads, and the old certificate stays
valid for the days that remain after the renewal. Reload within that window:

1. Run `320-cert-manager.yml`. The play waits until each pod holds the new files,
   sends `SIGHUP`, and compares the certificate that the pod serves on its own
   address with the projected one. It needs no restart.

To renew ahead of schedule, ask cert-manager to renew the Certificate first:

```bash
cmctl renew openbao -n openbao
```

Wait for the Certificate to be Ready, then run the play.

### Verify the renewal

1. The play ends without a failed pod check. The comparison in the play is the
   proof: a renewed certificate and the one before it verify against the same
   CA, so a successful verification alone does not show a reload.
2. Optional check by hand: compare the fingerprint of the certificate that a
   pod serves with the one in the Secret.

   ```bash
   kubectl -n openbao get secret openbao-tls \
     -o jsonpath='{.data.tls\.crt}' | base64 -d \
     | openssl x509 -noout -fingerprint -sha256
   ```

   Read the served certificate from a client on a node that connects to
   `<pod-ip>:8200`, and compare the two fingerprints.
3. The pod CLI works (`kubectl -n openbao exec <pod> -- bao status`).
4. The `ClusterSecretStore` stays `Valid` without a run of the ESO play. A forced
   sync succeeds:

   ```bash
   kubectl -n <namespace> annotate externalsecret <name> \
     force-sync="$(date -u +%s)" --overwrite
   ```

## C. Renew the CA

The root Certificate keeps its private key when it renews, so the renewed root
has the same subject and key. Leaves signed before the renewal, and client
bundles that hold the old root, keep verifying until the old root expires.
cert-manager does not reissue leaves when the root renews, so the `openbao`
Certificate keeps the `ca.crt` of the old root until you reissue it. Do these
steps in order, before the old root expires:

1. Run `320-cert-manager.yml`. Its proof verifies the existing certificate
   against the renewed root, so the play completes.
2. Run `vertical-orchestration/100-eso.yml`, and
   `vertical-resilience/100-object-storage-credentials.yml` if object storage
   is on. They put the renewed root in the stores.
3. Run `cmctl renew openbao -n openbao`, wait for it to finish, then run
   `320-cert-manager.yml` again. The pods then get the renewed root in `ca.crt`,
   and the reload loads the reissued certificate.

Verify with the checks in part A, then the checks in part B.

## Recovery

- **A pod CLI fails with an `x509` error.** The pod still serves a certificate
  from before the change. Run `320-cert-manager.yml` again. If the play cannot
  finish, delete the pod (`kubectl -n openbao delete pod <pod>`) so that it
  loads the new certificate, then unseal it. Delete one pod at a time, and never
  the last unsealed one.
- **A client or the ESO play stops with "OpenBao CA Certificate does not
  exist".** The environment has not moved to the CA. Run part A step 1. For a
  store that points at an external endpoint whose certificate you trust another
  way, set `eso_openbao_external_trust` (main store) or
  `object_storage_eso_openbao_external_trust` (per-class stores) to `true`.
- **The play stops because a pod runs without a pod IP, or because the pod
  serves another certificate than the projected one.** Wait a minute for the
  kubelet, then run the play again. If it still fails, check the pod's events.
- **The move stops halfway.** Every play above is safe to run again. Start from
  the step that did not finish.
- **Roll back to the self-signed certificate.** There is no supported rollback.
  The CA keeps working, and a rerun of the steps above reaches a consistent
  state.

## Related

- [OpenBao Bootstrap And Security Model](https://github.com/dmfdeploy/dmf-infra/blob/main/docs/openbao-bootstrap-security-model.md)
  (the design, the stop points of the Raft migration, and the trust model).
- [`dmf-openbao-unseal`](../../.agents/skills/dmf-openbao-unseal/SKILL.md)
  (unseal after a pod restart).
- [ADR-0007](../decisions/0007-secrets-never-in-argv.md) (no secret values in
  argv).
