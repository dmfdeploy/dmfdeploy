# DMF Bootstrap — Tier 1 Implementation Review

**Date:** 2026-05-08
**Reviewer:** Opus 4.7 (umbrella session)
**Reviewed:** Tier 1 deliverables of `docs/handoffs/DMF Bootstrap Implementation Handoff 2026-05-08.md`
**Subject of review:** uncommitted changes in `dmf-env`, `dmf-infra`, and umbrella docs as of 2026-05-08 12:50 local
**Status of work:** Substantially complete, exceeds Tier 1 minimum scope. **Two concrete fixes required before commit; a third is defense-in-depth and may defer.**

## Verdict

The implementation is high-quality, scope-disciplined, and matches the answered questions (A1–A10) with one operator-side ADR-0007 leak that must be fixed before commit. The agent went beyond the documented Tier 1 minimum by also completing the role-defaults credential elimination (Plan Phase 3 / Design Step 5) — that was the right call because the credential-grep gate is the acceptance test and partial completion would have left a known fail.

Nothing in this review revisits the architectural decisions in the handoff's "do not relitigate" list. All concerns are at the implementation layer.

## What was verified

The reviewer ran the acceptance gates and read the relevant files end-to-end. These pass:

- **Credential-grep gate**: `grep -rnE "default\(\s*['\"](changeme|admin|password|dev)['\"]" dmf-infra/k3s-lab-bootstrap/roles/ | grep -vE 'acme_email|@example\.com'` returns **zero hits**.
- **Phase 0 baseline diff**: `docs/baselines/lifecycle-provision-list-tasks-{baseline,after-refactor}-2026-05-08.txt` differ only in tag-list normalization on the `219-host-verify` play (added `bootstrap-preflight` per A8). Behaviorally equivalent.
- **`bootstrap-secrets.sh` fail-closed checks**: `DMF_BOOTSTRAP_BUNDLE_DIR` unset → refusal; bundle dir inside any git tree → refusal; `DMF_AWX_CONTROL_NODE_SSH_PATH` unset for the AWX subcommand → refusal. All three exit 1 with corrective error messages (verified via static read of lines 36–50, 859–864).
- **Doctor check coverage**: age key present, age key perms 0600, bundle exists, bundle decryptable, no plaintext sibling, bundle dir not in git tree, schema completeness, entropy floors (admin password ≥24, k3s token ≥32), no break-glass material in bundle. (lines 452–538.)
- **`seed-bao` collision behavior** (lines 669–704, 793–830): missing→write; same value→no-op; differing **platform** path→fail with "use rotate" message; differing **app-local admin** path→fail with deliberate-migration message. App-local compat copies written for `forgejo`, `netbox`, `grafana`, `awx`, `zot`, `authentik`. `last_seeded_to_bao_at` updated and re-encrypted atomically.
- **`seed-awx-control-node-ssh`** (lines 854–949): separate subcommand per A4, validates PEM header, fingerprint-based idempotency (sha256 → 16-hex compare), fail-closed on differing keys.
- **Wrappers are thin `import_playbook` lists** per A7. `bootstrap-provision-pre-seed.yml` correctly stops at OpenBao + ESO + Authentik + breakglass-verify + zot-oidc; `bootstrap-provision-post-seed.yml` covers monitoring + Layer 6 vanilla; `bootstrap-configure.yml` covers SoT + automation + CMS wiring.
- **`lifecycle-provision.yml`** is a clean compatibility wrapper with a header comment documenting the canonical fresh-bootstrap path. **`lifecycle-configure.yml`** is the documentation stub per A5.
- **`dmf-env/.sops.yaml`** scaffolds the recipient list with a TODO placeholder and clear instructions.
- **9 role/task files** refactored to source from `vault_bootstrap_admin_*` with `mandatory` failure when unset:
  - `roles/stack/operator/forgejo/defaults/main.yml` (incl. `dev` → `vault_bootstrap_admin_username`)
  - `roles/stack/operator/forgejo-bootstrap/defaults/main.yml`
  - `roles/stack/operator/netbox/defaults/main.yml`
  - `roles/stack/operator/netbox-sot/defaults/main.yml`
  - `roles/base/grafana/defaults/main.yml`
  - `roles/stack/operator/zot/defaults/main.yml`
  - `roles/stack/operator/awx/defaults/main.yml`
  - `roles/stack/operator/awx-integration/defaults/main.yml`
  - `roles/stack/operator/cms/tasks/main.yml`
- **`docs/handoffs/DMF Bootstrap Implementation Progress Handoff 2026-05-08.md`** is detailed and accurate. Tier 2 queue is correct. A9 decision tree carried forward.

## Concerns

### CONCERN 1 — `bundle_set` exposes secret values via operator-side argv (must fix before commit)

