---
status: executed
date: 2026-06-07
executed: 2026-06-08
---
# DMF dmf-init Container Productization Plan — cold-bootstrap smoke gate (2026-06-07)

**Status:** Proposed task spec (operator-approved 2026-06-07). Sandbox lane.
**Goal:** make the **dmf-init container** run a from-scratch sandbox bootstrap with **no manual
runtime patching** — the precondition for the full fresh **sslip.io** e2e (the v0.1
"reproducible by a stranger" milestone).
**Origin:** the first container-driven VPS deploy (`tzje-voik`, 2026-06-07) needed ~3 classes of
runtime workaround. See handoff `DMF First Container-Driven VPS Deploy + Passkey UX Handoff
2026-06-07.md`, `TODOS.md` §"dmf-init CONTAINER path — productization", and memory
`project_dmf_init_container_bootstrap_gaps`.
**Decision basis:** [[project_phase]] v0.1 — these workarounds are the *content* of the v0.1
cold-bootstrap smoke gate; baking them in is the gate, not polish.

---

## What this changes (and what it does NOT)

**Changes:** three repos so a cold container bootstrap completes unattended —
`dmf-init` (Dockerfile deps), `dmf-infra` (`200-baseline` trixie-safe node pip), `dmf-env`
(`unseal-openbao.sh` no longer hard-requires macOS `security` on the sandbox profile).

**Does NOT change:** any bootstrap *logic*, the security posture, passkeys (mandatory, ADR-0028
D8), the sslip.io addressing (already landed), or cloud-lane behaviour. Pure environment/packaging
fixes. No ADR change.

---

## Key environment facts (verified 2026-06-07, container `dmf-init-marty`)

- The image base is `python:3.12-slim` but it is **trixie-based**: `/usr/bin/ansible` →
  `#!/usr/bin/python3` = **Python 3.13.5**. `pip install .` installs `dmf_init` into the
  *3.12* `/usr/local/bin/python`. **Ansible's collections/modules import from
  `/usr/bin/python3` (3.13)** — so all controller py-libs MUST be installed there.
- Trixie's apt-managed `PyYAML` (6.0.2) has **no pip RECORD** → pip refuses to uninstall/upgrade
  it; any dependency pulling `pyyaml>=6.0.3` fails unless `--ignore-installed PyYAML` is used
  first. This bites **both** the container controller py-libs **and** the k3s node
  (`200-baseline`).

---

# Work packages — cold-agent implementation spec

> A freshly-cleared agent can execute from here. Do WP0 first.

## WP0 — Onboarding (every agent, first)
- **Boot ritual:** `cd "$DMFDEPLOY_UMBRELLA" && git fetch && git pull`; `bin/generate-status.sh
  --no-fetch`; read `STATUS.md`, this plan, the handoff above; skim `docs/decisions/INDEX.md`.
- **Repos/branch:** changes touch `dmf-init`, `dmf-infra`, `dmf-env` (sibling repos).
  🔒 **ALL work lands on `main`. No feature branches.** Verify `git -C <repo> rev-parse
  --abbrev-ref HEAD == main` before each commit; ask before touching a sub-repo with dirty state.
  Do NOT push unless told.
- **Commits:** conventional-commit, end each with `Co-Authored-By: Claude Opus 4.8
  <noreply@anthropic.com>`. If dispatched via agent-bridge, reply `DONE <repo> <hash>` /
  `BLOCKED <repo> <reason>` to the caller.
- **Guardrails:** sandbox lane; no bootstrap-logic changes; no ADR change; passkeys stay mandatory.

## WP1 — Dockerfile: bake in bootstrap deps  ·  repo `dmf-init`
**File:** `Dockerfile` (single `python:3.12-slim` stage from `:13`; apt block `:31-45`; binary
download block `:54-72`; `pip install .` `:74`).
**Change:**
1. **apt block (`:33-44`):** add `bind9-dnsutils` (provides `dig`) and `apache2-utils` (provides
   `htpasswd`).
2. **helm binary:** add a pinned download alongside kubectl/sops/tofu in the `:54-72` block —
   `ARG HELM_VERSION=3.18.4` (matches what the `dmf-infra` roles install for arm64/amd64 —
   confirmed 2026-06-07). Fetch
   `https://get.helm.sh/helm-v${HELM_VERSION}-linux-${arch}.tar.gz`, extract
   `linux-${arch}/helm` → `/usr/local/bin/helm`, `chmod +x`, clean up.
