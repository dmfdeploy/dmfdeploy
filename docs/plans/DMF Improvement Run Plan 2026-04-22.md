---
status: executed
date: 2026-04-22
---
# DMF Improvement Run — Execution Plan (2026-04-22)

> **Vocabulary aligned 2026-04-25** with the EBU *Dynamic Media Facility Reference
> Architecture* White Paper V2.0. See `DMF EBU Mapping (2026-04-25).md` for the
> canonical layer / vertical / lifecycle map.

> **Status (2026-04-24):** Steps A, B, C, E DONE on `main`. Step D
> (DR drill) PARTIAL — Layer 2 (Host Platform) and Layer 3 (Container Platform)
> repeatable, paused at vertical-security/vertical-monitoring due to
> Loki PVC cleanup and SSH ControlMaster mux hang. See
> `DMF DR Drill Session Log 2026-04-22-B.md` for the 12 in-tree bugfixes
> produced by the partial drill.
>
> Key commits: infra `d21dde6` (site.yml), `128a32d` (5-location Shamir),
> `be8cde3` (!Find + CF-scope preflights); env `8e8d934` (runner wrapper),
> `a924e34` (longer timeouts for site/lifecycle wrappers).

**Purpose:** Concrete, ordered implementation plan for "Before a productive
rerun" — Steps A through E. Step F (provider-token migration) is carved
off to its own later session.

**Context docs (read in order if resuming cold):**
1. `<note-store>/System/Lessons.md` — 7 new entries from today
2. `docs/sessions/DMF Rebuild Session Notes 2026-04-22.md` — what ran, what broke, current state
3. `docs/architecture/DMF EBU Mapping (2026-04-25).md` — canonical layer/vertical/lifecycle map; old→new playbook table.
   `docs/plans/DMF Orchestrator and Renumbering Plan 2026-04-22.md` — superseded; kept for historical guardrails in §5b.
4. This doc

**Decisions already made (do not re-litigate):**
- **Commit cadence:** one commit + push per step (A, B, C, D, E). Use the existing remotes (`origin` on GitHub and `forgejo` on homelab Forgejo for dmf-infra; `origin` on homelab Forgejo for dmf-env).
- **Verify playbooks ship as stubs** — placeholder tasks only. Real content lands later in small follow-up PRs.
- **OpenBao Shamir layout:**
  - Shares 1, 2 → `<secure-store>/openbao-breakglass/hetzner-lab/share-{1,2}.json`
  - Share 3 → macOS Keychain `security add-generic-password -s openbao-breakglass-share-3`
  - Shares 4, 5 → Mac-attached USB `OPENBAO_A` at `/Volumes/OPENBAO_A/share-{4,5}.json`
- **Step F is its own session** (provider-token migration).

**Cluster state assumption:** By the time the fresh session runs, the
Hetzner cluster has been DESTROYED by the operator (`hcloud server delete`
× 3). Steps A, B, C, E-refactor land as code/config only. Then the
operator re-provisions and runs `site.yml` end-to-end as Step D. That
rebuild **is** the DR drill — timed, unattended, zero manual fixes once
started.

The prior combined `~/secure/openbao-breakglass/hetzner-lab/openbao-keys.json`
becomes a dead artifact after the rebuild and should be `shred`'d at the
end of the session. The NEW OpenBao init writes directly to the 5-location
layout; no migration script is used.

**Critical guardrails every step must honor:**
- Never use `| tail` on `ansible-playbook` output; always write to `/tmp/dmf-playbook-logs/<name>.log` and stream-tail.
- Never pipe through `tail -N` on bash output either — same buffering pitfall.
- If a playbook hangs >2× the expected time: it's the SSH ControlMaster mux. `pkill -f "ansible-playbook.*<name>"; rm -f <home>/.ansible/cp/<hash>`, then re-run.

---

## Step A — wrapper + monitor pattern

**Estimate:** 30–45 min.
**Touches:** `dmf-env/bin/run-playbook.sh`, new `dmf-env/bin/monitor-playbook.sh`.
**Cluster impact:** none.

### A.1 `bin/run-playbook.sh` changes

Target behavior:
- Hard cap total runtime to 15 min (`timeout 900`). Override via `RUNBOOK_TIMEOUT=1800 bin/run-playbook.sh ...`.
- Always write full output to `/tmp/dmf-playbook-logs/<playbook-basename>-<YYYYMMDD-HHMMSS>.log`.
- Also stream output to the terminal (so existing interactive invocations still see progress).
- Print the log path on stdout BEFORE ansible starts, so if the run hangs the operator knows where to tail.

