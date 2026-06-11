# DMF Aliyun-123 Bootstrap Green-Run + ADR-0023 + Runner Spike Handoff

**Date:** 2026-05-14
**Cluster:** aliyun-123
**Session type:** mixed — bootstrap debug + architectural decision + spike Phase 1
**Outcome:** first clean end-to-end `bootstrap-configure.yml` run; passkey enrollment verified

---

## 1. Headline

After 13 attempts spanning ~24 hours of debugging across two calendar
days, `bin/run-playbook.sh aliyun-123 bootstrap-configure.yml` reached
`PLAY RECAP failed=0` end-to-end on aliyun-123. Operator subsequently
retrieved the Authentik passkey enrollment URL and enrolled successfully.

Eleven distinct walls were debugged. Five of them ate hours apiece. They
fell into three categories:

| Category | Walls | Mechanism |
|---|---|---|
| Ansible-level bugs in role logic | 1, 2, 5, 9 | Hard-to-see censor + retry-loop semantics |
| Live-cluster drift from playbook defaults | 6, 7, 8, 10 | Live admin user ≠ role default; password mismatch; var-name fragmentation |
| Architectural mismatch | 3, 4, 11 | Public URLs where internal would work; wrong service DNS name; secret-path divergence |

The architectural-mismatch category is what drove the most strategic
work today: it surfaced the case for moving configure-stage ansible
**inside the cluster** (ADR-0023 + runner-pod spike).

---

## 2. Walls debugged + fixes (commit-by-commit)

### `dmf-infra` commits this session (chronological)

| Commit | Wall | Fix |
|---|---|---|
| `46a57a7` | NetBox sync wait hung forever on TCP stall | block/rescue around poll task + `timeout: 30` on `uri:` |
| `685b32b` | NetBox `until` condition compared dict to string | switched to `status.value` accessor |
| `07d0e00` | NetBox→Forgejo sync URL had wrong service name | `forgejo` → `forgejo-http` (Helm chart appends `-http` to fullname) |
| `1d9d1eb` | Forgejo-svc user `active=false` after PATCH | added `active: true` to PATCH body |
| `7b006ee` | NetBox DataSource kept the stale `source_url` placeholder forever | PATCH `source_url` alongside parameters; `default('...', true)` for empty host |
| `3e7a9d0` | born-inventory crashed on `librenms_host` undef | `default('')` (LibreNMS not deployed on aliyun-123) |
| `3457513` | 698 cms-tokens defaulted to placeholder `dmf.example.com` | initially migrated to internal-DNS — turned out to be wrong direction (see `37dbb56`) |
| `37dbb56` | 698 `uri:` caller is control-node, can't resolve `*.svc.cluster.local` | `*_host` derivation pattern (matches 697's pattern) |
| `ff36ee8` | — | **ansible-runner spike Phase 1 — foundation role + install playbook** |
| `30ba2ff` | 698 Forgejo admin password read from wrong OpenBao path | read from `secret/apps/forgejo/admin → password` (canonical) instead of `/runtime → admin_password` |

### `dmf-env` commits this session

| Commit | Topic |
|---|---|
| `d7c48c6` | `get-admin-cred.sh` + `get-passkey-enrollment-url.sh`: use `parse_yaml_scalar_anywhere` for `openbao_key_path` resolution (fixes resolver bug where openbao.yml-vs-openbao_secrets.yml split silently fell back to hetzner-lab default) |

### `umbrella` commits this session

| Commit | Topic |
|---|---|
| `67073e3` | App Admin Drift Audit doc — fill aliyun-123 rows for authentik/forgejo/zot/librenms |
| `c1a9167` | App Admin Drift Audit doc — record cross-playbook variable-name fragmentation finding (§5.4) |
| `bfeb7f2` | ADR-0023 (initial) + Internal Service DNS Migration Survey plan |
| `a9fc882` | ADR-0023 §Scope amendment after run-11 caller-location discovery |
| `0ca8919` | In-Cluster Ansible Runner Pod Implementation Plan (910 lines, designed for cold-pickup by a fresh agent) |

