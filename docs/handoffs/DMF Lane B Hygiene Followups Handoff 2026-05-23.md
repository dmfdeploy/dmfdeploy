# DMF Lane B Hygiene Followups Handoff

**Date:** 2026-05-23
**Origin:** Phase 8 hygiene sweep following ADR-0025 Lane B landing. Five
of six hygiene items shipped this session; the sixth (chart bump to
0.1.1) is parked for fresh-session pickup. This handoff captures #1
plus all adjacent followups surfaced during the sweep.

## TL;DR

Lane B is in production. ADR-0025 is Accepted. The NMOS catalog
launcher runs end-to-end via an in-cluster AWX EE pod. **Nothing in
this handoff is blocking** — the production workload is stable. Every
item below is "make the source-of-truth clean and self-consistent"
work that benefits from a fresh session.

| # | Item | State | Effort |
|---|---|---|---|
| 1 | Chart bump `nmos-cpp` 0.1.0 → 0.1.1 with correct cluster-internal defaults | **PARKED** (this handoff) | M (~30 min) |
| 2 | Push 4 unpushed hygiene commits (dmf-infra ×3 + dmf-env ×1) | operator-authorized whenever ready | trivial |
| 3 | Hardcoded retired-cluster control-node IP in `SSH_TARGET` fallback of 3 dmf-env scripts (same staleness shape as the hetzner-lab fix in `7757eb2`) | identified, not fixed | S |
| 4 | Clean 7 stale `prewarm-zot-mirror-*` failed pods in `zot` ns (post `dmf-infra@62fdba2` deploy) | cluster-side operator action | trivial |
| 5 | Confirm `@dmfdeploy/maintainers` GitHub org team exists (codex flag from public-history remediation handoff) | external action | trivial |
| 6 | For Move 7: add pre-publish check that scans public gate files themselves (codex flag — extend the dmf-runbooks pattern to dmf-cms/dmf-central/dmf-infra/dmf-media when they go public) | new tooling work | M |
| 7 | Remove operator-identity regex patterns from per-repo `.gitleaks.toml` for the other public-target repos (codex's sharper insight from the dmf-runbooks remediation — the scanner config itself can expose identity tokens in public repos) | identified, not fixed | M |

The rest of this doc focuses on item #1 because it has the most
mechanical steps. Items #2-7 are one-liners or external actions.

---

## Item #1 — Chart bump to 0.1.1

### Why this exists

The Phase 6 verification chain surfaced a layered category of bug:
every role default that used to be a public ingress URL (e.g.
`registry.dmf.example.com/...`) needed to become cluster-internal
service DNS (`zot.zot.svc.cluster.local:5000/...`) because the
launcher migrated from operator-workstation execution to in-cluster
AWX EE execution (ADR-0023 + ADR-0025).

We fixed this in three places during Phase 6:
- `dmf-infra@efa9cd3` — awx-integration role defaults (EE + NMOS
  image refs).
- `dmf-infra@d0831cb` + `eb36581` — k3s containerd certs.d +
  pinned Zot ClusterIP + /etc/hosts (the architectural fix for the
  containerd-uses-node-DNS finding).
- `dmf-runbooks@c67c955` + `dd1a400` — launcher `netbox_api_url`
  default + `release_values:` overrides for the chart's image refs.

**The remaining `release_values:` overrides are a workaround.** The
chart's own `values.yaml` still ships placeholder defaults:

```yaml
# dmf-media/charts/nmos-cpp/values.yaml (current state, chart 0.1.0)
registry:
  image:
    repository: registry.dmf.example.com/dmf/nmos-cpp-registry
    tag: "0.1.0"
node:
  image:
    repository: registry.dmf.example.com/dmf/nmos-cpp-node
    tag: "0.1.0"
```

The launcher's `release_values:` override at install time makes
production work, but anyone consuming the chart standalone (a 3rd
party per ADR-0027 future-direction, or a future second catalog
function copying this pattern) gets the wrong defaults.

This item bumps the chart to 0.1.1 with correct cluster-internal-DNS
defaults so the chart is self-consistent.

### Concrete steps

Read the launcher playbook first to understand the override pattern
that will become redundant:

```bash
sed -n '40,70p' "$DMFDEPLOY_UMBRELLA/dmf-runbooks/playbooks/launch-nmos-cpp.yml"
```

#### Step 1 — Edit chart `values.yaml`

`dmf-media/charts/nmos-cpp/values.yaml`:

Change two repository lines from:

```yaml
registry:
  image:
    repository: registry.dmf.example.com/dmf/nmos-cpp-registry
node:
  image:
    repository: registry.dmf.example.com/dmf/nmos-cpp-node
```

to:

```yaml
registry:
  image:
    repository: zot.zot.svc.cluster.local:5000/dmf/nmos-cpp-registry
node:
  image:
    repository: zot.zot.svc.cluster.local:5000/dmf/nmos-cpp-node
```

#### Step 2 — Bump `Chart.yaml`

`dmf-media/charts/nmos-cpp/Chart.yaml`: bump `version: 0.1.0` to
`version: 0.1.1`. Leave `appVersion: "0.1.0"` (that tracks the
upstream NMOS-cpp release, not the chart).

#### Step 3 — Commit dmf-media + push

Subject:
```
fix(charts/nmos-cpp): default image repos to cluster-internal Zot DNS; bump 0.1.1 (ADR-0023; Lane B chart-bump followup)
```

Push to LAN Forgejo `origin`:
```bash
cd "$DMFDEPLOY_UMBRELLA/dmf-media"
git push origin main
```

dmf-media is private (not on GitHub) — LAN-only push.

#### Step 4 — Operator publishes chart 0.1.1 to GHCR

This requires the operator's GHCR token (out of agent scope). Run
the same script used for chart 0.1.0 on 2026-05-22:

```bash
cd "$DMFDEPLOY_UMBRELLA"
security find-generic-password -s "ghcr.io" -a "<github-username>" -w \
  | GHCR_USER="<github-username>" \
    dmf-media/bin/publish-chart-to-ghcr.sh
```

Expected: `pushed: oci://ghcr.io/dmfdeploy/charts/nmos-cpp:0.1.1`.

Verify anonymous pull:
```bash
mkdir -p /tmp/chart-011-verify
TMPHOME="$(mktemp -d)" HELM_REGISTRY_CONFIG="$TMPHOME/registry.json" \
  helm pull oci://ghcr.io/dmfdeploy/charts/nmos-cpp --version 0.1.1 \
  --destination /tmp/chart-011-verify
```

Make the package public via the GitHub Packages UI if not already
public by default (same as the 0.1.0 publish step on 2026-05-22).

#### Step 5 — Edit launcher to use chart 0.1.1

`dmf-runbooks/playbooks/launch-nmos-cpp.yml`:

Bump `nmos_cpp_chart_version: "0.1.0"` to `"0.1.1"` in the
top-of-playbook `vars:` block.

**Optional cleanup** in the same commit: now that chart defaults
are correct, the `release_values:` override block for `registry`
and `node` image repos is redundant. Either remove it (cleanest)
or leave it as belt-and-suspenders (more defensive). My lean:
remove it; the chart is now the source-of-truth and the launcher
shouldn't second-guess it. Keep `createNamespace: false` in
release_values — that's still load-bearing because the launcher
sets `create_namespace: false` and the chart defaults to creating
the namespace.

#### Step 6 — Commit dmf-runbooks + push

Subject:
```
fix(launch-nmos-cpp): bump chart to 0.1.1 with cluster-internal-DNS defaults (Lane B chart-bump followup)
```

Push to LAN Forgejo:
```bash
cd "$DMFDEPLOY_UMBRELLA/dmf-runbooks"
git push origin main
```

LAN Forgejo auto-mirrors to GitHub. Verify with
`git fetch github && git log github/main -1`.

#### Step 7 — Propagate to in-cluster Forgejo + AWX

Same propagation chain used for every dmf-runbooks change during
Lane B. Get Forgejo + AWX admin creds via
`bin/get-admin-cred.sh g2r6-foa9 <app>` (do NOT echo these), then:

```bash
# in-cluster Forgejo pull-mirror
curl -fsSk -u "$fj_user:$fj_pass" -X POST \
  "https://forgejo.dmf.example.com/api/v1/repos/forgejo-svc/dmf-runbooks/mirror-sync"

# AWX project sync (project name "dmf-runbooks")
proj_id=$(curl -fsSk -u "$awx_user:$awx_pass" \
  "https://awx.dmf.example.com/api/v2/projects/?name=dmf-runbooks" \
  | jq -r '.results[0].id')
curl -fsSk -u "$awx_user:$awx_pass" -X POST \
  "https://awx.dmf.example.com/api/v2/projects/$proj_id/update/"
```

Wait for AWX project to show `scm_revision` matching the new commit.

#### Step 8 — Re-run Stage 4b to seed chart 0.1.1 into Zot

```bash
cd "$DMFDEPLOY_UMBRELLA/dmf-env"
ANSIBLE_LOCAL_TEMP=/tmp/.ansible ANSIBLE_REMOTE_TEMP=/tmp/.ansible \
  DMF_BOOTSTRAP_BUNDLE_DIR="$HOME/secure/dmf-bootstrap" \
  ./bin/run-playbook.sh g2r6-foa9 \
  ../dmf-infra/k3s-lab-bootstrap/playbooks/630-zot-seed-platform.yml
```

Stage 4b skopeo-copies chart 0.1.1 from GHCR to Zot. The existing
0.1.0 in Zot is left intact (Stage 4b uses HEAD-check; new tag means
new copy).

#### Step 9 — Optional: bump `nmos_cpp_chart_version` in awx-integration defaults

`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/defaults/main.yml`:
change `nmos_cpp_chart_version: "0.1.0"` to `"0.1.1"`.

This default isn't currently consumed at JT-launch time (the
launcher's own `vars:` block at Step 5 is what's load-bearing). But
keeping it consistent prevents future drift. Commit + push if
adopted; re-run 693 to update AWX state (idempotent — 0 changes
expected on JT objects).