Implementation sketch (to be refined during execution):
```bash
LOG_DIR="/tmp/dmf-playbook-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(basename "$PLAYBOOK" .yml)-$(date +%Y%m%d-%H%M%S).log"
TIMEOUT_SEC="${RUNBOOK_TIMEOUT:-900}"

echo "==> Logging to: $LOG_FILE"
echo "==> Timeout: ${TIMEOUT_SEC}s"
echo "==> Stream with: bin/monitor-playbook.sh $LOG_FILE"

exec timeout "$TIMEOUT_SEC" ansible-playbook \
  -i "$INVENTORY" \
  -e "@${TMP_VARS_FILE}" \
  "$PLAYBOOK" \
  "$@" 2>&1 | tee "$LOG_FILE"
```

Notes:
- `exec` replaces the shell so `timeout` sees the right pid.
- `| tee` streams AND persists, no buffering issue (tee line-buffers stdout).
- `timeout` exit code 124 means "we hit the cap" — log a clear message.

### A.2 New `bin/monitor-playbook.sh`

Takes a log path. Tails it with the filter the current sessions are using:
```bash
#!/usr/bin/env bash
LOG="${1:?usage: monitor-playbook.sh <log-file>}"
[[ -f "$LOG" ]] || { echo "no such file: $LOG" >&2; exit 1; }
exec tail -F "$LOG" | grep -E --line-buffered \
  "^(TASK |PLAY |fatal:|failed=|FAILED - RETRYING|PLAY RECAP|Blueprint invalid|Entry invalid)"
```

### A.3 README / inline docs

Update `dmf-env/README.md` (or create a one-liner if none exists) documenting the new pattern: `bin/run-playbook.sh <playbook>` + `bin/monitor-playbook.sh <path>` from the prior command's output.

### A.4 Commit

Branch: `feat/playbook-runner-guardrails`.
Commit message: `feat(runner): wrap timeout 900 + log to file + monitor helper`
Push to both remotes.

---

## Step B — renumbering + `site.yml` (stubs)

**Estimate:** 3–4 hours.
**Touches:** `dmf-infra/k3s-lab-bootstrap/playbooks/*`, new `site.yml`, lifecycle wrappers.
**Cluster impact:** none (pure code change).

### B.1 Mechanical renames — 23 `git mv` operations

Full table in `DMF EBU Mapping (2026-04-25).md`. Checklist (legacy
intermediate numbering shown; final EBU paths are in the Mapping doc):

```bash
cd <repos>/dmf-infra/k3s-lab-bootstrap/playbooks
# Layer 2 — Host Platform
git mv 01-verify-environment.yml    00-verify-environment.yml
git mv 00-baseline.yml              01-baseline.yml
git mv 05-harden.yml                02-harden.yml
# Layer 3 — Container Platform (k3s)
#   10-k3s.yml stays
git mv 18-post-bootstrap-verify.yml 11-k3s-verify.yml
# Layer 3 — Container Platform (network)
git mv 15-ingress.yml               20-ingress-public.yml
git mv 15-ingress-private.yml       21-ingress-private.yml
git rm 15-metallb.yml
git mv 16-cert-manager.yml          22-cert-manager.yml
git mv 17-tailscale.yml             23-tailscale.yml
# Layer 3 — Container Platform (storage)
git mv 20-longhorn.yml              30-longhorn.yml
git mv 21-zot.yml                   31-registry-zot.yml
git mv 22-landing-page.yml          32-landing-page.yml
# vertical-security + vertical-orchestration + vertical-monitoring
git mv 23-openbao.yml               40-openbao.yml
git mv 24-external-secrets-operator.yml 41-eso.yml
git mv 25-prometheus.yml            45-prometheus.yml
git mv 26-loki.yml                  46-loki.yml
git mv 27-grafana.yml               47-grafana.yml
git mv 28-promtail.yml              48-promtail.yml
# vertical-security (identity)
git mv 29-authentik.yml             50-authentik.yml
# Layer 6 — Application & UI
git mv 30-netbox.yml                60-netbox.yml
git mv 31-forgejo.yml               61-forgejo.yml
git mv 32-librenms.yml              62-librenms.yml
git mv 35-awx.yml                   63-awx.yml
# Layer 6 — App integration glue
git mv 40-netbox-sot.yml            70-netbox-sot.yml
git mv 41-forgejo-bootstrap.yml     71-forgejo-bootstrap.yml
git mv 42-awx-integration.yml       72-awx-integration.yml
```

