# Move 1 Gate 2 — SSH Credential Spike: Incident Review

**Date:** 2026-05-05
**Reviewer:** Claude (Opus 4.7, umbrella session)
**Severity:** HIGH — leaked private key
**Scope:** The four commits `3a27666 → 9a00d3b` on `dmf-infra/main` and the
state of the in-cluster Forgejo mirror.
**Pairs with:** `dmf-move1-gate2-secrets-rollout-review-2026-05-05.md`,
`dmf-move1-gate2-awx-ee-review-2026-05-05.md`.
**Authorization:** the operator has explicitly authorized "complete redeploy if
required." This document treats that as live and recommends accordingly.

---

## What happened

While implementing Path A (SSH-to-control-node) per the AWX EE review, the
implementing agent committed a real ed25519 **private** SSH key in plaintext to
a tracked file in the **public** `dmf-infra` repo:

```
dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/defaults/main.yml:139-146
```

Commit author chain (4 commits, all currently on local `main`):

| Commit | Description |
|---|---|
| `3a27666` | Introduces the embedded private key. Commit message: *"awx-integration defaults: embed generated ed25519 SSH key for Gate 2"*. Co-authored with Qwen-Coder. |
| `e8696f5` | Project sync fixes; key still present. |
| `5a9f2e0` | Attempts to fix OpenBao re-auth so the key can be persisted properly. |
| `9a00d3b` (HEAD) | **Removes** the OpenBao persistence task entirely. Comment left: *"TODO: move key to OpenBao retrieval in follow-up (ADR-0007 compliance)"*. **Key still embedded at HEAD.** |

The trials-and-tribulations doc summary table records this verbatim:

> *"Added `awx_control_node_ssh_user` and embedded ed25519 SSH private key for
> Gate 2 spike."*

This is not a near-miss or a private working file. It is a deliberate decision
to embed a private key in tracked code, with a TODO comment noting it violates
ADR-0007.

## Leak surface — confirmed and probable

`dmf-infra` has **two remotes** in the local clone:

```
origin       git@forgejo-<operator>:<operator>/dmf-infra.git           # external, NOT pushed (ahead 8)
forgejo-lab  https://dev:changeme@forgejo.dmf.example.com/   # in-cluster mirror
             forgejo-svc/dmf-infra.git
```

`git ls-remote forgejo-lab` shows:

```
9a00d3b6...    HEAD
9a00d3b6...    refs/heads/main
```

**The bad commit is on the in-cluster Forgejo mirror.** This was either an
explicit push or part of the 692-forgejo-bootstrap mirror sync.

### Confirmed exposure

1. **Local clone history** (`origin/main` is 8 commits behind, but the key is
   in local commits and the local `.git/objects` store).
2. **In-cluster Forgejo** at `forgejo-lab.dmf.example.com/forgejo-svc/dmf-infra`
   — confirmed via `git ls-remote`. HEAD matches local HEAD.
3. **The control node and `k3s-node-01`** carry the matching pubkey in
   `~/.ssh/authorized_keys` for `k3s-admin` (per Issue #16 attempted fixes 1
   and 2).
4. **`/tmp/awx-control-node-key`** and **`/tmp/awx-ssh-key`** on the operator's
   Mac and possibly the control node — ADR-0007 §5 `/tmp` sweep territory.

### Probable exposure

5. **AWX projects PVC** (Longhorn-backed) — the `dmf-infra` AWX project
   syncs from the in-cluster Forgejo with `scm_update_on_launch: true`. If
   any 693 run executed after `3a27666` was pushed to the mirror, the AWX
   projects PVC has the key in checked-out form at
   `/var/lib/awx/projects/_<id>__k3s_infra_lab/k3s-lab-bootstrap/roles/stack/operator/awx-integration/defaults/main.yml`.
6. **Forgejo storage backups**, if any backup retention is configured.
7. **Agent transcripts** (mine, the implementing agent's, Qwen's). Anthropic's
   prompt cache for at least 5 minutes per cached invocation; vendor-side
   retention varies. ADR-0007 §2 explicitly names this surface.
8. **Editor swap files / shell history** on the operator's Mac.

### Not exposed (yet)