#### Step 10 — Re-launch + verify

Launch `media-launch-nmos-cpp` via AWX API (or via dmf-cms catalog
page). Expected: succeeds end-to-end, helm release `nmos-cpp` now
at chart_version `0.1.1`.

Five verification checks (same as Phase 6 gate):

1. JT pod execution_environment + instance_group correct
2. `helm list -n nmos` shows `nmos-cpp` chart `0.1.1`
3. Resource count: 1 STS, 2 Deps, 3 Svcs, 4 CMs, 1 PVC (unchanged
   from 0.1.0)
4. NetBox `lifecycle:active` tag set
5. NMOS Query API HTTP 200 from in-cluster

#### Step 11 — Write a wrap-up handoff

`docs/handoffs/DMF Lane B Chart 0.1.1 Landed Handoff <date>.md`:
captures the new chart version, the now-correct chart defaults, the
launcher override cleanup, and removes the "chart 0.1.1 bump"
followup from the open-items list.

### State right now (2026-05-23, this handoff)

- Chart on GHCR: `0.1.0` (placeholder defaults)
- Chart on Zot: `0.1.0` (same)
- Launcher: hardcodes `0.1.0`; overrides image repos via
  `release_values:` at install time
- Live workload: deployed from chart `0.1.0` with overrides; healthy
  (verified job 131 + ongoing)