**Before running these:** the current live Hetzner cluster still thinks the old numbers are the operational names. Anything that references them in dmf-env (docs, next-steps hints) needs updating too.

### B.2 Create 6 stub playbooks

Content pattern for each stub:
```yaml
---
# playbooks/<path>/<name>.yml
# STUB — real verification logic will land in a later PR.
# The slot is reserved so site.yml + lifecycle wrappers import cleanly.
- name: <Human-readable purpose>
  hosts: localhost
  become: false
  gather_facts: false
  tasks:
    - name: TODO — verify <what>
      ansible.builtin.debug:
        msg: |
          STUB: <path>/<name>.yml has not yet been implemented.
          Intended checks:
          - <check 1>
          - <check 2>
          See DMF EBU Mapping (2026-04-25).md for the full intent
          of this playbook.
```

Files to create:
- `playbooks/339-container-platform-verify.yml` — intended: CF wildcard A records match tailnet IPs, LB healthy, Certificate Ready
- `playbooks/vertical-monitoring/190-monitoring-verify.yml` — intended: Watchdog ping seen by healthchecks.io in last N min, ntfy topic has recent message
- `playbooks/vertical-security/190-breakglass-verify.yml` — intended: API login as seeded break-glass admin returns 200 BEFORE OIDC
- `lifecycle/operate-stack-verify.yml` — intended: all app URLs reachable on public + private lanes, OIDC login succeeds for each
- `lifecycle/finalise-teardown.yml` — intended: revoke ESO AppRole, wait for Longhorn backup flush, `hcloud server delete`, preserve floating IP + SSH key

(The 6th of the "6 new" is `301-k3s-verify.yml`, which is the rename of the old `18-post-bootstrap-verify.yml` — it already has content.)

### B.3 `site.yml` + lifecycle wrappers

`site.yml`:
```yaml
---
# Orchestrator for k3s-lab-bootstrap. Import-based so ansible sees the full
# plan up front; --list-tasks and --start-at-task work across the whole run.
# Each lifecycle wrapper is individually runnable for ad-hoc operator work.
- import_playbook: lifecycle-provision.yml
```

`lifecycle-provision.yml` imports the per-layer / per-vertical playbooks
with tags. Example slice for Layer 3 (Container Platform — network):
```yaml
# lifecycle-provision.yml (slice)
---
- import_playbook: playbooks/310-ingress-public.yml
  tags: [layer3, network, ingress]
- import_playbook: playbooks/311-ingress-private.yml
  tags: [layer3, network, ingress, private-lane]
- import_playbook: playbooks/320-cert-manager.yml
  tags: [layer3, network, tls]
- import_playbook: playbooks/321-tailscale.yml
  tags: [layer3, network, tailscale]
- import_playbook: playbooks/339-container-platform-verify.yml
  tags: [layer3, verify]
```

Full layer/vertical map (keep in sync with the EBU Mapping doc):
- Layer 2 — Host Platform: 200-baseline, 210-harden, 219-host-verify
- Layer 3 — Container Platform (k3s): 300-k3s, 301-k3s-verify
- Layer 3 — Container Platform (network): 310-ingress-public, 311-ingress-private, 320-cert-manager, 321-tailscale, 339-container-platform-verify
- Layer 3 — Container Platform (storage): 330-longhorn, 331-registry-zot
- vertical-security: vertical-security/100-openbao, vertical-security/110-authentik, vertical-security/190-breakglass-verify
- vertical-orchestration: vertical-orchestration/100-eso
- vertical-monitoring: vertical-monitoring/100-prometheus, 110-loki, 120-grafana, 130-promtail, 140-librenms, 190-monitoring-verify
- Layer 6 — Application & UI: 600-landing-page, 610-netbox, 620-forgejo, 640-awx, 650-dmf-cms
- Layer 6 — App integration glue: 691-netbox-sot, 692-forgejo-bootstrap, 693-awx-integration
- lifecycle-operate: lifecycle/operate-stack-verify.yml
- lifecycle-finalise: lifecycle/finalise-teardown.yml