---

## 3. Architectural artifacts produced

### 3.1 ADR-0023 — Internal service DNS for cross-app wiring

`docs/decisions/0023-internal-service-dns-for-cross-app-wiring.md`

Status: Accepted. Principle: cross-app HTTP wiring defaults to
`http://<svc>.<ns>.svc.cluster.local:<port>` for pod-to-pod callers.
Public URLs are reserved for user-facing flows (browser UI, OIDC
callbacks, webhooks).

§Scope was amended later in the session after run-11 surfaced that
`ansible.builtin.uri:` tasks running on the ansible target host
(k3s_control[0]) can't resolve `*.svc.cluster.local` — their resolver
path is the node's `/etc/resolv.conf`, not CoreDNS. So the principle
applies in two halves:

- **In scope:** pod-to-pod calls (runtime app→app via CoreDNS)
- **Out of scope (transitionally):** ansible-from-control-node calls
  — use `*_host`-derivation pattern until configure-stage ansible
  moves in-cluster (runner-pod spike, see §3.3)

§Future direction explicitly references the runner-pod spike as the
work that collapses the §Scope split.

### 3.2 App Admin Drift Audit & Realignment Plan

`docs/plans/DMF App Admin Account Drift Audit and Realignment Plan 2026-05-14.md`

Audits six apps with local admin accounts (Authentik, AWX, Forgejo,
NetBox, Zot, LibreNMS). Per-app result blocks filled in for aliyun-123
via direct cluster probes. Surfaces **four distinct drift shapes**:

| App | Drift shape | Workaround |
|---|---|---|
| Authentik | none | — (uses canonical `app-admin-facts` reconciliation pattern) |
| AWX | username + password | `-e awx_*_admin_user=<user>` + one-time `awx-manage update_password` resync (done) |
| Forgejo | username-only | `-e forgejo_admin_username=<user>`, `-e cms_forgejo_admin_user=<user>` |
| NetBox | username-only | `-e netbox_sot_admin_username=admin` |
| Zot | password-only (htpasswd ≠ OpenBao) | delete `zot-htpasswd` Secret; role regenerates on next run |
| LibreNMS | deferred (not deployed) | — |

§5.4 records the **cross-playbook variable-name fragmentation** finding:
same identity referenced under different var names across playbooks
(e.g. `awx_admin_user` in 697 vs `awx_integration_admin_user` in 693).
Each new playbook needs its own override. Path 3 consolidation candidate
for post-rollout cleanup.

### 3.3 In-Cluster Ansible Runner Pod Implementation Plan

`docs/plans/DMF In-Cluster Ansible Runner Pod Implementation Plan 2026-05-14.md`

910-line implementation handoff. Spike target: playbook 698.

**Phase 1 done** (`dmf-infra@ff36ee8`):
- `roles/stack/operator/ansible-runner/` — namespace + SA + ClusterRoleBinding
- `playbooks/050-ansible-runner.yml` — one-shot install
- README + variable surface

**Phases 2–4 ready for next-session pickup:**
- Phase 2: wrapper `bin/run-playbook-in-cluster.sh` + Job/Pod template
- Phase 3: `openbao-session` role gains `mounted-secret` mode for in-pod auth
- Phase 4: end-to-end 698 test with internal-DNS defaults (revert `37dbb56`)

Estimated effort to complete Phases 2–4: 3–4 hours of focused work.

The doc is designed for **cold pickup** — includes the boot ritual,
required reading list (ADRs + skills), problem statement with the 11
walls as evidence, architecture sketch, phase-by-phase implementation
skeletons, verification gates, 10 failure modes seen this session, do's
and don'ts, post-spike work (ADR cascade + RBAC narrowing + migration
rollout), reference index, glossary.

### 3.4 Internal Service DNS Migration Survey

`docs/plans/DMF Internal Service DNS Migration Survey 2026-05-14.md`

