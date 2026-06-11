---
status: executed
date: 2026-06-10
executed: 2026-06-11
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/4
---
# dmf-init UI redesign — installer-style flow

> **Status:** ✅ EXECUTED 2026-06-11 — both passes shipped as **dmf-init
> v0.2.0** (tagged). Pass 1 landed via dmf-init PR #3; pass 2 landed as
> dmf-init PRs #4 (workstation pause merge), #5 (recovery-package download
> with safe-to-delete gating) and #7 (console installer skin + Configure
> wizard + install splash; supersedes #6). Field-validated by three full
> operator Lima E2E runs, the last end-to-end through package download and
> the optional Validate (doctor) run. Operator field feedback from the final
> run was folded in before landing: doctor auto-starts on Validate, and the
> long playbook steps show an honest within-step Ansible task ticker +
> per-step elapsed time. That run also surfaced a doctor false-negative in
> dmf-env (BSD-first `stat` probe poisons the perms capture under GNU
> coreutils) — fixed via dmf-env PR #1.

## Context

`dmf-init` is the Day-0 stateless bootstrap container: a localhost-only React +
FastAPI UI that wraps `dmf-env`'s wizard + bootstrap scripts to take a cluster
from zero → verified, then hands the operator a passphrase-wrapped backup so the
container can be deleted.

The current UI works but feels wrong:

- **Sprawl.** `App.tsx`, `BootstrapView.tsx`, `ManageView.tsx` each render a
  two-column grid of always-visible "cards" (operator identity, sandbox, render
  output, step rail, checkpoints, log console…). Everything is on screen at once;
  nothing guides the eye.
- **Interruptions.** The three human-in-the-loop steps (CA-cert trust, hosts
  mapping, passkey enrollment) fire as **full-screen modal pop-ups**
  (`fixed inset-0 z-50` in `BootstrapView.tsx:823`) that ambush the operator
  mid-run, on top of a scrolling log.
- **No clear arc.** Values collection, bootstrap, CA/enroll handoff and
  validation are tangled together instead of being distinct, sequential phases.

**Desired outcome:** reframe the create-new flow as a calm, linear **installer**
(think OS installer): a clean *values collection* step → a *comprehensive
bootstrap* progress screen → a *finish / package* screen (backup download + CA
cert + enrollment instructions, "safe to delete") → an *optional validate* run.
The three pauses stop being surprise modals and become designed, inline stations
in the arc.

This is a **frontend re-architecture only** — the FastAPI backend, its endpoints,
the NDJSON event/pause/resume contract, and the redaction model stay unchanged.
That keeps the change low-risk and reviewable.

## Design constraints (inherited, binding)

From the umbrella **DMF Console UX Constitution** (`docs/design/DMF Console UX
Constitution 2026-05-25.md`) — the hard gates that govern this work:

- **Art. 2 — Close every loop.** Every action has a visible outcome anchored
  where it was taken (start, each step, each pause, finish).
- **Art. 5 — No disruptive reflow.** State patches in place; the step list never
  collapse-and-rebuilds on identical data.
- **Art. 7 — Safe easy, dangerous deliberate.** Teardown (Manage) keeps its
  typed confirmation; the happy path stays frictionless.
- **Art. 8 — Errors are content.** Failures render as designed states with
  what-happened / what-it-means / what-to-do, not raw red boxes.
- **Art. 9 — Design the unhappy path first.** Loading, waiting-for-pause,
  reconnecting, failed, stale-CA-not-ready are first-class states.
- **Art. 11 — Accessible.** Status never by colour alone (dot **+** label),
  keyboard-operable, `prefers-reduced-motion` respected.

**Visual language:** keep dmf-init's existing cyan onboarding identity
(`--accent: #7dd3fc`, `frontend/src/index.css`) but borrow dmf-cms's component
discipline (status dot = colour + shape + text; calm density; border-driven
hierarchy). Self-contained / air-gap: no CDN fonts or scripts (already true).

