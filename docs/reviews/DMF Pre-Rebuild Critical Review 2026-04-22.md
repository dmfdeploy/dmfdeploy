# DMF Pre-Rebuild Critical Review — 2026-04-22

> **Vocabulary updated 2026-04-25** — playbook numbering and Phase / Layer
> language in this doc references the pre-EBU naming. Canonical layer /
> vertical / lifecycle map is `DMF EBU Mapping (2026-04-25).md`.

**Status:** Review complete; action items pending.
**Context:** Hetzner cluster was deleted. Before re-provisioning, a critical
review was requested of the playbook sequencing, credential staging, the
Tailscale + socat private-lane approach, and anything else a senior reviewer
would flag. This doc is the resulting punch list.

**Related docs:**
- `DMF Platform Plan.md` — canonical architecture (stale wrt the Tailscale pivot)
- `DMF Session Handoff 2026-04-20.md` — pre-pivot handoff; phase-1 details superseded
- `DMF Open Questions 2026-04-20.md` — baseline live-state findings
- `System/Lessons.md` — known-gotcha log (all 8 lessons verified in-tree except the cert-readiness wait, now fixed in commit `2fb1044`)

---

## 1. Playbook sequencing

### 1.1 Private lane has a single-node SPOF
`playbooks/17-tailscale.yml` runs on `k3s_control[0]` only. socat on
`k3s-node-01` is the sole private-ingress forwarder. If that node is drained
or lost, every admin UI becomes unreachable — including the one an operator
would use to diagnose the outage. On a 3-node "HA" cluster this is a glaring
asymmetry. Options: run Tailscale+socat on all three nodes with healthchecked
failover (keepalived, round-robin DNS in Headscale), or document this as
accepted risk with a runbook for "node-01 is down, here's how to recover the
private lane."

### 1.2 No orchestrator
28 manually-sequenced playbooks. No `site.yml`, no tag-based composition, no
dependency metadata. On a fresh rebuild this is a 28-step ritual where a
single skip or wrong-order invocation breaks everything silently. A phased
wrapper (e.g. `00-baseline.yml` through `99-integrate.yml`) with fail-fast
gates between phases is the standard fix.

### 1.3 Collision-numbered playbooks
`15-ingress`, `15-ingress-private`, `15-metallb` share a numeric prefix. Their
effective order depends on shell glob sort rules rather than intent. Rename
to `15a`, `15b`, `15c` or restructure into separate phases.

### 1.4 `18-post-bootstrap-verify` is misnamed
It runs after k3s is up, not after the full stack. "Bootstrap" in doctrine
means through monitoring + apps. Either rename (`18-k3s-verify`) or split
into `18-k3s-verify` and a later `50-stack-verify`.

### 1.5 No idempotency proof
Every playbook claims idempotency, but there is no CI that re-runs them on an
existing cluster to verify. Authentik blueprint re-apply, OpenBao init guard,
ESO AppRole re-seed — any of these could silently diverge on a second run.
The recent `d41abd8` "bootstrap stability" commit suggests the last dry-run
revealed problems; no evidence the full suite has been re-run cleanly
end-to-end since.

### 1.6 OIDC redirect URIs baked at Authentik deploy time
If a later app playbook changes its FQDN, the Authentik blueprint does not
know. Re-running `29-authentik.yml` may or may not upsert existing providers
cleanly. Not tested.

---

## 2. Credential staging

### 2.1 Shamir is defeated on disk
`~/secure/openbao-breakglass/hetzner-lab/openbao-keys.json` contains the root
token, **all five unseal shares**, ESO AppRole role_id+secret_id, and
ops-admin userpass. The whole point of 5-of-3 Shamir is that no single
location holds enough material to unseal. Storing all five shares in one JSON
on one laptop makes Shamir pure theatre — might as well use a single key.
Minimum fix: after bootstrap, split shares across locations (paper/safe/
YubiKey/second operator) and have the role delete N-3 of them from the JSON.

### 2.2 ESO AppRole secret_id has TTL=0 (never expires)
Persistent god-mode credential. If that JSON ever leaks, forever-cluster-wide
read access. Should be a finite TTL with a rotation runbook or AWX-driven
re-auth.

