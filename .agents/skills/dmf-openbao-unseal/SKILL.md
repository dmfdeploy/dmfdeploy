---
name: dmf-openbao-unseal
description: Strict procedure for unsealing OpenBao on the live DMF Hetzner cluster using the 3-of-5 Shamir quorum (JuiceFS shares 1+2 + Keychain share 3). Drives dmf-env/bin/unseal-openbao.sh; never improvise share handling. Env slug rotates; current id in umbrella STATUS.local.md (run bin/generate-status.sh).
---

# DMF — OpenBao Manual Unseal

OpenBao seals on every pod restart. Most of the time the openbao role's auto-unseal
(reading `openbao-keys-automation.json` from JuiceFS) handles this without a human.
This skill is for when **auto-unseal can't run** — typically because the cluster
came back up before the JuiceFS volume was mounted, the automation file is stale,
or someone restarted the pod outside a playbook context.

## 🛑 Read this first

The unseal procedure handles **three of the five Shamir shares**. Capturing three
shares = full master key compromise. Treat this skill like handling raw key
material — because that's exactly what it does.

Hard rules:

1. **Use the script. Never type share values into a terminal.** The script pipes
   shares from their canonical sources directly into `bao operator unseal` via
   stdin. No share value lands in argv, env, `/tmp`, shell history, or stdout.

2. **Never invoke this through an AI agent if you can avoid it.** Run it in your
   own terminal. The script is designed so its stdout contains only seal status
   (no secrets), but defense in depth: keep the conversation transcript out of
   the path entirely.

3. **Don't paste shares anywhere.** Not into chat, not into Notes, not as
   "temporary" backups. If you find yourself wanting to, stop and use the script.

4. **If you suspect a share is exposed**, that's a re-key event, not a re-unseal.
   See §6.

## 1. When to run

| Symptom | Run this skill? |
|---|---|
| `bao status` says `sealed: true` and no playbook is running | **Yes** |
| ESO failing, secrets unreachable across the cluster | **Yes** (after confirming root cause is sealed bao) |
| Routine pod restart during a playbook run | No — auto-unseal handles it |
| You want to *re-key* (rotate share material) | No — see §6, separate procedure |
| Disaster recovery / re-init from scratch | No — uses USB shares 4+5, separate procedure |

## 2. Pre-flight (read-only, no secrets touched)

```bash
cd ~/repos/dmfdeploy/dmf-env
bin/unseal-openbao.sh --status
```

Confirms:
- Cluster + openbao pod reachable from your Mac via SSH
- Whether OpenBao actually is sealed
- Shamir threshold (`t`) and total share count (`n`)
- Current unseal progress (number of shares already fed in this attempt)

If status reports `sealed: false`, you don't need to do anything.

## 3. Execute

```bash
cd ~/repos/dmfdeploy/dmf-env
bin/unseal-openbao.sh
```

What it does, in order:

1. **Pre-flight** — checks ssh/kubectl/jq/security commands exist, cluster
   reachable, pod reachable, all 3 share sources present.
2. **Confirms** the operation interactively (skip with `--yes` only if scripting
   from another wrapper).
3. **Feeds share 1** — `jq -r '.key' share-1.json` piped via SSH+kubectl-exec
   stdin to `bao operator unseal`.
4. **Feeds share 2** — same pattern from `share-2.json`.
5. **Feeds share 3** — `security find-generic-password -w` from Keychain piped
   via the same path. Keychain may prompt to unlock.
6. **Verifies** final seal status and prints the bao status JSON (no secrets).

Total wall time: ~10 seconds when sources are local.

## 4. Where the share values live

This skill does not work without these:

| Share | Source | Format |
|---|---|---|
| 1 | `<secure-store>/openbao-breakglass/<env-name>/share-1.json` | `{"key": "<base64>"}` |
| 2 | `<secure-store>/openbao-breakglass/<env-name>/share-2.json` | `{"key": "<base64>"}` |
| 3 | macOS Keychain `service=openbao-breakglass-share-3, account=share` | base64 string |
| 4, 5 | USB `OPENBAO_A` at `/Volumes/OPENBAO_A/share-{4,5}.json` | reserved for re-init/rekey |

Shares 1 and 2 require the JuiceFS mount to be available (it almost always is on
your Mac). Share 3 requires the login keychain to be unlocked. If any of these
fails the pre-flight, the script exits with a clear error before touching the
cluster.

## 5. Failure modes

| Exit code | Meaning | What to do |
|:-:|---|---|
| 0 | Unsealed (or already was) | Done |
| 2 | Already unsealed | Confirm with `--status`; usually nothing to do |
| 3 | A share source is missing | Mount JuiceFS / unlock Keychain / verify the share files exist |
| 4 | Cluster or pod unreachable | Check the cluster is up and openbao-0 is scheduled |
| 5 | A share fed but bao reported an error | The script prints bao's response to stderr — read it; could be a corrupted share or wrong field name |
| 6 | Still sealed after 3 shares | The shares may not be from the same key material as the running OpenBao; re-init may be required (see §6) |

If the script fails partway through, OpenBao tracks unseal progress server-side
(`progress=1` after share 1, `progress=2` after share 2, etc.). Re-running picks
up where it left off — the partial progress is not a leak risk.

## 6. Out of scope (deliberately)

This skill **does not** cover:

- **Re-keying** (rotating Shamir share material). That's a planned procedure,
  not yet automated. Source: `dmfdeploy/docs/plans/DMF Improvement Run Plan 2026-04-22.md`.
- **Disaster recovery / re-init.** Uses USB shares 4+5 and the offline backup
  bundle. If the running OpenBao no longer has matching key material, you've
  crossed into re-init territory; stop and consult the relevant plan rather
  than improvising.
- **Rotating ops_admin / userpass credentials.** Different secret tier (runtime
  not breakglass), different procedure. See `DMF Secret Ownership and OpenBao
  Migration Plan.md`.

## 7. References

- `dmf-env/bin/unseal-openbao.sh` — the script this skill drives
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/tasks/main.yml` — share writers, source of truth for the file format
- `dmfdeploy/docs/plans/DMF Improvement Run Plan 2026-04-22.md` — Shamir layout
  decisions and re-key plan
- `dmfdeploy/docs/plans/DMF Secret Ownership and OpenBao Migration Plan.md` —
  secret-tier classification (breakglass vs runtime vs offline)
- Sibling skills: `dmf-cluster-access` (broader cluster ops), `dmf-cms-build-and-release`

---

**When in doubt:** run `bin/unseal-openbao.sh --status` first. It's free, touches
nothing, and tells you whether you actually need this skill. If you're contemplating
typing a share value somewhere, stop — that's the moment the leak happens.
