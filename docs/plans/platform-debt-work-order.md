---
status: draft
date: 2026-10-24
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/727
---

# Platform debt work order

## Goal

Pay down the debt that survives the roadmap, and stop spending effort on layers the roadmap replaces. When this plan is done, every open `platform-debt` issue is foundation debt with a priority and an effort, or a deliberately kept item, and the work order below says which to do next.

## How debt is separated

An issue is **foundation debt** when it lands in a layer that v0.2, v0.3 and a possible orchestration-backend move all keep. Those layers are security and secrets, data integrity, cluster truth (NetBox, the coordinator state, the facility lock), outcome contracts, monitoring, CI and gate correctness, and the durable UI substrate (tokens, shared primitives, interaction doctrine). A defect in a real component counts even when only the demo exposed it, because the demo has to run on the real architecture.

An issue is **superseded** only when a named deliverable replaces the specific layer it lands in:

- **v0.2 replaces the demo media function template.** The package format and catalog index ([#634](https://github.com/dmfdeploy/dmfdeploy/issues/634), [#636](https://github.com/dmfdeploy/dmfdeploy/issues/636), [#637](https://github.com/dmfdeploy/dmfdeploy/issues/637), [#638](https://github.com/dmfdeploy/dmfdeploy/issues/638), [#625](https://github.com/dmfdeploy/dmfdeploy/issues/625)) replace the template and its hand-rolled launch, switch and teardown playbooks. The IS-05 actuator and workload-scoped locks ([#633](https://github.com/dmfdeploy/dmfdeploy/issues/633), [#632](https://github.com/dmfdeploy/dmfdeploy/issues/632), [#630](https://github.com/dmfdeploy/dmfdeploy/issues/630)) replace the AWX-driven switch path and the per-entry lock.
- **v0.3 replaces today's lifecycle procedure.** The gated Provision, Configure and Operate rail becomes peer views ([#493](https://github.com/dmfdeploy/dmfdeploy/issues/493), [#557](https://github.com/dmfdeploy/dmfdeploy/issues/557)), the four-step create wizard becomes one transaction ([#490](https://github.com/dmfdeploy/dmfdeploy/issues/490)), and a template can back more than one workload ([#489](https://github.com/dmfdeploy/dmfdeploy/issues/489)). Teardown keeps the workload as a reusable template, and only an explicit permanent delete releases its NetBox records.
- **The backend move** makes AWX internals (the awx-integration role, receptor, the execution environment, the operator) sunk cost. AWX gets operational fixes only.

A **mixed** issue reports a symptom in a replaced layer over a root cause that survives. Its durable core becomes its own issue, and the original closes.

A superseded issue closes only after any durable acceptance criterion it carries is in the replacing deliverable.

## Result

| Class | Issues | Action |
|---|---|---|
| Foundation | 56 | Keep; ordered below |
| Mixed | 23 | File the durable core as its own issue, then close the original |
| Kept on purpose | 4 | Stay open: frozen questions and trackers that no deliverable replaces |
| Superseded by v0.2 | 3 | Close after carrying any durable acceptance criterion into the deliverable |
| Superseded by v0.3 | 6 | Close after carrying any durable acceptance criterion into the deliverable |
| Superseded by the backend move | 4 | Close; reopen only if an operational failure recurs before the move |
| Done, stale or not planned | 6 | Close with the evidence |
| Duplicate | 1 | Close in favor of the issue named |
| **Total** | **103** | |

## Work order

Work the phases in order. Inside a phase, take the issues top to bottom.

### Phase 1: security and gate integrity (P1)

Secrets that expire or leak, and gates that pass when they shouldn't. Each one makes the platform say something untrue about its own safety.

| Issue | Title | Effort | Durable outcome |
|---|---|---|---|
| [#11](https://github.com/dmfdeploy/dmfdeploy/issues/11) | OpenBao credential hygiene: AppRole secret_id TTL rotation + root-token disposal | M | AppRole secret_id rotation and disposal of bootstrap root-token artifacts; sequence with #396 (pre-expiry alerting). |
| [#396](https://github.com/dmfdeploy/dmfdeploy/issues/396) | Alert before AppRole SecretID expiry; schedule pre-expiry rotation | M | Monitored SecretID lifetime signal (platform monitoring), scheduled rotation inside the TTL, coverage of every TTL'd AppRole, documented steady state. Prefer a Prometheus-side alert (dmf-promsd) so it survives the AWX/Temporal move; schedule through whichever backend runs the plays. |
| [#717](https://github.com/dmfdeploy/dmfdeploy/issues/717) | Make the OpenBao unseal wrapper verify TLS by default | M | Remove the -k fallback in dmf-env/bin/unseal-openbao.sh; verify via in-pod bao or a covered address with the openbao-tls CA; fail with a clear message; keep shares on stdin only; add a failure-path test; repoint dmf-infra quick start. |
| [#15](https://github.com/dmfdeploy/dmfdeploy/issues/15) | Bootstrap-user privilege residue: Forgejo OAuth auto-create + cross-app admin audit | M | Audit that no bootstrap admin access remains across apps; close in-cluster Forgejo OAuth auto-account creation |
| [#650](https://github.com/dmfdeploy/dmfdeploy/issues/650) | scrub-public-repos skips re2-only manifest patterns, so cloud resource ids pass the scan | S | The scrub must apply every manifest pattern, or report skipped patterns. Mark dmf-cloud-resource-id and dmf-dev-changeme with pcre, or run the re2 patterns; make skipped patterns visible in the output. |
| [#548](https://github.com/dmfdeploy/dmfdeploy/issues/548) | PR body saying 'does not close #N' creates a real closing link; the reconciler closes the issue | S | Issue-link CI gate rejects a negated closing keyword in the PR body. Secondary defence in bin/close-completed-issues.sh: re-read the PR body before closing. |

### Phase 2: truth and contracts left of the seam

The backend-agnostic layer the roadmap says value must land in: the console refuses unsafe actions on the server, records outcomes from structured events, and reads cluster truth. Most of these are also v0.2 enablers, because a shared console needs them.

| Issue | Title | Effort | Durable outcome |
|---|---|---|---|
| [#341](https://github.com/dmfdeploy/dmfdeploy/issues/341) | No server-side duplicate-deploy refusal; client guard is the only protection | S | Server-side refusal (or explicit override) in api_catalog_deploy when the entry lifecycle is already active; then bring ProvisionStage to the same gating |
| [#255](https://github.com/dmfdeploy/dmfdeploy/issues/255) | Launcher NetBox service-tags PATCH is unguarded read-modify-write | M | Guard the merge_owned_tags GET-merge-PATCH in the dmf-runbooks launcher roles: verify after write, or use a conditional request. Test it with the tag-preservation harness. |
| [#302](https://github.com/dmfdeploy/dmfdeploy/issues/302) | L3 admission should be utilization-based for media loads (gate under-counts 73%) | L | Capacity gate that reads measured media CPU (with CFS-throttle as a fault signal) and requests modelled for constant-rate media. Must be settled before a second topology is admitted. |
| [#495](https://github.com/dmfdeploy/dmfdeploy/issues/495) | Divergence as the are-we-OK primitive: NetBox intent vs Prometheus observation | L | KSM metricLabelsAllowlist plus a Service/controller-level orphan query joined on app.kubernetes.io/instance and scoped by namespace, with AWX EE pods and L3 ConfigMaps excluded |
| [#497](https://github.com/dmfdeploy/dmfdeploy/issues/497) | dmf-cms: message bus cannot detect its own silence; expose bus liveness to Prometheus | M | Tier 1: add /metrics, a ServiceMonitor or scrape target, and a heartbeat counter that ticks on a timer, which also gives up{job="dmf-cms"}. Tier 2: end-to-end liveness of the audit stream through to Loki, separate from event counts. Idle silence must not be an alert. |
| [#652](https://github.com/dmfdeploy/dmfdeploy/issues/652) | dmf-cms: remaining pollers and health probes return upstream error bodies or 500 when AWX sleeps | S | No upstream body or str(exc) reaches a client response. A stable reason vocabulary (awx-not-running, awx-unreachable) is used on poll and probe failure, with sentinel-body tests. |

### Phase 3: release and gate correctness

Make what ships verifiable and make the checks deterministic.

| Issue | Title | Effort | Durable outcome |
|---|---|---|---|
| [#6](https://github.com/dmfdeploy/dmfdeploy/issues/6) | Release automation (E2): tag-driven publish workflows | M | Tag-driven image publish in component repos; survives the backend move and both UI milestones |
| [#14](https://github.com/dmfdeploy/dmfdeploy/issues/14) | Cosign image signing for dmf-cms releases | M | Image signing and verification in the release pipeline (build-image.sh / publish-to-ghcr.sh) survives any orchestration or UI change. |
| [#667](https://github.com/dmfdeploy/dmfdeploy/issues/667) | dmf-cms: refuse to publish an image whose revision isn't the tagged commit | S | publish-to-ghcr.sh checks the image revision label against v<VERSION>^{commit} and the working tree, and exits non-zero without pushing. |
| [#387](https://github.com/dmfdeploy/dmfdeploy/issues/387) | dmf-cms: test_login_and_overview_shell_render asserts unsatisfiable 'App Catalog' text against a real build | S | Split the test: the built shell is covered by test_base_path; 'App Catalog' belongs in a fallback-shell-only test. |
| [#356](https://github.com/dmfdeploy/dmfdeploy/issues/356) | check-docs is nondeterministic: false 'ADR not mentioned in INDEX' | S | Remove the echo\|grep -q pipelines (SIGPIPE + pipefail) in bin/check-docs.sh:177 and :372 and the small-payload sites; close with root cause or 'hazard removed'. |
| [#460](https://github.com/dmfdeploy/dmfdeploy/issues/460) | generate-scripts-catalog.sh silently truncates SCRIPTS.md when run from a git worktree | S | Fail closed when a component repo does not resolve. Name each missing repo on stderr. Optionally resolve through git-common-dir. |
| [#426](https://github.com/dmfdeploy/dmfdeploy/issues/426) | issue-close reconciler: a reverted PR's Closes ref still closes its issue | M | The reconciler must not close an issue for a merge that was later reverted, or must make that visible. |
| [#546](https://github.com/dmfdeploy/dmfdeploy/issues/546) | audit-log-retention-policy.md is cited as the authoritative retention contract but has never existed | S | Write docs/processes/audit-log-retention-policy.md (content already specified in the readiness plan, A.4), or restate the 12-month contract inline at every citation. |
| [#165](https://github.com/dmfdeploy/dmfdeploy/issues/165) | Umbrella security-audit remediation, script-hardening remainder | M | Script injection fixes, token-in-argv removal, dependabot for github-actions, .gitignore secrets patterns, mktemp traps, pins and dependency bounds. |
| [#171](https://github.com/dmfdeploy/dmfdeploy/issues/171) | dmf-init: Manage restore does not rewrite absolute data-root paths in group_vars | S | Restore into a different DMF_DATA_ROOT rewrites (or avoids) all absolute data-root paths: openbao_key_path, eso_openbao_breakglass_file, awx_control_node_ssh_privkey_path. Preferred fix is a data-root variable in the inventory instead of absolute paths. |
| [#409](https://github.com/dmfdeploy/dmfdeploy/issues/409) | Read-only platform survey: evidence-led cleanup and gate-correctness program | M | Gate correctness: hook-scoping.sh benign-case failure, check-docs.sh ADR index and broken links, dmf-cms Forgejo CI placeholder, dmf-init backup-contract doc drift, NetBox chart tarball provenance. Doc fixes for stale READMEs and the launch_rescue reference. |

### Phase 4: the single node stays healthy

Production-shaped components tuned for the small node, so the demo runs on the real architecture.

| Issue | Title | Effort | Durable outcome |
|---|---|---|---|
| [#282](https://github.com/dmfdeploy/dmfdeploy/issues/282) | loki-gateway rolling update deadlocks on single-node envs (hard pod anti-affinity) | S | Soft anti-affinity, or a Recreate strategy, for the Loki gateway in the single-node profile. |
| [#314](https://github.com/dmfdeploy/dmfdeploy/issues/314) | Chronic CFS throttling on platform containers at tiny average usage | S | Raise CPU limits on netbox-postgresql (150m is the standout), valkey and prometheus-server after measuring burst profiles. Requests stay as calibrated. |
| [#281](https://github.com/dmfdeploy/dmfdeploy/issues/281) | Standalone vertical-play runs silently drop sandbox-profile right-sizing facts | M | Roles must resolve or fail loudly on profile right-sizing facts, so a standalone play cannot silently un-size a node. |
| [#142](https://github.com/dmfdeploy/dmfdeploy/issues/142) | Investigate: base/harden fail2ban banned the Ansible controller mid-bootstrap | S | Invariant: the platform must never fail2ban-ban its own control plane. Add harden_fail2ban_ignoreip from inventory and exempt the controller before fail2ban starts. |
| [#336](https://github.com/dmfdeploy/dmfdeploy/issues/336) | Capture MXL flow real-time delivery in Prometheus (fps vs target, head-index lag) | M | Per-flow delivered grain rate vs target, head-index lag and drift, FlowNotRealtime and FlowLatencyDrifting alerts, discovered via dmf-promsd per ADR-0038. |
| [#340](https://github.com/dmfdeploy/dmfdeploy/issues/340) | Record the full VPS environment in NetBox | M | Node VM records with vcpus/memory/disk/platform, IP objects with primary_ip, provider/region, k8s role, populated at provision time by the dmf-infra registration play. |
| [#469](https://github.com/dmfdeploy/dmfdeploy/issues/469) | dmf-cms: Facility page doesn't show its env — no Environment card, k3s nodes never queried | M | Facility page leads with an Environment card from NetBox Site/Cluster dmf_env_* fields and lists nodes (virtual machines) plus the LB, read-side only, no new tags. |
| [#614](https://github.com/dmfdeploy/dmfdeploy/issues/614) | dmf-cms: fix the axe and jsx-a11y findings the UI invariant harness records as known failures | M | Bell accessible name, icon-link name, link-in-text-block, muted-text contrast, ReasonConfirm label htmlFor. Re-evaluate the InstanceLiveModal jsx-a11y warnings after #610 reworks the modal. |

### Phase 5: later (P3)

Foundation debt with no urgency. Pick these up when they block something or fit beside related work.

| Issue | Title | Effort |
|---|---|---|
| [#10](https://github.com/dmfdeploy/dmfdeploy/issues/10) | Hetzner leakage audit cleanup (items 1-10) | M |
| [#12](https://github.com/dmfdeploy/dmfdeploy/issues/12) | OpenBao lifecycle: HA raft migration + re-key procedure + DR drill | L |
| [#13](https://github.com/dmfdeploy/dmfdeploy/issues/13) | init-wizard cloud-lane gaps (six folded items) | M |
| [#18](https://github.com/dmfdeploy/dmfdeploy/issues/18) | Sandbox teardown leaves node dirty: add decommission step or document re-image | S |
| [#23](https://github.com/dmfdeploy/dmfdeploy/issues/23) | Tier A compliance finish (A.1/A.3/A.4/A.5/A.6/A.8/A.9) | M |
| [#25](https://github.com/dmfdeploy/dmfdeploy/issues/25) | ADR-0034 permanent internal collection source (offline/air-gap catalog path) | L |
| [#73](https://github.com/dmfdeploy/dmfdeploy/issues/73) | DRY cross-repo-identical files; guard hooks; centralize community health | M |
| [#129](https://github.com/dmfdeploy/dmfdeploy/issues/129) | dmf-media: retire nmos-crosspoint wss sed-patch once upstream #15 is in the ref | S |
| [#159](https://github.com/dmfdeploy/dmfdeploy/issues/159) | dmf-init native desktop (menubar/tray) launcher wrapper, tier 2 | L |
| [#199](https://github.com/dmfdeploy/dmfdeploy/issues/199) | Slice 2.2b: flip /api/media-workloads to grouped, add /api/media-function-instances | S |
| [#244](https://github.com/dmfdeploy/dmfdeploy/issues/244) | Console disclosure Level axis: implement default<->expert (Constitution 1) | M |
| [#245](https://github.com/dmfdeploy/dmfdeploy/issues/245) | Marketplace and resource-placement RFC track: grounded roadmap + RFC sequence | L |
| [#451](https://github.com/dmfdeploy/dmfdeploy/issues/451) | dmf-cms: Monitoring tables render empty alert names | S |
| [#523](https://github.com/dmfdeploy/dmfdeploy/issues/523) | dmf-cms: action buttons become a neutral light/dark pair; secondary hover direction | S |
| [#524](https://github.com/dmfdeploy/dmfdeploy/issues/524) | dmf-cms: no light mode and no theme mechanics (system-follow plus user toggle) | L |
| [#529](https://github.com/dmfdeploy/dmfdeploy/issues/529) | dmf-cms: sidebar's complementary landmark wraps only the nav | S |
| [#586](https://github.com/dmfdeploy/dmfdeploy/issues/586) | dmf-cms: active-source view polls ordinary instances for topology forever | S |
| [#596](https://github.com/dmfdeploy/dmfdeploy/issues/596) | [dmf-cms] Arc 4 plan still states the shipped frontend CI gate is missing | S |
| [#654](https://github.com/dmfdeploy/dmfdeploy/issues/654) | MXL: alignment assessment of mxl-k8s control plane and two upstream contributions | S |
| [#669](https://github.com/dmfdeploy/dmfdeploy/issues/669) | Closed-loop assurance: intent-versus-observed deltas into operator actions | L |
| [#675](https://github.com/dmfdeploy/dmfdeploy/issues/675) | Write the short, mid and long-term goal statement for the front door | S |
| [#703](https://github.com/dmfdeploy/dmfdeploy/issues/703) | Move the frozen plans to the archive once their readers are repointed | M |
| [#705](https://github.com/dmfdeploy/dmfdeploy/issues/705) | Try Dependabot for the pinned GitHub Actions | M |
| [#725](https://github.com/dmfdeploy/dmfdeploy/issues/725) | Split ADR-0020 so it holds only the Accepted Mode A decision | S |
| [#726](https://github.com/dmfdeploy/dmfdeploy/issues/726) | Fold the amendments in ADR-0032 and ADR-0038 into their current Decision | M |

## Durable cores to file from mixed issues

Each row becomes one new `platform-debt` issue. The listed originals close with a link to it.

| From | New durable issue |
|---|---|
| [#496](https://github.com/dmfdeploy/dmfdeploy/issues/496), [#480](https://github.com/dmfdeploy/dmfdeploy/issues/480) | Emit a terminal-outcome audit record and keep the audit stream in a retained Loki stream (ADR-0028 D7) |
| [#693](https://github.com/dmfdeploy/dmfdeploy/issues/693) | Classify outcomes only from a structured outcome event, never by searching job output |
| [#182](https://github.com/dmfdeploy/dmfdeploy/issues/182), [#666](https://github.com/dmfdeploy/dmfdeploy/issues/666), [#123](https://github.com/dmfdeploy/dmfdeploy/issues/123) | Deliver secrets to launchers from OpenBao at runtime, never as stored plaintext; test that no rendered job config contains one |
| [#196](https://github.com/dmfdeploy/dmfdeploy/issues/196) | Contract test: any stage that writes NetBox keeps its workload:* tags, written against the stage contract so it outlives the demo task files |
| [#322](https://github.com/dmfdeploy/dmfdeploy/issues/322) | Runtime source truth comes from cluster truth with an allowlisted payload and honest provenance |
| [#271](https://github.com/dmfdeploy/dmfdeploy/issues/271) | Capacity-budget report contract and its retry message, so a deploy never blocks the facility |
| [#141](https://github.com/dmfdeploy/dmfdeploy/issues/141) | Bring-your-own node: enroll the generated key before the connectivity check, without tripping fail2ban |
| [#158](https://github.com/dmfdeploy/dmfdeploy/issues/158) | Pinned, checksum-verified installer path instead of curl \| bash off main |
| [#347](https://github.com/dmfdeploy/dmfdeploy/issues/347) | Robustness items from the demo-journey arcs: reserved-variable scanner, list-shaped defaults, fallback-state rendering |
| [#559](https://github.com/dmfdeploy/dmfdeploy/issues/559) | Audit event contract for configuration changes: parameter, old value, new value |
| [#232](https://github.com/dmfdeploy/dmfdeploy/issues/232) | Workload review record (audit extract, job-log pointers, config snapshot) as a backend capability |
| [#608](https://github.com/dmfdeploy/dmfdeploy/issues/608), [#286](https://github.com/dmfdeploy/dmfdeploy/issues/286), [#520](https://github.com/dmfdeploy/dmfdeploy/issues/520), [#527](https://github.com/dmfdeploy/dmfdeploy/issues/527) | Durable UI substrate: surface, border, status, radius and type tokens; the Tile hover contrast; a console-wide button affordance |
| [#348](https://github.com/dmfdeploy/dmfdeploy/issues/348) | Versioned data-testid selector contract with a contract test |
| [#187](https://github.com/dmfdeploy/dmfdeploy/issues/187) | Alarm priority model research doc that feeds the Alarm Philosophy spec |
| [#345](https://github.com/dmfdeploy/dmfdeploy/issues/345) | Align ADR-0046 and the EBU mapping doc: five orchestration stages plus Operate in the Control vertical |
| [#563](https://github.com/dmfdeploy/dmfdeploy/issues/563) | NetBox media modelling plugin (signal classes, directionality, crosspoints), re-filed on that premise |
| [#646](https://github.com/dmfdeploy/dmfdeploy/issues/646) | Multi-arch MXL build with the pin recorded by digest and a loud failure on a moved anchor |

## Kept on purpose

These stay open. No named deliverable replaces them.

| Issue | Title | Why it stays |
|---|---|---|
| [#8](https://github.com/dmfdeploy/dmfdeploy/issues/8) | Authentik cross-cluster federation with passkey enrollment (FROZEN thesis-killer) | Frozen non-goal with a documented re-open trigger (architectural-commitments-v1, OPEN-QUESTIONS). Keep open with freeze-1 and no milestone. |
| [#9](https://github.com/dmfdeploy/dmfdeploy/issues/9) | EBU V2.0 taxonomy hard case: two-function fabric (paused) | Open thesis question: does the EBU taxonomy hold for a two-function shared-data-plane case? #634 validates descriptors and does not answer it. Keep frozen. |
| [#28](https://github.com/dmfdeploy/dmfdeploy/issues/28) | Shared UI framework between dmf-cms and dmf-init | Waits on the #29 decision about the Day-0 UI boundary; #29 is pre-ADR and keeps a standalone seeder. Keep open until #29 decides. |
| [#200](https://github.com/dmfdeploy/dmfdeploy/issues/200) | v0.2 presentable-journey execution track | Owns the integrated v0.2 acceptance: an outsider runs the written v0.2 demo end to end on a fresh environment, including the live switch. No component issue owns that. Candidate for the v0.2 milestone. |

## To close

### Superseded by v0.2

| Issue | Title | Replaced by or evidence | Before closing |
|---|---|---|---|
| [#189](https://github.com/dmfdeploy/dmfdeploy/issues/189) | v0.2 EBU re-anchor - facility-orchestration lifecycle (tracking) | #633/#632 (nmos-is05 actuator owns switch and rollback, replacing v0.2b reconnect-actuator switch #201); #634/#637 (descriptor and package format); Media Workload entity delivered via ADR-0046 slices #195-#199 | - |
| [#664](https://github.com/dmfdeploy/dmfdeploy/issues/664) | [dmf-media] MXL status server preview stalls or runs away on one flow | #627/#628 (NMOS MXL sidecar and viewer activation) and #637 (existing charts to the package format), which replace the mxl-fabrics-demo image and status server | Before closing: add bounded preview CPU and memory (videorate and multifilesink limits) to the acceptance of #627 or #628. |
| [#665](https://github.com/dmfdeploy/dmfdeploy/issues/665) | [dmf-media] Keep nmos-cpp heartbeats independent of slow cluster DNS | #627 NMOS MXL sidecar chart (with #638 restore of nmos-cpp catalog entries) | Before closing: add 'registry discovery must not lose heartbeats to slow per-request DNS' to the acceptance of #627. |

### Superseded by v0.3

| Issue | Title | Replaced by or evidence | Before closing |
|---|---|---|---|
| [#48](https://github.com/dmfdeploy/dmfdeploy/issues/48) | Create-env exactly-once: idempotency key for sequential re-submit | #29 dmf-init to dmf-cms convergence (v0.3) | - |
| [#146](https://github.com/dmfdeploy/dmfdeploy/issues/146) | dmf-init: auto-detect node network interface (optional override) + ARM64 note | #29 dmf-init to dmf-cms convergence (wizard UI); the hard NAT bind failure from the repro comment is already fixed by #163 | - |
| [#484](https://github.com/dmfdeploy/dmfdeploy/issues/484) | dmf-cms mobile layout: bottom nav and vertical lifecycle rail | #493/#557 (lifecycle stages become peer views, no gated sequence); the vertical rail is the gated rail layout those issues remove | - |
| [#507](https://github.com/dmfdeploy/dmfdeploy/issues/507) | dmf-cms: rail icons ship as 1.5px lucide strokes, decision specified filled silhouettes | #493/#557 lifecycle stages become peer views, no gated sequence | - |
| [#516](https://github.com/dmfdeploy/dmfdeploy/issues/516) | dmf-cms: the rail's horizontal scrollbar is Chrome's unstyled default (chevron affordances) | #493/#557 (lifecycle stages become peer views, no gated sequence) | - |
| [#525](https://github.com/dmfdeploy/dmfdeploy/issues/525) | dmf-cms: make Create media workload a round plus button with label beneath | #490 (replace the four-step create wizard with a single create-media-workload transaction); the v0.3 canvas work reshapes the Media Workloads page entry point | - |

### Superseded by the backend move

| Issue | Title | Replaced by or evidence | Before closing |
|---|---|---|---|
| [#136](https://github.com/dmfdeploy/dmfdeploy/issues/136) | AWX constrained-node: tune JOB_EVENT_WORKERS to shrink awake footprint | Backend move away from AWX (Temporal direction); AWX is 'ops fixes only, never investments' | - |
| [#303](https://github.com/dmfdeploy/dmfdeploy/issues/303) | AWX CR: set termination_grace_period_seconds (preStop drain hook) | Backend move away from AWX; AWX operator CR settings are sunk-cost internals | - |
| [#304](https://github.com/dmfdeploy/dmfdeploy/issues/304) | AWX autoscale: REST-only plays (693) need an explicit renewable Lease hold | Orchestration backend move away from AWX (Temporal direction); the awx-integration role (693/697/699) | - |
| [#330](https://github.com/dmfdeploy/dmfdeploy/issues/330) | dmf-infra follow-ups from the receptor-mitigation deployment (RWO PVC default, retry-var, 640 wait budget) | Backend move away from AWX (AWX is ops-fixes-only; awx role, receptor EE and the 640 play are sunk cost) | - |

### Done, stale or not planned

| Issue | Title | Replaced by or evidence | Before closing |
|---|---|---|---|
| [#193](https://github.com/dmfdeploy/dmfdeploy/issues/193) | Retire mxl-hello — superseded by the videotest workload | Comments: dmf-media#15, dmf-runbooks#14, dmf-infra#44, dmf-cms#28 merged 2026-07-08; catalog entry removed in Slice 2.1 (dmf-media#14). `git grep mxl-hello` in dmf-media returns nothing. Live teardown targeted env <env>, | Before closing: record the live teardown result in #193, or record that it is waived because the environment was destroyed. |
| [#385](https://github.com/dmfdeploy/dmfdeploy/issues/385) | dmf-cms live survey: navy band, dead boot palette, page identity, focus ring, degraded empty state | gh pr view 79 dmf-cms is MERGED. Commits 2844cf6 (fill viewport, retire boot palette) and 98f7c8d (real favicon, page-identity tests). frontend/src/__tests__/pageIdentitySweep.test.tsx. MediaWorkloads/index.tsx:236 canno | - |
| [#477](https://github.com/dmfdeploy/dmfdeploy/issues/477) | check-backlog-hygiene.sh silently checks only the first 100 open issues | Commit 8af0291 'ci(hygiene): ... read every issue'. bin/check-backlog-hygiene.sh lines 45 (ISSUE_LIMIT 2000), 88-91, 163 (finding when limit reached), 249 (first:100 with orderBy DESC). | - |
| [#506](https://github.com/dmfdeploy/dmfdeploy/issues/506) | dmf-cms: rail icon set on screen is not the agreed set | dmf-cms commit d28641c 'feat(rail): swap in the recovered exact stage icon set, filled not stroked'. frontend/src/lib/stageIcons.tsx is now inline SVG, and its header quotes the recovered decision verbatim and says it su | - |
| [#583](https://github.com/dmfdeploy/dmfdeploy/issues/583) | [dmf-cms] AGENTS.md release context still describes the pre-v0.10 console | grep -n -i 'release 0\\|Release Context' dmf-cms/AGENTS.md returned no matches. git log shows later commits to AGENTS.md (3206029 pin working-model block, 0264c98, f0dae52). The issue was scanned at source SHA 321dd63, w | - |
| [#592](https://github.com/dmfdeploy/dmfdeploy/issues/592) | WORKING-MODEL.md allows bare 'Closes #N'; the issue-link guard rejects it | origin/main .github/workflows/guard.yml line 156: regex '((dmfdeploy/dmfdeploy)?#[0-9]+\|https://...)' with the comment 'Bare #N is fine here'. WORKING-MODEL.md line 191 says 'Closes #N in the umbrella'. | - |

### Duplicate

| Issue | Title | Replaced by or evidence | Before closing |
|---|---|---|---|
| [#517](https://github.com/dmfdeploy/dmfdeploy/issues/517) | dmf-cms: 'you are here' and 'action this' same hue, action colour needs to move | #523 (action buttons become a neutral light/dark pair). Close when #523 lands, per the operator ruling of 2026-09-01. | - |

## Method

Eight read-only classifiers each read 12 or 13 issues in full, with comments, against the rules above, and cited evidence for every done or superseded call. The orchestrator spot-checked the done evidence against the repos. An adversarial review then challenged every close call. It moved four issues to the kept list and added the conditions in the "Before closing" column. Nothing in the backlog changes until the maintainer agrees to this plan.