Methodology + two-axis classification (workload-type × caller-location).
Worked examples from this session anchor the structure. The survey
itself hasn't been executed — only the methodology + known-surface
table are populated. Next session's work item.

---

## 4. Operator override list as of run-13 (persistent until App Admin realignment)

```bash
bin/run-playbook.sh aliyun-123 \
  ../dmf-infra/k3s-lab-bootstrap/bootstrap-configure.yml \
  -e netbox_sot_admin_username=admin \
  -e forgejo_admin_username=<user> \
  -e awx_integration_admin_user=<user> \
  -e awx_admin_user=<user> \
  -e cms_forgejo_admin_user=<user> \
  -e awx_control_node_ssh_privkey_path=/Volumes/<user>/secure/awx-control-node.privkey
```

Six flags. Three categories:

| Category | Flags | Resolution path |
|---|---|---|
| Admin-username drift | `*_admin_user(name)=<user>`, `=admin` | persists until fresh-rollout (App Admin Drift Audit §5.6) |
| Variable-name fragmentation | `awx_integration_admin_user` + `awx_admin_user` for same identity; `forgejo_admin_username` + `cms_forgejo_admin_user` for same identity | Path 3 consolidation (audit doc §5.4) — reduces but doesn't eliminate |
| Path-convention split | `awx_control_node_ssh_privkey_path=/Volumes/<user>/secure/...` | Operator-side env-specific path; inventory could derive from `openbao_juicefs_mount_path` (already defined in env) as a follow-up |

Runner-pod spike (Phases 2–4) eliminates a different category — `cms_*_api_url`
flags that the migration survey was originally going to require. Those
flags didn't end up on the list because Path 1 (override) wasn't taken
on `cms_*_api_url`; instead, Path 3 (`*_host`-derivation in 698) was
committed.

---

## 5. One-time cluster operations performed this session

These are state changes applied to `aliyun-123` directly (not just code
commits). Important to know about if the cluster is ever rebuilt:

### 5.1 AWX admin password resync (run-6 unblock)

The live AWX superuser `<user>` had a DB password that didn't match the
`awx-admin-password` k8s Secret (Secret created 05:35:44, user created
05:41:43 — ~6min gap, suggests bootstrap timing race). Path 2 resync:

```bash
# inside deploy/awx-web pod, fed via stdin:
awx-manage shell  → Django set_password(<secret-value>)  → user.save()
```

After resync, Basic auth on `/api/v2/me/` returns 200. If the cluster is
ever rebuilt fresh, the bootstrap will (presumably) create the user
correctly the first time and this resync is unnecessary.

### 5.2 Zot htpasswd Secret deletion (run-7 prep)

The audit confirmed `zot-htpasswd` Secret contained a bcrypt hash that
didn't match `secret/apps/zot/admin → password` in OpenBao (auth probe
returned 401). Path 2 remediation:

```bash
kubectl -n zot delete secret zot-htpasswd
```

The Zot role regenerates the Secret from the OpenBao value on the next
playbook run via a hash-annotation pattern. Verified working in run-7+.

### 5.3 Forgejo `admin_password` copied from `/admin` to `/runtime` (run-12 unblock)

Playbook 698 read Forgejo admin password from `secret/apps/forgejo/runtime
→ admin_password`, but that key didn't exist (only `forgejo_admin_token`,
`forgejo_svc_password`, `forgejo_svc_token` were populated). Fallback to
`vault_bootstrap_admin_password` didn't match `<user>`'s actual password.

Path B one-time: `bao kv patch` added `admin_password` to `/runtime` with
the value from `/admin → password` (sha256 prefix `984c915e4971`).
Verified equal hash; existing keys preserved.

Path C committed as `dmf-infra@30ba2ff`: playbook 698 now reads from
`/admin` directly. Future deploys don't need Path B's manual copy.

---

## 6. Outstanding workstreams (in priority order)

### 6.1 Runner-pod spike Phases 2–4 (strategic, biggest win)

