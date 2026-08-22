# DMF Platform Demo Journey

**Status:** Presenter-facing runbook. The full end-to-end demo of the DMF
platform on a **standing sandbox env**, from operator login through the
media-workload lifecycle. Written to be executed by **someone who did not
build the platform, and who does not come from broadcast** — every beat
gives a concrete action and the expected result, and every domain term is
glossed the first time it matters, so you never have to improvise or fall
back on jargon you weren't handed.

**Provenance — read this before you present from this file.** This is a
full rewrite (2026-08-19) against **dmf-cms v0.24.0**. The previous edit
(2026-08-16) was written entirely from committed source with the standing
sandbox env down, so nothing in it had been watched happen on screen — every
expected result carried an explicit UNVERIFIED caveat. This edit replaces
that with **two live walks against 0.24.0**: the first covered create
through a working Switch; a second covered Teardown, Delete permanently,
the audit trail, and AWX's re-idle behaviour — the whole journey end to
end, not inferred from source. UI copy quoted below was additionally
cross-checked against the frontend source at the same commit for both
rounds — not just transcribed from the screen — because two earlier
editions of this file each had verbatim-quote defects a prior review pass
had already declared clean; treat a verbatim sweep as a standing step
whenever this file is touched again. Claims stated as plain fact below were
observed live. Anything marked *(carried forward)* was not — it survives
from an earlier edit, unconfirmed against this build, and is not
contradicted by anything either round found. What's left uncovered by
either walk — login/rail specifics, a couple of narrower details inside
pages already otherwise confirmed, and the standing read-aloud pass — is
concentrated in §9 rather than spread through the whole file.

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
| **Media namespace clean of this template (mandatory — see below)** | confirm no instance of **MXL Test-Pattern Viewer** is already deployed on this facility | Media Workloads reads, verbatim, *"No Media Function instances in your scope."* — confirmed live this round, this exact string |

