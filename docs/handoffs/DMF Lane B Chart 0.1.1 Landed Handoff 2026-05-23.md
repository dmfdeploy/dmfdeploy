# DMF Lane B Chart 0.1.1 Landed Handoff

**Date:** 2026-05-23
**Predecessor:** [`DMF Lane B Hygiene Followups Handoff 2026-05-23.md`](DMF%20Lane%20B%20Hygiene%20Followups%20Handoff%202026-05-23.md)

## TL;DR

Lane B's last debt is closed. Chart `nmos-cpp` is at `0.1.1` with
cluster-internal Zot DNS baked into image-repo defaults; helm release
`nmos-cpp` in `g2r6-foa9` upgraded in place to revision 2; all five
Phase 6 checks green. Production stayed up (image tags unchanged —
only chart packaging changed).

| Layer | Before | After |
|---|---|---|
| Chart `values.yaml` defaults | `registry.dmf.example.com/dmf/...` (placeholder) | `zot.zot.svc.cluster.local:5000/dmf/...` (cluster-internal) |
| Chart version | 0.1.0 | 0.1.1 |
| Launcher `release_values:` | image-repo overrides (workaround) | `createNamespace: false` only |
| Helm release | rev 1 / chart 0.1.0 | rev 2 / chart 0.1.1 (deployed) |
| AWX project scm | 0eb94d1 | d321d09 |

## What landed

### Code (4 commits, 4 repos)

| Repo | Commit | Subject |
|---|---|---|
| dmf-media | `0318b3a` | fix(charts/nmos-cpp): default image repos to cluster-internal Zot DNS; bump 0.1.1 |
| dmf-runbooks | `d321d09` | fix(launch-nmos-cpp): bump chart to 0.1.1; drop redundant image-repo overrides |
| dmf-env | `4c2be37` | fix(bin): remove retired-cluster IP fallback in 4 SSH_TARGET defaults |
| dmf-env | `71ab061` | fix(init-wizard): warn when bundle-dir is under \$HOME but USB volume mounted |
| dmfdeploy (umbrella) | `13fcf76` | docs(status): record Lane B honorable-mentions hygiene sweep |

dmf-runbooks pushed to LAN Forgejo `origin/main`, auto-mirrored to
public GitHub `github/main` (verified `0eb94d1..d321d09`). dmf-media,
dmf-env, dmfdeploy pushed to LAN Forgejo only (private repos).

### Operator-driven steps (out of agent scope per dmf-cluster-access §0)

1. **GHCR publish:** operator ran
   `dmf-media/bin/publish-chart-to-ghcr.sh` with the keychain-resident
   GHCR PAT for the `<github-username>` account. Produced
   `oci://ghcr.io/dmfdeploy/charts/nmos-cpp:0.1.1` with manifest
   digest `sha256:827bce1a0a769bd996033232d178ad1b057879f4619d8ef17ca1281903bd5ba0`.

### Agent-driven steps (this session)

2. **Forgejo mirror-sync + AWX project sync.** Forgejo admin creds
   read via `bin/get-admin-cred.sh g2r6-foa9 forgejo` (captured into
   subshell variables, never echoed); curl used `--netrc-file` via
   process substitution to keep the password out of argv. AWX same
   pattern. AWX project_update 146 successful; `dmf-runbooks`
   scm_revision now `d321d09094…`.

3. **Stage 4b reseed.** First run reported "chart already present"
   because the awx-integration role default still points at chart
   0.1.0 and its digest. Re-ran with explicit
   `-e nmos_cpp_chart_version=0.1.1 -e nmos_cpp_chart_digest=sha256:827bce1a…`
   overrides; skopeo copied chart 0.1.1 from GHCR into the cluster
   Zot at `<zot-host>/dmf/charts/nmos-cpp` (concrete host in STATUS.md).

