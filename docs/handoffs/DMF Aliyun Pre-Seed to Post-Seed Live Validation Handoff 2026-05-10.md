# DMF Aliyun — Pre-Seed → Post-Seed Live Validation Handoff

**Date:** 2026-05-10
**Audience:** Next session — assume zero prior context.
**Scope:** `dmf-env`, `dmf-infra/k3s-lab-bootstrap`, umbrella docs.
**Status at end of session:** Pre-seed + seed-bao + post-seed all
**GREEN end-to-end** on the aliyun cluster. Configure stage NOT yet run.

## What happened today

The 2026-05-09 implementation plan §1–§21 changes were exercised against
a fresh aliyun cluster (full teardown + new tofu apply at start of
session). Five additional defects surfaced during live validation and
were fixed; the plan grew to §22–§27. The bring-up sequence now
reproduces cleanly.

## Cluster state — end of session

- **aliyun-frankfurt → `aliyun`** rename complete (paths, content,
  inventory references). Historical handoff/review docs retain
  `aliyun-frankfurt` as a record.
- **3 ECS instances** running k3s `v1.30.6+k3s1`:
  `8.211.28.16` / `47.87.138.154` / `47.245.149.55`
  (private `10.0.0.90/91/92`).
- **OpenBao** unsealed, ESO ClusterSecretStore reconciling, breakglass
  JSON at `<secure-store>/openbao-breakglass/aliyun/openbao-keys-automation.json`.
  Operator username `<operator>`, password length 32.
- **Layer 6 apps deployed** (post-seed PLAY RECAP `failed=0`):
  Authentik, Prometheus / Loki / Grafana / Promtail, landing-page,
  NetBox, Forgejo, AWX, dmf-cms.
- **Cloudflare** wildcard `*.<lan-host>` → `100.64.0.16/17/18`
  (Tailscale CGNAT); apex `<lan-host>` → `47.87.134.99` (public
  Traefik SLB).
- **One** Aliyun SLB remaining (`dmf-traefik-slb`, `47.87.134.99`).
  The redundant private-lane SLB `lb-gw8kyr3sslf03akbb87bv`
  (`8.211.19.167`) was deleted — `traefik-private` Service patched to
  `type: NodePort`; private lane reached via Tailscale DNAT → NodePort
  `30443`.

## Live passkey enrollment URL

A bootstrap-passkey invitation was generated during post-seed. URL
issued at 17:32 Z 2026-05-10 with a ~22h TTL:

```
https://auth.lab.dmf.example.com/if/flow/dmf-bootstrap-passkey-enrollment/?itoken=<itoken-redacted>
expires: 2026-05-11T15:32:14Z
```

Reach it via Tailscale (`auth.<lan-host>` resolves to the tailnet
CGNAT). To regenerate after expiry:

```bash
bin/get-passkey-enrollment-url.sh aliyun
```

## Implementation plan additions (§22 → §27)

All in `docs/plans/DMF Bootstrap Pre-Seed Blocker Fix Implementation Plan 2026-05-09.md`.
Brief summary; the plan has the full audit and rejected alternatives.

- **§22** — seed-bao acquires a one-shot root token from the 3 Shamir
  shares in the breakglass JSON for `secret/platform/*` writes; revokes
  via `bao token revoke -self`. Mirrors the role's
  `120-ops-admin-rotation.yml` pattern. Resolves cascading defects
  along the way: `expand_local_path` tilde-quoting bug (`${1#~/}` does
  tilde expansion on the *pattern*), `remote_kubectl` SSH arg quoting
  (use `printf '%q'`), sops decrypt `--output-type json` for the
  metadata-stamp pass.

- **§23** — `bootstrap-provision-post-seed.yml` boundary guard switched
  from `bao kv get` to `bao kv metadata get`; ops-admin's
  `app-admin-writer` policy granted **read** on exactly
  `secret/metadata/platform/{bootstrap_admin,k3s/cluster}`. Existence
  check without exposing secret values. Strictly smaller scope than
  ops-admin's existing data-read on `secret/data/apps/*`.