**Severity:** P0 — operator-side ADR-0007 violation.

**File:** `dmf-env/bin/bootstrap-secrets.sh`, lines 154–183.

**What's wrong.** The `bundle_set` helper passes the new value as `sys.argv[1]` to `python3 -c`:

```bash
sops --decrypt --output-type json "${bundle}" 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
parts = '${field_path}'.split('.')
obj = data
for p in parts[:-1]:
    if p not in obj:
        obj[p] = {}
    obj = obj[p]
obj[parts[-1]] = sys.argv[1]
print(json.dumps(data, indent=2))
" "${value}" > "${tmp_file}"
```

`bundle_set` is called by `cmd_rotate` (line 1019) for `bootstrap_admin.password`. During rotate, the new password is briefly visible to `ps` on the operator's machine. ADR-0007 explicitly forbids secrets in argv.

**Required fix.** Pass via stdin instead. The bundle JSON and the new value can both come from stdin (concatenate with a delimiter, or use a header line for the field path). Concrete pattern:

```bash
bundle_set() {
  local env_name="$1"
  local field_path="$2"
  local value="$3"
  local bundle="${DMF_BOOTSTRAP_BUNDLE_DIR}/${env_name}.sops.yaml"

  local tmp_file
  tmp_file="$(mktemp)"
  chmod 0600 "${tmp_file}"
  trap "rm -f '${tmp_file}'" RETURN

  # Pass value via stdin (after the JSON, separated by NUL).
  {
    sops --decrypt --output-type json "${bundle}" 2>/dev/null
    printf '\0%s' "${value}"
  } | python3 -c "
import json, sys
raw = sys.stdin.buffer.read()
json_blob, _, value = raw.partition(b'\0')
data = json.loads(json_blob)
parts = sys.argv[1].split('.')
obj = data
for p in parts[:-1]:
    if p not in obj:
        obj[p] = {}
    obj = obj[p]
obj[parts[-1]] = value.decode('utf-8')
print(json.dumps(data, indent=2))
" "${field_path}" > "${tmp_file}"

  sops --encrypt "${tmp_file}" > "${bundle}.tmp"
  chmod 0600 "${bundle}.tmp"
  mv "${bundle}.tmp" "${bundle}"
  chmod 0600 "${bundle}"
}
```

`field_path` stays in argv (it's a non-secret path string like `bootstrap_admin.password`). Only the new secret value moves to stdin. The JSON-then-NUL-then-value framing is one of several valid patterns; alternatives include reading the value from a separate file descriptor or using `tempfile + sops_set` if available.

**Acceptance test.**

```bash
# Set a recognizable value through rotate
( DMF_BOOTSTRAP_BUNDLE_DIR=... bin/bootstrap-secrets.sh rotate hetzner-arm bootstrap_admin.password ) &
ROTATE_PID=$!
# In another shell, snapshot ps for the rotate process tree during the run:
ps -ef | grep -i "$(sops_password_marker)" | grep -v grep
# Expectation: zero hits. Both before and after the fix:
#   - Before: python3 -c '...' <plaintext-password>  appears
#   - After: python3 -c '...' bootstrap_admin.password  appears (path only)
wait "$ROTATE_PID"
```

In practice, run `rotate` once and `ps -ef | grep python3` during the brief execution window; should not see plaintext.

---

### CONCERN 2 — `bao kv put` argv exposure inside the OpenBao pod (defense-in-depth, defer acceptable)

**Severity:** P2 — narrow inside-pod exposure; operator-side is clean.

**Files:** `dmf-env/bin/bootstrap-secrets.sh`, multiple places — lines 691–699, 714–717, 736–739, 749–752, 762–765, 780–786, 816–824, 940–943.

**What's wrong.** The pattern is correct on the operator side (no secret in `kubectl exec`'s argv — only stdin):

```bash
printf '%s' "${SECRET}" | kubectl exec -i -n openbao "${bao_pod}" -- sh -c '
  IFS= read -r V
  bao kv put secret/path field="${V}"
'
```

But inside the pod, `sh -c` expands `${V}` and the resulting `bao kv put secret/path field=ACTUAL_VALUE` line is in `bao`'s argv. `ps` inside the pod would show plaintext during the brief execution window.

**Risk profile.** Narrow. Anyone with `kubectl exec` access to the OpenBao pod has equivalent or greater access via the pod's userpass/AppRole anyway, so the argv exposure is a moment-in-time race with `ps` against an attacker who already has shell access. ADR-0007's explicit list addresses operator argv; pod-internal argv is a defense-in-depth concern.

**Recommended fix when addressed.** Use `bao kv put -` with JSON on stdin so `bao` reads field values from stdin only. Per-write conversion:

```bash
printf '{"username":%s,"email":%s,"password":%s}' \
  "$(printf '%s' "$U" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
  "$(printf '%s' "$E" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
  "$(printf '%s' "$P" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
  | kubectl exec -i -n openbao "${bao_pod}" -- bao kv put -mount=secret platform/bootstrap_admin -
```

(The Python helper is just for safe JSON quoting; values with quotes/newlines need it.)

Per-field pattern using `key=-` if `bao` supports it in this version:

```bash
printf '%s' "${SECRET}" | kubectl exec -i -n openbao "${bao_pod}" -- bao kv put secret/path field=-
```

**When to fix.** Acceptable to defer. Trigger conditions to revisit (per ADR-0011 spirit): public/OSS, external collaborators, or move-2 hardening begins. Add a `# TODO(adr-0011-trigger): bao kv put argv hardening` comment near each affected block.

---

### CONCERN 3 — `bootstrap-verify.yml` is a placeholder stub

**Severity:** P3 — explicitly acknowledged by the agent; acceptable for Tier 1.

**File:** `dmf-infra/k3s-lab-bootstrap/bootstrap-verify.yml`.

**What it is.** Single placeholder play with an `ansible.builtin.debug` task and a header comment listing target checks (k3s nodes Ready, CoreDNS, Traefik, cert-manager, OpenBao, ESO, app admin matches shared identity, OIDC operator admin in every app, NetBox/Forgejo/AWX APIs, born-inventory, DMF Console `/healthz`).

**Why this is acceptable.** Plan and design both said "if a verify playbook is still a stub, do not present it as a hard gate." The header comment frames it as a documented entrypoint awaiting cluster-side assertions. Real assertions need cluster access (Tier 2) and depend on the Bootstrap Configure OIDC seeding being implemented first.

**Required follow-up.** When implementing Tier 2:

- Land per-target-check assertion plays under `playbooks/bootstrap-verify/`.
- Specific Fix #19 from the plan (audit policy filter assertion for `secret/platform/*` and `secret/apps/*/admin`) goes here.
- `bootstrap-verify.yml` becomes a real `import_playbook` wrapper; the placeholder play is removed.

Until then the wrapper must not be cited as a passing gate in any acceptance discussion.

## Minor observations

These are nits, not blockers. Note for future tightening passes.

- **`gen_secret`** (line 187): `openssl rand -base64 N | tr -d '+/=' | head -c L`. With `N == L`, there's a small chance the post-strip string is shorter than `L` (because `+/=` were stripped). The doctor entropy check (≥24 / ≥32) catches the worst cases at validation time, but `init` itself doesn't loop until the length check passes. **Suggested tightening**: oversample (`N = L + 8`) or loop until `[ ${#out} -ge $L ]`. Edge-case probability with current values is small but nonzero.
- **`read -r -d ""`** (line 941): reads SSH key data until null/EOF. PEM keys end with newline + EOF, so this works in practice. Slightly unusual idiom; a comment explaining it would help future readers.
- **Concurrent `init`/`rotate` runs** have no flock/locking. Two simultaneous operators could clobber the bundle. Edge case; mitigations: `flock "$BUNDLE_FILE"` around mutating subcommands, or a `.lock` sibling file with `mkdir`-based locking.
- **Re-init partial bundle**: when the bundle exists with missing fields, `cmd_init` reports status and exits — operator must edit manually or re-init from scratch. UX, not security. Reasonable for v1.
- **Sensitive shell variables** in `cmd_init` (admin_password, k3s_token, hcloud_token, etc.) live in function scope and are released on return. Practical risk is low; an `unset` at end of function would be belt-and-braces.
- **Tag normalization on host-verify play**: the after-refactor list-tasks shows `[bootstrap-preflight, host-platform, layer2, verify]` (alphabetized) where the baseline showed `[host-platform, layer2, verify]`. Behaviorally equivalent; flag only because tag ordering may matter for downstream parsing. The legacy `layer2` and `host-platform` tags are preserved, so any existing `--tags layer2` invocation still selects the play.
- **`bundle_field`** uses `'${field_path}'.split('.')` interpolated into a python `-c` string. `field_path` is always a hardcoded constant from script callers, so injection is not a practical risk; mentioned only for completeness.

## Recommended commits

Three repos, three commits. Suggested messages:

### `dmf-env` (private, no remote)

```
feat: add bootstrap-secrets.sh + .sops.yaml scaffolding

7 subcommands: init, doctor, export-vars, seed-bao,
seed-awx-control-node-ssh, status, rotate. Pre-Bao bundle lives at
$DMF_BOOTSTRAP_BUNDLE_DIR (fail-closed; refuses any path inside a git
tree). Operator generates age key per A2 of the implementation
questions; script validates. Doctor checks include schema completeness,
entropy floors, and an explicit break-glass-leak scan. seed-bao
collision behavior: fail on differing platform/app-local-admin values,
no-op on same. Updates docs/initial-data-gathering.md §2b with
operator-side setup.
```