### 2.3 Root token not disposed
Default `openbao_dispose_root_token: false`. Justification is "app-admin-
facts re-runs need it." That's an auth-scope problem, not a reason to keep
root. Fix: mint a scoped `app-admin-writer` policy (write to
`secret/apps/*/admin` only), persist a long-lived token with that policy,
let the root token get disposed as it should be. Today the platform has a
permanently-valid root credential on the operator laptop — no reviewer will
sign off on that.

### 2.4 Plaintext dotfiles for bootstrap bearer tokens
`~/.config/cf/dns.txt` (Cloudflare DNS) and `~/.config/ts/authkey.txt`
(Tailscale) are plaintext files on the operator workstation. No encryption
at rest, no audit, no rotation. macOS Keychain or `age`-encrypted files are
trivial alternatives. Currently: stolen laptop = Cloudflare DNS takeover +
cluster tailnet join.

### 2.5 `--authkey=<plaintext>` on the Tailscale command line
`roles/base/tailscale/tasks/main.yml:77, 84`. Visible in `ps`, in Ansible
logs at higher verbosity, and in cached facts. Tailscale supports
`--authkey-file`; switch to it.

### 2.6 App admin passwords concentrate in one file
Authentik, NetBox, Forgejo, AWX generated admins all end up in the single
`openbao-keys.json`. Single backup = single risk surface. No rotation path,
no MFA. Doctrine says "dormant 99% of the time" but dormancy is not
security.

### 2.7 Implicit operator-workstation contract
`bin/export-openbao-vars.sh` is the undocumented handshake between operator
workstation prep and the playbooks. Missing prereqs fail late.

---

## 3. Tailscale + socat

### 3.1 socat is the wrong shape for L7 ingress forwarding
It's a user-space pipe: no healthcheck, no graceful drain, no concurrency
limit, unlimited `fork`, no metrics. A single slowloris client could explode
the process table. Works in a lab; any reviewer will flag it.

### 3.2 Tailscale has a first-party answer not in use
`tailscale serve --bg --https=443 tcp://localhost:30443` is precisely this
use case, handled by tailscaled with healthchecks and cert management. The
commit message for the socat switch says "avoid conflicts with kube-proxy's
nat/PREROUTING chain" — that explains why iptables DNAT was dropped, but
does not explain why `tailscale serve` was rejected over socat. Revisit;
switch cost is low.

### 3.3 Hardcoded socat fallback IP `100.64.0.13`
`roles/base/tailscale/tasks/main.yml:145`. If `tailscale_ip` fact is ever
unset, socat binds to an IP that probably isn't this host. Not a fallback;
a footgun. Should fail hard instead.

### 3.4 Headscale dependency not acknowledged
Using a self-hosted control plane (`tailscale_headscale_url`). If Headscale
runs on the homelab, and the homelab is down, a new Hetzner cluster cannot
be brought up. Circular dependency worth surfacing explicitly.