Plan: `docs/plans/DMF In-Cluster Ansible Runner Pod Implementation Plan 2026-05-14.md`

Once Phases 2–4 land:
- ADR-0023's §Scope caveat collapses (caller is always in-pod now)
- 698's `*_host` derivation reverts to internal DNS defaults
- Migration plan §3 table fills out (rest of configure-stage migrates one playbook at a time)
- Override list shrinks (no more `*_api_url` envvars in scope)

Estimated 3–4 hours of focused work. Fresh agent ready (doc designed for it).

### 6.2 Internal Service DNS migration execution

Plan: `docs/plans/DMF Internal Service DNS Migration Survey 2026-05-14.md`

Walk §3 table top-to-bottom: classify each `dmf.example.com` /
`*_host`-defaulted reference into bins A/B/C/D × P/C/O. Migrate the
(A, P) and (A, C) bins per the decision matrix. Approximately 8–10
playbook files to walk through.

Blocked by 6.1 for the (A, C) → (A, P) migration. (A, C) entries with
the `*_host` derivation pattern stay valid as a transitional state.

### 6.3 ntfy notification skip in 110-authentik

The Authentik playbook's "Send passkey enrollment URL via ntfy" task
was `skipping` — gated by a `when:` clause (likely missing `ntfy_topic`
or `ntfy_enabled` var). Operator deferred during this session. Small
follow-up.

Investigation start:
```bash
grep -nA 5 "Send passkey enrollment URL via ntfy" \
  dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/tasks/main.yml
```

### 6.4 Stale breakglass hygiene check

When fixing `get-passkey-enrollment-url.sh`'s resolver bug, we noticed
that earlier in the session qwen-right's audit *reportedly* succeeded
using `get-admin-cred.sh aliyun-123 forgejo` — which would have hit the
same resolver bug and fallen back to the hetzner-lab breakglass file.
Either:

- The hetzner-lab breakglass file contains aliyun-123-compatible creds
  (hygiene smell — should be one cluster, one breakglass)
- qwen used an `OPENBAO_BREAKGLASS_FILE=` env override that wasn't
  reported
- The audit didn't actually succeed and qwen mis-reported

Verify by:
```bash
sha256sum /Volumes/<user>/secure/openbao-breakglass/hetzner-lab/openbao-keys-automation.json
sha256sum /Volumes/<user>/secure/openbao-breakglass/aliyun-123/openbao-keys-automation.json
# Or compare specific fields:
jq -r '.ops_admin_username' /Volumes/<user>/secure/openbao-breakglass/hetzner-lab/openbao-keys-automation.json
jq -r '.ops_admin_username' /Volumes/<user>/secure/openbao-breakglass/aliyun-123/openbao-keys-automation.json
```

If they're the same — hygiene incident. Rotate.

### 6.5 App Admin Drift fresh rollout (long-term)

Planned in audit doc §5.5/§5.6. Once runner-pod spike + internal-DNS
migration are done, schedule a Layer-1 reset + full bootstrap on
aliyun-123. After rollout:
- All admin-username `-e` flags disappear (live state == role defaults)
- All `awx-manage update_password`-style Path 2 resyncs become unnecessary
- The override list collapses to zero

Needs an ADR to make the "when to burn down + rebuild" decision concrete.

### 6.6 Variable-name fragmentation consolidation

Audit doc §5.4. Three proposed approaches:
- Canonical var per app set role-side, referenced everywhere
- Per-app `set_fact` at top of bootstrap-configure
- Read-live pattern (mirrors `awx_integration_read_admin_password_from_cluster`)

Low priority — only valuable if a fresh-rollout is deferred indefinitely.

---

## 7. Known minor gotchas (worth recording so they don't bite twice)

1. **`bao write -format=json -field=token` returns the value with literal
   JSON quotes wrapping it** (OpenBao v2.5.2). Strip with `tr -d '"'`
   before setting `BAO_TOKEN`. Otherwise downstream `bao` calls return
   "permission denied" (it's literally trying to use `"<token>"` as the
   token).