### `dmf-infra` (public)

```
refactor(bootstrap): split lifecycle into pre-seed/post-seed/configure/verify

Adds bootstrap-{provision-pre-seed,provision-post-seed,configure,verify}
wrappers as thin import_playbook lists. lifecycle-provision becomes a
compatibility wrapper that imports the four. lifecycle-configure becomes
a documentation stub pointing at dmf-runbooks for workload configure.
site.yml comments corrected. 219-host-verify retagged with
bootstrap-preflight (file not renamed).

Removes default('changeme'/'admin'/'dev'/'password') from 9 role and
task files; all local admin paths now source from
vault_bootstrap_admin_* with mandatory failure when unset.
Credential-grep acceptance gate green.

bootstrap-verify.yml ships as a documented placeholder; real
assertion plays land in Tier 2 alongside cluster-side work.
```

### `dmfdeploy` (umbrella)

```
docs: capture bootstrap Tier 1 baselines + progress handoff

Adds before/after lifecycle-provision --list-tasks baselines under
docs/baselines/. Diff is tag normalization on the host-verify play
(bootstrap-preflight added, legacy layer2/host-platform preserved);
behaviorally equivalent.

Adds DMF Bootstrap Implementation Progress Handoff with Tier 2 work
queue and cluster-state decision tree.

Adds DMF Bootstrap Tier 1 Implementation Review documenting verified
strengths, two operator-side concerns to address before/after commit
(bundle_set argv exposure, pod-side bao kv put argv), and minor
observations.
```

## Tier 2 queue (do not start without cluster-state check)

Per A9 of the questions doc: before any Tier 2 work, run the kubectl checks listed in the progress handoff and follow the decision tree. Then in order:

1. **`bundle_set` argv fix** (Concern 1) — actually this is operator-side static, not cluster-touching. **Land it before commit.** Listing here only because rotate is the only caller; if you skip the fix, defer rotate usage until after.
2. **`seed-bao` live test** against a fresh OpenBao. Exercise: missing-path write, same-value no-op, differing-platform rotate-required path, differing-app-local-admin migration-required path.
3. **`seed-awx-control-node-ssh` live test**. Verify AWX Machine credential creation flows end through to AWX CR reconciliation.
4. **Role task splits** (`tasks/main.yml` dispatch by `app_stage`) for the apps still mixing provision and configure: `authentik`, `zot`, `grafana`, `netbox`, `forgejo`, `awx`. (`forgejo-bootstrap`, `awx-integration`, `netbox-sot` are configure-only; `cms` is provision-only.)
5. **Bootstrap Configure — OIDC admin seeding**. Authentik role creates the shared bootstrap admin identity (matching `vault_bootstrap_admin_*`) and maps to admin/superadmin groups in every OIDC-backed app. **Coordinate with Plan Q9** — `akadmin` deprecation timing.
6. **Audit policy extension** (Specific Fix #19). Extend the Kubernetes audit policy file to cover `secret/platform/*` and `secret/apps/*/admin` at Metadata level. Add the `bootstrap-verify.yml` assertion that the running policy contains the rule.
7. **bootstrap-verify.yml population**. Replace the placeholder with real assertion plays as roles gain verify tasks.
8. **Defense-in-depth pod-side argv hardening** (Concern 2) — defer until ADR-0011 trigger conditions or move-2 hardening begin.

## Acceptance for closing this review

The review is closed when:

- Concern 1 (`bundle_set` argv) is fixed and the rotate-time `ps` check passes.
- The three commits land per the suggested split (or equivalent).
- The progress handoff is referenced from `STATUS.md` (auto-refreshed by the pre-commit hook).
- A new follow-up handoff is written when Tier 2 begins, citing this review and the answered questions doc.

Concern 2 and the minor observations track separately as part of normal hardening.

---

## Fix status (2026-05-08, post-review)

### Concern 1 — `bundle_set` argv exposure — FIXED

`bundle_set` now passes the secret value via NUL-delimited stdin instead of `sys.argv[1]`. The `python3 -c` invocation receives only `${field_path}` (non-secret) as argv. Verified at line 172: `raw.partition(b'\0')` splits JSON from secret value. `cmd_rotate` (line 1034) calls `bundle_set "${env_name}" bootstrap_admin.password "${new_pw}"` — only the field path appears in `ps`.

### Concern 2 — `bao kv put` argv inside pod — ANNOTATED (deferred)

TODO comments added at lines 632 and 867 with `adr-0011-trigger` tag. Will revisit when ADR-0011 trigger conditions fire (public/OSS, external collaborators, move-2 hardening).
