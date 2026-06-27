---
status: executed
date: 2026-06-26
executed: 2026-06-27
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/150
---

# DMF Init Long-Run Re-Entry & Resume Hardening Plan (v0.1-polish)

> **Milestone: v0.1-polish.** dmf-init is a v0.1 milestone component; this plan
> closes the robustness seam that locks an operator out of a healthy bootstrap
> during long constrained-node runs. Self-contained: a freshly-cleared agent
> should be able to resume from this doc + issue #150 alone (see **Resume guide**).

> **Shipped 2026-06-27 (#150 done).** All facets merged, each codex-reviewed:
> **(a)** sliding session + absolute cap & **(b)** SIGHUP launch re-mint —
> dmf-init #27; **(c1)** tmpfs fail-closed enforcement — dmf-init #28; **(c2)**
> forced checkpoint-export gate — dmf-init #29; **(d)** sealed-OpenBao auto-unseal
> preflight on resume — dmf-init #30 (+ dmf-env #18, `unseal-openbao.sh` rc=2
> disambiguation); **(e)** first-class expired-session UX + dead-session-poll fix
> — dmf-init #31. Remaining operator-gated follow-up: cut a dmf-init release
> (VERSION bump + appliance re-bake) to package these onto a tagged image.

## Why (the incident that motivated this)

dmf-init's robustness goal is to get a **slow / resource-limited bootstrap
through regardless** — phases are idempotent, you *resume the failed phase, you
don't start over*. That intent is real and has been pursued release over release:

- v0.3.0 — UI resume of a failed phase (#87)
- v0.3.2 — Pi-class `RUNBOOK_TIMEOUT` 5400 → 7200 s
- v0.3.4 — disk-backed resume + persistent recovery bundle (survive a GC'd/restarted run)

But the **session / launch-token layer was never hardened to match**, and it is
the seam that breaks the goal.

**Incident (env `piot-j6hv`, 2026-06-25 → 26).** A Pi-class run failed at the
`configure` step ~12 h after container start (resume cursor:
`failed_step_id=configure`, `final_status=error`, 2026-06-26 04:48 UTC). The
container was healthy and **never restarted**. Yet the operator was locked out:

- `DMF_SESSION_TTL_SECONDS=43200` = **exactly 12 h**, used as the session
  cookie's `max_age`. Container start `16:55` + 12 h = `04:55` — the session
  expired at almost the precise moment recovery was needed.
- The only re-entry path — the launch link — is **single-use + 30-min TTL**
  (`DMF_LAUNCH_TOKEN_TTL_SECONDS=1800`), long gone.
- Result: `401 "launch session required"` on `/api/envs`,
  `/api/bootstrap/passkey`, and four `/api/manage/restore` attempts.
- The data root was on the overlay layer (no `--tmpfs`), which is why the data
  survived the recovery `docker restart` — a true tmpfs mount, as designed,
  would have been RAM and gone.

> **Correction (codex cross-check).** An earlier draft claimed the
> backup-bundle Manage-restore would *also* have failed on a tmpfs assertion.
> That is wrong: `_assert_data_root_tmpfs` (`manage.py:83-125`) only
> `logger.warning`s — it does **not** raise or block, and `tests/test_manage.py`
> exercises restore on a plain tmp path and expects success. The lockout was
> the session 401 + spent launch token **only**. (Separately, that the check
> merely warns is a *latent weakness*: restore onto a non-tmpfs root is
> permitted, so secrets can touch disk — fold into facet (c).)
>
> **Mechanism (codex cross-check).** Starlette's `SessionMiddleware` emits
> `Set-Cookie` only when `session.modified` is true, and this app writes
> `request.session` exactly once — when the launch token is consumed
> (`main.py:161-163`). The session is never re-written, so the cookie **never
> refreshes**: it is a **hard 12 h wall from issuance**, not a sliding window.
> (Verified against logs: cookie issued 16:55:52; the *lockout* 401s on
> `/api/manage/restore` + `/api/envs` are at 04:56+, ~12 h later. Earlier 401s
> from 17:26 are passkey/package status **polls** hitting a protected route
> without the cookie — a separate pattern, evidence for facet (e), not the
> lockout.)

Recovery required an out-of-band `docker restart` to mint a fresh launch token
(operator data was rescued first as insurance). That is exactly the manual
intervention dmf-init is supposed to make unnecessary.

## Root-cause gaps

1. **Session TTL (12 h) < a constrained-node run can take.** The session can die
   mid-run or at the recovery moment, with no warning. The threat model is
   already `127.0.0.1`-only (single-use launch token gates initial entry), so a
   long / sliding session is low marginal risk.
2. **No in-band re-entry.** Once the session dies, the single-use/30-min launch
   token is spent; the *only* recovery is a container restart.
3. **"Survive a restart" is self-contradictory.** Disk-backed resume promises
   restart survival, but the tmpfs data-root (design) + `--rm` (README) means a
   restart wipes the cursor it depends on. It worked this time only by accident
   (non-tmpfs overlay). The Manage-restore tmpfs assertion conflicts with the
   same durability story.

## Goal

An operator can walk away from a multi-hour constrained-node bootstrap, come
back after it has failed (or while it is still running), and **always get back
into the same run to resume it** — without an out-of-band `docker` command and
without losing state. No silent lockout.

## Design

### (a) Session lifetime — sliding idle TTL + absolute cap, with a warning

- Make the session **sliding** — but note the mechanism (codex): Starlette only
  re-sends `Set-Cookie` when `session.modified` is true, and today the app writes
  the session exactly once (token consume, `main.py:161-163`). A bare
  `max_age` bump therefore still yields a **hard wall**. The fix must **mark the
  session modified on each authenticated request** (e.g. stamp a rolling
  timestamp) so the cookie actually refreshes. **Caveat:** a long-lived SSE
  stream emits `Set-Cookie` only at stream open, so SSE alone won't slide the
  session — the slide must hang off the polling/auth requests, not the stream.
- **Sliding idle TTL + an absolute cap** (codex), not an unbounded slide. Raise
  the idle default well past any plausible single run; keep an absolute ceiling.
- A 7-day-class bearer cookie is acceptable **only because** the trust surface is
  localhost — but note that is **not app-enforced** (the server binds `0.0.0.0`
  inside the container; loopback safety is the `docker` publish mapping only).
  Call this dependency out explicitly.
- Surface a **pre-expiry warning** + a remaining-session signal so the operator
  is never surprised.

### (b) Re-entry without losing state

The single-use launch token is the right *initial* gate; the gap is **re-entry
after the session dies while the container is still up**.

- **Recommended (codex): on-demand re-mint to logs.** A signal (e.g. `SIGHUP`)
  makes the running process **issue a fresh launch token and print it to the
  container logs** — the *same* trust surface as the original launch token
  (`docker logs` access == operator). No restart, no state loss.
- **Rejected: a localhost HTTP re-auth endpoint.** The image binds `0.0.0.0`
  inside the container and relies on the `docker` publish mapping for
  loopback-only safety (`Dockerfile:17-27`). A re-auth endpoint becomes a
  **second auth surface** that a mis-published container would expose; the
  SIGHUP/log reissue stays on the existing trust surface. (Revisit only if a
  hard localhost bind is enforced.)

Either way, the launch-token TTL must stop being a *lockout*: an expired token
on a live container must be **recoverable in-band**.

### (d) Survive an env reboot mid-bootstrap — sealed-OpenBao pre-flight on resume

A long constrained-node bring-up often spans an **env-node reboot** (Pi power
blip, kernel update, operator reboot). OpenBao **re-seals on every reboot**
(sandbox Tier-3 Shamir 1-of-1), after which the `configure` phase fails on the
first Bao-dependent task — surfaced only as a generic step error, giving the
operator no actionable signal. Observed live in this incident: after an env
reboot, `bao status` reported `Sealed: true`, `configure` errored; an out-of-band
`bao operator unseal` (1-of-1 key from `openbao-keys.json`, HTTPS
`-tls-skip-verify`) cleared it and the phase could proceed.

**Mechanism (codex):** retry-by-env slices the step list **from the failed step
onward** (`main.py:746-756`), so a resume from `configure` **skips the earlier
unseal step entirely** — which is exactly why the live resume re-failed on a
sealed Bao. The fix is a phase-scoped pre-flight, **not** re-running unseal.

dmf-init already holds the unseal key in tmpfs (`openbao-keys.json`) and unseals
once during the original bootstrap. The fix:

- **Pre-flight only for Bao-dependent phases:** before such a phase, check
  `bao status`; if sealed, **auto-unseal from the in-tmpfs key** — idempotent.
  **Not** on every resume; **loud** event/log when it fires (codex: silent
  auto-unseal is a security smell).
- **Legible failure if auto-unseal is impossible** (key absent / Bao
  uninitialized): a specific "OpenBao is sealed — unseal and retry" error, not a
  generic configure failure.
- Keep it scoped to the **sandbox 1-of-1** self-recovering profile; the Hetzner
  3-of-5 quorum stays manual (the `dmf-openbao-unseal` skill).

### (e) First-class expired-session UX + stray poll 401s

Even with the backend fixed, the operator hits opaque symptoms today: `/api/envs`
is fetched once on mount and failures are **silently ignored**
(`App.tsx:121-136`); other 401s bubble up as raw error text. Add:

- **First-class 401 handling** in the frontend: detect an expired session and
  show an actionable re-entry path (point at facet (b)'s re-mint), not raw text.
- **Investigate the stray poll 401s as a separate client-side bug (codex).**
  During this run, `GET /api/bootstrap/passkey/<id>` (×59) and
  `GET /api/package/<env>/status` (×50) returned 401 starting ~30 min in — long
  before the lockout. Most fetches set `credentials: 'same-origin'`
  (`App.tsx:125-128`, `useCreateFlow.ts:371-385,422-429`,
  `useEventStream.ts:91-99`), so this looks like a **missing-credentials path in
  the specific poll code** or a same-site/cookie-attachment edge on those routes.
  Track + fix distinctly — it is an **adjacent weakness, not the lockout cause**.

### (c) Resume durability — DECIDED by ADR-0044: stay stateless, no host persistence

> **Resolved in [ADR-0044](../decisions/0044-dmf-init-stateless-tmpfs-recovery-model.md)
> (Proposed, codex gate-reviewed).** The contract change was *considered and
> rejected*: dmf-init **stays stateless** rather than persisting a cursor to host
> disk. Rationale — facets (a)+(b) remove the need to restart a *healthy*
> container, so the only restart left is a genuine crash, covered by the recovery
> bundle. The decision tightens, rather than loosens, the contract.

- **Enforce tmpfs fail-closed at startup** (not warn-only). `_assert_data_root_tmpfs`
  today only `logger.warning`s (`manage.py:116`), which let this incident's
  secrets land on the overlay layer. Promote to a fail-closed startup check;
  scope out dev/test (appliance-only enforce / override env / `/dev/shm` in tests).
- **The resume cursor stays tmpfs-only** — a within-container-lifetime convenience
  (survives in-process restart + run-GC), explicitly **not** durable across
  `docker rm`. No host volume.
- **Crash recovery = rollback to the last *exported* checkpoint** (downloaded
  bundle), checkpoints only at #2/#3 — strictly weaker than cursor resume, and
  **only exists if the bundle has left tmpfs**. So the flow **must force/prove
  checkpoint export before long unattended phases** (auto-download on seal, or
  gate continuation past #2 on a proven download). See ADR-0044 Decision 3-4.
- **Docs sequencing:** the README run command must mark `--tmpfs` mandatory in
  the *same* change that enables fail-closed enforcement, or the documented
  invocation starts failing.

## Implementation steps (sequence)

0. **Codex cross-check — DONE (2026-06-26).** Corrected the diagnosis (tmpfs
   check warns, doesn't block; hard 12 h wall because the session is written
   once) and reshaped (a)–(e). **Eng-review + facet-(c) ADR done:** ADR-0044
   (Proposed) decides *stay stateless*; codex gate-review (CHANGES-NEEDED →
   addressed: crash contract = rollback-to-exported-checkpoint, forced export
   required). Findings folded in. Implementation paused pending operator ratify.
1. **(c) Enforce statelessness (ADR-0044)** — promote `_assert_data_root_tmpfs`
   to a fail-closed startup check (dev/test scoped); **force checkpoint export**
   before long unattended phases; make README `--tmpfs` mandatory in the same
   change. **No host-persisted cursor.**
2. **(a) Sliding session** in `dmf-init/src/dmf_init/main.py` — **mark the
   session modified on each authed request** (Starlette only re-cookies on
   `session.modified`); sliding idle TTL + absolute cap; remaining-session signal
   + UI pre-expiry warning. Tests for slide + expiry semantics.
3. **(b) In-band re-mint** — SIGHUP/log reissue of the launch token; test that an
   expired/spent token on a live container is recoverable without restart and
   without state loss.
4. *(folded into step 1 — ADR-0044 rejected the durable cursor; the
   statelessness-enforcement + forced-export work lives in step 1.)*
5. **(d) Sealed-Bao pre-flight** — phase-scoped auto-unseal from the in-tmpfs key
   (not every resume; loud event); legible error if impossible. Test a
   reboot→sealed→resume cycle on the sandbox profile.
6. **(e) Frontend 401 UX** — first-class expired-session handling; separately,
   chase the stray poll-401 credentials bug.
7. **Docs** — README + the dmf-init plan/handoff: document the long-run
   re-entry story so an operator knows the supported recovery path.
8. **Release** — version bump per `dmf-cms`-style release rules for dmf-init;
   the completing PR closes #150 and flips this plan's frontmatter to `executed`.

## Verification

- Simulated long-run lockout: start a run, let the session lapse, confirm
  in-band re-entry (facet b) resumes the same run with **no** `docker restart`.
- Statelessness (ADR-0044): non-tmpfs `DMF_DATA_ROOT` → startup **refusal** (not
  a warning); secrets never touch disk; `docker rm` stays safe.
- Crash contract: a crash before any checkpoint export leaves no artifact →
  verify the forced-export gate prevents entering long unattended phases without
  an exported checkpoint; restore-from-bundle rolls back to the last exported
  checkpoint (#2/#3), as documented (not same-step resume).
- Security: localhost-only trust surface unchanged; gitleaks/scrub gates green.

## Open questions

- (a) Idle-slide value + absolute-cap value (codex: cap, don't slide unbounded).
- (c) **Decided** by [ADR-0044](../decisions/0044-dmf-init-stateless-tmpfs-recovery-model.md)
  (Proposed): stay stateless. Remaining: the dev/test scoping of fail-closed
  tmpfs, and the exact forced-export mechanism (auto-download on seal vs. gated
  continuation).
- (e) Root cause of the stray poll-401s (missing-credentials path vs. same-site
  cookie edge on those specific routes).

## Resume guide

State at authoring: incident diagnosed; operator env `piot-j6hv` recovered via
out-of-band `docker restart the dmf-init container` + fresh launch token + UI resume from
`configure`; a host-side rescue copy of the env was taken as insurance. Issue
**#150** filed (v0.1-polish, `component:dmf-init` + `workstream:hardening`).
Next action: Step 1 (eng review + codex cross-check) → implement (a)→(b)→(c).
No code has been written yet.
