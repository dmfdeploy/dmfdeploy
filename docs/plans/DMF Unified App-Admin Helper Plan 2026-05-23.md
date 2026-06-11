---
status: executed
date: 2026-05-23
---
# DMF Unified App-Admin Helper Plan

**Date:** 2026-05-23
**Status:** Accepted — three-reviewed (claude-bottom drafter,
claude-top reviewer, codex reviewer); reframed 2026-05-24 as
**implementation under [ADR-0028](../decisions/0028-identity-and-authority-chain.md)
D1** (OpenBao custody half of the Identity and Authority Chain).
**Authors:** claude-bottom (drafter) + claude-top (co-design + review) + codex (independent code-grounded review, 2026-05-23 22:30-22:45)
**Supersedes:** the "Generalise the helper to read OpenBao too"
deferred alternative in [ADR-0024](../decisions/0024-two-identity-admin-model.md)
§Alternatives — ADR-0024's deferral entry is now annotated as
"superseded by ADR-0028."

**Relationship to architecture (added 2026-05-24):** This plan is the
*implementation mechanism* for ADR-0028 D1's OpenBao custody half. The
architecture doc at
[`docs/architecture/DMF Identity and Authority Model.md`](../architecture/DMF%20Identity%20and%20Authority%20Model.md)
is the canonical model; this plan executes one slice of it (the unified
helper + 698 + forgejo-bootstrap + 191 post-task cleanup). The eight
PRs in §Sequencing are the implementation tickets. Other ADR-0028
follow-ons (AWX local-admin rename, NetBox/Forgejo/Grafana renames,
OIDC client-secret rotation) are tracked separately per the survey §5.

**Revision history:**
- 2026-05-23 v1 — initial draft (claude-bottom).
- 2026-05-23 v2 — claude-top review pass: PR 1 split into 1a (refactor) + 1b (new mode); PR 3.5 Phase-0 audit added before netbox role migration; `app_admin_fallback_chain:` list parameter added to API spec to eliminate call-site duplication; §Audit integration made `app_admin_mode: live-read` explicit for audit invocations; PR 6 scope clarified as a K8s-Secret-side verifier rewrite (admin-identity-resolve, not app-admin-facts). Both reviewers converged on all four operator decisions.
- 2026-05-23 v3 — codex review pass surfaced six material issues both prior reviewers missed. HIGH: (1) NetBox / netbox-sot were misclassified — they read `secret/apps/netbox/runtime`, not `secret/apps/netbox/admin`, so PR 3 + 3.5 + 4 dropped from scope entirely; (2) PR 6 verifier rewrite used the wrong helper (admin-identity-resolve expects username+password pairs, verifier reads single token), so PR 6 collapses to docs-only ADR amendment; (3) ADR-0007 inconsistency clarified — task-scoped Ansible `environment:` blocks are the canonical pattern and not forbidden by the rule against argv. MEDIUM: (4) `app_admin_fallback_chain` reshaped to paired `{username, password}` candidates; (5) grep acceptance criterion narrowed to `secret/apps/.*/admin`; (6) 191-zot-oidc.yml post-task validation block (bespoke OpenBao login + read at lines 49-89) folded into PR 1a scope. Sequencing collapses from 8 PRs to 6; effort estimate drops from ~7-8h to ~4-5h.

## TL;DR

DMF has two co-existing admin-identity helpers (`common/app-admin-facts`
for OpenBao-backed install-time materialisation; `common/admin-identity-resolve`
for K8s-Secret-backed live runtime reads) and **two bespoke OpenBao
admin-identity consumers**: `698-cms-netbox-forgejo-tokens.yml` (Forgejo
half) and the `forgejo-bootstrap` role. A third site —
`191-zot-oidc.yml`'s post-task validation block — re-implements both
helpers inline. ADR-0024 explicitly deferred unifying them, citing the
kubectl-exec/bao-CLI/stdin pattern. That citation is now stale: the
pattern is *already canonical* in two helpers and three playbooks. The
remaining work is generalisation, not new mechanism.

> **NetBox / netbox-sot are NOT consumers.** v3 scope correction
> (codex review): both roles read `secret/apps/netbox/runtime` for DB /
> Valkey / superuser-API-token material — runtime/data, not admin
> identity. NetBox admin user flows through `vault_bootstrap_admin_username`
> at install time only; no OpenBao admin secret exists for NetBox. Out
> of scope for this plan. A future "OpenBao runtime-secrets helper"
> could address the bespoke runtime reads, but that is a separate
> design problem.

This plan:

1. Extends `common/app-admin-facts` with a `live-read` mode that exposes
   the same `<prefix>_username` / `<prefix>_password` facts without
   writing. Default `materialize` mode behaviour is unchanged.
2. Refactors the role to delegate OpenBao session establishment to
   `common/openbao-session` (eliminating ~30 lines of inlined login).
3. Migrates **two bespoke consumers** (698 Forgejo half, forgejo-bootstrap
   role) onto the unified helper, plus cleans up the 191-zot-oidc.yml
   post-task validation block to use the canonical session helper.