### B.4 Doc updates

- `DMF Session Handoff 2026-04-22.md` §6 — rewrite the run-order table with new numbers.
- `DMF Rebuild Session Notes 2026-04-22.md` §1 — same.
- `DMF Orchestrator and Renumbering Plan 2026-04-22.md` — mark §4.1 done (note: doc is superseded by `DMF EBU Mapping (2026-04-25).md`).
- `dmf-env/bin/provision-nodes.sh` final "Next:" message — update the filenames.

### B.5 Commit + push

Two commits to keep history legible:
1. `refactor(playbooks): renumber per EBU layer/vertical scheme + drop metallb-only play`
2. `feat(orchestrator): add site.yml + lifecycle wrappers + 6 verify stubs`

Push to both remotes.

---

## Step C — preflights (authentik, cert-manager)

**Estimate:** 30–60 min each, ~1 hour total.
**Touches:** `roles/stack/operator/authentik/tasks/main.yml`, `roles/base/cert-manager/tasks/main.yml`.
**Cluster impact:** none (preflights run as part of playbook; will simply pass on current cluster).

### C.1 Authentik blueprint `!Find` preflight

Before the `apply_blueprint` loop, add a task that exec's `ak shell` against the worker pod and evaluates the three scope-mapping `!Find` references. If any resolves to None (or to the string `"None"`), fail loudly with the guidance `Use authentik_core.propertymapping, not authentik_providers_oauth2.scopemapping` + link to Lesson 2026-04-22.

### C.2 cert-manager CF-token scope preflight

Before creating the Cloudflare ClusterIssuer, add a task that:
1. Hits `https://api.cloudflare.com/client/v4/user/tokens/verify` — confirms token valid.
2. Hits `https://api.cloudflare.com/client/v4/zones?name=<apex>` — confirms token can list the zone.
If step 2 returns empty list, fail with the explicit message:
`"Your Cloudflare DNS-01 token lacks Zone.Zone.Read. Add that scope to the token, then rerun."`

### C.3 Commit + push

Branch: `feat/preflights-authentik-certmanager`.
Single commit: `feat(preflights): catch authentik !Find and cert-manager CF-token-scope failures early`.

---

## Step D — full DR drill via `site.yml`

**Estimate:** 60–90 min wall-clock (target: <90 min unattended).
**Touches:** the whole cluster. This is a destructive rebuild.
**Cluster impact:** total — cluster is rebuilt from zero state.

### D.0 Pre-flight

Before starting, the operator should have:
- Destroyed the previous cluster via `hcloud server delete` × 3 (or
  equivalent) — BEFORE the fresh session starts.
- Plugged in the USB labeled `OPENBAO_A` — the refactored OpenBao role
  (Step E) expects it mounted at `/Volumes/OPENBAO_A/`. Confirm with:
  ```bash
  ls /Volumes/OPENBAO_A/   # USB has been verified mounted, ExFAT, 59 GiB free
  ```
- Confirmed Mac-side state intact:
  - `~/.config/hcloud/cli.toml`, `~/.config/cf/dns.txt`,
    `~/.config/ts/authkey.txt`, `~/.config/ntfy/alertmanager-url.txt`,
    `~/.config/healthchecks/watchdog-url.txt`
  - `~/.ssh/id_ed25519_k3s_hetzner{,.pub}`
  - `<secure-store>/openbao-breakglass/hetzner-lab/` exists
    (JuiceFS-backed — shares 1, 2 will be written here)

### D.1 Provision fresh nodes

```bash
cd <repos>/dmf-env
bin/provision-nodes.sh
```

3 new CAX21 Hosts, private net, floating IP, cloud-init seeds `k3s-admin`.
Idempotent on re-runs if the SSH key + network + floating IP already exist.

### D.2 Run the full stack via site.yml

```bash
bin/run-playbook.sh ../dmf-infra/k3s-lab-bootstrap/site.yml
# wrapper from Step A logs to /tmp/dmf-playbook-logs/site-<timestamp>.log
```

Monitor progress with the Step A helper:
```bash
bin/monitor-playbook.sh /tmp/dmf-playbook-logs/site-<timestamp>.log
```

Target: one continuous unattended run from Layer 2 through lifecycle-operate
verify (verify stubs will no-op with a visible STUB message). Time it
end-to-end.

### D.3 Troubleshoot policy