- **§24** — Reordered post-seed so `vertical-security/110-authentik.yml`
  runs *before* the monitoring stack and Layer 6 apps. Authentik's
  blueprint provisions OAuth2Providers for Grafana / Forgejo / NetBox
  / AWX; consumers' install-time tasks (Grafana role queries
  `OAuth2Provider.objects.get(name="Grafana")` at install) depend on
  those providers existing.

- **§25** — seed-bao writes per-app conventional usernames matching
  what each install role creates: `authentik → akadmin`,
  `zot → admin`, others → `${bootstrap_admin.username}`. The
  `common/app-admin-facts` role's `app_admin_expected_username`
  assertion previously failed on `authentik` because the operator's
  bundle name (e.g. `<operator>`) was being written everywhere.

- **§26** — Three-way audit: install role / seed-bao / consumer. Zot
  install role hardcoded `admin` (was reading
  `vault_bootstrap_admin_username`); NetBox/Grafana
  `secret/apps/<app>/admin` username brought into line with Helm chart
  defaults (`admin`). NetBox/Grafana mismatches were cosmetic (consumers
  use API tokens / OIDC); Zot was the functional blocker —
  `cms` image push hit 401 because Zot's htpasswd was provisioned with
  the operator's bundle name while consumers read `admin` from OpenBao.

- **§27** — `password_hash('bcrypt', rounds=10)` in the Zot role
  silently produces wrong hashes on bcrypt 5.x: passlib hits an
  `AttributeError` on `bcrypt.__about__.__version__`, traps it, falls
  through to a fallback backend. The traced `(trapped) error reading
  bcrypt version` line in the Ansible log is the only symptom — the
  task itself reports `ok`. Replaced with `htpasswd -inB -C 10` CLI
  (password via stdin, kept out of argv). Reverted a speculative
  `adminPolicy` template addition added during diagnosis — Zot's
  `defaultPolicy: ["read","create","update","delete"]` already
  authorises authenticated pushes once the htpasswd hash is correct.

## Other code/config landed today

- **Role default robustness** — `metallb_vip` referenced inside
  `external_base_url | default('http://' ~ metallb_vip)` was
  eager-evaluated by Jinja even when `external_base_url` was set; five
  role defaults (forgejo / awx / awx-integration / netbox-sot /
  forgejo-bootstrap) now wrap it in
  `metallb_vip | default('placeholder')` so cloud-native ingress envs
  don't have to set placeholder values.
- **Aliyun inventory** — `external_base_url: "https://{{ cert_manager_cluster_domain }}"`
  added (was missing entirely; the above default fallback only kicks
  in if `external_base_url` is also unset).
- **`bin/get-admin-cred.sh`** — env-aware (mirrors `unseal-openbao.sh`):
  `[ENV_NAME]` positional, breakglass / SSH target / SSH key all
  derived from inventory.
- **`bin/get-passkey-enrollment-url.sh`** — env-aware.
- **`bin/bootstrap-operator-approle.sh`** — env-aware (also derives
  `SECRETS_YML` from `inventories/<env>/group_vars/all/openbao_secrets.yml`).
- **`bin/rotate-approle-secret-id.sh`** — env-aware.
- **`bin/provision-nodes.sh`** — `HOSTS_INI` env-aware.
- **`bin/cluster-{bootstrap,rotate}-approle-*.sh`** — comment-only update;
  the `<node-public-ip>` literal in the docstrings swapped for a
  `<control-node>` placeholder.

## Live operations performed (not in git, captured here)

- **Aliyun teardown earlier in the session** — disabled
  `DeleteProtection` on the two `managed.by.ack` SLBs (CCM was
  degraded after the partial init), deleted via `aliyun slb`, stripped
  stuck k8s Service finalizers, `tofu destroy -auto-approve -lock=false`,
  Cloudflare `*.<lan-host>` record cleanup, Headscale node 67/68/69
  deletion, operator-side state confirmed clean.