4. Amends ADR-0024 to promote the deferred alternative.

End state: one helper, two modes, one OpenBao access pattern, and the
audit playbook (`audit-admin-identities.yml`) becomes the closing
verification of a closed loop — *prevent drift via helper, detect drift
via audit*.

## Why now

Three concrete signals converged this session:

1. **2026-05-23 — Authentik Secret-name miswire (dmf-infra@f434e8a).**
   `verify-oidc-admin-bridge.yml` hardcoded `authentik-runtime` as the
   default K8s Secret name; the role default is `authentik-env`. The
   verifier failed cleanly on g2r6-foa9 only because the playbook was
   wired into `bootstrap-verify.yml` minutes earlier. STATUS notes:
   *"the Secret-name drift is exactly the failure mode the unified
   helper would make structurally impossible"* (dmfdeploy@26594a4). A
   helper that sources `<app>_runtime_secret_name` from inventory at
   call time has no place for the literal default to drift from.

2. **2026-05-23 — 698 refactor inlined the helper pattern instead of
   adopting it (dmf-infra@29ca24b).** The Forgejo username resolution
   now reads `secret/apps/forgejo/admin → .username` with the right
   fallback chain — *exactly what `common/app-admin-facts` would do
   in a live-read mode*. The reason it's inlined: the helper today only
   has `materialize` semantics (read-or-generate-and-write). The
   live-read path doesn't exist yet, so 698 reinvented it. The new
   698-inline OpenBao read is correct but un-reusable; the next consumer
   would have to copy it again.

3. **2026-05-23 — convergence queue §#1 closure was scope-narrow.** The
   handoff retired the 6-flag override tax (an `aliyun-123` artefact)
   and added the audit playbook, but the bespoke-per-site OpenBao read
   pattern survived the cleanup. Two admin-identity sites
   (`698-cms-netbox-forgejo-tokens.yml` Forgejo half, `forgejo-bootstrap`
   role) still read OpenBao bespoke; the 191-zot-oidc.yml post-task
   validation block reinvents the entire session helper. The friction
   isn't operator-facing today but is structurally fragile (any of them
   could drift the way the verifier default did).

## Where things stand (audit, 2026-05-23 after dmf-infra@f434e8a)

| Site | Backend | Today's pattern | In scope? |
|---|---|---|---|
| `playbooks/vertical-security/110-authentik.yml` | OpenBao `secret/apps/authentik/admin` + `/breakglass` | `include_role: common/app-admin-facts` × 2 | ✅ caller-side openbao-session include added in PR 1a (no behaviour change) |
| `playbooks/vertical-security/191-zot-oidc.yml` (`roles:` block) | OpenBao `secret/apps/zot/admin` | `roles: - role: common/app-admin-facts` × 1 | ✅ same as above |
| **`playbooks/vertical-security/191-zot-oidc.yml` (`post_tasks:` validation block, lines 49-89)** | OpenBao `secret/apps/zot/admin` | bespoke breakglass JSON load + inline `bao write auth/userpass/login/ops-admin` + token extraction + `bao kv get` | **🔧 PR 1a — refactor onto `common/openbao-session` + single `bao kv get` task** |
| `playbooks/697-cms-awx-token.yml` | K8s Secret `awx-admin-password` | `include_role: common/admin-identity-resolve` × 1 | ✅ out of scope (K8s-Secret backend, correct helper) |
| `roles/stack/operator/awx-integration/tasks/main.yml` | K8s Secret | `include_role: common/admin-identity-resolve` | ✅ out of scope (correct helper) |
| **`playbooks/698-cms-netbox-forgejo-tokens.yml`** (Forgejo half) | OpenBao `secret/apps/forgejo/admin` | inline `bao kv get` via openbao-session | **🔧 PR 2 — migrate onto helper live-read mode** |
| **`roles/stack/operator/forgejo-bootstrap/tasks/main.yml`** | `vault_forgejo_admin_username` / `_password` direct + `openssl rand` for svc password | no OpenBao session; direct var read | **🔧 PR 3 — migrate admin-read onto helper live-read mode; svc-password `openssl rand` retained** |
| `roles/stack/operator/netbox/tasks/main.yml` | OpenBao `secret/apps/netbox/runtime` (DB, Valkey, superuser API token) | bespoke login + runtime-secret read | ❌ **out of scope — runtime/data, not admin identity** |
| `roles/stack/operator/netbox-sot/tasks/main.yml` | OpenBao `secret/apps/netbox/runtime` + `secret/apps/forgejo/runtime` | same shape, smaller surface | ❌ **out of scope — runtime/data, not admin identity** |
| `roles/stack/operator/awx/tasks/main.yml` (install) | direct vars + `awx-manage update_password` | admin password sync, not identity resolution | ❌ out of scope (tangential) |

Two helpers cover four sites today (110 × 2, 191 roles-block, 697,
awx-integration). **Three sites carry bespoke admin-identity code that
this plan migrates:** 191 post_task validation, 698 Forgejo half, and
forgejo-bootstrap. Roughly ~90 lines of bespoke code drop after
migration.