### 3.5 No Tailscale ACLs
Default-allow means any tailnet peer reaches `:443` on the k3s node, plus
potentially `:22` via Tailscale SSH. Need tag-based ACLs:
`tag:k3s-admin → tag:k3s-lab:443`, explicit deny on `:22` (operators SSH via
the bastion's public IP, not through Tailscale).

### 3.6 Verify `--ssh=false`
If Tailscale SSH is enabled, it bypasses sshd hardening (fail2ban, key-only,
etc.). Not passed either way in the current `up` command.

### 3.7 `--accept-dns=false` is correct
Good — MagicDNS disabled, one less thing to debug.

---

## 4. Other items a senior reviewer would catch

### 4.1 No alerting rules, no receivers
kube-prometheus-stack is deployed, but no `PrometheusRule` CRDs or
Alertmanager receiver config found. Auto-renewed cert failure at day 89
goes unnoticed until day 91.

### 4.2 No backup target
Longhorn is up but no `BackupTarget` configured in role defaults. Postgres
for NetBox/AWX/Authentik — what backs them up? Day-2 recovery story is
"reinstall and lose state."

### 4.3 DR drill does not exist
Decision log treats "restore central services from backup to fresh cluster"
as a Phase 5 goal. Until that works, there is an install process, not a
disaster recovery process.

### 4.4 No `--check --diff` path
Shell/command tasks (`bao kv put`, `tailscale up`, `nft`, `socat`) bypass
Ansible check mode. Can't dry-run the risky parts.

### 4.5 Two TLSStore default certs?
Public Traefik's `TLSStore/default` references `cluster-tls` in
`kube-system`. Private Traefik (`traefik-private` namespace) needs its own
copy of the wildcard secret — cert-manager issues to one namespace. The
audit hinted at secret replication or duplicate Certificate; which was
chosen? If duplicate Certificate, the wildcard issues twice per renewal
cycle and double-counts against LE rate limits.

### 4.6 cert-manager HTTP-01 issuer naming is misleading
Both DNS-01 and HTTP-01 issuers end up named `letsencrypt-http` (from the
`cert_manager_cluster_issuer` default). A DNS-01 issuer called "-http" is
confusing during incidents.

### 4.7 Redundant SANs
Inventory declares `[*.dmf.example.com, dmf.example.com, auth.*, forgejo.*]`.
Wildcard covers auth+forgejo; listing them explicitly is noise and may
re-trigger issuance on SAN list churn.

### 4.8 No fail-fast precondition tasks
No playbook asserts `vault_cloudflare_dns_token` or `tailscale_authkey` are
set with non-empty values before using them. First failure will be mid-role
when a secret creation task emits an empty string.

### 4.9 SSH bastion is a shared public IP
`<control-node-public-ip>` is also node-01 — same SPOF as socat. If node-01 is down, SSH
is down too. Lab-appropriate, but should be documented.

---

## 5. Pre-provisioning action list

### Must-fix before rebuild
1. Add fail-fast precondition tasks asserting `vault_cloudflare_dns_token`
   and `tailscale_authkey` are defined and non-empty at the start of their
   consuming playbooks.
2. Switch `--authkey=…` to `--authkey-file=…` in the Tailscale role.
3. Replace the hardcoded socat fallback IP (`100.64.0.13`) with a hard fail.

### Should-fix before rebuild (each ~30 min)
4. Prototype `tailscale serve` as a socat replacement; if it works, switch.
5. Run Tailscale on all three nodes, not just `k3s_control[0]`.
6. Write an Alertmanager receiver config + a minimum alert set
   (Certificate-not-Ready, node-down, pod-crashloop) into the monitoring
   role.

### Can-defer — document as known debt
7. Shamir share splitting (post-bootstrap operator ritual).
8. Root token disposal + scoped `app-admin-writer` policy.
9. Tailscale ACLs.
10. `site.yml` orchestrator + playbook renumbering.
11. Authentik blueprint re-apply idempotency test.
12. Longhorn `BackupTarget` + postgres backup jobs.
13. DR drill against a fresh cluster.
14. Move Cloudflare DNS token + Tailscale authkey into macOS Keychain or
    an `age`-encrypted store.

---

## 6. Fixes already landed during this review cycle

- **cert-manager Certificate readiness wait** —
  commit `2fb1044` on `main` adds a `kubernetes.core.k8s_info` poll loop
  between Certificate creation and TLSStore creation in
  `roles/base/cert-manager/tasks/main.yml`. Prevents the TLSStore pointing
  at a secret that does not yet exist and the next app playbook's HTTPS
  endpoints failing handshakes until ACME completes. Defaults: 30 retries
  × 10 s = 5 min max wait.

---

## Appendix A — Alerting: bootstrap-time vs steady-state

Two different problems; easy to conflate.

### Steady-state (what §4.1 is actually about)

In-cluster Prometheus is the correct answer once the cluster is up, even
for alerts *about* cluster health. Prometheus scraping its own stack is
fine — if a subset fails, Prometheus on the healthy subset still catches
and alerts. The one thing in-cluster Prometheus cannot catch is
"Prometheus itself is dead, and therefore silent."

**Fix:** add an external dead-man's switch. A tiny external job
(healthchecks.io, Grafana Cloud synthetic check, cron on the homelab or
bastion) that pings Prometheus `/-/ready` and pages if it stops
answering. Cert-expiry at day 89 works fine with in-cluster Prometheus
because the Prometheus pod does not care about the cert's state — it
just scrapes cert-manager's metrics and fires the rule.

### Bootstrap-time (playbooks 00 → 24)

Prometheus does not exist until playbook `25-prometheus.yml`. The
bring-up cannot be alerted on by an in-cluster tool. Substitutes:

1. **Ansible fail-fast assertions** — preconditions, `assert` modules,
   `until`/`retries` loops that fail loud. Synchronous bootstrap
   failures, not alerts — the operator sees them in terminal. §5.1 of
   this review adds this for the two most dangerous missing values.
2. **Post-bootstrap verification playbooks** — `18-post-bootstrap-verify`
   now, and a later `50-stack-verify`, asserting invariants and failing
   the run if anything is wrong. Gated assertions, not alerts.
3. **External synthetic probes** (cheap, worthwhile) — Grafana Cloud
   free tier, healthchecks.io, or self-hosted probe on the homelab.
   Point them at `https://auth.dmf.example.com`,
   `https://dmf.example.com/`, etc. the moment DNS is live. These cover
   *both* bootstrap ("has the LE cert been issued yet?") and steady
   state, and simultaneously act as the dead-man's switch for in-cluster
   Prometheus.

**Rule of thumb:** alert rules live in-cluster; one external probe lives
outside the cluster as the backstop. During bootstrap, Ansible
assertions replace the in-cluster layer until Prometheus is up.

---

## Appendix B — Ephemeral device-local wizard: the right shape and the hard parts

The user's proposed direction (device-local wizard that collects
customizations + API tokens and hands them to the playbooks) is correct
in spirit, but the hard problem is not the UI.

