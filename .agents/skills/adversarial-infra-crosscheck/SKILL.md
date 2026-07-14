---
name: adversarial-infra-crosscheck
description: Adversarial pressure-test of deployment feasibility analyses — verify resource margins, image availability, control-plane wiring, and strategic value before committing
source: auto-skill
extracted_at: '2026-06-05T12:30:00Z'
type: durable-pattern
scope: review-workflow
owner: operator
review_by: '2027-01-14'
---

# Adversarial Infrastructure Cross-Check

When an operator presents a deployment feasibility analysis (resource budgets, missing pieces, tentative verdicts), pressure-test every claim before agreeing. The goal is to surface overconfidence, technical misconceptions, and hidden dependencies that would cause the run to fail or destabilize the cluster.

## When to use

- An operator asks "is my margin analysis right?" or "what am I missing?" about a planned deployment.
- Someone is deciding whether to run a workload on a resource-constrained node.
- A catalog entry or chart claims single-node compatibility but the control plane isn't wired up.
- Image strategy decisions: consolidate vs publish separate images, or digest placeholders.

## Procedure

### 1. Verify every factual claim against current code

Do **not** trust the operator's summary. Read the actual files:

- **Chart values** — check `resources.requests/limits`, `nodeSelector`, `tolerations`, `emptyDir` medium and sizeLimit, container count and image refs.
- **Catalog entry** — check `provision.image` (single vs list), `configure.playbook` (exists?), `configure.awx_job_template` (wired in AWX defaults?), `health_probe` (container name, log pattern).
- **AWX integration defaults** — grep `awx_catalog_job_templates` for the JT names the catalog references. Missing JTs = runtime failure.
- **Playbooks** — check the `configure.playbook` and `finalise.playbook` paths exist in the runbooks project.
- **Image availability** — check if the images referenced actually exist on the registry. Digest placeholders (`sha256:0000...`) mean "not yet published."

### 2. Pressure-test resource margins

For memory-constrained nodes:

- **GStreamer v210/uncompressed video RSS is the wildcard.** v210 is ~5.5 MB/frame (uncompressed 10-bit 4:2:2). At 1080p29 with buffered frames, typical RSS is 300–600 MiB. Factor this into the margin, not just container count × nominal.
- **Resource limits are mandatory on shared nodes.** Without `resources.limits.memory`, kubelet assumes 0 RAM for scheduling, and the OOM killer picks the highest-RSS process arbitrarily. Add limits before running: writer 512Mi, sidecars 128Mi each.
- **tmpfs emptyDir and container RSS are NOT double-counted in cgroups.** tmpfs reads land in the kernel page cache (separate from container cgroup RSS). The risk is the *sum* pushing the node past reclaimable thresholds without kubelet-level accounting. The operator may think these double-count (making margins look worse than they are) — correct this misconception.
- **Catalog the full memory stack:** baseline platform RSS + transient EE pod peak + tmpfs limit + container RSS estimates + headroom = node free RAM. If headroom < 200 MiB, the deployment is risky on a 10 GiB node.

### 3. Identify control-plane gaps

The operator usually finds the obvious gaps (missing playbooks, missing JTs). Look for the non-obvious ones:

- **AWX project sync dependency:** New playbooks in the runbooks repo require AWX to sync the project (git pull) before JTs can reference them. Sequence: write playbooks → AWX project sync → create JTs → catalog goes live.
- **Catalog-to-chart image mismatch:** If the catalog lists a single `provision.image.repository` but the chart deploys multiple containers with different binaries, the Provision stage's image fetch logic will only pull one image. Either fix the catalog schema to express a list, or use a consolidated image and update the catalog to match.
- **NetBox CatalogEntry sync:** The catalog entry's `netbox_service` block may be informational for v1, but flag it for v2 enforcement.
- **Image registry accessibility:** `IfNotPresent` pull policy means images must already be on the node or reachable from the registry. Side-loaded images work for dev; production needs published images.

### 4. Assess strategic value (control chain vs data plane)

When the operator frames a deployment as "step 1" toward a larger goal:

- **What it validates:** catalog → Provision → AWX JT → playbook → helm install → health_probe → Finalise chain. This is the control chain. Proving it green for a new catalog entry is genuinely valuable.
- **What it does NOT validate:** hostNetwork, cross-host TCP, RSMC coordination, initiator/target handshake — these are the data plane challenge. If the target step uses a fundamentally different data plane (e.g., intra-pod emptyDir vs cross-host hostNetwork), the deployment does not exercise the actual challenge.
- **Reframe honestly:** Call it "control chain validation" not "step 1 of X." The data plane step is a separate validation with different criteria.
- **Net value judgment:** If the playbook pattern can be reused (copy-paste-edit from existing playbooks), it's accelerating. If the deployment validates nothing reusable for the larger goal, it's a detour.

### 5. Reply structure

Structure the adversarial reply around the operator's questions, but add corrections and gaps:

```
## A. Resource feasibility: [your verdict on margins]
- Correct what they got right
- Correct what they got wrong (with technical explanation)
- Add what they missed (limits, requests, RSS estimates)

## B. Image strategy: [your verdict on consolidation vs separate]
- Verify image claims against reality
- Flag catalog-to-chart mismatches

## C. Control-plane gaps: [add to their list]
- Gaps they found: confirm
- Gaps they missed: add

## D. Strategic value: [control chain vs data plane assessment]
- What this validates
- What this does not validate
- Net value judgment
```

## Principles

- **Verify against current code, not memory or operator summary.** Memory is 6 days old; code is current.
- **Be specific with numbers.** "GStreamer is heavy" is less useful than "v210 1080p29 RSS is typically 300–600 MiB."
- **Correct technical misconceptions precisely.** Explain why tmpfs and RSS aren't double-counted, what the real risk is.
- **Distinguish control chain from data plane.** This is the most common framing error in deployment sequencing.
- **Propose mitigations, not just problems.** "Add resource limits: writer 512Mi, sidecars 128Mi" not "containers are unbounded."