NetBox / netbox-sot are excluded — their bespoke OpenBao reads target
*runtime/data secrets* (DB passwords, Valkey passwords, superuser API
tokens), not admin identity. Those reads are correct as written; a
follow-on plan could design a "common/app-runtime-facts" sibling
helper if the per-role login-chain duplication becomes a maintenance
problem, but that is a different design problem and out of scope here.

## Design — one helper, two modes

### Decision

**Extend `common/app-admin-facts` with a `live-read` mode** rather than
introduce a third role. Rationale:

- The role already provides the canonical `<prefix>_username` /
  `<prefix>_password` / `<prefix>_email` / `<prefix>_secret_path` fact
  surface. Live-read consumers want the same surface, just without the
  write path.
- Caller code stays uniform: `include_role: common/app-admin-facts`
  works at both install time (materialize) and provisioning/runtime
  (live-read). Switching modes is one extra `app_admin_mode:` var.
- `common/admin-identity-resolve` stays as the K8s-Secret-backed
  sibling. The two helpers split on **backend**, not on lifecycle —
  matching how the data physically lives in the cluster.

Alternative considered and rejected:

- **Three roles** (`app-admin-facts` + `app-admin-resolve` (new) +
  `admin-identity-resolve`) — splits the OpenBao operations across two
  roles for no architectural reason. Adds a discoverability tax.
- **One role with `backend: k8s-secret | openbao`** dispatch — collapses
  too much. K8s-Secret reads don't need an OpenBao session; OpenBao
  reads do. Branching inside the role on `backend` would duplicate the
  switch in every task. Two backend-specific roles with stable outputs
  is the right factoring.

### Secondary refactor — delegate session establishment to `common/openbao-session`

Pre-condition for both materialize and live-read modes: caller has
already included `common/openbao-session` (mode `operator`). This:

- **Eliminates 30 lines** of inlined OpenBao login from
  `app-admin-facts/tasks/main.yml` (lines 13-84 today).
- **Aligns with the established pattern.** 698, 110-authentik, and
  691-vault-init all use `common/openbao-session`. `app-admin-facts`
  is the outlier still rolling its own login.
- **Single source of truth for session expiry / re-login semantics.**
  Future hardening (token TTL bumps, automatic re-login) lands in one
  place.

`app-admin-facts` reads `_openbao_session_pod` and
`_openbao_session_client_token` from the play scope (same facts that
699-cms-* playbooks already consume). Validation tasks fail loud if
those facts are missing.

## Helper invariants

Five rules the unified helper must satisfy. Per claude-top's regret on
dmf-infra@29ca24b (the 698 `_cms_forgejo_admin_user` set_fact was gated
on `not _cms_forgejo_token_exists`, so standalone reruns skipped the
consumer path entirely):

1. **Always set the resolved fact unconditionally.** The
   `<prefix>_username` / `<prefix>_password` facts are always exposed,
   regardless of idempotency gates downstream. Consumer tasks may carry
   their own `when:` guards; the resolution layer never does.
2. **Live-read mode never writes.** No `bao kv put`, no password
   generation, no email defaulting. If the OpenBao secret is missing or
   incomplete, fall back to caller-supplied values. If neither yields a
   non-empty username, fail loud with a structured error message
   pointing at the secret path.
3. **No secret values in argv, env-vars-visible-via-ps, or
   transcripts.** All credential-touching tasks carry `no_log: true`.
   Bao tokens enter pod stdin via `printf '%s\n' "$VAR" | kubectl exec
   -i ...` — the canonical pattern used by openbao-session and
   app-admin-facts today.
4. **One session, many reads.** A single play including
   openbao-session once may include app-admin-facts (live-read) N times
   for N apps without re-logging-in. Reuses
   `_openbao_session_pod` + `_openbao_session_client_token`.
5. **Default mode is materialize — backward compatible.** Existing
   consumers (110-authentik, 191-zot-oidc) pick up the
   session-delegation refactor transparently. They will need a paired
   `common/openbao-session` include added immediately before the
   `common/app-admin-facts` include in the same play. This is a
   one-line caller change per existing site.

## API spec (proposed)

### New inputs

| Var | Required? | Default | Purpose |
|---|---|---|---|
| `app_admin_mode` | no | `materialize` | One of `materialize` or `live-read`. |
| `app_admin_fallback_username` | live-read only | — | Returned when OpenBao secret missing/empty. |
| `app_admin_fallback_password` | live-read only | — | Returned when OpenBao secret missing/empty. |
| `app_admin_fallback_candidates` | optional, live-read | `[]` | **Ordered list of paired `{username, password}` candidates.** Helper picks the first candidate where **both** `username` AND `password` are non-empty. When set, takes precedence over the scalar `app_admin_fallback_username` / `_password` pair. Each candidate is one source — username and password cannot be mixed across sources. v3 spec correction (codex MEDIUM-4): v2's flat-list `app_admin_fallback_chain` could mix username-from-source-1 with password-from-source-2; the paired structure makes that impossible. |

