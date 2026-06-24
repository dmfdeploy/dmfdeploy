---
status: executed
date: 2026-06-24
executed: 2026-06-24
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/81
---
# DMF Sandbox Substrate-Agnostic Onboarding

> **Status:** ✅ EXECUTED 2026-06-24 — landed as dmf-init PR #22 (Target-node
> UI defaults + per-field hints + README) and dmf-env PR #15 (`recreate-sandbox-vm.sh`
> macOS-only note); this umbrella PR records the decision and closes #81.

> **Problem.** The sandbox provider accepts any SSH-reachable node, but everything
> that *guides* an operator to one assumed the maintainer's macOS + Lima setup — so
> a non-macOS operator (the #36 "stranger") stalled at the first wizard step with no
> help. Surfaced live during a dmf-init install trial on Linux (Steam Deck): the
> Target-node form defaulted the Ansible user / interface to `lima` / `lima0`, which
> exist only inside the macOS Lima VM.

## Decision

**Bringing any SSH-reachable Debian 12/13 ARM64 node is the primary onboarding
path, regardless of the operator's workstation OS.** (Other distros and
architectures are untested for now.)
`dmf-env/bin/recreate-sandbox-vm.sh` remains a *macOS/Lima convenience* — explicitly
documented as such, not the paved path. The installer must not hardcode one host's
substrate values, and the Target-node fields must carry enough inline guidance that a
newcomer can fill them without reading the maintainer's setup.

## Scope (three-part, three repos)

1. **dmf-init** (`frontend/src/create/ConfigureStep.tsx` + `README.md`)
   - Blank the macOS-Lima defaults: `ansibleUser: 'lima'` → `''`,
     `iface: 'lima0'` → `''`. Per-page validation already rejects empty values, so
     blanks force a deliberate, host-correct entry instead of a silently-wrong one.
   - Add per-field `hint` (the `Field` component already supports it) to the three
     fields that had none:
     - **Node IP** — an address reachable *from the installer container*; **not**
       `localhost` / `127.0.0.1` (that resolves to the container itself).
     - **Ansible user** — the SSH login on the node (`root`, or the image's
       default user such as `debian`); `lima` only applies to a macOS Lima VM.
     - **Interface** — the node's primary NIC (`eth0`, `ens3`, …); `lima0` only on Lima.
   - README: a "Target node" subsection under *Run it* framing bring-any-SSH-node as
     the primary path and `recreate-sandbox-vm.sh` as a macOS convenience.

2. **dmf-env** (`bin/recreate-sandbox-vm.sh`)
   - Header note declaring the script macOS + Lima ONLY — a maintainer convenience,
     not the paved path — and pointing at the substrate-agnostic flow.

3. **dmfdeploy (umbrella)** — this plan doc, recording the decision + tracking #81.

## Non-goals / deliberately deferred

- **No second per-OS node-creation helper.** Adding a Linux/Windows analogue of
  `recreate-sandbox-vm.sh` would re-introduce the hidden-assumption problem; the
  generic "bring any SSH-reachable Debian 12/13 ARM64 node" path is the substitute.
- **No auto-detection of user/interface from the node.** The issue floats detecting
  these once SSH is established, but that depends on where in the wizard flow the
  connection is actually made (unverified). Blank-with-guidance is the committed,
  low-risk fix; detection is a possible follow-up, not part of this work.
- **No frontend test harness.** dmf-init's frontend has no vitest/test runner (vite
  build only); standing one up for this copy/default change is out of scope.
  Verification is `tsc` typecheck + `vite build` + on-disk confirmation of the
  defaults and hint copy. The backend `tests/*.py` pass `lima`/`lima0` as explicit
  fixture *values* and are unaffected by the UI default change.

## Acceptance

- `npm run build` (`tsc && vite build`) passes in dmf-init.
- Target-node defaults render blank; Node IP / Ansible user / Interface each show a
  hint, including the Node-IP localhost-trap warning.
- README "Target node" guidance, the dmf-env script note, and this plan doc are
  landed; #81 closes.

## Tracking

[`dmfdeploy/dmfdeploy#81`](https://github.com/dmfdeploy/dmfdeploy/issues/81)
(`enhancement`, `component:cross-repo`, `workstream:entrance`, milestone
`v0.1-polish`). Lands as: dmf-init PR (UI + README), dmf-env PR (script note), and
the umbrella PR carrying this plan + `Closes dmfdeploy/dmfdeploy#81`.
