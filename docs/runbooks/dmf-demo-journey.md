# DMF Platform Demo Journey

**Status:** Presenter-facing runbook. The full end-to-end demo of the DMF
platform on a **standing sandbox env**, from operator login through the
media-workload lifecycle. Written to be executed by **someone who did not
build the platform, and who does not come from broadcast** — every beat
gives a concrete action and the expected result, and every domain term is
glossed the first time it matters, so you never have to improvise or fall
back on jargon you weren't handed.

**Provenance — read this before you present from this file.** This is a
full rewrite (2026-08-16) against **dmf-cms v0.21.1** and **dmf-runbooks
v0.4.6** committed source — the standing sandbox env was **down** while this
was written (its node was reclaimed), so
nothing in this rewrite was watched happen on screen. UI copy quoted below
(button text, field labels, stage names, error strings) is transcribed
verbatim from the frontend source and should render exactly as written.
Everything about **behavior over time** — how long a step actually takes,
whether a job actually completes cleanly, what a screenshot actually looks
like — is a separate claim this rewrite cannot make, and is called out
explicitly wherever it appears. **§9 is a checklist for the next live
walk**; do not present from this runbook, and do not close
[dmfdeploy/dmfdeploy#379](https://github.com/dmfdeploy/dmfdeploy/issues/379),
until §9 is cleared.

**Scope note.** The console's demo catalog was reduced to **one template**
on 2026-08-03 (Arc 2a) — provisioning it launches a small *topology*, not a
single piece (see the glossary below). The **Switch** beat, a placeholder in
every previous edit of this file, is **present in dmf-runbooks' committed
source since 0.4.4** and wired into the console — it is a real beat now, §5
(§379's known-stale table dates it live on the env 2026-07-31; this rewrite
did not watch it run — see §5's own note and §9). This runbook is part of the v0.2
presentable-journey track
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
| **Reason / audit trail** | Every write on this platform requires you to type a short reason before it fires; that reason, plus who you are and what role you held, is permanently recorded. That record is "the audit trail" (§6b). |
| **The six-stage lifecycle** | **Design → Plan → Provision → Configure → Operate → Finalise & Review.** This is not documentation vocabulary — all six names appear as real on-screen labels throughout this journey. |

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
| Demo persona has the right role | (see below) | persona holds **engineer** (or admin) capability |
| AWX is asleep at rest | (informational) | expected — the first Provision click wakes it; see §3 |
| **Media namespace clean of this template (mandatory — see below)** | confirm no instance of **MXL Test-Pattern Viewer** is already deployed on this facility | Design (§2) offers the template at all — see the paragraph below |

**This precondition is mandatory, not a nicety — it will block the journey
outright if skipped.** With a single-entry catalog, if any Media Function
instance from **MXL Test-Pattern Viewer** is already deployed (lifecycle
**active**) anywhere on this facility, the Design step's "Use this
template" control is withheld entirely: a badge reads *"Already deployed"*
and the on-screen line is, verbatim, *"Already deployed on this facility,
so it can't start a new workload here."* (`CreateWorkload.tsx` TemplatePicker
— source-verified). There is no second template to fall back to, and
provisioning a second workload is already forbidden by this journey's own
one-workload scope above — so an unclean facility doesn't just make the
demo messier, it makes §2 impossible to finish. Before you begin: confirm
the facility is clean (ask the operator, or check yourself once logged
in — Design will tell you). If a prior deploy is still standing, tear it
down (§6a) first — a successful Teardown flips the entry's lifecycle tag
to `bootstrapped`, which clears this gate on its own (source-confirmed;
full mechanism and citations in §6a). **Delete permanently is not
required between runs.**

**(UNVERIFIED — the "Expected" column above is carried forward from the
previous edit of this file and was not independently re-checked against
source or against a live env this round; confirm each row on the next live
walk, §9.)**

**Two operational gotchas learned since the last edit of this file** (from
[#379](https://github.com/dmfdeploy/dmfdeploy/issues/379)'s own scope — not
things this rewrite could re-derive from dmf-cms/dmf-runbooks source, so
treat them as operational folklore, not code fact):

- **AWX does not wake itself just because you ran a playbook against it.**
  It has to be woken through the autoscale `ensure-awake` seam first (the
  same seam the console's own Provision click uses — see §3). Running an
  ordinary operations playbook against a scaled-to-zero AWX **does not**
  wake it, and its first run will burn its **full timeout** — and the
  failure it reports will look like an SSH ControlMaster multiplexing hang,
  which has **nothing** to do with the real cause. If a playbook run against
  this env times out mysteriously before you've done anything else, check
  whether AWX was actually awake first.
- **Don't trust the documented `ansible_user` default.** Read it from the
  env's own inventory instead — the documented default can be wrong for a
  given standing env.

**Demo persona role.** The whole journey now lives on **one** rail —
**Media Workloads** — and one family of pages under it. Reaching that rail
at all needs the **engineer** or **admin** role, or membership of the
`media-engineers` group (the nav gate and the server-side gate agree — nav
visibility is cosmetic, the backend enforces the same boundary on every
request). But group membership alone does not let you *act*: every write
this journey makes — Provision, Switch, Teardown, Delete permanently — is
separately gated on at least the **operator** role (roles rank
viewer < operator < engineer < admin), so a `media-engineers` member who is
only a viewer can watch the whole journey but cannot perform any of it. The
one persona that can see the rail **and** perform every write in this
journey, in a single login, is **engineer (or admin)** — log in as that.

If passkeys show `0/2` or `1/2`, complete
[`passkey-enrollment.md`](passkey-enrollment.md) **before** the demo — do not
try to enrol a first passkey live; the ceremony has authenticator-choice
pitfalls that runbook covers in full.

> **PRESENTER NOTE — pacing (non-blocking).** The slowest beat is the
> **cold AWX wake** on the first Provision click (§3) — exactly how slow is
> one of the things §9 asks you to time on the next live walk; do not quote
> a number on camera until it's been measured against *this* build (the
> single click now launches three pieces in one job, not one, so an old
> measurement from before 2026-08-03 is not a safe stand-in). Narrate the
> wake regardless ("the platform is scaled to zero at rest; this click is
> spinning the automation plane up on demand") so the pause reads as a
> *feature*, not a hang.

---

## The journey at a glance

| # | Beat | What the audience sees | Surface |
|---|---|---|---|
| 1 | **Log in** | Passkey login as a demo persona — no password | Console |
| 2 | **Create the workload** | Name a studio, pick the one template on offer, confirm where it runs | Console → Media Workloads → New |
| 3 | **Provision** | One click → automation plane wakes → three pieces go Running together | Console → Media Workloads → New → Provision |
| 4 | **Operate** | Live tiles for all three pieces, live preview on the receiver | Console → Media Workloads → workload → Operate |
| 5 | **Switch** | Re-point the receiver from one source to the other | Console → Media Workloads → workload → Configure |
| 6 | **Finalise & Review** | Two possible endings — tear down, or delete permanently — plus the audit trail | Console → Media Workloads → workload → Finalise & Review; Activity → History |

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
rewrite could not independently confirm it, so treat it as a pending check,
not a completed one, until §0/§9 clears it. The full ceremony lives in
[`passkey-enrollment.md`](passkey-enrollment.md). This beat is just the
login, on the assumption that check already passed.

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
A page's own name now lives in the **topbar breadcrumb**, not the rail.
**Admin** appears as a fourth icon, below a divider, only if the persona is
an admin. **There is no Catalog icon** — the page still technically exists
in the app, but nothing links to it any more, and this journey never visits
it (see §2 for where its job moved).

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
*(This paragraph is carried forward unchanged from the previous edit and was
not independently re-verified this round — it isn't on the known-stale list.
§9 asks you to confirm it too.)*

---

## 2. Create the workload — Identity, Design, Plan

This is where the old "open Catalog" beat lives now. There is no separate
Catalog page in the journey any more — naming and choosing a **media
workload** (see Terms, above) is one guided flow.

**Action.** From the icon-only rail, open **Media Workloads**. On a clean
environment the page reads:

> No Media Function instances in your scope.

(If it doesn't — if a tile is already there — stop and resolve it per §0's
mandatory precondition before continuing; Design, next, will not let you
select the template past an existing active deploy.)

Click **Create media workload** (top-right, blue). This opens
`/media-workloads/new` — a step-by-step wizard. **There is no chip-row rail
on this page** (that only appears once the workload is real, from §3
onward) — each step is its own panel with **Previous**/**Next** at the
bottom. Work through it in order:

**Step 1 — Identity.** Two fields: **Studio name** (free text, e.g. "Studio
A") and **Workload identity** — a `workload:` -prefixed field you also type,
shown and editable, not a hidden derivation of the name above. This is the
literal identity ("workload slug") the platform will record. An amber note
states the honest limit up front: *"This draft lives only in this browser
tab until Provision runs — refreshing or closing the tab before then loses
it, and nothing about it is recorded anywhere until then."* Enter a name
that resolves to a valid identity (lowercase letters, digits, hyphens; can't
start or end with a hyphen; 40 chars max) and click **Next →**.

**Step 2 — Design.** This is the console's whole **catalog** (see Terms) —
today, **one entry**: **"MXL Test-Pattern Viewer"**. Its on-screen summary
reads, verbatim: *"Media eXchange Layer consumer for the cross-host fabrics
demo: the receiver target exposes the received flow and preview from the
paired source over libfabric tcp. This is the view / receiver half of the
split demo."* In plain terms: "libfabric tcp" just names the low-level
networking transport carrying the test video between pods, and "cross-host"
means it still works when those pods land on different nodes — the part
that matters for you is simpler than either: this is the one thing you can
deploy, and it is the **receiving** half of a source/receiver pair —
provisioning it also brings its two sources along for the ride (that's the
"topology" from Terms, above; more in §3). Click **Use this template**.

> **PRESENTER NOTE — jargon on this screen (non-blocking, but real).** That
> summary sentence is quoted, not paraphrased, and it is denser than this
> runbook's own glossing standard allows — "libfabric tcp" and "cross-host
> fabrics demo" aren't explained anywhere on screen. This rewrite treats
> that as **evidence the surface itself needs a plainer summary**, not
> something to paper over here; it's flagged for the surface owner rather
> than fixed in this file. If you're asked what it means: it's the piece
> that receives and displays the test video the two sources produce.

**Step 3 — Plan.** A single sentence — *"This workload will run on
`<site name>`."* — with a **Confirm placement** button. This is a
confirmation, not a choice: the standing env has exactly one facility, and
there is no workload-to-facility field to pick from anywhere in the
platform. Click **Confirm placement**, then **Next →**.

Clicking **Next** again lands you on **Provision** — that's §3, next. If you
click ahead to **Configure** or **Finalise & Review** out of curiosity, each
renders only its own locked reason — two distinct strings, not one merged
sentence:

- Configure: *"Locked for the whole draft — nothing has been provisioned
  yet, so there is nothing to configure."*
- Finalise & Review: *"Locked for the whole draft — nothing has been
  provisioned yet, so there is nothing to finalise or tear down."*

Nothing runs yet, so there is genuinely nothing else to show.

---

## 3. Provision — the click that wakes the platform

This is the signature beat: **one console click drives the whole actuation
chain** — wake the automation plane, run a real job, materialise **three**
pieces of the workload at once.

**Action.** On the Provision step, click **▶ Provision now**. A confirm
panel opens, title and description as two distinct pieces of copy — title:
*"Provision this workload now?"*; description, verbatim: *"Deploys MXL
Test-Pattern Viewer via its AWX job template and records it as
workload:`<slug>`. Operator-gated: your reason is recorded in the audit
trail."* Type a **reason** — the textarea placeholder says why: *"Reason
(required, recorded in the audit trail)"* — and click **Confirm provision**.

**Expected result — watch it unfold, in order.**
**Everything after this line is inferred from source, not observed live —
confirm every claim in this list against §9 before trusting it on camera.**

1. **The click wakes the automation plane.** The console calls the same
   `ensure-awake` seam §0's operational note describes, before launching —
   the click itself is the wake, no separate trigger. AWX is scaled to zero
   at rest.
2. **One job launches three pieces, not one.** Because the single template
   is a *topology* (Terms, above), this one AWX job stands up the receiver
   **and both of its sources** together — a colour-bars ("SMPTE") pattern
   source and a checkerboard-pattern source, each a separate piece the
   console will track. **Do not quote the previous edit's timing numbers
   here** — they measured a single-piece deploy, and this build launches
   three pieces in the same job, which is not the same shape of work.
3. **The wizard hands off to a "Provisioning" screen.** You'll see *"Deploy
   accepted."* and a live job-status line (states like *Waking automation* →
   *Launching job* → a ticking AWX job status). This screen is deliberately
   honest about the gap between "accepted" and "exists": the workload's
   record only appears once the launcher stamps it, which happens
   **part-way through** the job, not at the end — an empty read in the
   meantime is expected, not a failure.
4. **The page becomes the real workload once it's recorded.** No further
   click needed — the same URL swaps from the materialising screen to the
   real workload detail page once the identity resolves.

You can narrate the wait with the cluster view if a terminal is on screen —
**SSH target and `ansible_user` per §0's second gotcha**:

```bash
# Optional live proof (operator terminal).
ssh <ssh-target> 'sudo k3s kubectl get pods -n mxl -w'
```

**(UNVERIFIED — convergence behaviour, not observed this round.)** Expected:
pods for the receiver and both sources appear and converge to Running.
**Exact pod/container counts per piece are not restated here** — the
previous edit's specific numbers described a different, one-piece deploy
and would misstate this one; time and count it fresh on the live walk (§9).

> **PRESENTER NOTE — ARCHITECTURE (non-blocking).** **AWX is the *actuator*,
> not the runtime.** It provisions the workload and then gets out of the
> way: the media workload runs decoupled from AWX's own wake/sleep cycle —
> you'll see this made concrete in §6.

> **PRESENTER NOTE — SECURITY (non-blocking).** The reason you typed is not
> cosmetic: **writes are reason-required** — a missing/empty reason is
> refused before any AWX call — and the reason is recorded in the audit
> trail: actor, effective role, request id, reason. You'll read this back in
> §6b (Activity → History). Every provision here is an *audited, attributed*
> action tied to the logged-in persona.

---

## 4. Operate — the live view

**Action.** The materialising screen (§3) swaps itself out for the
workload's own page once the grouped inventory can read the record —
which can happen while the launch job is still running, or lag briefly
after the job finishes; it is not simply "once Provision completes." Once
you're there: near the top, a **lifecycle badge** names the last completed stage in
plain-past-tense wording — not what you might expect. The console's own
grammar: at the *Provision* position the badge reads **"planned"**
(design+plan settled, deploy still ahead); once the deploy has actually run
it reads **"provisioned"**; once everything is healthy and flowing it reads
**"configured"**. *(Read that last one twice — a workload that just deployed
successfully will likely say "provisioned," and "configured" is what a
**healthy, running** workload says, not what the Configure step's own name
would suggest.)*

Below the badge is a single-row **lifecycle rail**: five chips — Design,
Plan, Provision, Configure, Finalise & Review — plus a separately-grouped
**Control** label with an **Operate** link next to it (Operate is
deliberately *not* a sixth chip in that row — it's something you watch, not
a step you work through). Click **Operate**.

**Expected result.** **(UNVERIFIED — this whole block is traced from
source, not watched on screen; confirm every bullet in §9.)**

- A **Live view** grid with **three tiles** — the receiver and both sources.
  The two source tiles' names may render as their raw internal identifiers
  (e.g. a string ending `-source-a` / `-source-b`) rather than a friendly
  label — that's expected: only the receiver has its own catalog entry to
  supply a display name, the two sources don't carry one of their own.
- The **receiver's tile shows a live sidecar preview** — caption **"Live ·
  sidecar preview"** — proxied live from its status sidecar (Terms, above).
  Per dmf-media's own source comments, the test pattern carries a **burnt-in
  clock overlay** meant to visibly tick — point at it to prove the frame is
  live, not a thumbnail, once you've confirmed it on the live walk.
- **Both source tiles read "Sidecar live · no preview on this side".** A
  source *produces* the pattern; it has nothing incoming to preview, so the
  platform says so rather than showing a blank or a fake image. **Call this
  out** — it's a correctness signal, not a missing feature, and it now
  applies to *two* tiles instead of one.
- Click any tile to open the **live detail modal**: a larger live preview
  plus nine flow stats — head index, latency, format, grain rate, role,
  provider, MXL version, **Active**, and **Node (NetBox)** (labelled that
  way on purpose — it's the NetBox-recorded placement, never the sidecar's
  own self-report) — ticking roughly 5×/s while open.

> **PRESENTER NOTE — a real gotcha if you open the Design step (non-blocking
> but worth knowing).** If you click back to the **Design** chip to show the
> workload's composition, the two source pieces will each show an amber
> line: *"This function key isn't in the current catalog — it may have been
> removed since this workload was deployed."* That claim is **false** for
> these two — they were never meant to have their own catalog entry; they're
> the topology's own sources, matched by internal name, not a removed
> template. This is a real, source-confirmed surface defect on the only
> supported demo path today (flagged separately, not fixed in this file —
> see this rewrite's own report). Don't improvise an explanation that
> contradicts what §2 already told the reader; just say the message is
> known-wrong and move on.

> **PRESENTER NOTE — MONITOR (non-blocking).** The Console's own
> **Monitoring** rail is the at-a-glance facility health view; the tile
> preview answers "is my media flowing?". For deeper telemetry, **Grafana**
> is fed by the cluster's monitoring stack — open it in a second tab if the
> audience wants metrics/alerting depth.

> **PRESENTER NOTE — SECURITY (non-blocking).** The Media Workloads surface
> is **hard-gated server-side**, not just hidden in the nav: reaching it —
> even the read — requires the **engineer/admin** role **or** membership of
> the `media-engineers` group. An **unauthenticated** request gets **401**; a
> **plain viewer** (below engineer, not in `media-engineers`) gets **403 on
> the whole surface** — the rail is hidden for them too. Writes additionally
> require a non-empty **reason** → **400** without one.

---

## 5. Switch — re-point the receiver's source

This beat **did not exist** in any previous edit of this file. Its
implementation is present in dmf-runbooks' committed source
(`playbooks/switch-mxl-fabrics-demo.yml`, shipped by 0.4.4) and wired into
the console's Configure stage — that much is a source fact, verified this
round. #379's own known-stale table dates it live on the env 2026-07-31;
this rewrite did not watch it run, so treat "live" as unconfirmed until §9.
It lives on the **Configure** chip, not on Operate: Operate is deliberately
read-only and only links out
to this step (its own copy: *"Source selection happens at the Configure
step — changing this workload's source is a configure-time re-point
performed by an automation job, not real-time flow control."*).

**Action.** From the workload page, click the **Configure** chip (or the
"Go to Configure →" link from Operate). Under **Source · `<receiver
instance>`**, the current active source is shown in mono text (e.g.
`source-a`). If a **Switch source** button is offered, click it.

**Expected result — the arm panel (UNVERIFIED — behaviour/appearance not
watched live; the copy below is source-verified, the rest is not).** Title,
verbatim: *"Switch active source"*. Description, verbatim: *"Coarse
reconfigure/reconnect actuator — not a live IS-05 switch. Re-points this
viewer to a different source and is recorded in the audit trail with your
reason."* In plain terms: this is **not** the
instant, frame-accurate crosspoint a real broadcast IS-05 switch (Terms,
above) performs — it's a slower, automation-driven re-point that genuinely
restarts the receiver against the new source. A **Target source** dropdown
lists only the *other* source (e.g. `source-b (checkers-8)` if `source-a`
is currently active) — type a reason, then click **Confirm switch**.

**Expected result — after confirming (UNVERIFIED, confirm on the live
walk).** Per dmf-runbooks' switch playbook, this runs three phases —
quiesce the old source, re-point and restart the receiver, then select the
new source — with a verified rollback if the restart doesn't come up
cleanly. Structurally, that means:

- The receiver's **live preview will likely blip or pause** for a real
  stretch of time (the playbook's own budget allows up to ~120s for the
  restart to verify, plus a fixed ~10s settle before it even starts) — this
  is a **pod restart**, not an instant cut, which is exactly why the
  description above disclaims being "a live IS-05 switch." Don't panic if
  the tile goes quiet for a while; do time it for §9.
- On success, the panel shows a green outcome line (e.g. *"Active
  source: source-b"*), and a **System details** disclosure names the
  request id.
- On failure, the platform automatically rolls the receiver back to its
  previous source and still reports the switch as **failed** — a switch
  that didn't reach its requested target never reports success, even if a
  rollback saved you from a broken state.

---

## 6. Finalise & Review

Close the loop. This is the one beat with a genuine **fork** since the last
edit — teardown alone is no longer the only ending.

**6a. Two endings, mutually exclusive.** On the **Finalise & Review** chip:

- **While anything is running,** the only action offered is **⏏ Teardown**
  (per catalog entry — here, the receiver's own entry). Confirm panel:
  *"Finalises this media function via its AWX teardown template. The action
  is operator-gated and recorded in the audit trail with your reason."*
  **One click here tears down all three pieces**, not just the receiver —
  dmf-runbooks' teardown playbook discovers and removes the topology's two
  source releases by name alongside the receiver's own, in the same job
  (UNVERIFIED against a live run — confirm on §9).
- **Once everything is torn down** (every piece back to a recorded, not-yet
  running state) **and** the read that decides this is fresh and trusted,
  the console instead offers **🗑 Delete permanently** — a *workload-level*
  action, not per-piece. Its confirm panel is marked **destructive** (a
  distinct red treatment) and requires you to **type the workload's own
  slug** to confirm, plus a reason: *"Removes this workload's residual
  catalog records from the source of truth via the finalise-purge
  automation. The entry stops existing — there is no rollback."*
  Per dmf-runbooks' finalise-purge playbook, this is the **only** launcher
  that deletes NetBox records outright (every other launcher only flips a
  lifecycle tag) — it runs under its own delete-only credential for exactly
  that reason, and only declares success once a fresh read confirms every
  member **and** the workload's own tag are gone.

Teardown leaves the record standing (recorded but not running — reusable
later). **This is source-confirmed, not inferred:** the Design step's gate
is literally `const deployed = entry.lifecycle === 'active'`
(`CreateWorkload.tsx` TemplatePicker); the catalog entry's `configure`
action tags success as `lifecycle:active`
(`dmf-media catalog/mxl-videotest-view.yaml:79-83`), and its `finalise`
action — `playbooks/teardown-mxl-fabrics-demo.yml` — tags success as
`lifecycle:bootstrapped` (`dmf-media catalog/mxl-videotest-view.yaml:89-93`).
`bootstrapped` is not `active`, so a successful Teardown clears the
"Already deployed" gate on its own — **Delete permanently is not required
between runs.** What's still unverified is the *round trip*, not the
mapping: that the teardown job actually succeeds, the tag actually lands,
and the Design step's own read actually picks it up promptly — confirm
that chain on the live walk (§9); the mapping itself needs no further
checking.

This makes the journey **repeatable between takes without builder help** —
which directly serves #383's unaided-completion bar: a reader who takes a
wrong turn, or a presenter re-running the demo, can Teardown and start
straight over from §2 with nothing more. Delete permanently goes further,
removing the source-of-truth record outright rather than just flipping the
tag back — with no way to undo that. Use Teardown alone if you plan to run
this journey again soon (the common case); Delete permanently only if you
want no residue left at all. Either one satisfies §0's mandatory
precondition for a next run — with a single-entry catalog, either is
effectively "empty" for this demo's purposes, even though Delete
permanently is the only one that removes the record itself.

**6b. The audit trail — Activity → History.** There is no Activity icon in
the rail — like Catalog, the route still exists, it's simply not linked
from anywhere in the nav (the same S1 IA cut). Type the URL directly:
`https://console.<env-base-domain>/activity/history`.

- **Expected.** The **"Console actions"** panel lists this session's writes
  — a row per action, titled in operator language. Deploy/teardown rows are
  keyed to the *catalog entry*, e.g. *"Deployed mxl-videotest-view"* /
  *"Tore down mxl-videotest-view"* (there being only one entry, that string
  is also the receiver's own instance name here — don't read that as a
  coincidence the console intends). The switch row is keyed to the
  *instance* you switched: *"Switched source on `<instance>`"*. The purge
  row is keyed to the workload slug: *"Deleted `<slug>` permanently"*. Each
  row shows the outcome, the **reason you typed**, in quotes, and
  **`<persona> (<role>) · request <id>`**.
- **Honest scope (say this).** This panel is the actions taken **from this
  console in this browser**, correlated by request id — it deliberately
  does *not* claim facility-wide completeness, because the backend has no
  queryable audit store yet. The durable, facility-wide record is the
  server-side structured log line the backend emits on every write.

**6c. Autonomous re-idle (scale-to-zero) — architectural expectation, not yet
observed.** By design, AWX is meant to scale itself back to zero on its own
some time after the last write, with no operator action — the "actuates,
then sleeps" story §3 sets up. **This rewrite could not confirm that it
actually happens**: the component that runs this reaper loop lives outside
dmf-cms and dmf-runbooks, the only two repos this rewrite could read, so
neither the mechanism nor any timing number could be re-derived from source
(the previous edit's "300s grace / 60s poll" numbers are dropped, not
carried forward, for the same reason). Do not narrate this as something
you've watched happen, and do not quote a number, until §9 confirms it
live. What the source *does* support without that caveat: **the running
media pieces are architecturally independent of AWX's wake/sleep state** —
nothing in dmf-cms or dmf-runbooks ties a media pod's lifecycle to AWX's
own, so it keeps running whether AWX is asleep or awake (the §3
architecture note, from the same source, holds regardless of §6c).

**6d. Workload independence — the closing line, *only* if §6c held.** If
(and only if) you watched AWX actually go back to sleep in §6c: with AWX
asleep and the media pieces still running (if you chose Teardown rather
than an immediate Delete permanently), you have the whole thesis in one
frame — the platform provisions on demand, attributes and audits every
change, runs the media decoupled from its own control plane, and — this
last part, now confirmed live — scales the control plane to zero when idle,
at no cost to what's running. If §6c hasn't actually been observed yet,
skip this closing beat rather than asserting it.

---

## 7. Known rough edges (so you don't improvise)

These are **known, tracked, and non-fatal**, or newly discovered while
writing this rewrite. Knowing them means a hiccup becomes a footnote instead
of a scramble.

| Symptom you might see | What it is | Reference |
|---|---|---|
| Design step's two source pieces show *"This function key isn't in the current catalog… may have been removed"* | False for topology-spawned sources — see §4's presenter note. Cosmetic/legibility only. | not yet filed as of this rewrite — flag for the surface owner |
| Provisioned instances show up **grouped as "Unassigned"** in the grid | The launcher hasn't stamped a `workload:<slug>` tag onto every member, so the grouping logic has nothing to group them by. Cosmetic/legibility only. | [dmfdeploy/dmfdeploy#239](https://github.com/dmfdeploy/dmfdeploy/issues/239) |
| The **first Console action right after a cold wake** returns a **5xx** | Possible transient: the first request can hit AWX in the instant before it's fully ready. Retrying the click is the **documented recovery** for this — unverified whether it always resolves; confirm on the live walk (§9) before promising it as a sure thing. | [dmfdeploy/dmfdeploy#134](https://github.com/dmfdeploy/dmfdeploy/issues/134) |
| Someone asks "what if the node dies?" (spot reclaim) | Not hypothetical — it happened to this env while this rewrite was being written. The standing env's addressing is derived from the node's public IP, so a reclaimed/replaced node means a new address. **Recovery is restore-from-backup + re-converge**, not a resume-in-place. | env recovery notes (operator-local) |

> **PRESENTER NOTE — if a beat stalls.** The two beats with real latency are
> **Provision** (§3, unmeasured against this build — see §9) and **Switch**
> (§5, up to ~120s of receiver restart). If a click 5xxs, retry it (#134).
> Nothing here should send you off-script.

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
- This rewrite's own tracking issue: [dmfdeploy/dmfdeploy#379](https://github.com/dmfdeploy/dmfdeploy/issues/379)

---

## 9. Live-walk verification checklist

**This section exists because this rewrite could not observe a single beat
happen.** Every row below is a claim this rewrite made from source, not from
watching it run. Work through this list on the next live walk; only once
every row is checked does #379's acceptance criterion — *"every expected
result was observed on the live env while writing, not inferred"* — actually
hold. Update the beat above with what you actually saw (including exact
timings, exact screenshots, and exact copy if anything here turns out
wrong), and only then consider closing #379.

- [ ] §1 — Login lands on Workspace; rail is icon-only with exactly the
      three tooltips named; Admin only appears for an admin persona.
- [ ] §2 — The Design step's catalog really does show exactly one entry
      ("MXL Test-Pattern Viewer") with the summary text quoted here,
      verbatim, on screen.
- [ ] §2 — Plan step really does show a single-facility confirmation with no
      picker.
- [ ] §3 — Time the wake + provision, start to a Running workload, on
      *this* build (three pieces in one job). Record the real number here
      and replace every "unverified/do not quote" caveat in §3 with it.
- [ ] §3 — Confirm pods/instances for the receiver and both sources
      actually appear in the inventory and converge to Running — not just
      that the AWX job itself reports success.
- [ ] §3 — Confirm the materializing screen's copy and that the handoff to
      the real workload page happens automatically, with no manual refresh.
- [ ] §4 — Confirm the lifecycle badge really reads "provisioned" (not
      "configured") in the window right after Provision, before health
      settles.
- [ ] §4 — Confirm the live view grid renders exactly three tiles, and
      record each tile's actual rendered name/identifier for the receiver
      and both sources — the two source names were predicted from source,
      not observed.
- [ ] §4 — Confirm both source tiles read "Sidecar live · no preview on
      this side" (not "No live view for this function" — the two captions
      mean different things and this rewrite could not confirm which one a
      topology-spawned source actually gets).
- [ ] §4 — Open the live detail modal and confirm all nine stat fields
      shown (head index, latency, format, grain rate, role, provider, MXL
      version, Active, Node (NetBox)) and that they visibly update at
      roughly the claimed ~5×/s.
- [ ] §4 — Confirm the burnt-in clock overlay actually ticks visibly on the
      receiver's live preview.
- [ ] §4 — Reproduce the Design-step false "removed from catalog" message
      on the two source pieces, screenshot it, and file it if it's real.
- [ ] §5 — Run a real Switch: confirm the dropdown, the description copy,
      the visible pause/restart on the tile, and time the whole thing
      start to finish.
- [ ] §6a — Run a real Teardown and confirm it removes all three pieces,
      not just the receiver, in one job.
- [ ] §6a — Run a real Delete permanently after teardown and confirm the
      typed-slug guard, the destructive styling, and the success copy.
- [ ] §6b — Confirm the Activity → History rows render with the exact
      titles/quoting described here for at least: a deploy, a switch, a
      teardown, and a delete-permanently.
- [ ] §6c — Confirm AWX actually re-idles to zero on its own at all — this
      rewrite could not verify the reaper mechanism exists as described
      (see §6c's own caveat). Only then time the window and decide whether
      it's worth stating a number in the runbook, or leaving it qualitative
      as written here. Do not present §6d until this box is checked.
- [ ] §0/§2/§6a — The lifecycle-tag mapping is source-confirmed
      (`entry.lifecycle === 'active'` gate; `finalise` tags
      `lifecycle:bootstrapped` on success) — what's still open is the round
      trip: run a real Teardown and confirm the job succeeds, the tag
      actually lands, and Design's own read picks it up in time to
      re-offer "Use this template" for a next workload.
- [ ] Read the whole file aloud as if you were the named outsider from #383
      and flag anywhere a term still isn't explained before it's needed.