Fallback-candidates example (consumer-side, eliminates per-site `default(... default(... default(...)))` duplication AND prevents username/password source mixing):

```yaml
app_admin_fallback_candidates:
  - { username: "{{ forgejo_admin_username | default('') }}",
      password: "{{ forgejo_admin_password | default('') }}" }
  - { username: "{{ vault_bootstrap_admin_username | default('') }}",
      password: "{{ vault_bootstrap_admin_password | default('') }}" }
  # No literal `dmfadmin` last-resort: empty password would force a hard
  # fail at consumer time, which is the right behaviour. If a deployer
  # really wants a literal fallback they can add a candidate explicitly.
```

Helper walks the list, returns the first candidate where **both** fields
are non-empty, exposed as `<prefix>_username` + `<prefix>_password`. If
all candidates have an empty field somewhere, fall through to the
scalar `app_admin_fallback_username` / `_password` pair (which may also
be empty — in which case the helper sets the diagnostic
`<prefix>_source: "no-fallback"` and downstream consumer assertions
should fail loud rather than papering over the missing credential).

Optional polish; can land in PR 1b alongside the `live-read` mode or as
a separate follow-up. Does not block PR 1a.

### Retained inputs (unchanged)

`app_admin_app_name`, `app_admin_fact_prefix`, `app_admin_secret_path`,
`app_admin_default_username`, `app_admin_default_email`,
`app_admin_username_input`, `app_admin_password_input`,
`app_admin_email_input`, `app_admin_expected_username`,
`app_admin_password_bytes`.

### Retired inputs

`app_admin_openbao_namespace`, `app_admin_openbao_pod_label_selector`,
`app_admin_openbao_breakglass_file` — all subsumed by the
`common/openbao-session` pre-condition.

### Outputs (unchanged)

```
{{ app_admin_fact_prefix }}_username
{{ app_admin_fact_prefix }}_password
{{ app_admin_fact_prefix }}_email          (materialize mode only)
{{ app_admin_fact_prefix }}_secret_path
{{ app_admin_fact_prefix }}_source         (NEW — diagnostic: "openbao" | "fallback")
```

### Call-site example — 698 after migration

```yaml
- name: Establish OpenBao operator session
  ansible.builtin.include_role:
    name: common/openbao-session
  vars:
    openbao_session_mode: operator
    openbao_session_breakglass_file: "{{ eso_openbao_breakglass_file | default((openbao_key_path | default('')) ~ '.json', true) }}"
    openbao_session_namespace: "{{ cms_openbao_namespace | default('openbao') }}"

- name: Resolve Forgejo admin identity from OpenBao
  ansible.builtin.include_role:
    name: common/app-admin-facts
  vars:
    app_admin_mode: live-read
    app_admin_app_name: forgejo
    app_admin_fact_prefix: _cms_forgejo_admin
    app_admin_secret_path: secret/apps/forgejo/admin
    app_admin_fallback_candidates:
      - { username: "{{ forgejo_admin_username | default('') }}",
          password: "{{ forgejo_admin_password | default('') }}" }
      - { username: "{{ vault_bootstrap_admin_username | default('') }}",
          password: "{{ vault_bootstrap_admin_password | default('') }}" }
```

Downstream consumer tasks reference `_cms_forgejo_admin_username` /
`_cms_forgejo_admin_password` directly. The ~50 lines of inlined
`bao kv get` + fact-parsing + assertion code in
`698-cms-netbox-forgejo-tokens.yml` collapse to the two `include_role`
blocks above.

## Migration roster (v3)

| # | Site | Mode | Surface dropped | Notes |
|---|---|---|---|---|
| 1 | `playbooks/698-cms-netbox-forgejo-tokens.yml` | live-read | ~50 lines | Forgejo half only. NetBox half doesn't read admin (Django shell bypass per dmf-infra@29ca24b). |
| 2 | `roles/stack/operator/forgejo-bootstrap/tasks/main.yml` | live-read | ~20 lines | Replace direct `forgejo_admin_username` / `forgejo_admin_password` var reads. `openssl rand -base64 24` for the *service* (not admin) password stays. |
| 3 | `playbooks/vertical-security/191-zot-oidc.yml` `post_tasks:` (lines 49-89) | n/a — session cleanup | ~40 lines | Bespoke breakglass JSON load + inline `bao write auth/userpass/login/ops-admin` + token-extraction `sed` + `bao kv get -field=password`. Refactor onto `common/openbao-session` (mode `operator`) + a single `bao kv get` task using the established `_openbao_session_*` facts. Pure session cleanup; no app-admin-facts include needed here. |
| 4 | `playbooks/697-cms-awx-token.yml` | (review only) | — | Already uses `common/admin-identity-resolve` (K8s-Secret-side, correct backend). Unified helper does *not* subsume this — different backend. Confirm no change needed; document the K8s-Secret/OpenBao split in the v3 ADR amendment. |

**v3 removals** (codex HIGH-1 + HIGH-2):

