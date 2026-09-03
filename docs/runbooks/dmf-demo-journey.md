# DMF Platform Demo Journey

**Status:** Presenter-facing runbook. The full end-to-end demo of the DMF
platform on a **standing sandbox env**, from operator login through the
media-workload lifecycle. Written to be executed by **someone who did not
build the platform, and who does not come from broadcast** — every beat
gives a concrete action and the expected result, and every domain term is
glossed the first time it matters, so you never have to improvise or fall
back on jargon you weren't handed.

**Provenance — read this before you present from this file.** A full
rewrite (2026-08-19, against **dmf-cms v0.24.0**, two live walks) replaced
an entirely source-derived edit that had no standing env to watch. This
edit (2026-09-02) is a **third live walk, end to end, against dmf-cms
v0.33.0** — nine releases of drift since the rewrite — done beat by beat
against the standing env, correcting every observed divergence rather than
re-deriving from source. Where this walk didn't re-touch a beat the
0.24.0 walks already confirmed and nothing since suggested had changed, that
earlier confirmation stands; where this walk found real drift (mostly a
console-wide copy sweep and a "throbber" redesign of every in-flight job
screen, both landed after 0.24.0), the text below reflects **only what was
observed on 2026-09-02**, not source-inference. UI copy quoted below is
transcribed directly from the live DOM, not typed from memory. Claims
stated as plain fact were observed live at least once, most as of this
round specifically — anything still marked *(carried forward)* survives
unconfirmed from an earlier edit and is not contradicted by anything any
round has found. What no round has yet covered is concentrated in §9.

Three things changed shape since the last edit, which is why this is a
rewrite rather than a touch-up:

1. **The route contract.** A media workload now resolves to three distinct
   URLs — a home page, a guided-flow page, and a compatibility redirect —
   replacing the single-page-that-changes-meaning model the last edit
   described. See "Three URLs, one workload," below.
2. **The rail dropped a key.** The guided flow's rail is five steps now, not
   six — **Operate is gone as a rail entry entirely**, not renamed or moved.
3. **Configure gained a forward exit.** With Operate off the rail, Configure
   needed its own way to send you to the live view; it now has one (§5).