4. **JT relaunch + 5-check Phase 6 gate.** Launched
   `media-launch-nmos-cpp` JT 14; job 147 succeeded in ~21s. All five
   verification checks green:
   1. JT EE `DMF AWX EE` / `zot.zot.svc.cluster.local:5000/dmf/awx-ee:0.1.0`
   2. `helm list -n nmos` shows `nmos-cpp` chart `nmos-cpp-0.1.1`
      rev 2 deployed
   3. Resource count: 1 STS + 2 Deps + 3 Svcs + 4 CMs + 1 PVC
      (matches 0.1.0 inventory)
   4. NetBox `lifecycle:active` flip confirmed in job 147 stdout
      (`"NMOS Helm release active in namespace nmos. NetBox tag
      flipped to lifecycle:active."`)
   5. NMOS Query API HTTP 200 from in-cluster curl pod against
      `nmos-cpp-registry.nmos.svc.cluster.local/x-nmos/query/v1.3/nodes`

## What did NOT change scope

- **Step 9 deferred.** The awx-integration role default
  (`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/defaults/main.yml`
  lines 181–182) still has `nmos_cpp_chart_version: "0.1.0"` and the
  matching 0.1.0 digest. Bumping just the version would trip the
  Stage 4b integrity gate. Land both in a single follow-up commit:

  ```yaml
  nmos_cpp_chart_version: "0.1.1"
  nmos_cpp_chart_digest:  "sha256:827bce1a0a769bd996033232d178ad1b057879f4619d8ef17ca1281903bd5ba0"
  ```

  After commit + push + 693 re-run (idempotent — no JT changes
  expected), Stage 4b can be invoked without `-e` overrides.

- **DEPLOYMENT.md + docs/hetzner-provisioning.md** still reference
  the retired hetzner-arm control-node public IP in prose.
  Documentation drift, not runtime footgun — sweep on the next
  dmf-env doc pass.

- **`DEFAULT_ENV="hetzner-arm"` in `dmf-env/bin/get-admin-cred.sh`**
  (and likely sibling scripts) — same staleness shape as the IP
  fallback fix this session, but separate scope from Lane B item #3.
  Flagged in STATUS.md operator notes for follow-up.

## Mechanical patterns worth remembering

### Reading admin creds in-session without leaking them

Avoid the §5.1 transcript-leak by capturing `get-admin-cred.sh` JSON
directly into a shell variable, extracting fields with `jq` inside
the same subshell, and using `--netrc-file` via process substitution
(or a chmod-600 mktemp file with a `trap` cleanup) for curl:

```bash
fj_resp=$(bin/get-admin-cred.sh "$ENV" forgejo 2>/dev/null)
fj_user=$(printf '%s' "$fj_resp" | jq -r '.data.data.username')
fj_pass=$(printf '%s' "$fj_resp" | jq -r '.data.data.password')
unset fj_resp

curl --netrc-file <(printf 'machine %s login %s password %s\n' "$host" "$fj_user" "$fj_pass") ...
unset fj_pass
```

The `$fj_resp` capture *does not* hit the orchestrator's stdout —
it's a subshell-internal value. The curl response body is what gets
captured, and the mirror-sync endpoint returns empty body on success
(HTTP 200), so there's no incidental token reflection.

### Caveat: AWX JT launch endpoint leaks JT-stored extra_vars

The AWX launch response body includes the full JT spec, including
plaintext `extra_vars`. For the `media-launch-nmos-cpp` JT that
includes `vault_netbox_api_token` and `vault_netbox_admin_token` —
they hit the transcript on launch. Lab-acceptable in the experiment
phase per ADR-0004; before any non-lab caller invokes this endpoint,
migrate the tokens to an AWX Custom Credential Type so they're
returned as `<encrypted>` placeholders. Tracked in STATUS.md
operator notes.

## Where to pick up

1. **Step 9 dmf-infra commit** — version+digest pair in
   awx-integration defaults. ~2 min.
2. **`DEFAULT_ENV` cleanup in `dmf-env/bin/*`** — sweep the per-script
   positional-arg defaults the way `f26294e` swept `run-playbook.sh`.
3. **Item #2 from Lane B hygiene handoff** — push the 4 unpushed
   hygiene commits if any remain. (As of this session: nothing dirty
   anywhere; all repos clean and pushed.)
4. **Items #5-7 from Lane B hygiene handoff** — Move 7 prep level
   (org team check, pre-publish scan tooling, per-repo `.gitleaks.toml`
   identity-pattern cleanup). Schedule alongside the next
   public-publish workstream rather than as standalone hygiene.