- ~~`roles/stack/operator/netbox-sot/tasks/main.yml`~~ — out of scope. Reads `secret/apps/netbox/runtime` (DB / cms_api_token / superuser API token material), not admin identity. The `_netbox_sot_openbao_breakglass.ops_admin_username/password` it loads is the OpenBao *operator* identity used to log into OpenBao, not a per-app admin to materialise.
- ~~`roles/stack/operator/netbox/tasks/main.yml`~~ — same. Reads `secret/apps/netbox/runtime`. No `secret/apps/netbox/admin` path exists in active code.
- ~~PR 3.5 Phase-0 audit of netbox~~ — moot now that netbox is out of scope.
- ~~`playbooks/verify-oidc-admin-bridge.yml` verifier rewrite~~ — wrong abstraction (admin-identity-resolve expects username+password keys; verifier reads single token `AUTHENTIK_BOOTSTRAP_TOKEN`). claude-top's f434e8a fix is sufficient. A generic `common/k8s-secret-key-resolve` for single-key lookups is a *separate* design problem; defer until a second single-key use case appears.

Existing materialize consumers (110-authentik × 2, 191-zot-oidc `roles:`
block × 1) get the openbao-session pre-condition added in the same PR
as the helper refactor. No behavioural change; one extra `include_role`
per site.

## ADR-0024 amendment (proposed text)

In ADR-0024 §Alternatives, the entry currently reads:

> - **Generalise the helper to read OpenBao too.** Plausible, and
>   would let NetBox + Forgejo opt into the same abstraction. Deferred:
>   the existing OpenBao-read code paths in 698 and the netbox role
>   are not broken, and OpenBao reads have ADR-0007 implications
>   (kubectl exec + `bao` CLI streaming via stdin) that don't map
>   cleanly onto a declarative helper. Revisit if a future env
>   exhibits OpenBao-side admin drift.

Replace with:

> - **Generalise the helper to read OpenBao too.** Plausible, and
>   would let NetBox + Forgejo opt into the same abstraction. Initially
>   deferred (2026-05-22) on ADR-0007 grounds. **Promoted to active
>   work 2026-05-23** when (a) the canonical kubectl-exec / bao-CLI /
>   stdin pattern proved to compose cleanly across
>   `common/openbao-session` + `common/app-admin-facts` + 698, and
>   (b) the Authentik verifier Secret-name miswire (dmf-infra@f434e8a)
>   exposed that bespoke per-site defaults are themselves a drift
>   surface the helper would close. Realised by
>   [`docs/plans/DMF Unified App-Admin Helper Plan 2026-05-23.md`](../plans/DMF%20Unified%20App-Admin%20Helper%20Plan%202026-05-23.md);
>   ADR-0024 §Enforcement updated to list the unified `live-read` mode
>   alongside the materialize mode.

Update §Enforcement to add `app_admin_mode: live-read` as a sanctioned
consumer pattern alongside `materialize`, with the migrated consumers
enumerated.

## ADR-0007 reading (v3 clarification — codex HIGH-3)

ADR-0007 rule 1 forbids secrets in **argv** — concretely, anything
visible to `ps` on the operator's workstation or the control node. The
ADR's §Context names environment as a leak surface (referencing
`/proc/<pid>/environ`), but the §Decision **rules** call out only argv
("`export TOKEN=xxx` on the command line", `docker login -p PASS`, etc.).

This plan reads ADR-0007 as **permitting Ansible task-scoped
`environment:` blocks** for streaming secrets to `kubectl exec`'s
stdin, because:

1. **Not argv.** The secret value never appears in the shell command
   line that `ps` sees. Only the literal `"$VAR"` placeholder appears.
2. **Task-scoped lifetime.** Ansible's `environment:` block scopes the
   variable to the single forked shell that runs the task. It is not
   exported into the operator's interactive shell, doesn't persist
   into shell history, and exits with the spawned process.
3. **The de-facto canonical pattern.** `common/openbao-session/tasks/main.yml:80`,
   `common/app-admin-facts/tasks/main.yml:86`, and every consumer of
   either (110-authentik, 191-zot-oidc, 698) use this exact shape.
   Treating it as forbidden would invalidate the entire established
   approach.
4. **The alternative is worse.** Ansible's `shell` module supports a
   `stdin:` parameter that bypasses env entirely for *single-value*
   streams. But the canonical `bao` interaction passes multiple values
   in one task (token + payload write), where `environment:` is the
   only clean multi-value option. Inlining values via Jinja
   substitution would put them in the shell command, which IS argv —
   strictly forbidden.

**Explicit rule for this plan:** Ansible `environment:` blocks may
carry secret values only when (a) the task body consumes them via
`printf '%s' "$VAR" | ... read ...` for stream-to-kubectl-exec, and
(b) the task carries `no_log: true`. The values must never reach
argv (Jinja-into-command-line), `/tmp` files, or `stdout`.

If a future ADR-0007 amendment narrows this, every existing helper
and consumer would need a sweep — out of scope for this plan, but
worth a follow-on ADR-0007 amendment if the operator wants the
strict reading enforced.

## ADR-0007 compliance checklist

The unified helper inherits two-year-old discipline; the checklist
exists to make it explicit in code review. **Read alongside the §ADR-0007
reading above** — env-vars-as-stdin-pipe is permitted under the
plan-explicit rule.