*(`HTTP/2 200` is a web server's own "yes, I'm here and working" answer —
200 is the success code; `5xx` is shorthand for the whole family of server
error codes (500, 502, …), so "no 5xx" just means the app didn't answer with
an error. Both are things you check with the `curl` command shown, not
something you'll see the audience encounter.)*

*(That last row's quoted string uses two terms this runbook hasn't glossed
yet, and the surface itself doesn't explain either: a "Media Function
instance" is the product's own name for one deployed piece — a receiver or
a source, in this demo's vocabulary — and "your scope" means the
facilities your login is permitted to see. Naming this rather than passing
it by silently: the surface's own copy assumes vocabulary this runbook's
own glossing standard wouldn't otherwise let go unexplained — flagged for
the surface owner, not fixed here, same treatment as §2's catalog-summary
jargon note.)*

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
verified server-side against a pre-run baseline (§6a). What's still open is
narrower than before: whether Design's own read on a fresh visit actually
re-offers "Use this template" once every member lands on `bootstrapped` —
the tag mapping predicts it will, but that specific round trip wasn't
re-walked this round; confirm it on the next live walk (§9) before
promising it on camera.

**(Table-row status, precisely: the clean-inventory row is confirmed live.
The AWX-asleep-at-rest row's underlying fact is confirmed too, indirectly
— §6c's live walk watched AWX reach 0/0 at rest — though this exact row
wasn't re-clicked-through as a pre-flight check. The demo-persona-role row
is new this round, not carried forward from a previous edition — it's
source-verified against the actual gating code (§0's own writeup below),
not watched live. The remaining three rows — cluster reachable, console
healthy, passkeys enrolled — are genuinely carried forward from the
previous edition and were not independently re-checked; confirm those on
the next live walk, §9.)**

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

> **PRESENTER NOTE — pacing (non-blocking).** Two beats carry real latency,
> and both now have a measured range from the live walk behind this rewrite:
> **Provision** (§3) — confirm-click to the exit control turning into a live
> "View live" link — ran **30–60 s**; **Switch** (§5) ran **150–180 s** end
> to end. Narrate the wait rather than standing in silence — for Provision,
> "the platform is scaled to zero at rest; this click is spinning the
> automation plane up on demand" — so the pause reads as a *feature*, not a
> hang. Both ranges are real measurements now, not placeholders, but treat
> them as approximate, not a promise: a single sample each.

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
confirmed devices before you start. That is §0's own pre-flight check; this
rewrite's live walk started from an already-logged-in session, so treat this
beat as *(carried forward)* until it's independently confirmed. The full
ceremony lives in [`passkey-enrollment.md`](passkey-enrollment.md). This beat
is just the login, on the assumption that check already passed.

**Action.** Open `https://console.<env-base-domain>/` in a private/incognito
window. Click **Sign in**. The browser offers the passkey picker; choose the
demo persona's authenticator and complete the WebAuthn ceremony — the
standard passkey handshake, no typing involved (Touch ID / security-key
touch).

**Expected result.** You land on the Console **Workspace** home as the demo
persona (a fictitious demo identity, e.g. `marty-mcfly` — never a real
operator name). No password was typed. The left rail is **permanently
icon-only** — three icons (Workspace, Facilities, Media Workloads), no text
labels at all; hover or keyboard-focus an icon to see its name as a tooltip.
A page's own name lives in the **topbar breadcrumb**, not the rail — the same
pattern the workload's own pages use (§4). **Admin** appears as a fourth
icon, below a divider, only if the persona is an admin. **There is no Catalog
icon** — the page still technically exists in the app, but nothing links to
it any more, and this journey never visits it (see §2 for where its job
moved).

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
environment the page reads, verbatim, and confirmed live this round:

> No Media Function instances in your scope.

(If it doesn't — if a tile is already there — stop and resolve it per §0's
mandatory precondition before continuing; Design, next, will not let you
select the template past an existing active deploy.)

Click **Create media workload** (top-right, blue). This opens
`/media-workloads/new` — a step-by-step wizard. **There is no chip-row rail
on this page** (that only appears once the workload is real, and even then
it lives on the workload's own `/setup` page, not this one — §3 onward) —
each step is its own panel with **Previous**/**Next** at the bottom. Work
through it in order:

**Studio name** is the human-friendly name for *this* workload —
distinct from the **Facility** it runs on, and distinct from the
workload identity (the slug) that's derived from it, below.

**Step 1 — Identity.** Two fields, and they start out linked, source-verified:
type into **Studio name** (free text, placeholder *"e.g. Studio A"*) and
**Workload identity** below it — a `workload:`-prefixed field — auto-populates
from what you typed, transformed by fixed rules: lowercased, runs of spaces
or underscores turned to a single hyphen, anything else stripped, leading
and trailing hyphens trimmed, capped at 40 characters (e.g. "Studio A"
proposes `studio-a`). This is a **proposal, not a hidden derivation** —
the platform's own stated principle for this field: the identity is shown
and editable the whole time, never computed somewhere out of sight, and the
moment you edit it directly it **detaches** — further edits to Studio name
stop touching it from then on. The identity showing when you advance,
auto-derived or hand-edited, is the literal value the platform records.
If it isn't valid (lowercase letters, digits, hyphens; can't start or end
with a hyphen; 40 chars max — the identity field's own rule, not the Studio
name's, which takes any free text), a red hint says so. An amber note
states the honest limit up front, verbatim: *"This draft lives only in
this browser tab until Provision runs — refreshing or closing the tab
before then loses it, and nothing about it is recorded anywhere until
then."* Enter a Studio name, confirm or edit the identity it proposes, and
click **Next →**.

**Step 2 — Design.** This is the console's whole **catalog** (see Terms) —
today, **one entry**: **"MXL Test-Pattern Viewer"** (confirmed live this
round, and matches `display_name` at
`dmf-media catalog/mxl-videotest-view.yaml:2`), with a **"Use this
template"** button (confirmed both live and against source). The console
renders this card's summary from `entry.summary` (`CreateWorkload.tsx:571`)
— that literal text lives in dmf-media's catalog data, not dmf-cms's own
source, but dmf-media is readable too, and its committed value reads,
verbatim: *"Media eXchange Layer consumer for the cross-host fabrics demo:
the receiver target exposes the received flow and preview from the paired
source over libfabric tcp. This is the view / receiver half of the split
demo."* (`dmf-media catalog/mxl-videotest-view.yaml:4-6` — source-confirmed
this round, not merely carried forward; the console applies no transform to
it, so what's committed there is what renders). In plain terms: "libfabric
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

**Action.** On the Provision step, click **▶ Provision now**. A confirm
panel opens, title and description as two distinct pieces of copy — title,
verbatim: *"Provision this workload now?"*; description, verbatim: *"Deploys
MXL Test-Pattern Viewer via its AWX job template and records it as
workload:`<slug>`. Operator-gated: your reason is recorded in the audit
trail."* Type a **reason** — the textarea placeholder says why, verbatim:
*"Reason (required, recorded in the audit trail)"* — and click **Confirm
provision** (disabled until you've typed something). Every string in this
paragraph is confirmed both live and against source.

**Expected result — watched happen, live, on 0.24.0.**

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
   and neither one predicts the other.** Its heading reads, verbatim,
   **"Provisioning"**; below it, **"Deploy accepted."**, plus an operation
   id and, once the job is assigned one, a job number — both for your own
   reference if something needs escalating, not something to read aloud.

   One signal is **the screen's own exit control**, which renders as
   **inert text, not a link** while the launch operation/job is
   non-terminal, reading, verbatim: *"View
   live — The launch job is in progress — wait for its outcome."* That
   text tracks job/operation terminality directly
   (`WorkloadMaterializing.tsx`) — nothing to do with whether the
   workload's record has shown up anywhere yet.

   The other signal is **the screen swap itself**, to the real guided-flow
   page. That's driven by a separate poll of the facility's workload
   inventory, and the screen is replaced on the first poll read that
   contains the record — not at the instant the record is written. The
   launcher writes that record **part-way through the job**, not only once
   it settles (the screen's own copy says as much: the workload "appears
   here once the launcher records it... The launcher does that PART-WAY
   through the job... so it can show up here while the job is still
   running"). **Timing observed this round: 30–60 s** from Confirm
   provision to the swap — an observed detection time on the poll's own
   cadence, not the record-write time.

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
   scope right now.' (`WorkloadHome.tsx`). Once the record exists, home
   only renders §4's monitoring view once it reaches Operate
   (`lifecycle === 'operate'` internally); short of that it shows a
   "Continue setup" panel or an unresolved-status notice instead, not
   §4's three tiles. If you follow the link early and land on any of
   these three, that's expected — but waiting it out only converges if
   the launch is actually succeeding. If it isn't, the tell is back on
   the Provisioning screen (§3): a failed job replaces "Deploy
   accepted." with "The launch job for this workload did not succeed.",
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
this round.** The page opens with a line of intro copy, verbatim: *"The
monitoring surface for this workload — observed running state only.
Changes are requested at the flow's own steps, not from here."* That's the
whole thesis of this page in one sentence: watch here, act on the guided
flow.

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
- **The viewer's tile is captioned, verbatim, "Live · sidecar preview"**, and
  it delivers on that caption: confirmed by a two-hour access-log sample
  against the live env, **2033 successful preview fetches against 49
  failures — a 97.6% success rate**, with the rare single-tick failure
  recovering on the very next poll. The preview genuinely works; don't
  undersell a working feature by hedging on it.
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

**(Carried forward from the previous edit, not part of this round's walk —
confirm before presenting.)** Clicking a tile opens a larger live-detail
modal with nine flow-stat fields — head index, latency, format, grain rate,
role, provider, MXL version, Active, and Node (NetBox) — ticking roughly
5×/s while open.

**A lifecycle-stage badge does exist — confirmed this round, though on the
guided-flow page, not necessarily this one.** §6a's Teardown walk confirmed
one reading **"finalizing"** while that job runs, rendered on the `/setup`
page's own header. Whether an equivalent badge also appears on **this**
page — the bare-slug live view — is still not confirmed either way; the
previous edition described one reading "planned" / "provisioned" /
"configured," tied to a rail-and-Operate-link layout that no longer exists
— treat that specific vocabulary as superseded pending a fresh check (§9),
which now covers this narrower question rather than whether a badge exists
at all.

> **PRESENTER NOTE — a defect from an earlier edition is now fixed
> (informational).** Earlier editions of this runbook flagged a false
> warning on the Design step, telling the reader the two topology-spawned
> sources' function keys weren't in the current catalog and may have been
> removed — untrue, since neither was ever meant to have its own catalog
> entry — plus raw slugs standing in for friendly names. Both were the same
> root cause, and both are resolved as of this release
> ([dmfdeploy/dmfdeploy#401](https://github.com/dmfdeploy/dmfdeploy/issues/401),
> merged via dmf-cms#97) — not re-confirmed live this round, since the walk
> behind this rewrite didn't revisit the Design step on a live workload, but
> there's no reason to expect it back. Dropped from §7's rough-edges table
> for that reason; spot-check it anyway on the next walk (§9).

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

**Expected result — the arm panel, confirmed live this round.** Title,
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

**Expected result — after confirming, confirmed live this round.**
**Completion took 150–180 s** end to end — slower than the previous
edition's untested ~120 s estimate; don't quote a tighter number than this
range until you've timed it again. On success, the Configure step's own
outcome line reads, verbatim, **"Active source: source-b"** (or whichever
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
is not the only ending. Confirmed live this round — Teardown, Delete
permanently, and the audit trail were all walked start to finish.

**6a. Three sections, confirmed live this round: Teardown, Delete
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
reason."* **Confirm teardown** stays disabled until a reason is typed, same
placeholder as elsewhere. While the job runs, the exit control reads,
inert, verbatim: *"View live — A Finalise & Review job is in progress —
wait for its outcome."* — the same inert-then-active pattern §3 uses for
Provision, and during this window the workload's lifecycle badge reads
**"finalizing"** (genuinely American spelling — an inconsistency with the
British "Finalise" used everywhere else on this same page, not a
transcription error in this runbook). **Duration observed this round: 90–120
s. One sample — treat as approximate, not a promise**, same caveat as
Provision's and Switch's own numbers.

**The removal half of the round trip is now confirmed, not just mapped
from source:** verified server-side against a baseline captured before the
run, three Helm releases, three pods, and three services all went to zero.
**One click here tears down all three pieces**, not just the receiver — the
runbook's long-standing claim that dmf-runbooks' teardown playbook removes
the topology's two source releases alongside the receiver's own, in the
same job, is upgraded from source-confirmed to **observed**. The other
half — whether Design's own read on a fresh visit actually re-offers "Use
this template" once every member lands on `bootstrapped` — is still only
mapped from the tag logic, not separately re-watched this round; see §0
and §9.

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
> open, not fixed).** This round's walk landed back on the **Provision**
> step, unprompted, showing its desired-state panel with **Clear for
> deployment** offered for each instance — the operator did not navigate
> there. **This was observed once; whether it happens on every Teardown is
> not confirmed, and no mechanism is asserted here** — a source-derived
> explanation offered in an earlier draft of this note turned out to be
> wrong and has been withdrawn, not replaced. Treat it as: it can happen,
> narrate it as a known rough edge if you hit it, and don't be surprised
> either way — it's disorienting, not dangerous, since nothing runs
> automatically from that panel without another explicit confirm. Also
> observed this round, on the **Teardown** section's own per-entry status
> line once torn down, verbatim: **"Not currently deployed."** — a status on
> Teardown's own panel, distinct from "Already deployed." elsewhere and
> not, as an earlier draft of this note had it, text on the Provision step
> itself.

**Clear for deployment — confirmed observed this round**, not merely
source-read: because Teardown returns every member to a bootstrapped
state, this control (§0's earlier note) is now offered for real. Its
confirm-panel description renders exactly as source predicted, verbatim:
*"This records the intent to run in the facility source of truth. It shows
as pending reconciliation until something deploys it — today, that's
Provision. This action does not deploy anything itself."* No separate
"automation lane" text anywhere near it.

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
cannot be undone.' — plus a reason textarea. Description ending, verbatim:
*"...from the source of truth via the finalise-purge automation. The entry
stops existing — there is no rollback."* The button itself reads **"Delete
permanently"** (not a separate "Confirm" label). **Two independent gates,
confirmed by direct test this round:** the button stays disabled until BOTH
the exact slug is typed AND a reason is supplied — typing a wrong slug
alone leaves it disabled, and typing the correct slug alone with no reason
also leaves
it disabled. Per dmf-runbooks' finalise-purge playbook, this is the
**only** launcher that deletes NetBox records outright (every other
launcher only flips a lifecycle tag) — it runs under its own delete-only
credential for exactly that reason, and only declares success once a fresh
read confirms every member **and** the workload's own tag are gone.

During the job, the panel reads, verbatim: **"Deleting `<slug>`
permanently…"**, plus an operation-id line reading **"op `<id>`... —
running"** (the id truncated to its first 8 characters). **Duration
observed this round: 30–60 s. One sample.**

After completion, the page reads, verbatim, **"Workload not found"** at the
same `/setup` URL, with a companion line — quoted here with single quotes
since the string itself contains double quotes — reading: 'No workload
named "`<slug>`" is in your scope right now.' A dead end: the collection
view no longer lists the workload, and the cluster is confirmed at zero
pods, services, and Helm releases. This landing is also part of #418 above
— that issue
covers both Teardown's and Delete permanently's post-action landing.

**6b. The audit trail — Activity → History. Confirmed live this round.**
There is no Activity icon in the rail — like Catalog, the route still
exists, it's simply not linked from anywhere in the nav (the same S1 IA
cut). Type the URL directly:
`https://console.<env-base-domain>/activity/history`. The browser tab
reads, verbatim, **"Activity — History · DMF Console"**.

- **Expected, confirmed live this round.** The **"Console actions"** panel
  (a real heading, not this runbook's paraphrase) lists this browser's
  persisted writes — a row per action, titled in operator language. The
  **common** shape is four lines: the action line; the outcome and the
  reason you typed, in curly quotes; actor, role, and request id; a
  timestamp. A **Clear for deployment** row (§6a) is the one exception this
  journey hits: it carries a genuine **fifth line**, a
  reconcile-expectation note, every time — don't describe the shape as
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
  rather than pointing at the panel for a row that isn't there. (The
  backend's own structured log line still covers Provision — see the next
  bullet.) The actor line reads **`<persona> (<role>) · request <id>`**,
  with the request id truncated to its first 8 characters — `<role>` is a
  live value (whatever role the acting operator actually held), not a
  fixed label; don't quote it as always reading "admin" just because an
  admin persona happened to be the one testing it.
- **Honest scope, confirmed live this round — verbatim, right on the
  panel itself:** *"Actions taken from this console in this browser —
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
  which lands in Loki — bounded too, not permanent: the platform's shipped
  default retention is 30 days, with a 6-month override for streams
  labelled as security-relevant. Even the longer of the two is still a
  bound, not an indefinite record. The passkey invitation in §1 is the one
  write in this journey that emits neither this log line nor a
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
directions, this round.** By design, AWX is meant to scale itself back to
zero on its own some time after the last write, with no operator action —
the "actuates, then sleeps" story §3 sets up. **This round watched both
halves happen:** AWX was found at 0/0 replicas before this round's
Teardown/Delete walk began, its grace period from earlier jobs already
expired; it woke **automatically** the instant Teardown was fired, with no
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
becomes a footnote instead of a scramble. Three prior entries are gone from
the table below and are not replaced with softened versions, because none
of them is actually a rough edge any more: a false "not in the current
catalog" warning and a first-post-wake 5xx are fixed as of this release (see
§4's presenter note for the first); and a claimed viewer-preview failure
(dmfdeploy/dmfdeploy#417) turned out to be a measurement artifact — a
two-hour live-env sample logged a 97.6% preview success rate, and the issue
is closed as overstated. See §4: the preview works, and the two sources'
lack of one is by design, not a gap.

| Symptom you might see | What it is | Reference |
|---|---|---|
| The guided-flow page briefly shows an amber banner, *"`<Step>` isn't open yet: `<reason>`"*, on a step that is actually open | A latched-vs-live read race during background polling — the step really is open; the banner is stale for the length of one poll and clears itself. Cosmetic and self-clearing, but voiced aloud by a screen reader while it's up. | [dmfdeploy/dmfdeploy#416](https://github.com/dmfdeploy/dmfdeploy/issues/416) |
| After Teardown or Delete permanently completes, you may land somewhere you didn't ask for — Teardown was observed once bouncing unprompted to the Provision step's desired-state panel (recurrence unconfirmed); Delete permanently reliably strands you on a "Workload not found" page for the workload you just removed | A completed lifecycle action should hand you back to the workload's home or the collection view, not to an unrelated next step or a dead URL. Disorienting, not dangerous — nothing runs automatically from either landing without another explicit confirm. | [dmfdeploy/dmfdeploy#418](https://github.com/dmfdeploy/dmfdeploy/issues/418) |
| Provisioned instances show up **grouped as "Unassigned"** in the grid | The launcher hasn't stamped a `workload:<slug>` tag onto every member, so the grouping logic has nothing to group them by. Cosmetic/legibility only. | [dmfdeploy/dmfdeploy#239](https://github.com/dmfdeploy/dmfdeploy/issues/239) |
| Someone asks "what if the node dies?" (spot reclaim) | Not hypothetical — it happened to this env while the previous edition of this file was being written. The standing env's addressing is derived from the node's public IP, so a reclaimed/replaced node means a new address. **There is no cluster-state backup to restore from** — the standing archive covers operator-local material only. **Recovery is re-bootstrap plus re-pointing the IP-derived address**, not a resume-in-place and not a restore. | env recovery notes (operator-local) |

> **PRESENTER NOTE — if a beat stalls.** The two beats with real latency are
> **Provision** (§3, 30–60 s to the live-view handoff) and **Switch** (§5,
> 150–180 s). Both ranges are within what this rewrite watched happen — a
> stall past that isn't expected, but nothing here should send you
> off-script.

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

---

## 9. Live-walk verification checklist

**This section is what two rounds of live walking still haven't covered.**
The first round walked create through a working Switch; the second walked
Teardown through Delete permanently, the audit trail, and AWX's re-idle
behaviour. Almost everything that was open after round one is now closed —
what's left below is genuinely narrower: login specifics neither round
happened to touch, a couple of details inside pages this runbook already
otherwise confirmed, and the standing read-aloud pass. Two items from the
previous edition of this checklist were dropped outright rather than kept
open: the tile's own visual during a Switch restart (the mechanism and
timing are both confirmed elsewhere in §5; the specific "does the tile
visibly pause" detail isn't worth gating a merge on when "don't panic if it
goes quiet" is already the operative guidance either way). Work through
what remains on the next live walk; only once every row is checked does
#379's acceptance criterion — *"every expected result was observed on the
live env while writing, not inferred"* — fully hold.

- [ ] §1 — Login lands on Workspace; rail is icon-only with exactly the
      three tooltips named; Admin only appears for an admin persona.
- [ ] §2 — The Design step's template summary text renders on screen exactly
      as committed in `dmf-media catalog/mxl-videotest-view.yaml` (confirmed
      against that file directly, including the card title and button, but
      not watched paint on a live Design step by either round — the console
      applies no transform, so a mismatch would mean a stale render or a
      cache issue, not a wrong quote).
- [ ] §3 — Watch the pods/instances for the receiver and both sources
      actually converge to Running via the cluster itself, not just via the
      console's own screens (which did confirm all three reached a running
      state, just not by watching kubectl directly).
- [ ] §4 — A lifecycle-stage badge is now confirmed to exist on the `/setup`
      page (reads "finalizing" during Teardown, §6a) — confirm whether an
      equivalent badge also appears on the bare-slug **live view** itself,
      and if so its full vocabulary across the other stages; the previous
      edition's "planned" / "provisioned" / "configured" guess for the live
      view is still unconfirmed either way.
- [ ] §4 — Open the live-detail modal (click a tile) and confirm it still
      exists, still shows nine flow-stat fields (head index, latency,
      format, grain rate, role, provider, MXL version, Active, Node
      (NetBox)), and still ticks at roughly the claimed ~5×/s.
- [ ] §4 — Spot-check that the Design step no longer shows the false
      not-in-the-current-catalog warning on the two topology-spawned sources,
      now that dmfdeploy/dmfdeploy#401 is merged — this rewrite treats it as
      fixed on the strength of the merged fix, not a fresh observation.
- [ ] §6a — After a real Teardown, confirm Design's own read on a fresh
      visit actually re-offers "Use this template" once every member lands
      on `bootstrapped` — the tag mapping (§6a, source-confirmed) predicts
      it, but this specific round trip wasn't re-walked this round; the
      removal half (all three pieces going to zero) is confirmed separately.
- [ ] §6d — Watch AWX re-idle to zero on its own while the workload is still
      on the live view (§4) or mid-Switch (§5) — genuinely still running,
      not mid-Teardown. §6c confirms the wake/idle mechanism works at all;
      this is the narrower, still-unwatched pairing 6d's closing beat needs.
- [ ] Read the whole file aloud as if you were the named outsider from #383
      and flag anywhere a term still isn't explained before it's needed.