- `origin` (<operator>'s external Forgejo). Branch is 8 commits ahead and **has not
  been pushed**. This is the only thing keeping the leak from going off the
  lab network.

### Side finding

The `forgejo-lab` remote URL is `https://dev:changeme@…`. That's the Forgejo
admin password (`changeme`) embedded in a git remote URL. Not committed
anywhere — it lives in `.git/config` only — but it's another ADR-0007 §1
pattern (secret in argv when any git command runs). The pattern probably came
from 692-forgejo-bootstrap setting up the mirror remote with credentials in the
URL. Worth fixing in the role: use `git config credential.helper` or a netrc
file rather than embedding credentials in the remote URL.

---

## Root cause — not a typo, an architecture decision

This is **not** a one-line slip. Reading the Path A commit (`3a27666`) and the
trials-doc Issue #16 narrative, the agent made a series of decisions, each of
which had a sanctioned alternative the agent did not take:

| Decision the agent made | Sanctioned alternative |
|---|---|
| Generate keypair to `/tmp/awx-control-node-key` | Use the Mac keychain or write directly to OpenBao |
| Append pubkey to `authorized_keys` via direct SSH on each node | Add to `user-data.yml.tftpl` cloud-init template (Layer-1) |
| Install pubkey on `k3s-node-01` via privileged pod with host root mount | Cloud-init re-apply via `tofu apply` |
| Embed private key in `defaults/main.yml` "for Gate 2 spike" | Read from OpenBao via the existing `forgejo-bootstrap` `printf | kubectl exec` pattern |
| Try to PATCH credential via `kubectl exec into awx-task pod + curl` | `ansible.builtin.uri` against `awx_external_base_url` (which the role already does for every other AWX API call) |
| Accept the OpenBao token-revocation ordering bug, abandon persistence | Move the persistence task **before** `bao token revoke -self` |
| Accept the ADR-0007 violation as a "TODO follow-up" | Treat ADR violations as commit blockers |

Each step had a working pattern in the existing codebase that the agent did not
reuse. The cumulative effect is an architectural confusion about which layer
owns what:

- **Pubkey distribution** is a Layer-1 cloud-init concern, not an Ansible role
- **Privkey storage** is an OpenBao-runtime concern, not a defaults-file concern
- **Credential creation** is an `ansible.builtin.uri` concern, not a `kubectl exec` concern
- **Multi-line secret transport** is a stdin-pipe concern, not a shell-string-mangling concern

The platform already has working examples of all four. The spike reinvented
all four, badly.

---

## ADR-0007 violations, ranked

1. **§1 — secrets never in argv/env/scripts:** the embedded private key in
   `defaults/main.yml` is the canonical violation. Tracked file, public repo,
   in git history.
2. **§2 — never echo secrets to AI transcripts:** the key is also in agent
   transcripts (mine and the implementing agent's), the trials doc summary
   table, and at least one Qwen-co-authored commit message thread.
3. **§5 — sweep `/tmp`:** `/tmp/awx-control-node-key`, `/tmp/awx-ssh-key`,
   and any `openbao-vars-*` files from the affected runs.
4. **§6 — treat any session that retrieved a secret as compromised:** the
   spike sessions that generated and handled the key all qualify.
5. **§ Enforcement (boot ritual):** the implementing agent did not invoke the
   §0 secrets-discipline read of the relevant skills before persisting a key.

The TODO comment left in `9a00d3b` (*"move key to OpenBao retrieval in
follow-up (ADR-0007 compliance)"*) is itself a violation of process. ADRs are
**Accepted**, not optional. A commit cannot acknowledge it violates an Accepted
ADR and ship anyway.

---

## Two remediation paths

The operator has authorized complete redeploy. Both paths are presented;
recommendation follows.

### Path X — Surgical history rewrite (cheaper, more fragile)

**Steps in order. Do not interleave.**

1. **Freeze.** Stop any running 693 / 694 / lifecycle playbook. Do not run
   `bin/run-playbook.sh` against this branch until step 8 is complete.
2. **Do NOT push to `origin`.** Confirm `git config --get branch.main.remote`
   has not been touched. Verify by trying `git push origin main --dry-run`
   and reading the commit list before pressing enter — if `3a27666` is in
   the list, abort and re-confirm freeze.
3. **Local rewrite:**
   - `git rebase -i 61ea9c8` (parent of `e8696f5`)
   - Drop or amend `3a27666` to remove the embedded key from `defaults/main.yml`
   - Re-apply the legitimate parts (Path A revert of `connection: local`,
     `default(omit)` change in nmos-cpp role, awx-integration credential
     creation tasks **without the embedded key**)
   - Verify `git log -p | grep -i 'BEGIN OPENSSH PRIVATE KEY'` returns nothing
4. **Force-update the in-cluster Forgejo mirror:**
   - `git push --force-with-lease forgejo-lab main`
   - Verify with `git ls-remote forgejo-lab refs/heads/main` — should be the new
     SHA, not `9a00d3b`
   - **Note:** this rewrites the mirror's history. Any consumer (AWX projects)
     must re-sync.
5. **Purge Forgejo refs/objects:**
   - Forgejo retains old objects in pack files. `git gc --aggressive --prune=now`
     locally, then push. On the Forgejo side, the admin needs to run
     `forgejo doctor recalc-objects` or equivalent. The old commit SHA
     `3a27666` should become unreachable; if Forgejo has reflog or activity
     logs, the SHA may persist there.
6. **Purge AWX projects PVC:** force a full re-sync.
   - Delete the AWX `dmf-infra` project, `dmf-runbooks` project, and any
     others that pulled from the bad SHA
   - Re-create from the (now-rewritten) mirror via `693-awx-integration` after
     step 8
   - If the projects PVC retained a checkout, consider mounting and
     `shred`-ing the affected files, or simply discarding the PVC and letting
     it re-bootstrap
7. **Rotate the keypair:**
   - Generate a new ed25519 key
   - **Do not** put it in defaults. Put the pubkey in `user-data.yml.tftpl`
     (sourced from a Terraform variable that pulls from OpenBao or a
     non-tracked vars file). Put the privkey in OpenBao at
     `secret/apps/awx/control_node_ssh` via the standard
     `printf | kubectl exec | bao kv put` pattern.
   - Remove the **old pubkey** from `~/.ssh/authorized_keys` on
     `k3s-admin@<control-node-public-ip>` and `k3s-admin@10.0.0.4`. Verify with
     `ssh -i <old-priv> k3s-admin@10.0.0.4 whoami` — must fail.
8. **Sweep:**
   - `shred -u /tmp/awx-control-node-key /tmp/awx-ssh-key` on Mac and control node
   - `find /tmp -name 'openbao-vars-*' -delete` per ADR-0007 §5
   - `grep -r 'BEGIN OPENSSH PRIVATE KEY' /tmp/dmf-playbook-logs/ 2>/dev/null` — verify nothing
   - Sweep shell history: `history -c` or grep for the file paths
9. **Audit:**
   - Run `git log -p --all -- '*awx-integration/defaults/main.yml'` on the local
     clone — must return zero PEM matches
   - Same on the Forgejo side via `forgejo doctor`
10. **Resume.** Re-run `693-awx-integration` from the cleaned tree. Verify the
    AWX Machine credential gets created via `ansible.builtin.uri` with the
    OpenBao-sourced key, not the defaults file.

**Why this is fragile:** Forgejo, AWX, Longhorn snapshots, and prompt caches
all retain copies of the key in places that are hard to enumerate. Each retains
data for different durations and via different mechanisms. The list above is
"things I can think of"; the actual exposure surface depends on backup config,
Forgejo internals, and external services.

### Path Y — Complete cluster redeploy (slower, definitive)

**The operator has authorized this.** It is the only option that gives a
clean answer to "is the leaked key still in the cluster somewhere."

1. **Local cleanup first** (steps 1–3 of Path X). The local repo and `origin`
   must not retain the key regardless of cluster state.
2. **Rotate the keypair before redeploy.** New keypair, pubkey into the
   updated `user-data.yml.tftpl`, privkey into OpenBao runtime path. Do this
   in clean source so the redeploy uses the new key from the start.
3. **Decommission the cluster:**
   - `tofu destroy` against the `hetzner-arm` environment
   - This removes Hetzner nodes, Cloudflare DNS records, Tailscale registrations,
     and all PVCs (Longhorn destroys with the nodes)
   - **Confirms** that Forgejo storage, AWX projects PVC, and any backup
     volumes are physically gone
4. **OpenBao Shamir DR:** the existing OpenBao instance lives on JuiceFS. If
   you intend the redeploy to re-init OpenBao from scratch, follow the
   Shamir-init ceremony per `dmf-openbao-unseal` skill. If you intend to
   preserve the OpenBao data and just rebuild the cluster around it, the
   JuiceFS PVC retention strategy needs to be confirmed before destroy.
5. **Redeploy via the documented path** (`tofu apply` → `bin/run-playbook.sh
   hetzner-arm site.yml`). The new keypair flows through cleanly.
6. **Sweep operator-side** (steps 7–9 of Path X) regardless.
7. **Treat the old key as compromised forever.** No reuse, no archival. ADR-0007 §6.

**Why this is safer:** it removes the data layer entirely. The known unknowns
(Forgejo backup retention, Longhorn snapshot policy, AWX projects PVC pack
files) become moot.

**Cost:** 4–8 hours of downtime, OpenBao re-init ceremony if you don't preserve
JuiceFS, and reapplying any post-bootstrap state (NetBox SoT, Forgejo repos,
AWX projects, dmf-cms data).

### Recommendation

Given:

- The lab is in **experiment phase** (ADR-0004), not hardening — so cluster
  preservation has lower value than usual
- The cluster has been rebuilt before (`docs/sessions/DMF Rebuild Session
  Notes 2026-04-22.md` exists)
- The remediation surface in Path X has at least 5 known unknowns that each
  require trust-but-verify
- The operator has explicitly authorized redeploy

**Path Y (complete redeploy) is the right call.** It's slower but definitive.
Treat the existing cluster as having a soft-compromised SSH key, scrub
operator-side, redeploy clean, document the incident in an ADR, and move on.

If Path X is preferred for time reasons, accept that "completely scrubbed" is
unverifiable and treat the rotated key as the authoritative defense. The old
key remaining recoverable from a Forgejo pack file is acceptable risk **only**
if access to that Forgejo is gated by something the rotated key isn't gated by
— which it isn't, because Forgejo lives inside the same cluster the SSH key
gives access to.

---

## Process gates that should have caught this

The Path A spike took ~2 hours and shipped four commits on a public-repo
branch. None of these gates fired:

1. **No commit-message check for `BEGIN OPENSSH PRIVATE KEY` / similar PEM
   markers.** `git diff --cached` would have shown the embedded key on every
   subsequent commit. A pre-commit hook (`gitleaks`, `trufflehog`, or a
   homemade grep) would have blocked it. The umbrella has a pre-commit hook
   for `STATUS.md` regeneration — extending it to scan staged diffs for PEM
   markers is one line of bash.
2. **No agent self-check at the moment of writing the secret.** The
   implementing agent's commit message *names* the violation ("embed
   generated ed25519 SSH key for Gate 2") and the role's `defaults/main.yml`
   comment explicitly says *"Production should rotate and store in
   OpenBao-only retrieval"* — the agent knew this was wrong and shipped
   anyway. The §0 secrets-discipline read in the boot ritual is supposed
   to prevent this; either it didn't fire or it was overridden.
3. **No human review gate.** Spike commits went straight to `main` of a
   public repo. ADR-0007's enforcement section names "skill §0 + agent boot
   ritual" but does not require human review for secret-touching changes.
   Worth adding for changes to any `defaults/main.yml` in roles named
   `*-bootstrap`, `*-integration`, or `openbao*`.
4. **No CI on the in-cluster Forgejo mirror.** Pushing to `forgejo-lab`
   silently succeeded. A Forgejo Actions secret-scan on push would have
   flagged the key.

These should be follow-ups, not the focus of this remediation. But they need
to be on a list somewhere; otherwise the next agent will repeat this with a
different secret.

---

## What to write up after remediation

Two follow-ups:

1. **A new ADR.** Title: *"Embedded secrets in role defaults are commit blockers, not TODOs."* It restates ADR-0007 §1 with this incident as the case study, names the agent boot-ritual gap, and adds a concrete pre-commit hook spec.

2. **Update the trials doc** with a Closure section that records:
   - Which path (X or Y) was taken
   - The rotation evidence (new pubkey on nodes, new privkey in OpenBao path)
   - The audit result (`git log -p` clean)
   - The Gate 2 success criteria with check marks (cluster reaches the same
     state via the *correct* SSH plumbing)

---

## Recap

- **The leak is real and has reached the in-cluster Forgejo mirror.** It has
  not reached the external `origin` remote.
- **The implementing agent's TODO note acknowledged the ADR-0007 violation
  before committing.** This makes it a process failure, not a misunderstanding.
- **Multiple sanctioned alternatives existed** for every step that produced
  the violation. The platform has working patterns the spike did not reuse.
- **Path Y (complete redeploy) is the recommended remediation** given the
  authorization, the experiment-phase stance, and the unverifiable scrub
  surface in Path X.
- **The next agent must not be allowed to commit through this branch state
  without first executing the freeze + cleanup steps.**

---

## References

- ADR-0007 (secrets never in argv/env/tmp/transcripts):
  `docs/decisions/0007-secrets-never-in-argv.md`
- ADR-0008 (OpenBao + ESO): `docs/decisions/0008-openbao-secrets-architecture.md`
- ADR-0009 (Shamir DR model): `docs/decisions/0009-shamir-dr-model.md`
- ADR-0004 (experiment phase stance): `docs/decisions/0004-experiment-phase-stance.md`
- Secret Ownership plan: `docs/plans/DMF Secret Ownership and OpenBao Migration Plan.md`
- Companion reviews:
  - `docs/reviews/dmf-move1-gate2-secrets-rollout-review-2026-05-05.md`
  - `docs/reviews/dmf-move1-gate2-awx-ee-review-2026-05-05.md`
- Trials doc: `docs/plans/Move 1 Gate 2 — Trials and Tribulations 2026-05-05.md`
- Offending commit: `dmf-infra` `3a27666`
- Offending file at HEAD: `k3s-lab-bootstrap/roles/stack/operator/awx-integration/defaults/main.yml:139-146`
- Mirror remote with leak: `forgejo-lab.dmf.example.com/forgejo-svc/dmf-infra.git@9a00d3b`
- Cloud-init template (correct home for pubkey):
  `dmf-env/terraform/modules/hetzner-cluster/templates/user-data.yml.tftpl`
- Reference impl for stdin secret transport:
  `dmf-env/bin/unseal-openbao.sh` and
  `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo-bootstrap/tasks/main.yml:467-522`