If a layer/vertical fails, **do not improvise** fixes. Stop, document, decide:
- Minor data/credentials glitch → fix and resume from the failing layer/vertical.
- Role bug → commit the fix to the appropriate repo, re-run from that layer/vertical.
- Systemic bug that affects multiple layers → abort, fix, restart from
  Layer 2 — Host Platform (yes, destroy and re-provision).

Every fix must go through the commit path — no hot-patches to live files
that don't end up in a push.

### D.4 Post-run verification

After `site.yml` reports clean:
- All 3 Hosts `Ready`.
- Hetzner LB `dmf-traefik` healthy.
- Wildcard `*.dmf.example.com` has 3 A records = tailnet IPs of the new Hosts.
- `cluster-tls` Certificate Ready.
- OpenBao unsealed — verify share locations:
  - `<secure-store>/openbao-breakglass/hetzner-lab/share-{1,2}.json` exist
  - `security find-generic-password -s openbao-breakglass-share-3 -a share` returns
  - `/Volumes/OPENBAO_A/share-{4,5}.json` exist
  - `~/secure/openbao-breakglass/hetzner-lab/openbao-keys-automation.json` (3 shares + root token for auto-unseal)
- Alertmanager Watchdog ping visible on healthchecks.io.
- Authentik reachable, break-glass admin login works via API.

### D.5 Document the drill

Create `<note-store>/Projects/DMF DR Drill Report 2026-04-22.md` with:
- Start time, end time, total wall-clock.
- Per-layer / per-vertical timings.
- Any failures + resolutions.
- Final verdict: **green** (zero manual intervention), **yellow** (1–2
  small fixes), **red** (systemic issues to address before next drill).

### D.6 Clean up old artifacts

Once D.5 is green:
```bash
# Old combined Shamir file — dead artifact now
shred -u ~/secure/openbao-breakglass/hetzner-lab/openbao-keys.json
```
Also delete from any Time Machine snapshots you can reach (`tmutil`
delete-snapshot-volume, or just wait for rotation).

### D.7 Commit + push (if any fixes landed mid-drill)

Branch + commit per the specific bugs found. If zero bugs, no commit
needed — the DR Drill Report captures the result.

(Step D = lifecycle-provision end-to-end + lifecycle-operate verify.)

---

## Step E — OpenBao role writes Shamir shares to 5 locations at init

**Estimate:** 1.5–2 hours.
**Touches:** `roles/stack/operator/openbao/` (tasks + defaults),
`dmf-env/inventories/hetzner-arm/group_vars/all/openbao.yml`.
**Cluster impact:** none at code-land time. Applied at Step D when the
new cluster's OpenBao is initialized for the first time.

### E.1 Design

No migration from a combined file. The role's init path writes the 5
shares to their final destinations directly, and also writes an
**automation** copy for unattended unseal on pod restart. The 5
destinations are:

| Share | Destination | Delegate to |
|-------|-------------|-------------|
| 1 | `<secure-store>/openbao-breakglass/hetzner-lab/share-1.json` | localhost |
| 2 | `<secure-store>/openbao-breakglass/hetzner-lab/share-2.json` | localhost |
| 3 | macOS Keychain `openbao-breakglass-share-3` | localhost (`security add-generic-password`) |
| 4 | `/Volumes/OPENBAO_A/share-4.json` | localhost |
| 5 | `/Volumes/OPENBAO_A/share-5.json` | localhost |

**Automation file** (separate; holds a quorum of 3 for auto-unseal):
`~/secure/openbao-breakglass/hetzner-lab/openbao-keys-automation.json`
Content: `{"unseal_keys": [share1, share2, share3], "root_token": "<tok>", "_notes": "..."}`
Mode 0600. This file is what `openbao_key_path` in inventory points at.

### E.2 Role change — new tasks block after `bao operator init`

Add to `roles/stack/operator/openbao/tasks/main.yml` (location: right
after the existing Shamir init parse task, guarded by the same
`when: _init_status.not_initialized | bool` condition):