**Non-goals this pass:** full i18n (ADR-0030 LinguiJS/three-locale work is a
separate effort — we will keep copy centralised and avoid `count===1` plural
bugs so it isn't blocked, but we do not wire LinguiJS here); rclone remote config
(this build delivers backups as browser downloads); cloud/Hetzner profile.

## Backend contract we build against (unchanged)

Bootstrap step order (`src/dmf_init/bootstrap_steps.py:528`):
`pre-seed → checkpoint-2 → unseal → seed-bao → post-seed → configure →
ca-cert(pause) → hosts-map(pause) → passkey(pause) → verify → checkpoint-3`.

NDJSON events (`orchestrate.py`): `run_start, step_start, log, step_complete,
checkpoint, pause, resume, complete, error`. Pauses arrive **sequentially** —
each `pause` is followed by a `/api/bootstrap/resume`, then the next fires. This
maps cleanly onto a 3-station guided checklist.

**Contract truths to respect (codex cross-check):**
- **Passkey gating is client-side, not server-side.** `/api/bootstrap/resume`
  accepts the `passkey` pause like any other; `/api/bootstrap/passkey/{run_id}`
  only *reports* `confirmed/required`. The current UI enforces "Verify &
  Continue" by checking that count before it calls `resume`. The new Connect
  station keeps that client-side gate (don't claim the backend enforces it).
- **`complete` returns checkpoint *numbers* only**, not artifact names. Artifact
  names arrive on the `checkpoint` events during the stream — the UI must
  capture and keep them (survive replay) to build the Finish download list.
- **Not every artifact is on the download route.** Checkpoint **#2/#3** artifacts
  are copied into `data_root/artifacts` (servable via
  `/api/backup/artifact/{name}`); the initial create-new backup **#1** is not.
  Treat **checkpoint #3 as the primary, authoritative download**; #1 download
  would require a backend fix (out of scope).

Key endpoints reused as-is: `/api/repos/fetch`, `/api/render` (stream),
`/api/backup`, `/api/bootstrap/{start,stream,resume}`, `/api/bootstrap/passkey`,
`/api/ca-cert/{env_id}`, `/api/backup/artifact/{name}`, `/api/manage/*`.

## Target UX — the create-new arc

A persistent **StepProgress** rail (Configure · Install · Connect · Finish) sits
under a slim app header (brand + Create/Manage toggle). One phase owns the
viewport at a time; no two-column card sprawl.

1. **Configure** — single guided form (operator identity, sandbox inputs, SSH
   key paste/upload, passphrase ×2). Inline validation; a compact **Review**
   summary before the single primary action **“Start install”**. Replaces the
   three stacked `SectionCard`s + the always-present "Render output" pane.

2. **Install** — the OS-installer screen. Primary view is a **calm vertical step
   rail** (dot+label+state) driven by `step_start`/`step_complete`; the live log
   moves behind a **“Show details”** disclosure (collapsed by default). Runs
   `pre-seed … configure` unattended. Checkpoints #1/#2 render as quiet inline
   "✓ backup saved" ticks, not loud cards. `render` + `/api/backup` (checkpoint
   #1) happen at the head of this phase.

3. **Connect** — the three pauses, reframed as an **inline guided checklist**
   (Trust CA → Map hosts → Enroll passkey), one station active at a time, driven
   by the sequential `pause` events. No modal. These are **blocking, first-time
   tasks** that must complete *before* `verify` — not deferrable to Finish. Each
   station: clear "why", download/copy affordances (reuse `CaInstall`, hosts
   one-liner, QR), and a single **Continue**. Gating is **client-side**: passkey
   shows live `confirmed/required` (poll `/api/bootstrap/passkey`) and only lets
   Continue call `resume` once satisfied. **Advance the UI on the authoritative
   `resume`/`step_complete` stream events, not merely on the resume HTTP 200**
   (Art. 2). After the last resume, the mandatory `verify` runs (rail returns to
   Install) → `checkpoint-3` → `complete`.

4. **Finish / Your package** — “Safe to delete this container,” shown **only
   after `complete` (verify + checkpoint #3)** — never after #1. The durable
   handoff: **primary backup download = checkpoint #3 artifact** (name taken from
   the captured `checkpoint` events), the **CA cert + per-OS install instructions
   as a reference re-presentation** (already done in Connect — labelled "for your
   records", not a fresh task), enrollment summary, and the passphrase reminder.
   Offers an **optional “Re-validate”** action → step 5.

5. **Validate (optional)** — re-runs `doctor` and shows green checks. Skippable;
   the container is already safe to delete after Finish. **This is the one part
   that is NOT frontend-only:** there is no create-flow doctor endpoint today
   (`/api/manage/doctor` requires a Manage `session_id` from a restore). It needs
   a **small new backend route** that runs `doctor` against the still-in-tmpfs
   env from the create run (reusing `manage_actions`/`bootstrap_steps` doctor
   wiring). Flagged as a scoped backend follow-up; if rejected, Validate is cut
   and the mandatory in-run `verify` (surfaced in Install) stands as the proof.

**Manage mode** adopts the same shell + primitives but stays a 3-pane flow
(Restore → Env overview → Actions), de-sprawled into one column with the shared
`LogConsole`. Teardown keeps its typed confirmation (Art. 7). Scope: tidy/reuse,
not a full rebuild (confirm with user).

## Implementation

Pure frontend; files under `frontend/src/`.

**State model.** Replace the scattered booleans (`bootstrapOpen`, `stage`,
`phase`) with a **create-flow reducer** (`configure → installing → connect →
verifying → finish → validating`) that maps stream events to phases, so the UI
is a function of phase + event state (Art. 5: patch in place). **Keep the create
and manage reducers separate** — do *not* merge them into one mega machine
(codex). Share only the dumb pieces: `Shell`, `LogConsole`, `StatusDot`, and a
**transport-only `useEventStream`** hook.

`useEventStream` is transport only; the reducer interprets. Cursor rules
(currently duplicated and subtle in `BootstrapView`/`ManageView`): isolate state
**by `run_id`**; reset on run change; **replay from 0** when local state is lost;
handle terminal **404 / TTL-expired** runs; and **increment the cursor only after
the event is applied**, so a reducer error can't silently skip state.

**Decompose** the monoliths into focused components:
- `app/Shell.tsx` — header, Create/Manage toggle, `StepProgress` rail.
- `create/ConfigureStep.tsx` — the form + Review (extracts today's `App.tsx`
  form, adds validation).
- `create/InstallProgress.tsx` — calm step rail + collapsible `LogConsole`;
  reused for the `verify` tail. Extracts the rail/log from `BootstrapView.tsx`.
- `create/ConnectStep.tsx` — the 3-station checklist; **absorbs and deletes the
  modal pause block** (`BootstrapView.tsx:823-1034`), reusing its CA/hosts/passkey
  bodies inline.
- `create/FinishStep.tsx` — package + safe-to-delete; reuses `ArtifactDownload`,
  `CaInstall`, the CA fetch in `App.tsx`'s `CompletionCard`.
- `create/ValidateStep.tsx` — optional doctor/verify run via shared console.
- `shared/StepProgress.tsx`, `shared/LogConsole.tsx`, `shared/StatusDot.tsx`
  (dot+label, a11y), `shared/Disclosure.tsx`.
- Extend `ui.tsx` (`Field/Input/TextArea/SectionCard`) rather than re-inventing.
- Factor the duplicated NDJSON stream/reconnect loop (identical in
  `BootstrapView.tsx` and `ManageView.tsx`) into one `useEventStream` hook.

**Manage:** reskin `ManageView.tsx` onto `Shell` + shared console/primitives;
keep its restore/doctor/action logic (reducer stays separate from create).

**A11y / no-reflow / errors-as-content (Arts. 5/8/9/11 — codex #6), required:**
- Inline Connect stations use **fixed-height slots** so the QR, enrollment link,
  and live passkey count don't reflow as they populate (Art. 5).
- Move **focus** to the active station on change; status uses **`aria-live`**;
  the pulse/animation respects **`prefers-reduced-motion`** (Art. 11).
- Copy and download buttons give **explicit success feedback** (Art. 2).
- Collapsing the log is allowed **only** if the error state lifts the **current
  step + last useful log lines** into the visible error content (Art. 8) — a
  collapsed log must never hide the reason a run failed.

**Backend scope.** Frontend-only **except** the optional Validate route (above).
Any other backend need (e.g. making #1 downloadable, server-gating passkey) is
raised as a separate, explicit follow-up — not assumed.

**Backend (the one addition).** Add a create-flow doctor route to
`src/dmf_init/main.py` (e.g. `POST /api/bootstrap/doctor` taking the create
`env_id`/`run_id`) that runs `doctor` against the in-tmpfs env, reusing the
doctor step wiring in `manage_actions.py`/`bootstrap_steps.py` and streaming over
the existing NDJSON `/api/bootstrap/stream` contract. **Ship it with one API test**
in `tests/test_main.py` (route exists, runs doctor, streams `complete`) so the
pass is not mistaken for frontend-only.

## Critical files

- Add + test: `src/dmf_init/main.py` (create-flow doctor route),
  `tests/test_main.py` (one route test).
- Rewrite/replace: `frontend/src/App.tsx`, `frontend/src/BootstrapView.tsx`,
  `frontend/src/ManageView.tsx`.
- Extend: `frontend/src/ui.tsx`, `frontend/src/index.css`,
  `frontend/tailwind.config.ts` (add status/semantic tokens if needed).
- Reuse: `frontend/src/ndjson.ts` (`readNdjson`).
- New: `frontend/src/app/`, `frontend/src/create/`, `frontend/src/shared/`,
  `frontend/src/hooks/useEventStream.ts`, `useCreateFlow.ts`.

## Verification

- `cd frontend && npm run build` (and `tsc`) clean; existing lint passes.
- Drive the real flow against the dmf-sandbox Lima VM (the documented Phase-1 E2E
  path) using fake data: Configure → Install → Connect (3 stations) → Finish →
  optional Validate. Confirm no modal appears and the log is collapsed by default.
- Use the Playwright/`browse` MCP to screenshot each phase at desktop width;
  verify status is dot **+** label (Art. 11) and a forced step error renders as a
  designed error state (Art. 8/9), not a raw box.
- Reconnect test: kill the stream mid-Install; confirm cursor-resume still lands
  in the right phase.
- Backend test suite (`pytest`) green, **including the new API test** for the
  create-flow doctor route (route exists, runs doctor, streams to `complete`).
  All other endpoints unchanged (proves no contract drift).

## Decisions (confirmed with operator)

- **Pauses:** all three inline as Connect stations (no modal).
- **Manage:** reskin onto the new shell + shared primitives; keep logic.
- **i18n:** deferred — centralise copy and avoid `count===1` plural bugs so it
  isn't blocked; do not wire LinguiJS this pass.

- **Validate:** **add a small create-flow `doctor` backend route** (confirmed) —
  runs `doctor` against the still-in-tmpfs create-run env, reusing the existing
  doctor wiring in `manage_actions.py`/`bootstrap_steps.py`, streamed over the
  same NDJSON contract. This is the **one backend addition**; the rest is
  frontend.

---

# Pass 2 — Console installer skin (specced 2026-06-10, after operator feedback)

## Operator feedback driving this pass

1. Current chrome still reads like the old UI; wants the **dmf-cms console
   family look** (dmfdeploy logo, refined industrial dark) while staying
   visibly a Day-0 tool.
2. Wants the classic **OS-installer layout**: step rail on the LEFT, central
   content, splash + progress bar during install.
3. **Too much text per page** → multi-page wizard for values collection.
4. **Too many buttons**: target = Deploy → (stations) → Download package →
   optional Validate.

## Research grounding (2026-06-10)

- **Calamares**: persistent left sidebar step list, central content pane,
  Next/Back bottom; slideshow during long install steps; "easy to understand
  what will be done at every step without overwhelming the user."
- **Ubuntu Flutter installer (23.04+)**: centered content, one decision/topic
  per page, dedicated Review/Summary screen before commit, feature slideshow +
  progress bar during the long install phase.
- **Fedora Anaconda web UI**: their user research found hub-and-spoke
  confusing; deliberately moved to a **linear guided wizard** — validates the
  linear arc; our flow is enforced-linear anyway.

## Decisions

- **Accent:** keep **cyan** (`#7dd3fc`) as dmf-init's Day-0 identity, on
  **dmf-cms console chrome** — tokens `bg #0b121f`, `panel #151e2d`,
  `border #1f2937`, border-driven hierarchy, `rounded-lg`, denser type. Drop
  glass/glow/radial-gradient/hero. Copy `dmfdeploy-icon-white.svg` from
  dmf-cms assets.
- **Layout:** slim topbar (logo + "dmfdeploy **init**" wordmark + Create/Manage
  toggle) · **left step rail** (vertical, Calamares-style: Configure pages,
  Install, Connect, Finish) · central content pane. Manage uses same shell,
  rail hidden or manage-specific.
- **Landscape-first, viewport-fit (operator feedback 2026-06-10):** the current
  UI is an overly-portrait scrolling column. Like a real installer, every
  wizard page / station / splash must fit a standard laptop viewport
  (design target 1280×800; verify at 1440×900 and 1920×1080) with **no
  page-level scrolling**. Achieve via: console density (compact paddings, no
  hero), left rail absorbing navigation chrome, two-column content inside
  stations where it helps (e.g. instructions left, QR/artifact right), and
  **internal** scroll areas only for logs / PEM blocks / long reference text
  behind disclosures. Page scroll allowed only below ~720px height (small
  laptops) as graceful degradation.
- **Configure becomes a short wizard** (one topic per page, centered,
  Back/Next): 1) Identity 2) Target node (label/IP/user/iface + SSH key)
  3) Security (passphrase ×2) 4) **Review & Deploy** (single primary button —
  replaces today's Review-screen + Start-install double press). NOT one field
  per page; variants/hints into dropdowns/disclosures per Ubuntu pattern.
- **Install = splash screen**: centered dmfdeploy logo/splash, overall
  progress bar driven by step_complete count (honest N-of-M, per-step
  indeterminate within a step + elapsed time — no fake percent, Art. 1),
  current-step label, log behind "Show details". Checkpoints stay quiet ticks.
- **Stations are NOT wizard pages**: Connect stations remain run-gated
  sequential stations in the central pane (no Back/Next semantics mid-run);
  left rail shows position.
- **Text diet**: one sentence per screen + "Learn more" disclosure; CA install
  instructions show ONLY the detected OS expanded (others collapsed);
  reference prose moves into the package README.
- **Button inventory** (target): Deploy · Continue (workstation station) ·
  Verify & Continue (passkey) · Download package · optional Validate.

## Field note from live Lima E2E (2026-06-10, operator)

Full create-new run on the recreated Lima VM **succeeded end-to-end** (pass 1
validated). Two findings:
- The mid-run stops for user interaction (CA download etc.) feel disruptive →
  reinforces the `workstation` pause merge below.
- **Operator enrolled the passkey from an iPad WITHOUT installing the CA cert.**
  The "passkeys fail silently without CA trust" claim came from the desktop
  (Chrome) exercise; Safari/iOS evidently still allows WebAuthn after the cert
  warning. Action: soften the CA station copy from absolute ("will not work")
  to browser-specific ("required on desktop Chrome/Chromium — enrollment fails
  silently there; other browsers may proceed after a warning"), and keep CA
  install as a strongly-recommended checklist item inside the merged
  workstation station rather than a heavyweight ceremony of its own. Do NOT
  drop it: console access from the workstation still needs the CA trusted to
  avoid warnings on every service.

## Backend deltas (small, contained — do AFTER live Lima E2E validates pass 1)

1. **Merge `ca-cert` + `hosts-map` pauses** into one `workstation` pause in
   `bootstrap_steps.py` (combined payload; one resume). Update orchestrate
   tests + frontend station. (Passkey pause unchanged — it's the gated one.)
2. **`GET /api/package/{env_id}`**: zip of checkpoint #3 backup + CA cert +
   README (enroll summary, hosts entries, per-OS CA instructions) + MANIFEST
   with sha256s. Record download-completed on the run/session.
3. **Safe-to-delete gating**: Finish shows amber until package download
   completed (server-recorded stream completion + sha256 shown — honest about
   what we know); optional Validate also asserts package-downloaded.

## Sequencing

1. Operator's manual Lima E2E on pass 1 → fix anything it surfaces.
2. Backend deltas (pause merge + package endpoint + tests).
3. Frontend skin/layout pass (tokens, topbar+left rail shell, Configure wizard
   pages, Install splash, station/Finish slimming).
4. Re-verify: pytest, tsc/build, screenshots incl. Install splash + stations.

---

# Future direction (noted 2026-06-10, to discuss — not in scope for Pass 2)

Two operator ideas captured for a later ADR (also tracked in TODOS.md §dmf-init):

1. **Shared UI framework with dmf-cms.** The Pass-2 console skin hand-copies
   dmf-cms tokens/conventions into dmf-init. Instead, extract a shared
   template/component layer (tokens, primitives, shell patterns) consumed by
   both frontends so changes port between them. Candidate shapes: a shared
   npm package in the umbrella, or a git-subtree'd `ui-kit/`. Pairs with the
   React-Aria re-evaluation noted in ADR-0030.

2. **dmf-init converges into dmf-cms.** Long-term, the create-facility flow
   should live inside dmf-cms ("spawn new facilities" from the console), with
   env state in a proper OpenBao storage backend instead of passphrase-wrapped
   locally-saved files. The ADR must resolve the day-0 chicken-and-egg: a
   standalone bootstrapper is still required before any cluster/cms/OpenBao
   exists, so the likely end-state is a split — a minimal standalone day-0
   seeder plus a cms-integrated facility spawner for day-N. dmf-init's
   "wrap, don't reimplement" and answers-file contracts are the stable seam
   either way.