- [ ] All credential-touching tasks (`set_fact`, `shell`, `assert`,
      `uri`) set `no_log: true`.
- [ ] Bao tokens stream via the canonical pattern
      `printf '%s\n' "$ENV_VAR" | kubectl exec -i ... -- sh -c 'IFS= read
      -r BAO_TOKEN; export BAO_TOKEN; bao ...'` — `environment:` block
      sets `ENV_VAR`; task carries `no_log: true`. The secret value
      never appears in argv.
- [ ] OpenBao secret payloads piped via stdin in the same pattern when
      writing (materialize mode only).
- [ ] Resolved facts (`<prefix>_username`, `<prefix>_password`) carry
      `no_log` on their `set_fact` so resolved values don't appear in
      verbose-mode output.
- [ ] Helper README documents that downstream consumers must
      `no_log: true` any `uri:` / `command:` task that uses the resolved
      password.
- [ ] Test: run `bootstrap-configure.yml` on g2r6-foa9 with
      `ANSIBLE_VERBOSITY=2`; grep transcript for any 8-character bao
      token fragment or known-password substring. Expect zero matches.

## Audit integration — closed loop

The new `audit-admin-identities.yml` playbook (dmf-infra@29ca24b)
queries live cluster admin lists for 5 apps and asserts the role-default
expected username appears. Wired into `bootstrap-verify.yml` per
dmf-infra@596b28b.

With the unified helper landed, the integration story is:

1. **Helper sets resolved fact at runtime** — for every consuming role.
   The fact is sourced from OpenBao at the canonical
   `secret/apps/<app>/admin` path.
2. **Audit playbook compares live state against the same role-default
   expected username** that the helper would resolve to in fallback
   mode. If OpenBao + role default + live state all agree, no drift.
   If any disagree, audit fails and bootstrap-verify catches it.
3. **The two together implement prevent-and-detect.** The helper
   prevents the wrapper-vs-cluster drift class (ADR-0024 §Context). The
   audit detects any remaining drift introduced out-of-band
   (manual `kubectl exec` admin changes, OIDC shadow-superuser
   creation, etc.).

A new audit assertion can be added: "the helper's resolved username for
app X matches the live username." This catches the case where OpenBao
and live state agree but neither matches the role default — a class the
current audit doesn't cover.

**Audit must invoke the helper in `live-read` mode explicitly.** The
audit playbook never writes to OpenBao; the helper in `materialize`
mode would write a missing secret. Every `include_role` of
`common/app-admin-facts` inside `audit-admin-identities.yml` MUST
carry `app_admin_mode: live-read`:

```yaml
- name: Resolve {{ app }} admin identity for audit comparison
  ansible.builtin.include_role:
    name: common/app-admin-facts
  vars:
    app_admin_mode: live-read    # MANDATORY — audit never writes
    app_admin_app_name: "{{ app }}"
    app_admin_fact_prefix: "_audit_{{ app }}"
    app_admin_secret_path: "secret/apps/{{ app }}/admin"
    app_admin_fallback_username: ""   # fallback intentionally empty —
    app_admin_fallback_password: ""   # audit wants to see drift, not paper over it
```

Empty fallback values mean the audit reports "OpenBao missing this
secret" as a *finding*, not as a silent fallback resolution. Drift
detection requires explicit nulls.

## Sequencing (v3 — 6 PRs)