- **§22 / §26 cleanups against the live OpenBao** — `bao kv metadata
  delete` on `secret/apps/{authentik,zot,netbox,grafana}/admin` after
  realising they held stale `<operator>` usernames; subsequent seed-bao writes
  with the correct per-app conventions.
- **§27 live recovery** — `htpasswd -nbB admin "$BUNDLE_PW"` to
  regenerate `zot-htpasswd` Secret from the current bundle password
  (the broken passlib-generated hash didn't verify); StatefulSet
  rolled. Push works.
- **Redundant SLB delete** — `traefik-private` Service patched to
  `NodePort`; `lb-gw8kyr3sslf03akbb87bv` (8.211.19.167) deleted.
  Tailscale DNAT to NodePort `30443` continues serving the private
  lane unchanged.
- **DNS apex** — `<lan-host> A 47.87.134.99` (public Traefik SLB)
  created in Cloudflare; landing-page served by the public lane. Stale
  `*.aliyun.<lan-host>` records deleted.
- **SSH known_hosts** — ssh-keyscan of the 3 cluster nodes; entries
  appended.

## What's next

1. **Configure stage** (runbook §5):

   ```bash
   RUNBOOK_TIMEOUT=5400 bin/run-playbook.sh aliyun \
       ../dmf-infra/k3s-lab-bootstrap/bootstrap-configure.yml \
       -e baseline_update_apt_cache=false
   ```

   Wires Zot OIDC overlay (191-zot-oidc.yml — uses
   `secret/apps/zot/admin = admin`), NetBox SoT, Forgejo bootstrap,
   AWX integration, dmf-cms ↔ Authentik / AWX / NetBox / Forgejo
   tokens, smoke test.

2. **Passkey enrollment** — claim the URL above via Tailscale before
   its TTL expires (or regenerate with `bin/get-passkey-enrollment-url.sh aliyun`).

3. **Configure stage failures** are likely on first attempt — the
   integration playbooks haven't been exercised on aliyun yet. Loop on
   the log and treat surprises the same way the §22-§27 ones were
   treated: surface, audit, propose, fix.

## Known follow-ups (deferred)

- **Pre-seed Zot install reads from OpenBao when available** — currently
  the Zot install reads `vault_zot_admin_password` from the bundle's
  compatibility-copy mapping (set up in `run-playbook.sh`). If the
  bundle password is rotated between pre-seed and seed-bao, the
  htpasswd Secret can end up generated from a different password than
  what later lands in `secret/apps/zot/admin`. The new
  `htpasswd -inB -C 10` task guarantees a working hash *for the
  current run*, but doesn't reconcile across runs if the values drift.
  Worth a dedicated ADR if multi-rotation flows become a thing.
- **`docs/diagram-design-guide.md`** still describes the Excalidraw
  authoring path even though `docs/diagrams/` was removed in favour of
  the BPMN 2.0 process docs. Either banner-supersede it or rewrite
  for the new flow.
- **USB shares 4+5 on `/Volumes/OPENBAO_A`** — §20 env-scopes them but
  the deletion-protection / multi-env behaviour wasn't exercised live
  this session.

## File pointers

- Plan: `docs/plans/DMF Bootstrap Pre-Seed Blocker Fix Implementation Plan 2026-05-09.md`
  (now §1 → §27)
- Runbook: `docs/runbooks/dmf-deploy-quickstart.md`
- Original handoff: `docs/handoffs/DMF Bootstrap Pre-Seed Two Blockers Handoff 2026-05-09.md`
- Older aliyun handoffs (for historical context, env was still
  `aliyun-frankfurt`):
  `docs/handoffs/DMF Aliyun Frankfurt Audit + Phase A Handoff 2026-05-08.md`,
  `docs/handoffs/DMF Aliyun Frankfurt Rollout Next Steps Handoff 2026-05-08.md`