3. **Controller py-libs into Ansible's python (`/usr/bin/python3`, 3.13):** add a RUN step that
   does `PyYAML>=6.0.3 --ignore-installed` **first**, then
   `jmespath netaddr passlib jsonpatch kubernetes yq` (kislyuk `yq`), e.g.
   `pip3 install --break-system-packages --ignore-installed PyYAML>=6.0.3 && pip3 install
   --break-system-packages jmespath netaddr passlib jsonpatch kubernetes yq`. **Use the system
   `pip3` that targets `/usr/bin/python3`**, NOT the 3.12 `/usr/local/bin/pip`. Verify the target
   with `/usr/bin/python3 -m pip --version` in the same layer.
**Acceptance:** `docker build -t dmf-init:prod .` succeeds; in the built image
`docker run --rm --entrypoint sh dmf-init:prod -c '…'` shows `dig`, `htpasswd`, `helm version`,
and `/usr/bin/python3 -c "import jmespath,netaddr,passlib,jsonpatch,kubernetes,yaml; print(yaml.__version__)"`
all resolve (yaml ≥ 6.0.3), and `yq --version` works.

## WP2 — `200-baseline` trixie-safe node pip  ·  repo `dmf-infra`
**File:** `k3s-lab-bootstrap/playbooks/200-baseline.yml` (`:69-75` — "Install kubernetes Python
library", `extra_args: "{{ baseline_pip_extra_args | default('--break-system-packages') }}"`).
**Change:** before the kubernetes pip task, add a task that installs `PyYAML>=6.0.3` with
`--ignore-installed` (so the RECORD-less apt 6.0.2 is left alone and a fresh wheel satisfies
kubernetes), then install kubernetes. Keep it safe on non-trixie (Debian 12) too — e.g. default
`baseline_pip_extra_args` to `--break-system-packages --ignore-installed` for the kubernetes task,
and add the explicit `PyYAML>=6.0.3 --ignore-installed` pre-task. Document the trixie rationale in
the task comment.
**Acceptance:** on a trixie node `200-baseline` completes the kubernetes-lib step without the
PyYAML RECORD error (validated during the WP4 e2e); `ansible-playbook --syntax-check` passes.

## WP3 — `unseal-openbao.sh` no macOS `security` on sandbox  ·  repo `dmf-env`
**File:** `bin/unseal-openbao.sh` (`:283` `require security`; Keychain uses at `:351`,
`:449-450`).
**Change:** make the macOS Keychain dependency **conditional on a non-sandbox profile**. On the
sandbox profile (Shamir 1/1 self-unseal — the node already auto-unseals) the script must NOT
`require security` and must NOT attempt the share-3 Keychain fetch; it should no-op/exit cleanly
for sandbox. Detect the profile from the env (manifest/group_vars `posture: sandbox` or an
explicit `OPENBAO_PROFILE`/flag) the same way the rest of the toolchain does. **Cross-check the
node-local OpenBao HTTP-API unseal work** that landed 2026-06-01 (dmf-env `e514bd9`, per memory
`project_unseal_openbao_use_pty_bug`) — that path may already supersede the Keychain flow for
sandbox; align with it rather than duplicating. Do NOT change cloud-lane (3-of-5 Shamir) behaviour.
**Acceptance:** `bash -n` + shellcheck (`uvx --from shellcheck-py shellcheck bin/unseal-openbao.sh`)
clean; on the Linux container the script no longer aborts at `require security` for a sandbox env
(validated during WP4).

## WP4 — Verification: full fresh sslip.io e2e (Claude)
After WP1–WP3 land + image rebuilt (`dmf-init:prod`):
1. **Prereq (operator/Claude):** a fresh **internet-reachable** node (new VPS, or re-bootstrap
   the `tzje-voik` node clean — its current env is `.dmf.test` and can't be reused for sslip.io).
2. Drive a **from-scratch** container bootstrap with **no runtime patching**.
3. Assert the full chain: `console.<node-ip-dashed>.sslip.io` reachable with **no /etc/hosts** →
   trust the local CA once → enroll the **mandatory** passkeys end-to-end (this exercises WP2's
   reusable invite in a real ceremony + WP3's CA-trust UX live) → confirm a failed WebAuthn attempt
   does **not** burn the invite → `bootstrap-sandbox-verify` D8 passkey check green; all pods
   Running; checkpoint backup written to both remotes.
4. If green: this **closes the v0.1 cold-bootstrap smoke gate**. Write a handoff + update TODOS.

## Out of scope
- HA OpenBao / re-key (TODOS §HA bao migration) — unrelated.
- The maintainer DNS-01 `<env>.dmfdeploy.io` profile + localhost-origin sandbox (separate plans).
- Any image-publish path for dmf-init (still local-only).