Land in six PRs against `dmf-infra`. Each is independently revertable.
v3 collapsed from 8 PRs after codex review (HIGH-1 dropped netbox /
netbox-sot / PR 3.5; HIGH-2 dropped PR 6's verifier rewrite half).

| PR | Scope | Effort | Verification |
|---|---|---|---|
| **1a** | **Pure refactor, no new feature + 191 post-task cleanup.** (1) Drop inline OpenBao login from `common/app-admin-facts` (lines 13-84 today); add `common/openbao-session` as documented pre-condition. (2) Update existing materialize consumers (110-authentik × 2, 191-zot-oidc `roles:` block × 1) to include openbao-session immediately before app-admin-facts. (3) Refactor 191-zot-oidc.yml `post_tasks:` validation block (lines 49-89) onto the established session-pod facts — drops bespoke breakglass JSON load + inline `bao write auth/userpass/login/ops-admin` + token-extraction `sed` + standalone `bao kv get`; replaced by one `include_role: common/openbao-session` + one `bao kv get` task using `_openbao_session_pod` + `_openbao_session_client_token`. Materialize behaviour byte-identical end-to-end. | 1.5-2h | Re-run 110-authentik + 191-zot-oidc on g2r6-foa9 → `failed=0`. `bootstrap-verify.yml` byte-identical with pre-PR baseline (modulo the 191 post-task log lines). |
| **1b** | **New `app_admin_mode: live-read` mode** (read-only path; no write, no password generation, no email defaulting). Add `app_admin_fallback_candidates:` paired-dict list parameter alongside scalar fallbacks. README documents both modes; tests against a non-production fixture (no live cluster). No consumer migration yet. | 1-1.5h | Fixture-driven unit tests; no live-cluster gate. |
| 2 | Migrate 698 (Forgejo half) onto helper live-read mode. Drop ~50 lines of inlined OpenBao read. | 30min | Standalone 698 rerun on g2r6-foa9; rotate the token first so consumer-path tasks actually execute (lesson from dmf-infra@29ca24b). |
| 3 | Migrate `forgejo-bootstrap` role. Replace direct `forgejo_admin_username` / `_password` reads with helper live-read. Service-password `openssl rand -base64 24` retained (service != admin). | 1h | 692-forgejo-bootstrap rerun on g2r6-foa9. |
| 4 | **Docs-only — ADR-0024 amendment + STATUS update + convergence-queue note + 697 documentation pass.** Promote the deferred §Alternative; update §Enforcement to list both `materialize` and `live-read` modes with migrated consumers; STATUS HUMAN-START note pointing at the closing handoff; convergence-queue collapse to DONE marker. Document the K8s-Secret/OpenBao split for 697 — confirm `common/admin-identity-resolve` remains the right helper there (different backend). No code touches. | 30min | Doc-only. `git grep -E "secret/apps/.*/admin"` shows no bespoke reads outside `common/app-admin-facts/`. |
| 5 | End-to-end: `bootstrap-verify.yml` on g2r6-foa9 — all four imported plays `failed=0`. `audit-admin-identities.yml` (invoking helper in `live-read` mode per §Audit integration) confirms no drift. Capture log. Optionally: one fresh-wizard-env greenfield run as gold-standard validation. | 30min (g2r6-foa9) + ~60min (optional fresh wizard) | One full bootstrap-verify run. |

**Total in-repo effort:** ~4-5h spread over 1-2 sessions.

## Risks + open questions

1. **Existing materialize consumers need a one-line caller change**
   (add openbao-session include). 110-authentik and 191-zot-oidc are
   affected. If those plays are running anywhere outside the umbrella
   we control (unlikely — they're env-bootstrap plays), the migration
   could surprise downstream callers. Mitigation: PR 1 ships both
   helper refactor and caller updates in the same commit.

2. ~~**`netbox` role bespoke login** — RETIRED in v3 (codex HIGH-1).
   NetBox/netbox-sot read runtime/data secrets, not admin identity;
   out of scope for this plan. If a future "common/app-runtime-facts"
   helper is designed, this risk attaches to that plan, not this one.~~

3. **Fallback semantics in live-read.** Today the inlined 698 code
   falls back through three layers: OpenBao → `forgejo_admin_username`
   var → `vault_bootstrap_admin_username` → (no literal — fail loud).
   The unified helper accepts either scalar `app_admin_fallback_username`
   /`_password` *or* the paired `app_admin_fallback_candidates:` list
   (see API spec). When the list is set, callers express the canonical
   N-layer fold as `{username, password}` pairs — first pair with both
   fields non-empty wins. v3 made the list paired (not flat) per codex
   MEDIUM-4 so username and password cannot be sourced from different
   layers. README documents both forms; recommend
   `app_admin_fallback_candidates` in new migrations.

4. **697 scope check.** 697 uses `common/admin-identity-resolve`
   (K8s-Secret-side, correct backend). v3 retains 697 as-is; PR 4
   (docs-only) explicitly documents the K8s-Secret/OpenBao backend
   split in the ADR amendment so future maintainers see why 697
   doesn't migrate onto `app-admin-facts`. The verifier-rewrite half
   of the old PR 6 was dropped in v3 (codex HIGH-2) — admin-identity-resolve
   was the wrong helper for a single-token K8s Secret read. A generic
   `common/k8s-secret-key-resolve` for single-key lookups is a *separate*
   design problem; deferred until a second single-key use case appears.

5. **Live-read against a not-yet-materialized secret.** If the helper
   runs in live-read mode against `secret/apps/<app>/admin` before
   that secret has been materialised (e.g. mid-bootstrap, between
   install and configure stages), it falls back to caller-supplied
   values. This is correct semantics but a subtle behaviour. Capture
   `<prefix>_source` ("openbao" | "fallback") for diagnostic
   transparency — already in the API spec above.

6. **The audit playbook's "preamble noise" followup (handoff §What's
   still owed #2)** is unrelated to this plan but worth pairing —
   while migrating consumers, also clean up the Django-shell /
   awx-manage shell_plus preamble that pollutes audit stdout.

## Acceptance criteria (v3)

- [ ] `common/app-admin-facts` has `app_admin_mode: live-read`
      implemented and documented in README.
- [ ] `common/app-admin-facts` no longer contains an inline OpenBao
      login chain (delegated to `common/openbao-session`).
- [ ] `git grep -nE "bao kv (get|read|list) .*secret/apps/[a-z-]+/admin" k3s-lab-bootstrap/`
      returns matches **only** inside `common/app-admin-facts/tasks/`.
      Every other admin-identity read site uses the helper.
      **(v3 narrowed from `secret/apps` to `secret/apps/.*/admin` per
      codex MEDIUM-5; runtime-path reads at `secret/apps/.*/runtime` in
      netbox / netbox-sot / 696 / 697 / 698 / awx-integration are
      explicitly out of scope and excluded from this grep.)**
- [ ] `bootstrap-verify.yml` on g2r6-foa9 → `failed=0` across all four
      imported plays.
- [ ] `audit-admin-identities.yml` passes no-drift assertions on
      g2r6-foa9 after migration (5 apps: awx, forgejo, netbox, zot,
      authentik).
- [ ] 191-zot-oidc.yml `post_tasks:` validation block uses
      `common/openbao-session` (no bespoke `bao write
      auth/userpass/login` invocation in the playbook).
- [ ] ADR-0024 §Alternatives amended; §Enforcement lists the new
      live-read consumers; backend-split (K8s Secret →
      admin-identity-resolve, OpenBao → app-admin-facts) documented.
- [ ] STATUS HUMAN-START records the plan as DONE with a backref to a
      closing handoff.

## Cross-references

- [ADR-0024 — Two-Identity Admin Model](../decisions/0024-two-identity-admin-model.md)
  — the deferral this plan promotes.
- [ADR-0007 — Secrets never in argv](../decisions/0007-secrets-never-in-argv.md)
  — discipline the helper inherits.
- [ADR-0008 — OpenBao + ESO + AppRole shim](../decisions/0008-openbao-secrets-architecture.md)
  — the secrets-architecture context.
- [ADR-0021 — OpenBao AppRole reconciler identity](../decisions/0021-openbao-approle-reconciler-identity.md)
  — adjacent identity ADR.
- [DMF App-Admin Drift Realignment Handoff 2026-05-23](../handoffs/DMF%20App-Admin%20Drift%20Realignment%20Handoff%202026-05-23.md)
  — narrow-scope predecessor work; this plan finishes the job.
- [DMF Convergence Next Steps Queue 2026-05-23](DMF%20Convergence%20Next%20Steps%20Queue%202026-05-23.md)
  — §#1 closed by the handoff above; this plan addresses the
  bespoke-per-site pattern that the handoff left in place.
- `dmf-infra@29ca24b` — 698 Forgejo username consolidation (inlined
  pattern to be replaced).
- `dmf-infra@f434e8a` — Authentik verifier Secret-name miswire fix
  (motivating evidence #1).
- `dmfdeploy@26594a4` — STATUS closure with the framing line
  *"the Secret-name drift is exactly the failure mode the unified
  helper would make structurally impossible."*

## Operator decisions pending

Four small decisions before the plan is binding. Both reviewers have a
recommendation on each; operator is the final word.

1. **Mode name.** `live-read` vs `read-only` vs `resolve`.
   - Plan recommends: `live-read` — parallels `materialize`; signals
     runtime read semantics; `resolve` is taken by
     `common/admin-identity-resolve`.
   - claude-top: agrees with `live-read`. *"Don't bikeshed."*
2. **Whether to also migrate K8s-Secret-side `common/admin-identity-resolve`
   into `common/app-admin-facts`.**
   - Plan recommends: NO — keep two backend-specific roles. Plan
     §Design covers the reasoning.
   - claude-top: agrees with NO. *"The third-backend question is
     hypothetical today; over-abstracting now would force the
     K8s-Secret-side to grow a dispatch it doesn't need."*
3. **PR cadence.**
   - Plan recommends (v3): 6 incremental PRs (1a + 1b + 2 migrations +
     docs + verify). Reduced from 8 after codex review dropped the
     NetBox / netbox-sot / verifier-rewrite items.
   - claude-top: agrees. *"Independently revertable beats unified-but-large."*
4. **Live-test cadence.**
   - Plan recommends: each PR verifies on g2r6-foa9; optional fresh
     wizard env after PR 5 (was PR 7 pre-v3) as gold-standard greenfield
     validation.
   - claude-top: agrees. *"Don't gate every PR on a fresh wizard run."*

Both reviewers converged on the same answer to all four. Operator may
override; absent override, the recommendations apply.

## Process learning (v3, post-codex)

Two-reviewer (Claude × 2) under-performed on this plan. Codex's
independent 10-minute code-grounded review caught three HIGH issues
that bypassed both Claude reviewers — the most material being a wrong
scope-claim (NetBox migration) that would have wasted hours of
implementation effort before failing.

The root cause: both Claude reviewers accepted the framing claim
("NetBox stores admin in OpenBao like Forgejo does") without verifying
the OpenBao path actually existed. Codex's first check was to grep for
`secret/apps/netbox/admin` and discover it doesn't exist — a sanity
check neither Claude reviewer ran.

**Recommendation for future plan documents of this size:** institute
a three-reviewer pattern — drafter + adversarial reviewer + independent
code-grounded reviewer. The third seat is not redundant; it's the
sanity-check on framing claims. Codex is well-suited to the third seat
because its review tends to verify-everything-against-code rather than
reason-from-summary.

Not a process rule; a recommendation. If future plans choose two
reviewers, this note serves as the "you were warned" reference.