**Scope note.** The console's demo catalog is still **one template** —
provisioning it launches a *topology* of three pieces (a receiver plus two
sources), not a single one (see the glossary below). The **Switch** beat is
now a fully confirmed, working beat: this rewrite's live walk ran it end to
end, dropdown to completion (§5) — the first time in this runbook's history.
This runbook is part of the v0.2 presentable-journey track
([dmfdeploy/dmfdeploy#200](https://github.com/dmfdeploy/dmfdeploy/issues/200),
[#347](https://github.com/dmfdeploy/dmfdeploy/issues/347)) and its exit
criterion is a named outsider completing this journey **unaided**
([#383](https://github.com/dmfdeploy/dmfdeploy/issues/383)) — that is who
this file is written for, not just a presenter narrating to a room.

**Assumes:** a standing env is already deployed and healthy (bring-up is
[`dmf-deploy-quickstart.md`](dmf-deploy-quickstart.md) — *not* repeated here).
This runbook starts at "the cluster is up; now show it off."

**Scope note (operator decision, 2026-09-02):** this runbook deliberately
does not cover environment stand-up, and that is not a gap in this file —
it's a scoping choice. Env bring-up is a separate, already-validated
workflow (the `dmf-init` bring-up flow), tested and confirmed on its own
track; folding it into this file would test two different things with one
document and make neither easier to maintain. If you're starting from
nothing (no standing env at all), stop here and run bring-up first — this
file assumes you're past that point already.

**Intent model:** `docs/processes/README.md` (BPMN 2.0 — a standard
process-diagram notation) for *why* each beat exists; this file is the *how*
to present it.

---

## Terms you'll meet on screen

Read this once before you start. Every term here shows up as real UI copy or
a real automation concept somewhere in the journey below — this is not
background reading, it's a lookup table for words the console itself uses
without stopping to explain them (Console UX Constitution Art. 3: keep
industry vocabulary and explain it in place; treat this platform's own
internal vocabulary as unearned until it's explained too).

| Term | In one line |
|---|---|
| **Media workload** | One production's worth of pieces (here: two synthetic test-pattern sources and one receiver) that the console manages, audits, and shows a lifecycle for as a single group. |
| **Facility** | The physical/virtual site the workload runs on. This demo has exactly one. |
| **Flow** | One stream of video moving from a source to a receiver. This demo's flow is a synthetic test pattern, not a real camera. |
| **Source / viewer (receiver)** | A source *produces* a flow; a viewer (also called a receiver) *receives and displays* one. |
| **NMOS** | The broadcast-industry standard (AMWA) that lets devices discover each other and describe what they send/receive over a network, instead of a technician hand-wiring cables. |
| **ST 2110** | The SMPTE standard for carrying video/audio as separate IP streams — the transport this whole platform assumes. |
| **IS-04 / IS-05** | Two NMOS specs this platform's own "Switch" language descends from: IS-04 is discovery, IS-05 is live connection management. This console's Switch (§5) is explicitly **not** a live IS-05 switch — see below. |
| **Catalog / template** | The console's menu of things it knows how to deploy. This env's menu currently has **exactly one entry**. |
| **Topology** | How many pieces one template creates when you provision it. This demo's one template creates **three**: one receiver plus two sources. |
| **AWX** | The automation engine that actually runs the deploy/switch/teardown jobs. It is not always on — see the wake step in §3. |
| **NetBox** | The facility's own inventory system — the source of truth the console reads from and lightly writes to. The console never treats its own screen as the record. |
| **Sidecar** | A small helper process bundled with each running piece that reports its live status and preview — separate from the piece doing the actual media work. |
| **Reason / audit trail** | Every media-workload write this journey makes — Provision, Switch, Teardown, Delete permanently, Clear for deployment — requires you to type a short reason before it fires; that reason, plus who you are and what role you held, is recorded. That record is "the audit trail" — see §6b for the two places it lives and how long each actually keeps it. (The one write outside this set that the journey optionally touches — creating a passkey invitation, §1 — takes no reason and isn't part of that record; see §1's own note.) |
| **The rail** | Five steps, shown as chips on the guided-flow page: **Design → Plan → Provision → Configure → Finalise & Review.** All five names are real on-screen labels. There is no sixth "Operate" chip — the word "Operate" does not render anywhere on that page at all. See **Live view**, next. |
| **Live view** | The workload's own home page — its bare URL, no suffix. A read-only monitoring surface, not a rail step: this is where you *watch* the workload run. Every media-workload *write* this journey makes **against an already-real workload** happens on the guided-flow page instead — the one exception, the optional passkey invitation in §1, happens on Settings, not here or there. Provision itself is different again: it fires from the create wizard, before the workload is real at all — see "Three URLs, one workload," next. |

---

## Three URLs, one workload

Once a workload's identity (its **slug**, e.g. `studio-a`) exists, every
route that names it in its own URL is one of exactly three addresses —
confirmed this round by reading the router directly, not just by clicking
around. (This journey visits a fourth page too — Activity → History, §6b —
but that route is never slug-scoped; it's a browser-local log (§6b: this
browser's writes only, not facility-wide) that happens to list rows about
this workload alongside everything else, not a fourth workload-specific
address.)

| Address | What's there |
|---|---|
| `/media-workloads/<slug>` | **Live view** — the workload's home. This is where "View live" and "Open live view →" eventually send you. Read-only. |
| `/media-workloads/<slug>/setup` | **The guided flow** — the five-step rail. Every write this journey makes against an already-real workload happens here. |
| `/media-workloads/<slug>/operate` | A **compatibility redirect only**. It renders nothing of its own — it forwards straight to the bare-slug live view, and the back button doesn't bounce you back to it. Nothing in the console links here; you'd only land on it from an old bookmark. |

Keep this in mind reading §3 onward: **Provision itself fires from the
create wizard, `/media-workloads/new` — a fourth route this table doesn't
cover, since it only exists before a workload does.** Confirming it
navigates you to `/media-workloads/<slug>/setup`, which shows the
materialising handoff first and then the guided flow proper; the bare-slug
live view is reached later still, once you follow an exit control (§3's
"View live," or Configure's "Open live view →"). Three different jobs on
three different pages — create, then setup, then watch — not one page whose
meaning changes underneath you.

---

## 0. Presenter pre-flight

Do these **before** the audience is watching (or before the reader sits
down). Roughly 5 minutes.

**Placeholders.** This runbook uses `<env>` for the environment slug and
`<env-base-domain>` for the env's base domain — the console is at
`https://console.<env-base-domain>/`, auth at `https://auth.<env-base-domain>/`.
For the **standing sandbox env** the base domain is **IP-derived sslip.io**:
`<node-public-ip-dashed>.sslip.io` (the node's public IP with dots as dashes),
so the console resolves at `https://console.<node-public-ip-dashed>.sslip.io/`.
Substitute the real values from the env's operator-local notes — **never**
paste real IPs into a shared screen or chat.

**Repo paths.** The component repos are **siblings** of the umbrella. Set one
variable up front and reuse it for every command below:

```bash
# Umbrella checkout (adjust to your machine); component repos are its siblings.
export DMFDEPLOY_UMBRELLA="$HOME/repos/dmfdeploy"
DMF_ENV="$(dirname "$DMFDEPLOY_UMBRELLA")/dmf-env"      # sibling checkout
```

| Check | Command / action | Expected |
|---|---|---|
| Cluster reachable | `curl -sI https://console.<env-base-domain>/ \| head -1` | `HTTP/2 200` (or a redirect to auth — both fine) |
| Console app healthy | open `https://console.<env-base-domain>/` in a browser | login screen renders, no 5xx |
| Operator passkeys enrolled | `cd "$DMF_ENV" && bin/get-passkey-enrollment-url.sh <env>` | `confirmed passkeys: 2/2 (ADR-0028 D8, live)` |
| Demo persona has the right role | (see below) | persona holds the **engineer** role — this journey's demo persona is created with exactly that, not admin |
| AWX is asleep at rest | (informational) | expected — the first Provision click wakes it; see §3 |
| **Media namespace clean of this template (mandatory — see below)** | confirm no instance of **MXL Test-Pattern Viewer** is already deployed on this facility | Media Workloads reads, verbatim, *"No media workloads yet — they'll appear here once you create one."* — confirmed live 2026-09-02 (v0.33.0); this replaced the previous edition's quoted "No Media Function instances in your scope." string entirely, part of the same console-wide copy sweep §2 describes |

*(`HTTP/2 200` is a web server's own "yes, I'm here and working" answer —
200 is the success code; `5xx` is shorthand for the whole family of server
error codes (500, 502, …), so "no 5xx" just means the app didn't answer with
an error. Both are things you check with the `curl` command shown, not
something you'll see the audience encounter.)*

**This precondition is mandatory, not a nicety — it will block the journey
outright if skipped.** Confirmed live this round: on a clean facility, Media
Workloads shows nothing but the **Create media workload** button and the
line quoted above. With a single-entry catalog, Design reads this template's
status as **one aggregate value across all three of its member services** —
the receiver and both sources
(`src/dmf_cms/catalog.py get_lifecycle_status()` — fail-closed, no partial
success: any one service read erroring reports `error` for the whole
entry; the three services disagreeing, e.g. a genuinely partial prior
deploy or teardown, reports `unknown` rather than picking a side). Only
when **all three services agree `active`** does the aggregate itself read
`active`, and only then does the Design step's "Use this template" control
withhold itself entirely: a badge reads *"Already deployed"* and the
on-screen line is, verbatim, *"Already deployed on this facility, so it
can't start a new workload here."* (`CreateWorkload.tsx` TemplatePicker —
source-verified). There is no second template to fall back to, and
provisioning a second workload is already forbidden by this journey's own
one-workload scope above — so a facility where this template already
reads `active` doesn't just make the demo messier, it makes §2 impossible
to finish.

If you ever revisit an **already-provisioned** workload's own Provision step
later — not part of this journey's main path, but worth knowing about if a
facility isn't clean — the copy there is different again: an already-deployed
template row reads, verbatim, just *"Already deployed."*, no further
sentence, and if some member is recorded torn-down (`bootstrapped`) but not
yet re-deployed, a **Clear for deployment** button is offered. Its own
confirm-panel description reads, verbatim: *"This records the intent to run
in the facility source of truth. It shows as pending reconciliation until
something deploys it — today, that's Provision. This action does not deploy
anything itself."* **Confirmed observed, not just source-read:** a later
round's live walk exercised this control for real after a Teardown left
members bootstrapped — full detail and the exact confirmation is in §6a,
not repeated here.

Before you begin: confirm the facility is clean (ask the operator, or check
yourself once logged in — Media Workloads will tell you). If a prior deploy
is still standing, resolve it before the journey; **a successful Teardown
is now confirmed, not just mapped from source, to remove every piece —**
verified server-side against a pre-run baseline (§6a). **Updated
2026-09-02: the tag-mapping prediction below it is now also confirmed, not
just predicted** — this round revisited Design after a real Teardown and
"Use this template" was re-offered, un-gated, exactly as the mapping said
it would (full detail in §6a; this line used to say the round trip "wasn't
re-walked" and pointed at §9 — that was true through 0.24.0 and is fixed
here now that it's been walked).

(Table-row status, precisely, as of 2026-09-02. The clean-inventory row
is confirmed live this round (the string itself changed — §0's table
above). Cluster-reachable and console-healthy were both independently
re-checked this round (`curl` returned `HTTP/2 200`; the console loaded
with no 5xx). The AWX-asleep-at-rest row's underlying fact is confirmed
too, but only as of 0.24.0 — §6c's live walk that round watched AWX reach
0/0 at rest; this round didn't have cluster access to re-check it (§9). The
demo-persona-role row: source-verified against the gating code since
0.24.0 (not watched live then), and this round's own persona (see §1's
gap note) was independently observed live holding the engineer role via
its topbar avatar colour — so the row is now doubly grounded, live and by
source, just for a persona this file doesn't name. **Passkeys-enrolled has
a real gap, not just an omission:** this round did run the enrollment
check, but against `marty-mcfly` — the file's own example persona name —
while the actual walk logged in as a *different*, already-authenticated
account. The check that ran and the account that walked were not the same
account. Treat passkeys-enrolled as still unconfirmed for whichever persona
you actually use, and see §1 for why login itself wasn't independently
walked either.)

**Two operational gotchas learned since the last edit of this file** (from
[#379](https://github.com/dmfdeploy/dmfdeploy/issues/379)'s own scope — not
things this rewrite could re-derive from dmf-cms/dmf-runbooks source, so
treat them as operational folklore, not code fact):

- **AWX does not wake itself just because you ran a playbook against it.**
  It has to be woken through the autoscale `ensure-awake` seam first — a
  small internal check-and-wake call the platform makes before it trusts
  AWX to be listening (the same one the console's own Provision click uses
  — see §3). Running an ordinary operations playbook against a
  scaled-to-zero AWX **does not** wake it, and its first run will burn its
  **full timeout** — and the failure it reports will look like an SSH
  (secure remote terminal) connection-reuse hang, which has **nothing** to
  do with the real cause. If a playbook run against this env times out
  mysteriously before you've done anything else, check whether AWX was
  actually awake first.
- **Don't trust the documented `ansible_user` default.** Read it from the
  env's own inventory instead — the documented default can be wrong for a
  given standing env.

**Demo persona role.** The media-workload lifecycle at the centre of this
journey — §2 through §6 — lives on **one** rail: **Media Workloads**, and
one family of pages under it. (§1's login happens on Workspace, outside
that rail; §6b's Activity → History is reached by direct URL, not linked
from any rail either — "the whole journey" isn't literally one surface,
just its consequential middle.) Reaching the Media Workloads rail at all
needs the **engineer** or **admin** role, or membership of the
`media-engineers` group (the nav gate and the server-side gate agree — nav
visibility is cosmetic, the backend enforces the same boundary on every
read endpoint checked against directly: the grouped inventory, the
workload list, the topology read, and the mxl status/preview reads).
Underneath that one surface gate, this journey's media-workload writes
split into two different, independently-verified models — checked
against each endpoint's own guard, not assumed to be uniform:

- **Provision, Teardown, and Delete permanently require the operator role
  or above** (roles rank viewer < operator < engineer < admin) — group
  membership alone does not reach these three; a `media-engineers` member
  who is only a viewer cannot perform any of them.
- **Switch and Clear for deployment are gated the same way the surface
  itself is** — **engineer** role, or `media-engineers` group membership,
  with no operator floor. **This is intentional design, not a gap:** for
  these two writes specifically, group membership is the authority that
  scopes who can act, and the acting member's true role is still recorded,
  truthfully, in the audit trail as provenance rather than enforced as a
  second gate — a documented precedent
  ([dmfdeploy/dmfdeploy#185](https://github.com/dmfdeploy/dmfdeploy/issues/185)
  WP-B, Risk 3). A `media-engineers` viewer genuinely can Switch and
  genuinely can Clear for deployment.

The **engineer** role clears every gate above on its own — **this
journey's demo persona is created with the engineer role specifically**;
log in as that. Group membership alone is not enough for the whole
journey (Provision, Teardown, and Delete permanently would all refuse
it), and **admin is never required for anything in the main path** — the
one exception is the optional passkey-enrollment demo in §1, which needs
admin and should be skipped if you're presenting as engineer, per that
section's own note.

If passkeys show `0/2` or `1/2`, complete
[`passkey-enrollment.md`](passkey-enrollment.md) **before** the demo — do not
try to enrol a first passkey live; the ceremony has authenticator-choice
pitfalls that runbook covers in full.

> **PRESENTER NOTE — pacing (non-blocking).** Every beat with real latency
> now has a range from **three** live samples across two rounds (0.24.0 and
> 0.33.0), widened 2026-09-02 rather than replaced: **Provision** (§3) —
> confirm-click to the exit control turning into a live "View live" link —
> ran **30–90 s** (full convergence to a fully running workload took ~230 s
> in the third sample, a new figure); **Switch** (§5) ran **110–180 s**;
> **Teardown** (§6a) ran **90–170 s**; **Delete permanently** (§6a) stayed
> inside **30–60 s**. Narrate the wait rather than standing in silence — for
> Provision, "the platform is scaled to zero at rest; this click is
> spinning the automation plane up on demand" — so the pause reads as a
> *feature*, not a hang. These are still small samples — treat every range
> as approximate, not a promise.

---

## The journey at a glance

| # | Beat | What the audience sees | Surface |
|---|---|---|---|
| 1 | **Log in** | Passkey login as a demo persona — no password | Console |
| 2 | **Create the workload** | Name a studio, pick the one template on offer, confirm where it runs | `/media-workloads/new` |
| 3 | **Provision** | One click → automation plane wakes → three pieces go Running together | `/media-workloads/new` → `/media-workloads/<slug>/setup` |
| 4 | **Live view** | Live tiles for all three pieces — the workload's own home page | `/media-workloads/<slug>` (bare slug) |
| 5 | **Switch** | Re-point the receiver from one source to the other | `/media-workloads/<slug>/setup` → Configure |
| 6 | **Finalise & Review** | Two possible endings — tear down, or delete permanently — plus the audit trail | `/media-workloads/<slug>/setup` → Finalise & Review; Activity → History |

**One workload only.** This journey deliberately walks **one** media
workload through the full lifecycle and stops. With a single-template
catalog, provisioning a **second** workload can collide with inventory
records the first one already created — a known limitation of the
single-template catalog, out of scope for this demo. **Do not create a
second workload, on camera or off it.**

---

## 1. Log in

Passkey **enrollment must be done beforehand** — the persona needs 2/2
confirmed devices before you start. That is §0's own pre-flight check. The
full ceremony lives in [`passkey-enrollment.md`](passkey-enrollment.md).
This beat is just the login, on the assumption that check already passed.

**VERIFICATION GAP, stated plainly rather than left implicit: no round of
this file has independently walked the actual login ceremony.** The 0.24.0
walk started from an already-logged-in session. The 2026-09-02 walk did
too, and found one already authenticated in the operator's own browser —
neither round clicked **Sign in** and completed a fresh WebAuthn ceremony.
The **Action** and the first sentence of **Expected result** below (landing
on Workspace, no password typed) are therefore still *(carried forward)*,
unconfirmed by any live walk to date — not merely unmentioned, genuinely
untested. This isn't a gap either round could easily have closed: WebAuthn
needs a physically present human for the Touch ID / security-key touch, so
an agent-driven walk (this file's last two rounds) inherits an existing
session rather than performing the ceremony, the same constraint that rules
out headless/CI login entirely. Filed as
[dmfdeploy/dmfdeploy#535](https://github.com/dmfdeploy/dmfdeploy/issues/535)
so the next walker knows to plan for it (e.g. run this one beat by hand)
rather than hit the same wall cold.

**What IS independently confirmed live 2026-09-02, distinct from the login
act itself: the steady-state UI once authenticated.** This round observed
the following directly, on the console, under an inherited session — real
observations of the app's current state, just not caused by watching a
fresh login happen:

**Action.** Open `https://console.<env-base-domain>/` in a private/incognito
window. Click **Sign in**. The browser offers the passkey picker; choose the
demo persona's authenticator and complete the WebAuthn ceremony — the
standard passkey handshake, no typing involved (Touch ID / security-key
touch).

**Expected result — the login act itself is *(carried forward)*, per the
gap noted above. What follows about the resulting screen IS confirmed live
2026-09-02, independent of how you got there.** You land on the Console
**Workspace** home as the demo persona (a fictitious demo identity, e.g.
`marty-mcfly` — never a real operator name). No password was typed *(this
specific claim is carried forward along with the rest of the login act)*.
The left rail is **permanently icon-only** — three icons (Workspace,
Facilities, Media Workloads), no text labels at all, each confirmed to
carry an `aria-label` naming it. *(Carried forward, not confirmed this
round: that hovering or keyboard-focusing an icon shows its name as a
**visible** tooltip — this round confirmed the accessible name a screen
reader would announce, not that a hover/focus popup actually renders; see
§9.)* A page's own name
lives in the **topbar breadcrumb**, not the rail — the same pattern the
workload's own pages use (§4). **Admin** appears as a fourth icon, below a
divider, only if the persona is an admin — this round's own persona
(engineer) confirms the **absent** half of that claim directly; the
**present**-for-an-admin half isn't independently re-tested this round
(this walk never used an admin persona). **There is no Catalog icon** —
the page still technically exists in the app, but nothing links to it any
more, and this journey never visits it (see §2 for where its job moved).
The topbar's own avatar (top-right, initials in a
role-coloured circle — purple for engineer) opens a disclosure with the
persona's display name/email, **Settings**, and **Logout**.

**New since the 0.24.0 walk: Workspace is now a live facility dashboard, not
an empty landing page.** Two count tiles (**Critical** / **Warning**, both
`0` on a healthy facility), a **"Current problems"** panel — on a quiet
facility, verbatim: *"✓ No problems — facility monitoring reports all
quiet."* plus *"Verified: the alert pipeline's always-on Watchdog signal is
arriving, so silence means healthy, not broken."*, tagged **"live · updates
in place every 30s"** — and a **"Recent changes"** panel, which is a
facility-wide feed of the actual AWX/automation jobs run against this
facility (Deploy/Teardown/etc., each with its own template name and a real
timestamp) — cross-checked directly against AWX's own job list this round
and it matches. This is a genuinely different data source from §6b's
Activity → History: that one is this **browser's own** action log; this one
is **every job run on the facility**, by anyone. On a facility where nothing
has run recently it reads, verbatim, *"Facility automation is not running —
recent changes appear when it next runs."* A presenter can point at this
panel while Provision (§3) or Teardown/Delete (§6a) run to show the same job
landing on the facility-wide record, not just the browser-local one.

> **PRESENTER NOTE — SECURITY (non-blocking).** This is the whole identity
> story in one gesture: **passkey-only, no passwords**
> ([ADR-0015](../decisions/0015-dmf-console-passkey-only.md)), and the platform
> mandates **≥2 confirmed devices per human**
> ([ADR-0028 D8](../decisions/0028-identity-and-authority-chain.md)) so a lost
> authenticator never locks anyone out. To *add* a device you use the
> Console's Settings → *Create new device invitation* (self-service); full
> procedure in [`passkey-enrollment.md`](passkey-enrollment.md).

If you want to show enrollment itself (optional, adds ~2 min, **requires an
admin persona** — the invitation endpoint is admin-gated, so an engineer
persona gets a 403; skip this beat if you're demoing as engineer): user menu
→ **Settings** → **Passkey Enrollment** → **Create new device invitation** →
a single-use URL + QR renders. Don't complete it live unless you have a
second authenticator to hand — just show that the invitation minted.
*(Carried forward from the previous edit, not independently re-verified this
round.)*

---

## 2. Create the workload — Identity, Design, Plan

This is where the old "open Catalog" beat lives now. There is no separate
Catalog page in the journey any more — naming and choosing a **media
workload** (see Terms, above) is one guided flow.

**Action.** From the icon-only rail, open **Media Workloads**. On a clean
environment the page reads, verbatim, and confirmed live 2026-09-02
(v0.33.0 — this string changed since the 0.24.0 walk, see §0):

> No media workloads yet — they'll appear here once you create one.

(If it doesn't — if a tile is already there — stop and resolve it per §0's
mandatory precondition before continuing; Design, next, will not let you
select the template past an existing active deploy.)

Click **Create media workload** (top-right, blue). This opens
`/media-workloads/new` — a step-by-step wizard, now with its own intro line,
verbatim: *"Studio identity, template, and facility placement for a workload
that does not exist yet — Provision is what creates it."*, plus a **Start
over** control. **There is no chip-row rail on this page** (that only
appears once the workload is real, and even then it lives on the workload's
own `/setup` page, not this one — §3 onward) — each step instead shows a
small numbered header (e.g. **"1 · Design"**) with a status badge that reads
**Now** while you're on it and **Done** once you've completed it, plus
**Previous**/**Next** at the bottom. Work through it in order:

**Studio name** is the human-friendly name for *this* workload —
distinct from the **Facility** it runs on, and distinct from the
workload identity (the slug) that's derived from it, below.

**Step 1 — Identity.** Two fields, and they start out linked, source-verified:
type into **Studio name** (free text, placeholder *"e.g. Studio A"* — the
placeholder itself is unchanged since 0.24.0, confirmed live) and
**Workload identity** below it — a `workload:`-prefixed field — auto-populates
from what you typed, transformed by fixed rules: lowercased, runs of spaces
or underscores turned to a single hyphen, anything else stripped, leading
and trailing hyphens trimmed, capped at 40 characters (e.g. "Studio A"
proposes `studio-a`). A small helper line under Studio name now gives a
worked example, verbatim: *"Used to derive the workload's identifier —
'UI Review Studio' becomes 'ui-review-studio'."* This is a **proposal, not
a hidden derivation** — the platform's own stated principle for this field:
the identity is shown and editable the whole time, never computed somewhere
out of sight, and the moment you edit it directly it **detaches** — further
edits to Studio name stop touching it from then on. The identity showing
when you advance, auto-derived or hand-edited, is the literal value the
platform records. If it isn't valid (lowercase letters, digits, hyphens;
can't start or end with a hyphen; 40 chars max — the identity field's own
rule, not the Studio name's, which takes any free text), a red hint says so
*(this round didn't type an invalid identity to trigger it — carried
forward, not observed 2026-09-02)*.
An amber note states the honest limit up front — **wording changed since
0.24.0**, now more precise about what actually gets recorded, verbatim (confirmed
live 2026-09-02): *"This draft lives only in this browser tab until Provision
runs — refreshing or closing the tab before then loses it. Provision records
the workload identifier only; the studio name above is never stored
anywhere."* A further inline line appears below the fields before you've
typed anything: *"This is the first step. Enter a studio name that resolves
to a valid workload identity to continue."* Enter a Studio name, confirm or
edit the identity it proposes, and click **Next →**.

**Step 2 — Design.** This is the console's whole **catalog** (see Terms) —
today, **one entry**: **"MXL Test-Pattern Viewer"** (confirmed live
2026-08-19 and again 2026-09-02, byte-identical both times, and matches
`display_name` at `dmf-media catalog/mxl-videotest-view.yaml:2`), with a
**"Use this template"** button (confirmed both live and against source).
The console renders this card's summary from `entry.summary`
(`CreateWorkload.tsx:571`) — that literal text lives in dmf-media's catalog
data, not dmf-cms's own source, but dmf-media is readable too, and its
committed value reads, verbatim, unchanged across both rounds: *"Media
eXchange Layer consumer for the cross-host fabrics demo: the receiver
target exposes the received flow and preview from the paired source over
libfabric tcp. This is the view / receiver half of the split demo."*
(`dmf-media catalog/mxl-videotest-view.yaml:4-6`; the console applies no
transform to it, so what's committed there is what renders). In plain
terms: "libfabric
tcp" just names the low-level networking transport carrying the test video
between pods (a "pod" is the cluster's own unit of one running piece — each
of this workload's three pieces runs in one), and "cross-host" means it
still works when those pods land on different nodes — the part that matters
for you is simpler than either:
this is the one thing you can deploy, and it is the **receiving** half of a
source/receiver pair — provisioning it also brings its two sources along
for the ride (that's the "topology" from Terms, above; more in §3). Click
**Use this template**.

> **PRESENTER NOTE — jargon on this screen (non-blocking, but real).** That
> summary sentence is quoted, not paraphrased, and it is denser than this
> runbook's own glossing standard allows — "libfabric tcp" and "cross-host
> fabrics demo" aren't explained anywhere on screen. This rewrite treats
> that as **evidence the surface itself needs a plainer summary**, not
> something to paper over here; it's flagged for the surface owner rather
> than fixed in this file. If you're asked what it means: it's the piece
> that receives and displays the test video the two sources produce.

**Step 3 — Plan.** A single sentence — *"This workload will run on
`<site name>`."* — with a **Confirm placement** button, both confirmed
against source and against the live walk. This is a confirmation, not a
choice: the standing env has exactly one facility, and there is no
workload-to-facility field to pick from anywhere in the platform. *(This
sentence is specific to a still-being-created workload's own draft flow; an
already-provisioned workload's own Plan step shows different content — a
facility link, device count, and a capacity comparison, no confirmation
button — and is not part of this journey.)* Click **Confirm placement**,
then **Next →**.

Clicking **Next** again lands you on **Provision** — that's §3, next. If you
click ahead to **Configure** or **Finalise & Review** out of curiosity, each
renders only its own locked reason — two distinct strings, not one merged
sentence *(carried forward, not re-quoted this round)*:

- Configure: *"Locked for the whole draft — nothing has been provisioned
  yet, so there is nothing to configure."*
- Finalise & Review: *"Locked for the whole draft — nothing has been
  provisioned yet, so there is nothing to finalise or tear down."*

Nothing runs yet, so there is genuinely nothing else to show.

---

## 3. Provision — the click that wakes the platform

This is the signature beat: **one console click drives the whole actuation
chain** — wake the automation plane, run a real job, materialise **three**
pieces of the workload at once, and hand you off from the draft you've been
editing to the workload's own guided-flow page.

**Action.** On the Provision step, before you even click anything, a static
intro now sits above the button — **new since 0.24.0**, under a
**"Provisioning methods"** heading, verbatim: *"Provision now — Launches MXL
Test-Pattern Viewer immediately via the AWX launcher, recorded as
workload:`<slug>`."* ("methods" is plural — there is still only the one.)
Click **▶ Provision now**. A confirm panel opens, title and description as
two distinct pieces of copy — title, verbatim: *"Provision this workload
now?"*; description, verbatim: *"Deploys MXL Test-Pattern Viewer via its AWX
job template and records it as workload:`<slug>`. Operator-gated: your
reason is recorded in the audit trail."* Type a **reason** — the textarea
placeholder says why, verbatim: *"Reason (required, recorded in the audit
trail)"* — and click **Confirm provision** (disabled until you've typed
something). This confirm panel's own copy is unchanged since 0.24.0,
confirmed live both rounds; only the step's static intro above it is new.

**Expected result — watched happen, live, on 0.24.0 and again on 0.33.0
(2026-09-02) — the in-flight screen was rebuilt between the two rounds (a
"throbber" redesign) and its copy changed; read the whole block below as
current, not the 0.24.0 wording.**

1. **The click wakes the automation plane.** The console calls the same
   `ensure-awake` seam §0's operational note describes, before launching —
   the click itself is the wake, no separate trigger. AWX is scaled to zero
   at rest. *(Mechanism is source-derived — you can't watch a wake-up call
   directly — but the wait it produces is exactly what was timed below.)*
2. **One job launches three pieces, not one.** Because the single template
   is a *topology* (Terms, above), this one AWX job stands up the receiver
   **and both of its sources** together — a colour-bars ("SMPTE") pattern
   source and a checkerboard-pattern source, each a separate piece the
   console will track.
3. **The click also moves you off the draft.** Confirming does two things at
   once: it kicks off the deploy, and the browser navigates to the real
   workload's own guided-flow page, `/media-workloads/<slug>/setup` — you
   leave the `/media-workloads/new` draft URL behind for good at this point,
   even though the deploy itself hasn't finished.
4. **A "Provisioning" screen holds the middle, and two things happen while
   it's up that are worth keeping separate — they're independent signals,
   and neither one predicts the other.** The page breadcrumb/heading area
   still says **"Provisioning"**, and the panel below it now carries its own
   sub-heading, verbatim, **"Provisioning under way"**, plus a **live
   elapsed-time counter** (ticks in seconds, then minutes:seconds — confirmed
   watched live, 1s through past 1m20s) and a new guidance line, verbatim:
   *"Typically takes a few minutes."* A further new line ties this screen to
   §1's Workspace dashboard, verbatim: *"It shows up on Workspace while it
   runs, and in Media Workloads once it's recorded."* Below that, **"Deploy
   accepted."** (unchanged since 0.24.0), an operation id, and — new since
   0.24.0 — a **milestone-step label** under the op id (confirmed live:
   *"Waking automation"*), plus a job number once the job is assigned one —
   all for your own reference if something needs escalating, not something
   to read aloud.

   One signal is **the screen's own exit control**, which renders as
   **inert text, not a link** while the launch operation/job is
   non-terminal. **Wording changed since 0.24.0** — it no longer ends with
   "wait for its outcome"; confirmed live 2026-09-02, verbatim, it now reads
   just: *"View live — The launch job is in progress."* That
   text tracks job/operation terminality directly
   (`WorkloadMaterializing.tsx`) — nothing to do with whether the
   workload's record has shown up anywhere yet.

   The other signal is **the screen swap itself**, to the real guided-flow
   page. That's driven by a separate poll of the facility's workload
   inventory, and the screen is replaced on the first poll read that
   contains the record — not at the instant the record is written. The
   launcher writes that record **part-way through the job**, not only once
   it settles — the screen's own copy now says so in full (worth quoting
   complete rather than with "…", confirmed live 2026-09-02): *"This
   workload appears here once the launcher records it against the identity
   workload:`<slug>` in the facility source of truth. The launcher does that
   PART-WAY through the job below — not when the deploy was accepted, and
   not only once the job ends — so it can show up here while the job is
   still running, and an empty inventory in the meantime is expected rather
   than a missing workload."* **Timing re-measured 2026-09-02: the screen
   swap itself landed at ~85–90 s** this round — at or past the top of the
   0.24.0 walk's quoted 30–60 s range, not clearly inside it; treat the
   range as **30–90 s** pending a fourth sample. **Full convergence (all
   three pieces reading `active`/`running` on the Live view, §4) took
   materially longer — ~230 s (about 4 minutes) this round** — the new
   "Typically takes a few minutes" copy fits that number, not the
   screen-swap number; the two were never the same thing, but this is the
   first time this file gives a figure for full convergence specifically.

   **New, undocumented before this round: in the gap between the screen
   swap and full convergence, the real workload's own Provision step can
   show "Clear for deployment" controls for the not-yet-active sources** —
   visually identical to §6a's post-Teardown landing, but this is a workload
   on its first-ever deploy that was never torn down. Confirmed transient
   and benign this round (re-polled every 15s; it resolved on its own once
   the job actually finished) — narrate it as "still converging" if you see
   it, not as a problem.

   Because these two signals are independent, don't narrate an order
   between them — all orderings are reachable, including an active "View
   live" link on a screen still reading "Provisioning" / "Deploy
   accepted." (source-confirmed by a test that settles only the job,
   leaves the inventory empty, and still gets the link).

   The guided-flow page you land on has *its own*, separate exit
   control — tracking only jobs *it* starts, blind to whether the launch
   job handed off to it is still running. So on that page too, **"View
   live" can already be an active link**, and its heading can already
   read **"`<slug>` — Setup"**, while that job is still in flight. Its
   topbar breadcrumb confirms this a different way: **"Media Workloads /
   `<slug>` / Setup"**.
5. **An active "View live" link means you can navigate there — not that
   the destination is ready.** Following it takes you to the workload's
   home page — but what's there depends on how far the record has
   gotten, and the earliest case is no record at all: land before the
   launcher has written it into NetBox and home renders its own
   **"Workload not found"** heading instead, with a companion line —
   quoted here with single quotes since the string itself contains
   double quotes — reading: 'No workload named "`<slug>`" is in your
   scope right now.' (`WorkloadHome.tsx`). *(The string itself is
   genuinely confirmed live 2026-09-02 — it's the exact one Delete
   permanently lands on, §6a. This specific SCENARIO — following an
   active "View live" link early, mid-Provision, before the record
   exists — was not deliberately re-triggered this round; that half of
   this point is carried forward.)* Once the record exists, home
   only renders §4's monitoring view once it reaches Operate
   (`lifecycle === 'operate'` internally); short of that it shows a
   "Continue setup" panel or an unresolved-status notice instead, not
   §4's three tiles — **the "Continue setup" panel specifically was
   observed this round**, during the gap before full convergence (see
   the mid-convergence transient note above); the unresolved-status
   notice was not. If you follow the link early and land on any of
   these three, that's expected — but waiting it out only converges if
   the launch is actually succeeding. If it isn't, the tell is back on
   the Provisioning screen (§3): a failed job replaces "Deploy
   accepted." with "The launch job for this workload did not succeed."
   *(not exercised this round — this walk's own Provision succeeded)*,
   and the failure copy then tells you which of two things happened: a
   launch that never started, where nothing was recorded, or a job that
   failed after starting, where the record may or may not exist and the
   screen says it cannot tell which. Already navigated away before seeing
   that? Check the Media Workloads collection view — a failed launch is
   not something to keep waiting on.

**(Pod-level convergence not independently re-watched this round — watching
the pods (Terms-adjacent: see §2's gloss) converge means watching each of
the three go from starting to actually Running, one layer below what the
console itself reports. The live view, §4, later confirmed all three pieces
reached a running state either way, which is the outcome that matters for
the demo. The rest of this box is entirely optional and strictly for an
operator with cluster access — skip it if that's not you. If you want the
terminal proof too: `ssh` opens a secure remote terminal onto the node;
`kubectl` is the standard command for asking a Kubernetes cluster — the
platform this all runs on — what's happening inside it. SSH target and
`ansible_user` per §0's second gotcha:)**

```bash
# Optional live proof (operator terminal — needs cluster access, not
# something the presenter or audience will see or need).
ssh <ssh-target> 'sudo k3s kubectl get pods -n mxl -w'
```

> **PRESENTER NOTE — ARCHITECTURE (non-blocking).** **AWX is the *actuator*,
> not the runtime.** It provisions the workload and then gets out of the
> way: the media workload runs decoupled from AWX's own wake/sleep cycle —
> you'll see this made concrete in §6.

> **PRESENTER NOTE — SECURITY (non-blocking).** The reason you typed is not
> cosmetic: **every media-workload write on this journey's path is
> reason-required** — a missing/empty reason is refused before any AWX
> call — and the reason is recorded in the audit trail: actor, effective
> role, request id, reason. Provision's own attribution lives in the
> server's structured log, not in Activity → History — that surface is
> browser-local and, per §6b, never gets a row for this journey's
> Provision at all. What you'll read back in §6b are the journey's later
> browser-recorded actions instead (Switch, Teardown, Delete permanently).

If you ever need to re-run Provision on a workload that **already exists**
(not part of this journey's path), the button, panel copy, and confirm-label
are all different from the draft flow above — see §0's note on "Already
deployed." and **Clear for deployment**.

---

## 4. Live view — the workload's home

Once you've navigated here — whether you followed **View live** from the
Provisioning screen (§3) or opened `/media-workloads/<slug>` directly —
what's on screen depends on how far the workload's record has gotten
(§3's note on the exit link applies here too, including its earliest
case: no record yet, and home's own "Workload not found" state instead
of a home page at all). Once a record exists, you're on the workload's
**home page**, not a step in the guided flow, and the rest of this
section describes what's on screen once it reaches Operate. This is the
bare-slug route from "Three URLs, one workload," above; nothing here is
clickable in a way that changes state, and the page is deliberately
read-only.

**Page identity, confirmed against source.** The browser tab reads,
verbatim, **"`<slug>` · DMF Console"** — no further suffix. The page's own
name lives in the topbar breadcrumb, not visible header text — a
screen-reader-only heading carries the same `<slug>` text in the DOM,
matching this app's pattern elsewhere (§1).

**Expected result, once the workload has reached Operate — confirmed live
both 2026-08-19 and 2026-09-02, byte-identical.** The page opens with a line
of intro copy, verbatim: *"The monitoring surface for this workload —
observed running state only. Changes are requested at the flow's own
steps, not from here."* That's the whole thesis of this page in one
sentence: watch here, act on the guided flow.

- **Three tiles**, each pairing a friendly title with the raw identifier as
  a smaller line beneath it — the title/identifier pairs, source-confirmed
  (not re-screenshotted this round): the receiver reads **"MXL Test-Pattern
  Viewer"** over `mxl-videotest-view`; the two sources read **"MXL
  Test-Pattern Source · source-a"** over `mxl-videotest-view-source-a` and
  **"MXL Test-Pattern Source · source-b"** over `mxl-videotest-view-source-b`
  — all showing **active/running** once Provision has finished. The raw ids
  genuinely appear on the tile, just as the smaller identifier line, not as
  the title (`WorkloadTile.tsx`: the friendly name renders as the tile's
  title, `instance.instance` as a mono line beneath it); that identifier is
  the NetBox service name the launcher creates per source,
  `"<release>-<source id>"` (`dmf-runbooks`'s `l3_topology_release_group`,
  concretely `mxl-videotest-view-source-a` / `-source-b` for this catalog
  entry — confirmed against dmf-cms, dmf-media, and dmf-runbooks source
  together, not assumed from the naming pattern alone). Worth the irony
  check: §4's own presenter note below credits umbrella #401 with replacing
  raw slugs with friendly *names* on this tile — that's the title half; the
  raw identifier staying visible underneath is the intended design, not
  something #401 missed.
- **The viewer's tile is captioned, verbatim, "Live · sidecar preview"** —
  the caption text itself reconfirmed live 2026-09-02. The measurement
  behind "it delivers on that caption" is older, not repeated this round:
  a two-hour access-log sample against the live env (0.24.0-era), **2033
  successful preview fetches against 49 failures — a 97.6% success rate**,
  with the rare single-tick failure recovering on the very next poll. This
  round's own walk saw the preview area render without incident on every
  page load it made, consistent with that number but not a re-measurement
  of it. The preview genuinely works; don't undersell a working feature by
  hedging on it.
- **Both source tiles read, verbatim, "Sidecar live · no preview on this
  side"**, next to a small placeholder that renders, in caps, **"NO
  PREVIEW"** (the underlying label is lowercase; the console styles it
  uppercase). This is **by design, not a defect or a limitation**: a source
  *produces* the pattern and has nothing incoming to preview, so the
  platform says so rather than faking one — confirmed intended, not a gap
  to apologise for on stage. All three tiles, viewer and both sources alike,
  render in the same shared tile template; that's the intended presentation
  too, not a fallback.
- An **active-source panel** lists both sources by pattern, verbatim format:
  **"source-a (smpte)"** and **"source-b (checkers-8)"**. A separate section
  immediately below it, **"Request a configuration change"**, carries a
  **"Go to Configure →"** link — that's your way to §5.
- **New since 0.24.0, the string itself confirmed live 2026-09-02:** a tile
  whose browser tab has lost foreground visibility shows **"Paused — tab
  not visible"** next to its sidecar caption. (The mechanism named here —
  the Page Visibility API pausing the preview poll to save resources — is
  the obvious read of that string and consistent with it, but is inferred,
  not confirmed against source or by deliberately toggling tab visibility
  and watching the poll stop; don't cite it as a source-checked fact.)
  Don't read a paused tile as broken if you've tabbed away mid-demo; bring
  the tab back to the foreground and it resumes.

**Confirmed live 2026-09-02 (previously carried forward, unconfirmed).**
Clicking a tile opens a larger live-detail modal with the same nine
flow-stat fields as before — head index, latency, format, grain rate, role,
provider, MXL version, Active, and Node (NetBox) — still ticking roughly
5×/s while open, copy unchanged.

**A lifecycle-stage badge does exist, and this round independently observed
three different values of it, all on the guided-flow (`/setup`) page's own
header** — **"provisioned"** (right after Provision, §3), **"configured"**
(after a successful Switch, §5), and **"planned"** (post-Teardown, §6a). A
fourth value, **"finalizing"**, is documented separately (§6a) as appearing
while a Finalise & Review job is actually running — **that one is carried
forward from 0.24.0 specifically, not re-observed this round**: this
round's own Teardown was polled for exactly that string, among others, and
it never matched in any poll iteration, so treat it as unconfirmed since
0.24.0 rather than reconfirmed. Whether an equivalent badge also appears on
**this** page —
the bare-slug live view — is still not confirmed either way; the previous
edition's guessed "planned" / "provisioned" / "configured" vocabulary for
the live view specifically turns out to match real values observed
elsewhere on `/setup`, but that's not the same as confirming the live view
shows one too — still open, see §9.

> **PRESENTER NOTE — the false catalog warning is BACK (umbrella#401
> regressed, or never fully covered this state — see
> [dmfdeploy/dmfdeploy#532](https://github.com/dmfdeploy/dmfdeploy/issues/532)).**
> Earlier editions of this runbook flagged a false warning on the Design
> step, telling the reader the two topology-spawned sources' function keys
> weren't in the current catalog and may have been removed — untrue, since
> neither was ever meant to have its own catalog entry. The 0.24.0 rewrite
> reported this fixed (dmfdeploy/dmfdeploy#401, merged via dmf-cms#97) but
> flagged it as "not re-confirmed live" that round. **This round confirmed
> it live, and it's back:** on `runbook-walk`'s own Design step, post-
> Teardown (both sources reading `0/1 instance`), both
> `mxl-videotest-view-source-a` and `mxl-videotest-view-source-b` showed,
> verbatim: *"This function key isn't in the current catalog — it may have
> been removed since this workload was deployed."* Whether this is a
> regression of #401 or a state #401's own fix never covered (freshly
> torn-down/bootstrapped members specifically) isn't established here —
> that's for dmfdeploy#532 to determine. Don't tell an audience this is
> fixed; if you hit it, it's cosmetic (the two sources still deploy and run
> correctly regardless of what Design says about their catalog membership),
> so narrate it as a known rough edge, not a failure.

> **PRESENTER NOTE — MONITOR (non-blocking).** The Console's own
> **Monitoring** rail is the at-a-glance facility health view; the tile
> preview answers "is my media flowing?" directly — and, per the viewer
> tile's own confirmed reliability above, actually answers it. For deeper
> telemetry, **Grafana** is fed by the cluster's monitoring stack — open it
> in a second tab if the audience wants metrics/alerting depth.

> **PRESENTER NOTE — SECURITY (non-blocking).** The Media Workloads surface
> is **hard-gated server-side**, not just hidden in the nav: reaching it —
> even the read — requires the **engineer/admin** role **or** membership of
> the `media-engineers` group. An **unauthenticated** request gets **401**; a
> **plain viewer** (below engineer, not in `media-engineers`) gets **403 on
> the whole surface** — the rail is hidden for them too. Writes additionally
> require a non-empty **reason** → **400** without one.

---

## 5. Switch — re-point the receiver's source

This beat now has a **confirmed, end-to-end, working run** behind it — the
first time in this runbook's history. It lives on the **Configure** step of
the guided flow, not on the live view: the live view is deliberately
read-only and only links out to this step.

**Action.** From the workload's `/setup` page, click the **Configure** chip
(or follow "Go to Configure →" from the live view, §4). Configure is the
rail's last working step — it has **no Next button**; its own footer says
why, verbatim: *"There is no next step to configure. Finalise & Review stays
reachable at any time from the steps above."* Its own forward exit points
the other way, back toward the page you probably just came from, verbatim:
*"A trusted read reports this workload operating. Open live view →"*,
linking to the bare-slug live view (§4). Every string in this paragraph is
confirmed both live and against source.

Under **Source · `<receiver instance>`**, the current active source is shown
in mono text (e.g. `source-a`). Click **Switch source**.

**Expected result — the arm panel, confirmed live both 2026-08-19 and
2026-09-02, byte-identical.** Title,
verbatim: *"Switch active source"*. Description, verbatim: *"Coarse
reconfigure/reconnect actuator — not a live IS-05 switch. Re-points this
viewer to a different source and is recorded in the audit trail with your
reason."* In plain terms: this is **not** the instant, frame-accurate
crosspoint a real broadcast IS-05 switch (Terms, above) performs — it's a
slower, automation-driven re-point that genuinely restarts the receiver
against the new source. The **Target source** dropdown lists only the
*other* source (e.g. `source-b (checkers-8)` if `source-a` is currently
active) — confirmed this round to exclude whichever source is currently
active, by design, not by omission. Type a reason; **Confirm switch** stays
disabled until both a target is chosen and a reason is typed.

**Expected result — after confirming, confirmed live twice.** 0.24.0's walk
measured **150–180 s**; this round's sample (2026-09-02) completed in
**~114 s**, faster than that whole range, not just its edge — widen to
**~110–180 s** rather than trust either single number. On success, the
Configure step's own outcome line reads, verbatim, **"Active source:
source-b"** (or whichever
source you targeted). **The live view (§4) confirms the same change, but in
a different format — don't quote the same string there:** its own **"Active
source"** heading (no colon, no value in the heading itself) sits above the
new value on its own line, next to the same per-source list §4 already
describes (**"source-a (smpte)"** / **"source-b (checkers-8)"**) — a bare
value, not a composed sentence.

Per dmf-runbooks' switch playbook, this runs three phases — quiesce the old
source (a graceful pause, not a hard kill: let it finish what it's doing
before letting go), re-point and restart the receiver, then select the new
source — with a verified rollback (reverting to the last known-good state)
if the restart doesn't come up cleanly. That mechanism *(mapped from source,
not watched failing)* is consistent with a run this long: this is a **pod
restart** — the receiver's own running piece stopping and starting again,
not the whole platform — not an instant cut, which is exactly why the
description above disclaims being "a live IS-05 switch." Don't panic if the
tile goes quiet for a while.

**(Not exercised this round — carried forward from source reading only.)**
On failure, the platform automatically rolls the receiver back to its
previous source and still reports the switch as **failed** — a switch that
didn't reach its requested target never reports success, even if a rollback
saved you from a broken state. On success, a **System details** disclosure
names the request id.

---

## 6. Finalise & Review

Close the loop. This is the one beat with a genuine **fork**: teardown alone
is not the only ending. Confirmed live twice (2026-08-19, 2026-09-02) —
Teardown, Delete permanently, and the audit trail were all walked start to
finish both rounds. This round also **opened and inspected** (not
confirmed/completed) Clear for deployment's own confirm panel, and
**observed rendered** (not clicked) the inline redeploy "▶ Deploy" button
(§0), on the same workload, before deleting it — deliberately stopping
short of running either, to keep the one workload this journey allows
(§0) available for Delete permanently rather than spending it on a second
redeploy cycle that would add no new information over §3's own Provision
walk.

**6a. Three sections, confirmed live both rounds: Teardown, Delete
permanently, Review.** The Finalise & Review step's own body renders as
three small labelled sections — **TEARDOWN**, **DELETE PERMANENTLY**,
**REVIEW** (the console styles them uppercase; the underlying text is
title-case, same NO-PREVIEW-style CSS transform as §4's placeholder) — not
a simple two-way fork as the previous edition described from source alone.

**Before any teardown has run** (something is still active), Delete
permanently is gated and reads, verbatim: *"Delete permanently isn't
currently offered — see the rail state above."* A different string covers
the separate case where nothing has ever been provisioned at all, verbatim:
*"Nothing is running yet, so there is nothing to finalise."* Don't conflate
the two.

**Teardown.** Click **⏏ Teardown** (per catalog entry — here, the
receiver's own entry). A confirm panel opens, title a template — verbatim
for this entry: *"Teardown MXL Test-Pattern Viewer?"* — description,
verbatim: *"Finalises this media function via its AWX teardown template.
The action is operator-gated and recorded in the audit trail with your
reason."* Both re-confirmed byte-identical 2026-09-02. **Confirm teardown**
stays disabled until a reason is typed, same placeholder as elsewhere.
While the job runs, the exit control is documented as reading, inert,
verbatim: *"View live — A Finalise & Review job is in progress — wait for
its outcome."* — **not independently re-confirmed this round** (this walk
tracked the panel's own status text instead, not this specific exit-link
string); given that §3's equivalent Provision string dropped its own
"wait for its outcome" clause between 0.24.0 and 0.33.0 (§3), treat this
one as **likely also stale** and confirm on the next walk (§9) before
quoting it on camera. During this window the workload's lifecycle badge is
documented (0.24.0) as reading **"finalizing"** (genuinely American
spelling — an inconsistency with the British "Finalise" used everywhere
else on this same page, not a transcription error in this runbook). **Not
independently re-confirmed 2026-09-02**, despite an earlier draft of this
edit claiming it was: this round's own Teardown was polled repeatedly for
exactly this string among others, and it never appeared in any poll's
captured text — either the polling window missed it, or it's changed.
Treat as carried forward from 0.24.0 only; confirm on the next walk (§9).
**Duration: 90–120 s (0.24.0 sample), 167 s (2026-09-02 sample) — widen the
range to ~90–170 s**, not a promise either way.

**The removal half of the round trip is now confirmed, not just mapped
from source:** verified server-side against a baseline captured before the
run, three Helm releases, three pods, and three services all went to zero.
**One click here tears down all three pieces**, not just the receiver — the
runbook's long-standing claim that dmf-runbooks' teardown playbook removes
the topology's two source releases alongside the receiver's own, in the
same job, is upgraded from source-confirmed to **observed**, twice now
(2026-08-19 and 2026-09-02). **The other half is now also confirmed, not
just mapped from the tag logic:** this round revisited `/media-workloads/new`
after Teardown and Design's own "Use this template" control was re-offered,
un-gated, matching the tag-mapping prediction exactly.

Teardown leaves the record standing (recorded but not running — reusable
later). **This is source-confirmed, not inferred:** Design's gate reads
this template's status as one aggregate value across all three of its
member services (`src/dmf_cms/catalog.py get_lifecycle_status()` —
fail-closed, no partial success: any read error reports `error`; any
disagreement across the three reports `unknown`; only when all three agree
does that shared value come back), and `CreateWorkload.tsx` TemplatePicker
withholds "Use this template" only when that aggregate reads exactly
`active`. The catalog entry's `configure` action stamps each member
service `lifecycle:active` on success
(`dmf-media catalog/mxl-videotest-view.yaml:79-83`), and its `finalise`
action — `playbooks/teardown-mxl-fabrics-demo.yml` — stamps each member
`lifecycle:bootstrapped` on success
(`dmf-media catalog/mxl-videotest-view.yaml:89-93`). `bootstrapped` is not
`active`, so once every member is back to `bootstrapped` the aggregate can
no longer read `active`, and the gate clears — that's the tag logic the
paragraph above refers to.

> **PRESENTER NOTE — a real gotcha after Teardown completes
> ([dmfdeploy/dmfdeploy#418](https://github.com/dmfdeploy/dmfdeploy/issues/418),
> open, not fixed).** The 0.24.0 walk's Teardown landed back on the
> **Provision** step, unprompted, showing its desired-state panel with
> **Clear for deployment** offered for each instance — the operator did not
> navigate there. **This round's Teardown (2026-09-02) did NOT reproduce
> it** — landed cleanly on Finalise & Review and stayed there, no bounce.
> Two data points now, one each way: it can happen, it doesn't always
> happen, and no mechanism is asserted here (a source-derived explanation
> offered in an earlier draft of this note turned out to be wrong and was
> withdrawn). Narrate it as a known rough edge IF you hit it — it's
> disorienting, not dangerous, since nothing runs automatically from that
> panel without another explicit confirm — but don't expect it every time.
> Confirmed both rounds, on the **Teardown** section's own per-entry status
> line once torn down, verbatim: **"Not currently deployed."** — a status on
> Teardown's own panel, distinct from "Already deployed." elsewhere.

**Clear for deployment — the control's own appearance and confirm-panel
text are confirmed observed both rounds**, not merely source-read: because
Teardown returns every member to a bootstrapped state, this control (§0's
earlier note) is genuinely offered, and its confirm-panel description
renders exactly as source predicted, verbatim, byte-identical both rounds:
*"This records the intent to run in the facility source of truth. It shows
as pending reconciliation until something deploys it — today, that's
Provision. This action does not deploy anything itself."* No separate
"automation lane" text anywhere near it. A reason field is required here
too — present and required-looking (§0's Terms table already lists Clear
for deployment among the reason-gated writes). **The action itself —
actually clicking Confirm and watching it complete — was exercised on the
0.24.0 walk; this round opened the same panel and read its text but
deliberately stopped short of confirming it**, to preserve the one
workload this journey allows for Delete permanently rather than spend it
here. **Also confirmed
this round:** the Provision step for an already-provisioned, torn-down
workload shows the inline **"▶ Deploy"** button directly in its own body
(umbrella#518's retirement of the old promoted-action portal, dmf-cms
46d53cb) *alongside* each member's own "Clear for deployment" row — the two
controls sit on the same step, offering two different things (redeploy
everything at once vs. record intent for one member at a time).

**Delete permanently.** The real gate, source-confirmed: every member
settled to bootstrapped and not-running, plus a trustworthy read and purge
authorization — on this journey's own path, a completed Teardown is what
produces that state, but the gate itself is the member state, not
"a Teardown having specifically run." A *workload-level* action, not
per-piece. Its confirm panel is marked **destructive** (a
distinct red treatment). The title is a template, and it's keyed on the
**slug**, not on the Studio name you gave it back in §2 — that free-text
label never travels with the record this panel reads; the panel only ever
sees the slug — verbatim: *"Delete `<slug>` permanently?"* Everything else
in the panel is keyed on the slug too: a static
line, verbatim, *"Type the workload slug to confirm"*; a text input whose
placeholder is the slug itself; and, while the typed text doesn't yet
match, a hint verbatim (quoted here with single quotes since the string
itself contains double quotes): 'Type "`<slug>`" exactly to confirm — this
cannot be undone.' — plus a reason textarea. Description, confirmed live
2026-09-02, quoted here in full for the first time rather than with "…":
*"Removes this workload's residual catalog records from the source of truth
via the finalise-purge automation. The entry stops existing — there is no
rollback."* The button itself reads **"Delete permanently"** (not a separate
"Confirm" label). **Two independent gates** — the button stays disabled
until BOTH the exact slug is typed AND a reason is supplied — typing a
wrong slug alone leaves it disabled, and typing the correct slug alone with
no reason also leaves it disabled. **Confirmed by direct test on 0.24.0.
This round typed both fields together and confirmed the button then
enabled and the action worked — consistent with the gate logic, but not a
re-test of the two disabled sub-states independently** (didn't check the
button stayed disabled with only one field filled). Per
dmf-runbooks' finalise-purge playbook, this is the **only** launcher that
deletes NetBox records outright (every other launcher only flips a
lifecycle tag) — it runs under its own delete-only credential for exactly
that reason (confirmed at the AWX job-template level too this round: Delete
permanently ran as its own `media-finalise-purge` template, distinct from
Teardown's `media-finalise-<catalog-entry>`), and only declares success once
a fresh read confirms every member **and** the workload's own tag are gone.

During the job, the panel reads, verbatim: **"Deleting `<slug>`
permanently…"** — this specific line re-confirmed byte-identical 2026-09-02
(matched directly in this round's own poll output). It's also documented
as showing an operation-id line, **"op `<id>`... — running"** (the id
truncated to its first 8 characters) — **that specific line was not
independently re-captured this round**: this round's poll pattern included
it, but it never matched, unlike Provision's own op-id line (§3), which
did. Possibly just missed by the poll's timing; treat as carried forward
from 0.24.0 for the op-id line specifically, confirmed for the "Deleting…"
line. **Duration: 30–60 s (0.24.0), ~62 s (2026-09-02) — right at the edge
of the same range, leave it as-is.**

After completion, the page reads, verbatim, **"Workload not found"** at the
same `/setup` URL, with a companion line — quoted here with single quotes
since the string itself contains double quotes — reading: 'No workload
named "`<slug>`" is in your scope right now.' Confirmed again 2026-09-02,
byte-identical. A dead end: the collection view no longer lists the
workload, and the cluster is confirmed at zero pods, services, and Helm
releases (this round's own AWX job list showed the finalise-purge job
`801 — media-finalise-purge` completing Succeeded). This landing is also
part of #418 above — that issue covers both Teardown's and Delete
permanently's post-action landing.

**6b. The audit trail — Activity → History. Confirmed live both rounds.**
There is no Activity icon in the rail — like Catalog, the route still
exists, it's simply not linked from anywhere in the nav (the same S1 IA
cut). Type the URL directly:
`https://console.<env-base-domain>/activity/history`. The browser tab
reads, verbatim, **"Activity — History · DMF Console"**.

- **Expected, confirmed live both rounds, byte-identical.** The **"Console
  actions"** panel (a real heading, not this runbook's paraphrase) lists
  this browser's persisted writes — a row per action, titled in operator
  language. The **common** shape is four lines: the action line; the
  outcome and the reason you typed, in curly quotes; actor, role, and
  request id; a timestamp — this four-line shape is what this round's own
  Teardown/Switch/Delete rows show, directly confirmed. A **Clear for
  deployment** row (§6a) is the one exception this journey hits: it
  carries a genuine **fifth line**, a reconcile-expectation note, every
  time *(this specific claim is 0.24.0-only — this round deliberately
  didn't confirm a Clear for deployment action, §6a, so it never produced
  its own row to check)* — don't describe the shape as
  universal if you're demoing that control, or the row on screen won't
  match what you just said. Confirmed action-line formats: **"Tore down
  mxl-videotest-view"** (there being only one catalog entry, that string is
  also the receiver's own instance name here — don't read that as a
  coincidence the console intends), **"Switched source on `<instance>`"**,
  and **"Deleted `<slug>` permanently"**. **Not on this list: "Deployed
  mxl-videotest-view."** That action-line format exists, source-confirmed —
  but this journey's own Provision never produces the row: it fires from
  the create wizard (§3), and that wizard never calls the console-local
  recorder this panel reads from. At the audit-trail beat, there is no
  "Deployed" row for the Provision you just performed; say so plainly
  rather than pointing at the panel for a row that isn't there — reconfirmed
  again this round (this workload's own Provision left no "Deployed
  runbook-walk" row anywhere in the panel). (The backend's own structured
  log line still covers Provision — see the next bullet.) The actor line
  reads **`<persona> (<role>) · request <id>`**, with the request id
  truncated to its first 8 characters — `<role>` is a live value (whatever
  role the acting operator actually held), not a fixed label; don't quote
  it as always reading "admin" just because an admin persona happened to be
  the one testing it. **New this round:** the same job-completion facts
  also surface a second, facility-wide way — see §1's "Recent changes"
  finding on the Workspace dashboard; that one is every job on the
  facility, this one is this browser's own actions.
- **Honest scope, confirmed live both rounds, byte-identical — verbatim,
  right on the panel itself:** *"Actions taken from this console in this
  browser —
  correlated by request id. Other operators' sessions are not shown
  here."* Read that literally: it's **this browser's persisted record, not
  this session's** — the store is `localStorage`-backed, not in-memory, and
  capped at the newest 50 actions (the 51st write evicts the oldest; no
  storage-clearing involved). On an ordinary profile, that record survives
  a reload, a tab close, even quitting and reopening the browser. §1 has
  you open the console in a private/incognito window for the login beat,
  though, and that cuts the other way here: private-mode storage is
  discarded when the private session ends, so in the window this journey
  actually prescribes, the record lasts only for that session, not across
  a browser restart. What the private window *does* still buy you is a
  clean starting profile — on a reused ordinary profile, rows from an
  earlier run are still there and can read as if they belonged to this
  walkthrough. It deliberately does *not* claim facility-wide
  completeness, because the backend has no queryable audit store yet. The
  facility-wide record is the server-side structured log line the backend
  emits on every media-workload write (source-confirmed: a shared
  `_audit_awx_write` helper covers Provision/Deploy, Switch, Teardown, and
  Delete permanently; Clear for deployment emits its own equivalent line),
  which lands in Loki — bounded too, not permanent: the retention window is
  set per deployment profile, not a fixed platform default. Either way it
  is a bound, not an indefinite record. The passkey invitation in §1 is the
  one write in this journey that emits neither this log line nor a
  Console-actions row — it isn't a media-workload write, and it isn't
  covered by this record at all.

One nuance worth a sentence: the **Review** section back on Finalise &
Review — the third of §6a's three sections — reads, verbatim, *"No
teardown, switch, or delete has run yet in this session."* and is genuinely
**session-scoped local state**, not read from the server: it resets on
reload or on switching to a different workload, so it can read that way
even minutes after this page's own History shows real records for the same
session. A presenter reloading mid-demo will see it blank — don't read
that as History itself being wrong.

**6c. Autonomous re-idle (scale-to-zero) — confirmed observed, both
directions, on the 2026-08-19 walk; NOT independently re-checked
2026-09-02.** This round didn't have direct cluster/kubectl access from
where the walk was run, so AWX's own replica count before/after wasn't
re-observed — the walk instead confirmed every job (Provision, Switch,
Teardown, Delete permanently) actually ran and succeeded, directly in AWX's
own job list (cross-referenced against the Workspace "Recent changes" panel,
§1), which is consistent with AWX being awake for each job but doesn't by
itself prove it went back to zero afterward. Treat the paragraph below as
**still standing from 0.24.0**, not re-confirmed, and re-verify replica
counts specifically on the next walk (§9). By design, AWX is meant to scale
itself back to zero on its own some time after the last write, with no
operator action — the "actuates, then sleeps" story §3 sets up. **The
0.24.0 round watched both halves happen:** AWX was found at 0/0 replicas
before that round's Teardown/Delete walk began, its grace period from
earlier jobs already expired; it woke **automatically** the instant
Teardown was fired, with no
separate operator action — the same `ensure-awake` seam §0/§3 describe, and
independently confirmed generic to this codebase, with one condition
attached: dmf-cms's backend calls it on the async path every AWX-touching
write takes (deploy, teardown, switch, rollback, and finalise-purge alike,
not a Provision-only path) **when autoscale is enabled** — a sync fallback
path exists that calls AWX directly with no wake call at all, for an env
running with autoscale off. The standing sandbox env runs with autoscale
on, which is what this round actually watched happen; its wake floor
expired again after the jobs finished, returning it toward zero once
more. *(One walk's worth of observation — no grace-period or
re-idle-timing number was part of this round's report; don't quote a
duration for the idle window itself unless you time it yourself.)* What the
source has always supported, restated: **the running media pieces are
architecturally independent of AWX's wake/sleep state** — nothing in
dmf-cms or dmf-runbooks ties a media pod's lifecycle to AWX's own, so it
keeps running whether AWX is asleep or awake (the §3 architecture note,
from the same source, holds regardless of §6c).

**6d. Workload independence — an aside for *before* you tear anything
down.** This is not the next step after 6a/6b/6c in execution order — it
only works while the workload is still running, i.e. any time during §4
(Live view) or §5 (Switch), *before* you ever click Teardown in 6a. This is
a **different window** from the one §6c's re-idle observation actually
covered this round (that one watched AWX around the Teardown job itself,
by which point the workload was about to stop) — §6c confirms the
mechanism works, not that this specific pre-Teardown pairing has been
watched. Once
Teardown runs, the media pieces stop running too (6a's own note: one click
removes all three pieces), so this observation is no longer available —
don't try to make it after the fact. If, in that earlier window, you *also*
watched AWX re-idle to zero on its own (§6c) while the workload kept
running: you have the whole thesis in one frame — the platform provisions
on demand, attributes and audits every media-workload change demonstrated
here, runs the media decoupled from its own control plane, and scales the
control plane to zero when idle, at no cost to what's running. If you
never watched AWX re-idle while
the workload was still up, skip this closing beat rather than asserting
it.

---

## 7. Known rough edges (so you don't improvise)

These are **known, tracked, and non-fatal**. Knowing them means a hiccup
becomes a footnote instead of a scramble. Two prior entries stay gone from
the table below: a first-post-wake 5xx is still fixed as of the 0.24.0
release, unchallenged by this round; and a claimed viewer-preview failure
(dmfdeploy/dmfdeploy#417) turned out to be a measurement artifact — a
two-hour live-env sample logged a 97.6% preview success rate, and the issue
is closed as overstated. See §4: the preview works, and the two sources'
lack of one is by design, not a gap. **The false "not in the current
catalog" warning is back in the table below** — the 0.24.0 edition dropped
it as fixed, unconfirmed live; this round confirmed live that it recurs
(§4's presenter note has the detail and the string).

| Symptom you might see | What it is | Reference |
|---|---|---|
| The guided-flow page briefly shows an amber banner, *"`<Step>` isn't open yet: `<reason>`"*, on a step that is actually open | A latched-vs-live read race during background polling — the step really is open; the banner is stale for the length of one poll and clears itself. Cosmetic and self-clearing, but voiced aloud by a screen reader while it's up. | [dmfdeploy/dmfdeploy#416](https://github.com/dmfdeploy/dmfdeploy/issues/416) |
| After Teardown or Delete permanently completes, you may land somewhere you didn't ask for — Teardown was observed once (2026-08-19) bouncing unprompted to the Provision step's desired-state panel; **this round's Teardown (2026-09-02) landed cleanly on Finalise & Review instead, no bounce** — so it's confirmed NOT to happen every time, not fixed. Delete permanently reliably strands you on a "Workload not found" page for the workload you just removed (confirmed again this round) | A completed lifecycle action should hand you back to the workload's home or the collection view, not to an unrelated next step or a dead URL. Disorienting, not dangerous — nothing runs automatically from either landing without another explicit confirm. | [dmfdeploy/dmfdeploy#418](https://github.com/dmfdeploy/dmfdeploy/issues/418) |
| On the Design step, the two topology-spawned sources' function keys show *"This function key isn't in the current catalog — it may have been removed since this workload was deployed."* | Was reported fixed (0.24.0 edition). Confirmed back, live, post-Teardown, 2026-09-02. Cosmetic — the sources still deploy and run correctly regardless of what Design says about their catalog membership. | [dmfdeploy/dmfdeploy#532](https://github.com/dmfdeploy/dmfdeploy/issues/532) |
| Provisioned instances show up **grouped as "Unassigned"** in the grid | The launcher hasn't stamped a `workload:<slug>` tag onto every member, so the grouping logic has nothing to group them by. Cosmetic/legibility only. | [dmfdeploy/dmfdeploy#239](https://github.com/dmfdeploy/dmfdeploy/issues/239) |
| Someone asks "what if the node dies?" (spot reclaim) | Not hypothetical — it happened to this env while the previous edition of this file was being written. The standing env's addressing is derived from the node's public IP, so a reclaimed/replaced node means a new address. **There is no cluster-state backup to restore from** — the standing archive covers operator-local material only. **Recovery is re-bootstrap plus re-pointing the IP-derived address**, not a resume-in-place and not a restore. | env recovery notes (operator-local) |

> **PRESENTER NOTE — if a beat stalls.** The beats with real latency, ranges
> widened 2026-09-02 with a third sample each: **Provision** (§3, ~30–90 s
> to the screen swap; full convergence to all three tiles running took ~230
> s this round, a new figure this edition adds), **Switch** (§5, ~110–180
> s), and **Teardown** (§6a, ~90–170 s). Delete permanently stayed inside
> its previous 30–60 s range. None of this is a promise — three samples is
> still not many — but nothing here should send you off-script.

---

## 8. References

- Bring-up (deploy the standing env): [`dmf-deploy-quickstart.md`](dmf-deploy-quickstart.md)
- Passkey enrollment (full ceremony + pitfalls): [`passkey-enrollment.md`](passkey-enrollment.md)
- Identity & authority chain: [ADR-0028](../decisions/0028-identity-and-authority-chain.md)
- Console passkey-only: [ADR-0015](../decisions/0015-dmf-console-passkey-only.md)
- Media Workload entity + lifecycle derivation: [ADR-0046](../decisions/0046-first-class-media-workload-entity.md)
- Intent model (BPMN 2.0): `docs/processes/README.md`
- Demo track / acceptance: [dmfdeploy/dmfdeploy#347](https://github.com/dmfdeploy/dmfdeploy/issues/347)
  (part of [#200](https://github.com/dmfdeploy/dmfdeploy/issues/200))
- Domain-outsider exit criterion (who this file is written for): [dmfdeploy/dmfdeploy#383](https://github.com/dmfdeploy/dmfdeploy/issues/383)
- Route contract / rail amendment (why §4 is a live view, not "Operate"): [dmfdeploy/dmfdeploy#414](https://github.com/dmfdeploy/dmfdeploy/issues/414)
- This rewrite's own tracking issue: [dmfdeploy/dmfdeploy#379](https://github.com/dmfdeploy/dmfdeploy/issues/379)
- Filed from the 2026-09-02 walk: false catalog warning regression
  [dmfdeploy/dmfdeploy#532](https://github.com/dmfdeploy/dmfdeploy/issues/532),
  untimestamped stale Workspace job entry
  [dmfdeploy/dmfdeploy#533](https://github.com/dmfdeploy/dmfdeploy/issues/533)

---

## 9. Deferred verification — tracked by dmfdeploy/dmfdeploy#379

**This section is what three rounds of live walking still haven't
covered — and it stays open by design, not as a gate this runbook is
waiting on.** The first round (0.24.0) walked create through a working
Switch; the second (0.24.0) walked Teardown through Delete permanently, the
audit trail, and AWX's re-idle behaviour; the third (2026-09-02, v0.33.0)
walked the whole journey end to end again, closing most of what was still
open and surfacing new drift from the copy sweep and throbber redesign
(corrected throughout this file, not listed again here). What's left below
is genuinely narrower again.

Each item below is **deliberately deferred to**
[dmfdeploy/dmfdeploy#379](https://github.com/dmfdeploy/dmfdeploy/issues/379)
— which stays open for exactly this reason. This runbook does not claim any
of the following were observed; the relevant beat above already says so in
its own words (source-confirmed, carried forward, or not independently
re-watched, as each case actually is), and this list exists so the next live
walk has one place to start rather than a re-read of the whole file.

**MAINTENANCE NOTE, added after this section drifted from the beats it
summarises — twice, within the same round.** This section is a DERIVED
view of every beat above, not an independent source of truth. Every time a
beat gains or loses a carried-forward hedge, this section can silently go
stale unless it's re-checked at the same time — a beat-by-beat sweep (the
method this edit otherwise relies on) does not, by construction, cover
this section, because this section isn't a beat. Caught twice during this
same editing pass: once self-caught (this section briefly listed §1's
login as closed right after the beat itself was correctly hedged as
unconfirmed) and once reviewer-caught (this section listed Admin-icon
gating as fully closed after the beat itself had already been split into a
confirmed absent-half and an unconfirmed present-half). **Whoever next adds
or changes a carried-forward marker on any beat: re-read this section's
"Closed this round" paragraph and bullet list against that specific beat
before committing — don't assume the beat-level fix is complete on its
own.** [dmfdeploy/dmfdeploy#536](https://github.com/dmfdeploy/dmfdeploy/issues/536)
tracks the deeper fix (verification markers that name their source round,
so a partially-verified beat can't collapse into one true/false flag) —
not implemented here, but the shape to reach for if this file's own
hedging keeps needing hand-reconciliation.

**Closed this round** (kept here only as a record of what the 2026-09-02
walk resolved, not as open items): §1's rail/topbar claims specifically
(icon-only rail with exactly three items, each with an accessible name;
avatar disclosure) and the **absent** half of Admin-icon gating
specifically (confirmed no 4th icon for this round's non-admin persona) —
**not** the **present**-for-an-admin half of that same claim, which stays
open (below) since this round never used an admin persona; **not** the
login act itself, which stays open (below); and **not** the specific claim
that a hover/keyboard-focus tooltip renders: this round confirmed each
rail icon has an `aria-label` (Workspace/Facilities/Media Workloads),
which is what a screen reader announces, but did not confirm those icons
also carry a `title` attribute or a custom hover popup — an accessible
name existing isn't proof a *visible* tooltip appears on hover. Left open
below too. §2's Design step
template summary painting correctly on a live Design step; §4's live-detail
modal (still 9 fields, still ~5×/s); §6a's Design-re-offers-"Use this
template" round trip after Teardown. The §4 false-catalog-warning item is
also closed, but not the way hoped — it's back, confirmed, and now a filed
issue plus a corrected presenter note (§4) rather than a deferred check.

- §1 — **The login beat's actual WebAuthn ceremony has never been
  independently live-walked, by any round to date** — every walk so far,
  this one included, started from an already-authenticated session. See
  §1's own gap note and
  [dmfdeploy/dmfdeploy#535](https://github.com/dmfdeploy/dmfdeploy/issues/535).
  This is the single most important open item in this list: it's the very
  first beat a genuine outsider (#383) would hit.
- §1 — Whether the rail's per-icon tooltip is a real, visible hover/focus
  popup (not just an `aria-label` a screen reader announces) — this round
  confirmed the accessible name, not the visible affordance.
- §1 — The **present**-for-an-admin half of "Admin appears as a fourth
  icon only if the persona is an admin" — this round's persona was
  engineer, not admin, so only the absent-for-non-admin half was
  independently re-tested. Needs a walk using an admin persona.
- §2 — Whether an invalid workload identity actually shows the documented
  red validation hint — this round never typed one to trigger it.
- §6a — Delete permanently's two independent disabled-state gates (wrong
  slug alone stays disabled; correct slug with no reason also stays
  disabled) — this round filled both fields together and confirmed the
  end-to-end action worked, which is consistent with but not a direct
  re-test of each partial state.
- §6a — Clear for deployment's actual confirm action (clicking Confirm and
  watching it complete) is 0.24.0-only — this round opened and read the
  same confirm panel but deliberately didn't confirm it, to keep the one
  workload this journey allows available for Delete permanently.
- §3 — The specific "follow an active View live link before the record
  exists, land on Workload not found" sequencing — the string itself is
  confirmed (seen later, post-Delete), but this round never deliberately
  navigated early enough during Provision to retrigger that exact
  sequence.
- §4 — The 97.6% preview-success figure (2033/49 fetches) is a two-hour
  log sample from 0.24.0, not repeated this round — still presented as
  current; re-measure on a future walk if it's going to keep being cited.
- §3 — Watch the pods/instances for the receiver and both sources
  actually converge to Running via the cluster itself (`kubectl get pods`),
  not just via the console's own screens. Still not done by any round —
  needs a walk run from a machine with cluster/SSH access.
- §4 — A lifecycle-stage badge is confirmed to exist on the `/setup` page,
  and this round independently observed three values there (`provisioned`,
  `configured`, `planned`) — confirm whether an equivalent badge also
  appears on the bare-slug **live view** itself, and if so whether it uses
  the same vocabulary. Still open — this round didn't specifically check
  the bare-slug page's own header for a badge.
- §4/§6a — The fourth badge value, **"finalizing"**, and Teardown's own
  in-flight exit-control string (*"View live — A Finalise & Review job is
  in progress — wait for its outcome."*) are both still only documented
  from 0.24.0 — this round's own Teardown was polled for both and neither
  matched in any poll iteration. Given Provision's twin exit-control string
  dropped its own "wait for its outcome" clause between 0.24.0 and 0.33.0,
  treat both as likely stale, not just unconfirmed. Confirm the live
  wording on the next walk before quoting either on camera.
- §6a — Delete permanently's own in-flight operation-id line (*"op `<id>`...
  — running"*) is likewise only documented from 0.24.0 — this round
  confirmed the "Deleting `<slug>` permanently…" line directly but never
  captured the op-id line specifically, unlike Provision's own (§3), which
  this round did capture. Confirm on the next walk.
- §6c/§6d — Re-confirm AWX's own replica count actually returns to 0/0
  after a burst of jobs (Provision, Switch, Teardown, Delete permanently) —
  confirmed on the 0.24.0 walk, not independently re-checked 2026-09-02
  (no cluster/kubectl access from where that walk ran; this round could
  only confirm every job *succeeded*, via AWX's own job list, which is
  necessary but not sufficient evidence of re-idling afterward). Also
  still open from before: watch AWX re-idle to zero on its own while the
  workload is still on the live view (§4) or mid-Switch (§5) — genuinely
  still running, not mid-Teardown.
- The stale/failed "Failed to remove MXL Test-Pattern Viewer" entry this
  round noticed at the top of Workspace's new "Recent changes" panel (§1) —
  confirmed NOT from this round's own run (this run's AWX jobs all show
  Succeeded), but unconfirmed whether it's a genuinely still-relevant
  problem from an earlier session or safe to ignore as historical noise.
  Filed as
  [dmfdeploy/dmfdeploy#533](https://github.com/dmfdeploy/dmfdeploy/issues/533)
  rather than resolved here.
- Read the whole file aloud as if you were the named outsider from #383
  and flag anywhere a term still isn't explained before it's needed. Still
  not done by any round.