```yaml
# Preflight: USB must be mounted before we can write shares 4+5.
- name: Assert OPENBAO_A USB is mounted (holds recovery shares 4+5)
  ansible.builtin.stat:
    path: /Volumes/OPENBAO_A
  register: _usb_stat
  delegate_to: localhost
  become: false

- name: Fail if OPENBAO_A USB is missing
  ansible.builtin.assert:
    that: _usb_stat.stat.exists and _usb_stat.stat.isdir
    fail_msg: >-
      USB 'OPENBAO_A' is not mounted at /Volumes/OPENBAO_A. Plug it in
      and re-run. OpenBao init writes shares 4 and 5 to this USB.

- name: Assert JuiceFS mount is available (holds recovery shares 1+2)
  ansible.builtin.stat:
    path: <volumes>/secure
  register: _juicefs_stat
  delegate_to: localhost
  become: false

- name: Fail if JuiceFS <volumes>/secure is missing
  ansible.builtin.assert:
    that: _juicefs_stat.stat.exists and _juicefs_stat.stat.isdir
    fail_msg: >-
      JuiceFS mount <volumes>/secure is not available. Mount the
      share first — OpenBao init writes shares 1 and 2 there.

- name: Ensure hetzner-lab break-glass directory on JuiceFS exists
  ansible.builtin.file:
    path: <secure-store>/openbao-breakglass/hetzner-lab
    state: directory
    mode: "0700"
  delegate_to: localhost
  become: false

- name: Write share 1 to JuiceFS
  ansible.builtin.copy:
    dest: <secure-store>/openbao-breakglass/hetzner-lab/share-1.json
    mode: "0600"
    content: "{{ {
        'share_index': 1,
        'key': _openbao_init.unseal_keys_b64[0],
        '_notes': 'OpenBao Shamir share 1 of 5. Need any 3 of 5 to unseal.
                   Other shares: share 2 here on JuiceFS, share 3 in macOS
                   Keychain (service: openbao-breakglass-share-3), shares
                   4+5 on USB OPENBAO_A. See Breakglass Runbook for DR.'
      } | to_nice_json }}"
  delegate_to: localhost
  become: false
  no_log: true

- name: Write share 2 to JuiceFS
  ansible.builtin.copy:
    dest: <secure-store>/openbao-breakglass/hetzner-lab/share-2.json
    mode: "0600"
    content: "{{ {
        'share_index': 2,
        'key': _openbao_init.unseal_keys_b64[1],
        '_notes': 'See share-1.json for DR context.'
      } | to_nice_json }}"
  delegate_to: localhost
  become: false
  no_log: true

- name: Write share 3 to macOS Keychain
  ansible.builtin.command:
    argv:
      - security
      - add-generic-password
      - -s
      - openbao-breakglass-share-3
      - -a
      - share
      - -w
      - "{{ _openbao_init.unseal_keys_b64[2] }}"
      - -U  # update if exists
  delegate_to: localhost
  become: false
  no_log: true

- name: Write share 4 to USB OPENBAO_A
  ansible.builtin.copy:
    dest: /Volumes/OPENBAO_A/share-4.json
    mode: "0600"
    content: "{{ {
        'share_index': 4,
        'key': _openbao_init.unseal_keys_b64[3],
        '_notes': 'Share 4 of 5. Keep USB unplugged except during
                   ceremony. See Breakglass Runbook.'
      } | to_nice_json }}"
  delegate_to: localhost
  become: false
  no_log: true

- name: Write share 5 to USB OPENBAO_A
  ansible.builtin.copy:
    dest: /Volumes/OPENBAO_A/share-5.json
    mode: "0600"
    content: "{{ {
        'share_index': 5,
        'key': _openbao_init.unseal_keys_b64[4],
        '_notes': 'Share 5 of 5.'
      } | to_nice_json }}"
  delegate_to: localhost
  become: false
  no_log: true

- name: Write automation file (shares 1+2+3 plus root token)
  ansible.builtin.copy:
    dest: "{{ openbao_key_path }}.json"
    mode: "0600"
    content: "{{ {
        'unseal_keys_b64': _openbao_init.unseal_keys_b64[0:3],
        'root_token': _openbao_init.root_token,
        '_notes': 'Automation copy. Holds a quorum of 3 Shamir shares for
                   unattended unseal. If this file is lost, reassemble from
                   any 3 of: JuiceFS share-1, JuiceFS share-2, Keychain
                   share-3, USB share-4, USB share-5.'
      } | to_nice_json }}"
  delegate_to: localhost
  become: false
  no_log: true
```

### E.3 Role change — unseal path stays unchanged