2. **`bao kv get` does a UI mount-lookup first** (`/v1/sys/internal/ui/mounts/<path>`)
   that requires `sys/internal/ui/mounts/*` read permission on the token.
   `-mount=<name>` flag does NOT bypass this. If `bao kv get` returns
   403 but the token has explicit read on the data path, suspect a missing
   policy grant on `sys/internal/ui/mounts/*`.

3. **`awx-manage update_password` doesn't support `--password-stdin`.**
   Work around by piping the password into `awx-manage shell` and
   calling Django `user.set_password(sys.stdin.read().strip())` then
   `user.save()`.

4. **AWX EE pod doesn't symlink `python` → `python3`.** Use `python3`
   explicitly when running one-liners via `kubectl exec`.

5. **`base64 -d` leaves a trailing newline.** Strip with `tr -d '\n'`
   or use `printf '%s'` when piping into Basic-auth `-u` arguments.

6. **`no_log: true` blocks failure diagnostics in addition to success.**
   Use `block:/rescue:` pattern for tasks that should give sanitized
   debug on failure under `no_log`.

7. **Forgejo HTTP service is `forgejo-http`, not `forgejo`** in the
   standard Helm chart. The chart's HTTP service name template appends
   `-http` to the fullname.

8. **NetBox API returns `status` as a dict** (`{'value': 'failed',
   'label': 'Failed'}`), not a string. Use `.status.value` in comparisons.

9. **`ansible.builtin.uri` has no implicit timeout.** A stalled TCP
   hangs indefinitely. `until/retries/delay` only fires AFTER each call
   returns. Always set `timeout: 30` or env-appropriate value.

10. **Pre-commit gitleaks `dmf-operator-identity` rule fires on the operator username
    in any committed file.** For umbrella docs that intentionally
    reference live-cluster facts (drift audit, this handoff, etc.),
    add path to `.gitleaks.toml` allowlist under that rule. For dmf-infra
    docs, avoid the reference — use generic placeholders.

---

## 8. Boot ritual for tomorrow's agent

```bash
cd "$DMFDEPLOY_UMBRELLA"
git fetch && git pull
bin/generate-status.sh --no-fetch
# Read STATUS.md, this handoff, the App Admin Drift Audit, the Runner Pod
# Implementation Plan (if continuing the spike), and ADR-0023.
```

Skills to read §0 before any cluster-touching work:
- `.claude/skills/dmf-cluster-access/SKILL.md`
- `.claude/skills/dmf-openbao-unseal/SKILL.md` (if OpenBao is sealed)

If continuing the runner-pod spike, the implementation plan doc is the
single best entry point. Phase 1 already lands as `dmf-infra@ff36ee8`;
verify via `bin/run-playbook.sh aliyun-123 ../dmf-infra/k3s-lab-bootstrap/playbooks/050-ansible-runner.yml`
before touching Phase 2.

---

## 9. Open command lines (operator's working knowledge)

For copy-paste convenience:

**Run a full bootstrap-configure with the current override set:**
```bash
cd ~/repos/dmfdeploy/dmf-env
bin/run-playbook.sh aliyun-123 \
  ../dmf-infra/k3s-lab-bootstrap/bootstrap-configure.yml \
  -e netbox_sot_admin_username=admin \
  -e forgejo_admin_username=<user> \
  -e awx_integration_admin_user=<user> \
  -e awx_admin_user=<user> \
  -e cms_forgejo_admin_user=<user> \
  -e awx_control_node_ssh_privkey_path=/Volumes/<user>/secure/awx-control-node.privkey
```

**Retrieve passkey enrollment URL (after the resolver fix):**
```bash
bin/get-passkey-enrollment-url.sh aliyun-123
```

**Re-mint a passkey invitation (re-runs the Authentik playbook):**
```bash
bin/run-playbook.sh aliyun-123 \
  ../dmf-infra/k3s-lab-bootstrap/playbooks/vertical-security/110-authentik.yml
```