- Production is stable — this bump is for chart-self-consistency,
  not production correctness

### Authority bounds for the next session

- Commits on dmf-media + dmf-runbooks + dmf-infra OK with the
  Lane-B-followup framing.
- Push to LAN Forgejo OK (operator's standard pattern).
- Push to GHCR (chart publish) requires operator-side execution
  with the GHCR token — agent stops and asks.
- No live cluster destructive ops needed; only Stage 4b re-run and
  JT re-launch (both idempotent / read-shaped).

---

## Item #2 — Push 4 unpushed hygiene commits

| Repo | Commit | Subject |
|---|---|---|
| dmf-env | `7757eb2` | parameterize stale `hetzner-lab` in fallback paths with `${ENV_NAME}` |
| dmf-infra | `4a3e041` | docs(forgejo-bootstrap): explain why dmf-media + dmf-infra aren't mirrored yet |
| dmf-infra | `62fdba2` | fix(zot-mirror): skopeo sync uses `--dest`, not `--dst` |
| dmf-infra | `2d1cfbd` | chore(scrub): replace operator-identity tokens with placeholders for Move 7 readiness |

All operator-authorized in the original "let's do hygiene items"
session. Push to LAN Forgejo whenever ready:

```bash
cd "$DMFDEPLOY_UMBRELLA/dmf-env" && git push origin main
cd "$DMFDEPLOY_UMBRELLA/dmf-infra" && git push origin main
```

dmf-env is private (LAN-only). dmf-infra is also private at the
moment (Move 7 is the public-publish trigger for it).

After `62fdba2` deploys to a cluster, re-run
`playbooks/vertical-resilience/140-zot-mirror.yml` to update the
in-cluster ConfigMap, then clean up the 7 stale failed pods (item
#4).

## Item #3 — Retired-cluster control-node IP hardcoded in 3 scripts

Same staleness shape as the `hetzner-lab` fix in `dmf-env@7757eb2`.
Flagged in that commit's body, not fixed (scope discipline).

Files:
- `dmf-env/bin/get-admin-cred.sh` line 114
- `dmf-env/bin/bootstrap-operator-approle.sh` line 136
- `dmf-env/bin/rotate-approle-secret-id.sh` line 121

All three have the shape:
```bash
SSH_TARGET="${OPENBAO_SSH_TARGET:-${DERIVED_SSH_TARGET:-k3s-admin@<retired-control-node-ip>}}"
```

The literal in those scripts was the hetzner-arm control node
public IP — a retired cluster's address. For the current
`g2r6-foa9` env the control node is on a different IP. The
fallback is only used when both env var AND `DERIVED_SSH_TARGET`
are unset — in practice operators set one, so the literal is
rarely hit. But it's the same "stale literal default for a retired
cluster" pattern the hetzner-lab fix addressed.

Fix options:
- (a) Remove the literal fallback entirely; require env var or
  inventory-derived value. Breaks usage from outside a properly-
  configured env (probably the right safety call).
- (b) Replace with a generic placeholder like `k3s-admin@<control-node-public-ip>`.
  Cosmetic; breaks the script if it hits the literal.
- (c) Leave alone; just document.

My lean for the next session: option (a) — defaulting to a retired
cluster's IP is footgun-shaped.

## Item #4 — Clean stale `prewarm-zot-mirror-*` failed pods

After `dmf-infra@62fdba2` lands on the cluster (next
140-zot-mirror.yml run), the next CronJob run (Sundays 04:00 UTC)
will succeed. Clean the 7 historical failed pods/jobs:

```bash
kubectl -n zot delete jobs.batch -l app=zot-mirror \
  --field-selector status.successful=0
```

Or wait for the next successful run and let the job history
auto-trim per CronJob `successfulJobsHistoryLimit` / `failedJobsHistoryLimit`.

## Item #5 — Confirm `@dmfdeploy/maintainers` GitHub org team

Per codex's dmf-runbooks public-history remediation handoff: the
new CODEOWNERS in dmf-runbooks references the org team
`@dmfdeploy/maintainers` rather than a personal handle. If that
team doesn't exist in the GitHub org, code-owner review requests
won't resolve.

Check at https://github.com/orgs/dmfdeploy/teams — create the team
if missing, add at least the operator as a member.

## Item #6 — Pre-publish check on public gate files (Move 7 prep)

Codex's insight from the dmf-runbooks remediation: in a public
repo, the `.gitleaks.toml` and `.github/CODEOWNERS` files themselves
can leak identity. The umbrella's `bin/scrub-public-repos.sh`
currently allowlists those files for identity scans — which is
correct for the umbrella scan but incorrect for public-repo
preparation.

Codex already fixed this in the umbrella's scrub script
(removed the global allowlist on `.gitleaks.toml` and
`.github/CODEOWNERS`). The next session should:

- Verify the scrub-public-repos.sh fix is solid against each
  remaining public-target repo (dmf-cms, dmf-infra, dmf-media,
  dmf-central, dmfdeploy umbrella) before any of them go public.
- Add explicit per-repo `.gitleaks.toml` cleanup (item #7) as part
  of each repo's public-publish prep.

## Item #7 — Operator-identity patterns in per-repo `.gitleaks.toml`

Same insight as #6 from a different angle: each repo's local
`.gitleaks.toml` currently encodes the operator-identity tokens
(username stem, custom TLD, device hostname, GitHub handle) as
a literal regex pattern in the `dmf-operator-identity` rule. In a
public repo, that pattern publishes the very tokens it's trying
to detect.

Codex's resolution for dmf-runbooks v0.1.2: drop the operator-
specific identity rule from the public repo's `.gitleaks.toml`
entirely. Keep only the public-safe subset (default rules +
placeholder credential detection + private-network literal
detection + macOS metadata).

For the remaining public-target repos (Move 7):
- dmf-media: not on GitHub yet; trivial to apply codex's pattern
  before publishing.
- dmf-infra: not on GitHub yet; same.
- dmf-cms, dmf-central: not on GitHub yet; same.
- dmfdeploy umbrella: never goes public; no change needed.

The operator-specific identity detection stays in
`bin/scrub-public-repos.sh` (umbrella-side scrub gate) as the
authoritative private check before any public publish.

---

## Cross-references

- ADR-0025 (Accepted 2026-05-23): catalog launcher Lane B
- ADR-0027 (Proposed-deferred 2026-05-22): catalog instance/definition separation
- `docs/handoffs/DMF ADR-0025 Lane B Landed Handoff 2026-05-23.md`: the Lane B closure
- `docs/handoffs/DMF dmf-runbooks Public History Remediation Handoff 2026-05-23.md`: codex's parallel cleanup track
- `docs/plans/DMF ADR-0025 Lane B Implementation Plan 2026-05-22.md` §Phase 6 amendment: the containerd-uses-node-DNS architectural finding that triggered the URL-default consolidation

## Where to pick up

Next session:
1. Read this handoff in full.
2. Confirm push of the 4 hygiene commits (item #2) — fast unblock.
3. Decide whether to tackle items #1 + #3 in one sweep or one at
   a time. They're independent; either order works.
4. Items #5-7 are at the Move-7-prep level — schedule alongside
   the next public-publish workstream rather than as standalone
   hygiene.