### What is right about the shape

- **On-device is correct.** A central web service collecting customer
  API tokens is a honeypot; operator-device-local avoids that entirely
  and matches the flypack trust model.
- **"Ephemeral process, durable output"** is the right interpretation
  of *ephemeral*. The UI is short-lived; the manifest, inventory, and
  break-glass JSON it produces are durable.
- **Separating manifest (non-secret, git-committed) from secrets
  (keystore / OpenBao)** is already doctrine — see
  `DMF Deployment Workflow and Manifest Plan.md` §3.3.

### The hard problem

Key custody, not UI. The wizard solves *brain → first use*; it does not
solve *where do tokens live for re-runs?* Today's answer — plaintext
dotfiles in `~/.config/` — is exactly review item §2.4. The wizard must
also choose a durable secret store, and that choice is harder than the
form.

### Three layers that must be named

1. **Manifest store** — YAML file committed to `dmf-env`
   (`manifests/<env>.yaml`). Diffable, reviewable, re-runnable. Contains
   secret *references*, never values.
2. **Bootstrap-only secret store** — OS keystore (macOS Keychain,
   libsecret on Linux), 1Password CLI, or an `age`-encrypted file with a
   hardware key. Tokens live here from wizard-time until OpenBao is up.
   Fetched by the playbooks via a lookup helper, never dumped to
   `~/.config`.
3. **Steady-state secret store** — OpenBao. A post-bootstrap migration
   copies the bootstrap tokens from OS keystore into OpenBao so
   subsequent re-runs work without the OS keystore.

### Alternatives worth knowing

- **1Password CLI** — `op read "op://vault/cloudflare/dns-token"` with
  an Ansible lookup plugin: ~80 % of the wizard's value (no-plaintext-
  on-disk, auditable, cross-machine) for roughly zero build effort.
  Good *now* as an interim while the wizard is still months out.
- **SOPS + `age`** — encrypt the manifest inline, decrypt at deploy
  time with a YubiKey-backed age identity. Git-native, no UI. Good for
  repeat deploys, bad for first-time collection UX.
- **Devcontainer / Nix flake** — declarative operator prereqs. Solves
  reproducibility, not secret collection.

### Recommendation

- **Now (pre-rebuild):** adopt 1Password CLI (or age-encrypted file) as
  the immediate replacement for `~/.config/cf/dns.txt` and
  `~/.config/ts/authkey.txt`. ~1 hour of work, closes review §2.4.
- **Medium-term:** build the wizard as a subcommand or sibling of
  `dmf-cms` (FastAPI + HTMX — Platform Plan §8b already chose that
  stack). Output: manifest to `dmf-env/manifests/`, secrets to OS
  keystore, a one-shot Ansible runner invocation. This is Phases A–D of
  the Deployment Workflow plan.
- **Long-term:** same UI becomes part of the operator CMS, so the
  operator surface is consistent between day-0 deploy and day-2 ops.

The reason not to start with the wizard is that the secret-custody
model is the hard, specifiable-in-advance part. Get 1Password + lookups
working first; then the wizard is mostly form UI and manifest rendering
around an already-proven secret layer.
