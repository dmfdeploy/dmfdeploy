# AWX Deployments Stuck at Zero: Restart the AWX Operator

**Status:** Operator-facing runbook. Manual fix for the
`AWXReplicaDivergence` alert, where the AWX resource says AWX is awake
but the web and task Deployments have no running pods.

**Audience:** the human operator. Agents may run the read-only checks. Run
the restart in step 3 only with the operator's go-ahead.

**How you get here:** the alert's `runbook_url` points at this page. The
Prometheus role in dmf-infra sets that link
([dmfdeploy/dmf-infra#96](https://github.com/dmfdeploy/dmf-infra/pull/96)),
and that change merges after this page exists.

## What the alert means

The `AWXReplicaDivergence` alert fires when both of these hold for most of
a 20-minute window:

- The AWX resource asks for web or task replicas greater than zero.
- The matching `awx-web` or `awx-task` Deployment has zero available
  replicas.

AWX normally sleeps (scaled to zero) and wakes on demand. The awx-operator
reads the AWX resource at the start of its sleep reconcile and writes
`replicas=0` to the Deployments at the end, about 10 minutes later. If a
wake lands inside that window, the operator overwrites it. The AWX
resource then says awake while the Deployments stay at zero, and nothing
corrects them.

A normal sleep does not fire the alert. The sleep sets the AWX resource to
zero first, so the first condition never holds.

For the root cause and the evidence, see
[#540](https://github.com/dmfdeploy/dmfdeploy/issues/540) and
[#424](https://github.com/dmfdeploy/dmfdeploy/issues/424).

## When not to use this runbook

Do not restart the operator if AWX is asleep on purpose. Check the AWX
resource first (step 1). If `web_replicas` and `task_replicas` are `0`,
there is nothing to fix.

If the AWX resource is awake and the Deployments are at zero, but the
operator logs show a different failure, stop and read #424 before you
restart anything. A different cause needs a different fix.

## Safety class

The restart is a **WRITE** operation in the sense of the
`dmf-cluster-access` skill (section 4). It briefly restarts the operator
pod. It does not touch AWX data, the database, or the AWX resource. It is
not a destructive operation. It is a one-off manual step, so it sits
outside the playbook path. Use it only for this condition.

## Steps

Run the commands on the control node, with the cluster's kubeconfig.

1. Confirm the divergence. These commands are read-only.

   ```bash
   kubectl -n awx get awx awx \
     -o jsonpath='web={.spec.web_replicas} task={.spec.task_replicas}{"\n"}'
   kubectl -n awx get deploy awx-web awx-task
   ```

   The condition is `web=1 task=1` (or any value above zero) in the first
   output, with `0/0` ready in the second.

2. Confirm that the operator made the write. Look for the manager
   `OpenAPI-Generator` on the `awx-web` Deployment, with an update time
   after the last wake.

   ```bash
   kubectl -n awx get deploy awx-web --show-managed-fields -o yaml \
     | grep -B2 -A6 'manager: OpenAPI-Generator'
   ```

3. Restart the operator controller manager.

   ```bash
   kubectl -n awx rollout restart deploy/awx-operator-controller-manager
   kubectl -n awx rollout status deploy/awx-operator-controller-manager \
     --timeout=120s
   ```

   The new operator pod reconciles the AWX resource from scratch and
   scales the Deployments to match it.

4. Confirm the Deployments converge. This usually takes a few minutes.

   ```bash
   kubectl -n awx rollout status deploy/awx-web --timeout=300s
   kubectl -n awx rollout status deploy/awx-task --timeout=300s
   ```

5. Confirm recovery in the console. The AWX status shows as ready, and the
   `AWXReplicaDivergence` alert resolves within a few minutes.

If the Deployments do not converge, read the operator logs
(`kubectl -n awx logs deploy/awx-operator-controller-manager`) and add
what you find to #424.

## See also

- [`dmf-cluster-access` skill](../../.agents/skills/dmf-cluster-access/SKILL.md),
  section 4 (write operations).
- [`dmf-awx-wake-and-runbooks-release` skill](../../.agents/skills/dmf-awx-wake-and-runbooks-release/SKILL.md),
  for waking AWX correctly before a playbook run.