The existing "Preload root token from existing break-glass JSON (rerun
path)" and "Unseal OpenBao — share N" tasks already read from
`{{ openbao_key_path }}.json`. They expect that file to contain the shares
it uses. Because the automation file now contains exactly 3 shares (which
is the threshold), the existing loop over `_init_result.unseal_keys_b64`
still works — but reads from the slurped automation file on reruns. No
change needed.

### E.4 Defaults + inventory

`roles/stack/operator/openbao/defaults/main.yml` — no functional change;
`openbao_key_path: /tmp/openbao-keys` stays as the development default.

`dmf-env/inventories/hetzner-arm/group_vars/all/openbao.yml` —
already set from the last rebuild:
```yaml
openbao_key_path: "{{ lookup('env', 'HOME') }}/secure/openbao-breakglass/hetzner-lab/openbao-keys-automation"
```
Keep it. The role will now ALSO write the 5 external share files on init.

### E.5 DR runbook

Create `<note-store>/System/Breakglass Runbook 2026-04-22.md`:
- Normal operation: pod restart → role's rerun path reads the automation
  file and unseals. Automatic.
- Automation file lost (fresh Mac, corrupted disk): reassemble any 3 of
  the 5 shares manually and run `bao operator unseal` three times. Specific
  commands for each medium:
  - JuiceFS: `jq -r .key <secure-store>/openbao-breakglass/hetzner-lab/share-1.json`
  - Keychain: `security find-generic-password -s openbao-breakglass-share-3 -a share -w`
  - USB: `jq -r .key /Volumes/OPENBAO_A/share-4.json` (after mounting)
- Total operator Mac loss: reassemble the 3 lowest-friction shares
  (JuiceFS 1 + JuiceFS 2 + USB 4 is the typical quorum on a replacement Mac).

### E.6 Commit + push

Single commit:
```
feat(openbao): write Shamir shares to 5 separate custody locations at init

JuiceFS (1,2), macOS Keychain (3), USB OPENBAO_A (4,5). Automation file
retains a quorum of 3 shares for unattended unseal. Fail-fast if JuiceFS
or USB is not mounted at init time. Closes pre-rebuild action item #1.
```

---

## Step ordering (updated for destroy-then-rebuild)

1. **A — wrapper + monitor** (code only)
2. **B — renumbering + site.yml + stubs** (code only)
3. **C — preflights** (code only)
4. **E — OpenBao role writes 5-location Shamir split at init** (code only)
5. **D — full DR-drill rebuild via site.yml** (destructive; validates A+B+C+E)

A/B/C/E can be done in any order but must all land before D. D is the
capstone and ONLY runs after the previous cluster has been destroyed and
USB `OPENBAO_A` is plugged in.

---

## What NOT to do in this session

- Do not run `32-librenms.yml` or anything past 31 against the cluster
  (those playbooks still exist in the 32–42 numbering today; after Step B
  they become `vertical-monitoring/140-librenms.yml`,
  `playbooks/640-awx.yml`, and `playbooks/691-/692-/693-` integration glue).
  They are out of scope for this session until site.yml can carry them —
  but this session focuses on Layer 2 through vertical-security
  (authentik) only until the drill is green.
- Do not touch the live cluster during A/B/C/E — those are code-only.
- Do not start Step F (provider-token migration from `~/.config/*.txt` to
  in-cluster OpenBao). Carved off to a separate session.
- Do not skip the "push to both remotes" part of any commit.
- Do not run D before the operator has destroyed the old cluster AND
  confirmed USB `OPENBAO_A` is mounted at `/Volumes/OPENBAO_A/`.

---

## Exit criteria for the session

- A, B, C, E committed and pushed to both remotes.
- Old Hetzner cluster destroyed by operator.
- `bin/provision-nodes.sh` succeeds against fresh Hetzner project.
- `bin/run-playbook.sh site.yml` runs end-to-end unattended (Layer 2
  through lifecycle-operate verify inclusive) in under 90 minutes.
- 5 Shamir shares present at their 5 destinations; automation file
  present with 3-share quorum.
- `<note-store>/Projects/DMF DR Drill Report 2026-04-22.md` written with
  timings + verdict.
- Old combined `~/secure/openbao-breakglass/hetzner-lab/openbao-keys.json`
  `shred`'d.
- `DMF Improvement Run Plan` (this doc) — add a final §7 "Execution log"
  with what was done and what time it took, for the next session's
  sizing calibration.
