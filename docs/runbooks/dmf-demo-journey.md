# DMF Platform Demo Journey

**Status:** Presenter-facing runbook. The full end-to-end demo of the DMF
platform on a **standing sandbox env**, from operator login through the
media-workload lifecycle. Written to be executed by **someone who did not
build the platform** — every beat gives a concrete action and the expected
result, so you never have to improvise in front of an audience.

**Scope note — written against the *current* single-source lifecycle.** The
coarse connection-intent **Switch** beat lands with **v0.2b**
([dmfdeploy/dmfdeploy#201](https://github.com/dmfdeploy/dmfdeploy/issues/201));
until then §6 is a marked placeholder and the journey is a single-source
walk. This runbook is part of the v0.2 presentable-journey track
([dmfdeploy/dmfdeploy#200](https://github.com/dmfdeploy/dmfdeploy/issues/200),
[#203](https://github.com/dmfdeploy/dmfdeploy/issues/203)).

**Assumes:** a standing env is already deployed and healthy (bring-up is
[`dmf-deploy-quickstart.md`](dmf-deploy-quickstart.md) — *not* repeated here).
This runbook starts at "the cluster is up; now show it off."

**Intent model:** `docs/processes/README.md` (BPMN 2.0) for *why* each beat
exists; this file is the *how* to present it.

---

## 0. Presenter pre-flight

Do these **before** the audience is watching. Roughly 5 minutes.

**Placeholders.** This runbook uses `<env>` for the environment slug and
`<env-base-domain>` for the env's base domain — the console is at
`https://console.<env-base-domain>/`, auth at `https://auth.<env-base-domain>/`.
For the **standing sandbox env** the base domain is **IP-derived sslip.io**:
`<node-public-ip-dashed>.sslip.io` (the node's public IP with dots as dashes),
so the console resolves at `https://console.<node-public-ip-dashed>.sslip.io/`.
Substitute the real values from the env's operator-local notes — **never**
paste real IPs into a shared screen or chat.

**Repo paths.** The component repos are **siblings** of the umbrella (since the
2026-06-11 public restructure — `../dmf-env`, `../dmf-infra`, … next to the
umbrella, *not* nested inside it). Set one variable up front and reuse it for
every command below:

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
| Media namespace clean (optional reset) | ask the operator, or leave prior workloads running | a clean `mxl` namespace makes the "materialises from nothing" beat land harder |

**Demo persona role.** The journey visits both **Catalog** (needs the operator
capability or above) and **Media Workloads** (needs **engineer/admin** role
*or* membership of the `media-engineers` group — see §5). Note the two rails
gate differently: `media-engineers` membership **does** grant the Media
Workloads rail (even to a viewer-role member), but it does **not** grant
Catalog, which still needs operator+. The simplest persona that covers *both*
rails in one role is **engineer (or admin)** — log in as that so nothing is
hidden and §5 can be shown.

If passkeys show `0/2` or `1/2`, complete
[`passkey-enrollment.md`](passkey-enrollment.md) **before** the demo — do not
try to enrol a first passkey live; the ceremony has authenticator-choice
pitfalls that runbook covers in full.

> **PRESENTER NOTE — pacing (non-blocking).** The single slow beat is the
> **cold AWX wake** on the first Provision click (~60 s, §3). Everything else
> is interactive-fast. Narrate the wake ("the platform is scaled to zero at
> rest; this click is spinning the automation plane up on demand") so the
> pause reads as a *feature*, not a hang.

---

## The journey at a glance

| # | Beat | What the audience sees | Surface |
|---|---|---|---|
| 1 | **Log in** | Passkey login as a demo persona — no password | Console |
| 2 | **Catalog** | The menu of provisionable media functions | Console → Catalog |
| 3 | **Provision** | One click → automation plane wakes → workload goes Running | Console → Catalog → Deploy |
| 4 | **Configure** | The companion viewer provisioned and reported healthy | Console + verifier |
| 5 | **Operate** | Media Workloads grid, **live sidecar preview** on the viewer tile | Console → Media Workloads |
| 6 | **Switch** *(v0.2b, placeholder)* | Re-point a viewer to a different source | *lands with #201* |
| 7 | **Finalise & review** | Audit trail (Activity → History), autonomous re-idle, workload independence | Console + cluster |

---

## 1. Log in

Passkey **enrollment is done beforehand** (the persona already has 2/2
confirmed devices — you verified this in §0 pre-flight; the full ceremony
lives in [`passkey-enrollment.md`](passkey-enrollment.md)). This beat is just
the login.

**Action.** Open `https://console.<env-base-domain>/` in a private/incognito
window. Click **Sign in**. The browser offers the passkey picker; choose the
demo persona's authenticator and complete the WebAuthn ceremony (Touch ID /
security-key touch).

**Expected result.** You land on the Console **Workspace** home as the demo
persona (a fictitious demo identity, e.g. `marty-mcfly` — never a real
operator name). No password was typed. The top-right user menu shows the
persona; the left rail shows Workspace, Facilities, Media Workloads, Catalog
(the persona has the engineer capability, so both Catalog and Media Workloads
are visible).

> **PRESENTER NOTE — SECURITY (non-blocking).** This is the whole identity
> story in one gesture: **passkey-only, no passwords**
> ([ADR-0015](../decisions/0015-dmf-console-passkey-only.md)), and the platform
> mandates **≥2 confirmed devices per human**
> ([ADR-0028 D8](../decisions/0028-identity-and-authority-chain.md)) so a lost
> authenticator never locks anyone out. To *add* a device you use the
> Console's Settings → *Create new device invitation* (self-service); full
> procedure in [`passkey-enrollment.md`](passkey-enrollment.md).

If you want to show enrollment itself (optional, adds ~2 min, **requires an
admin persona** — the invitation endpoint `POST /api/admin/invitations` is
admin-gated, so an engineer persona gets a 403; skip this beat if you're
demoing as engineer): user menu → **Settings** → **Passkey Enrollment** →
**Create new device invitation** → a single-use URL + QR renders. Don't
complete it live unless you have a second authenticator to hand — just show
that the invitation minted.

---

## 2. Catalog

**Action.** From the left rail, open **Catalog**. This is the menu of media
functions the platform can provision onto the facility.

**Expected result.** The Catalog lists the available functions. For the
single-node standing env the headline pair is **"MXL Test-Pattern Source"**
(catalog key `mxl-videotestsrc` — an EBU DMF MXL video test-pattern producer)
and its companion **"MXL Test-Pattern Viewer"** (key `mxl-videotest-view` —
the receiver/preview half). Each catalog entry describes what it deploys.

> **PRESENTER NOTE — the mental model (non-blocking).** The Catalog is the
> "what could run here" list; **Provision** (next beat) turns a catalog entry
> into a live software-defined media workload on the facility. This is the
> Facilities → Media Workloads split: the facility is already provisioned
> (the standing env); the Catalog is how you place *workloads* onto it.

---

## 3. Provision — the click that wakes the platform

This is the signature beat: **one console click drives the whole actuation
chain** — wake the automation plane, run a real job, materialise a workload.

**Action.** In the Catalog, open **"MXL Test-Pattern Source"** and click
**Deploy**. When prompted, enter a **reason** for the write (reason-required;
e.g. "demo: provision test-pattern source") and confirm.

**Expected result — watch it unfold, in order:**

1. **The click wakes the automation plane.** The Console backend `POST`s to
   `/ensure-awake` *before* launching, so the click itself is the wake — no
   out-of-band trigger. AWX is scaled-to-zero at rest; this scales it `0→1`.
   Cold wake to a live AWX API is **~60 s** (measured ~62 s on the gate walk).
2. **A real AWX job runs and completes.** The provision job launches against
   the now-awake AWX and **completes ~1–2 min after the wake** (~97 s after
   the AWX API came up, on the gate walk).
3. **The workload materialises.** The `mxl` namespace goes from empty
   ("No resources found") to the source workload **Running**. End to end —
   **click to a live, Running workload in under 4 minutes** (~3m35s on the
   gate walk; the source pod is `mxl-videotestsrc-initiator`, 5/5 Running).

You can narrate the wait with the cluster view if a terminal is on screen:

```bash
# Optional live proof (operator terminal). SSH target from the env's inventory.
ssh <ssh-target> 'sudo k3s kubectl get pods -n mxl -w'
```

Expected: the `mxl-videotestsrc-initiator` pod appears and transitions to
`Running` (5/5).

> **PRESENTER NOTE — ARCHITECTURE (non-blocking).** **AWX is the *actuator*,
> not the runtime.** It provisions the workload and then gets out of the way:
> the media workload runs **decoupled from AWX's wake/sleep cycle**. You will
> prove this in §7 when AWX re-idles to zero and the workload keeps running.
> A second provision click landing *mid-idle-countdown* simply **resets the
> wake window** (single-flight `/ensure-awake`) rather than racing a second
> wake — so back-to-back provisions are safe.

> **PRESENTER NOTE — SECURITY (non-blocking).** That reason you typed is not
> cosmetic: **writes are reason-required** (a missing/empty reason is refused
> with a 400 *before* any AWX call), and the reason is recorded in the **C5
> audit trail** ([ADR-0028](../decisions/0028-identity-and-authority-chain.md)):
> actor + effective role + request-id + reason. You will read these back in §7
> (Activity → History). Every provision here is an *audited, attributed*
> action tied to the logged-in persona.

---

## 4. Configure

**Action.** Provision the companion **"MXL Test-Pattern Viewer"** the same way
(Catalog → **MXL Test-Pattern Viewer** → **Deploy** → reason → confirm), so
there is a source *and* a viewer to show in Operate. Then confirm the platform
considers the workloads configured and healthy.

**Expected result.** The second workload (pod `mxl-videotest-view-target`)
goes **Running** in the `mxl` namespace, in the same sub-4-minute envelope —
but with **no second cold-wake wait**, because AWX is already awake from §3.
The pair — a test-pattern **source** and its **viewer** — is the configured
topology for the single-source demo.

Optional objective proof (the all-green verifier, if the operator wants to run
it live — it takes a few minutes):

```bash
cd "$DMF_ENV"
bin/run-playbook.sh <env> \
    ../dmf-infra/k3s-lab-bootstrap/bootstrap-verify.yml
```

Expected in an **awake** window: `failed=0`, all green, and the D8 passkey
gate green. (See §8 for the one known asleep-window caveat on this play.)

---

## 5. Operate — the Media Workloads grid + live preview

This is the payoff beat: the operator's live view of running media.

**Action.** From the left rail, open **Media Workloads**. You see a grid of
tiles, one per running workload.

**Expected result.**

- A **grid of tiles** for the running workloads, each showing its instance
  **active / running (1/1)**.
- The **viewer tile shows a live sidecar preview** of the flow the viewer is
  receiving — its caption reads **`Live · sidecar preview`**, and the preview
  frame is proxied live from the instance's MXL status sidecar (the source-level
  guarantee is a live receiver-side preview, refreshed continuously). On the
  standing env the received flow is EBU DMF MXL test-pattern bars carrying a
  **burnt-in clock that visibly ticks second-by-second** (live evidence from the
  gate walk) — point at the ticking seconds to prove it's a live frame, not a
  thumbnail.
- The **source tile caption reads `Sidecar live · no preview on this side`.**
  The source *generates* the pattern; it has no inbound flow to preview, so the
  platform says so rather than showing a blank or a fake image. **Call this
  out** — it's a correctness signal, not a missing feature.
- Click the viewer tile to open the **live detail modal** (single detail
  surface): a larger live preview plus flow stats (head index, latency,
  format, grain rate) that tick ~5×/s. The source's modal shows
  **"No preview on this side"** with the same live flow stats.

> **PRESENTER NOTE — MONITOR (non-blocking).** The Console's own **Monitoring**
> rail is the at-a-glance facility health view; the tile preview answers "is my
> media flowing?". For deeper telemetry, **Grafana** (dashboards + alerts) is
> fed by the cluster's monitoring stack — open it in a second tab if the
> audience wants metrics/alerting depth.

> **PRESENTER NOTE — SECURITY (non-blocking).** The Media Workloads surface is
> **hard-gated server-side** (not just hidden in the nav): reaching it — even
> the **grid read** — requires the **engineer/admin** role **or** membership of
> the `media-engineers` group (`_require_media_workloads_access`, ADR-0037 §5).
> So:
> - **Unauthenticated** request to `/api/media-workloads` → **401**.
> - **A plain viewer** (below engineer, not in `media-engineers`) → **403 on
>   the whole surface** — they don't even see the grid; the rail is hidden for
>   them too.
> - **In-surface writes** (deploy/clear-for-deployment) additionally require a
>   non-empty **reason** → **400** without one.
>
> If you have a plain-viewer login to hand, switching to it and being bounced
> off the surface is a strong beat; if not, state it — it's enforced
> server-side on every gated endpoint either way (view-as downgrade included).

---

## 6. Switch — *placeholder, lands with v0.2b (#201)*

> **This beat is not in the current build.** The coarse connection-intent
> **Switch** — re-pointing a viewer from one source to another via the Console
> — ships with **v0.2b**
> ([dmfdeploy/dmfdeploy#201](https://github.com/dmfdeploy/dmfdeploy/issues/201):
> multi-source topology + launcher source selection + connection-intent
> switch). **Until it lands, the demo is a single-source lifecycle** — one
> source, one viewer, no crosspoint.
>
> **What to say to the audience:** "Re-pointing a viewer to a different source
> is the next increment — the platform is single-source today; the switch is
> the v0.2b beat." Do not improvise a switch; there is no supported path yet.
> When #201 lands, this section gets rewritten with the concrete action +
> expected result and the scope note at the top of this file is removed.

---

## 7. Finalise & review

Close the loop by showing the three properties that make this a *platform*,
not a demo script.

**7a. The audit trail — Activity → History.** From the left rail open
**Activity**, then the **History** tab (rail: `Activity`; tab: `History`;
direct URL `.../activity/history`).

- **Expected.** The **"Console actions"** panel lists the writes from this
  session — a row per deploy. Each row renders the catalog **key** (not the
  display name), so you'll see **"Deployed mxl-videotestsrc"** and
  **"Deployed mxl-videotest-view"** — each showing the **outcome / state
  transition**, the **reason string you typed** in quotes, and
  **`<persona> (<role>) · request <id>`** (the C5 quartet: actor, effective
  role, request-id, reason).
- **Honest scope (say this).** This panel is the actions taken **from this
  console in this browser**, correlated by request-id — it deliberately does
  *not* claim facility-wide completeness, because the backend has no queryable
  audit store yet. The **durable, facility-wide** audit record is the
  **server-side C5 structured log line** the backend emits on every AWX write
  (a queryable console-wide audit lane is a follow-up). So for the live demo,
  do the two deploys and open Activity → History **in the same browser**.

**7b. Autonomous re-idle (scale-to-zero).** Leave AWX untouched. After the idle
grace period it **scales itself back to zero**:

- The reaper enforces a **300 s grace period** after the last active work and
  polls on a **60 s loop**, so it patches AWX to `state=asleep` on the **first
  reaper pass after the grace period expires — within ~1 min of expiry** — with
  no operator action.
- **Crucially, the running media workloads are unaffected** — they stay
  `Running` right through the re-idle. This is the architecture beat from §3
  made concrete: **AWX actuates, then sleeps; the media keeps flowing.**

Optional proof (operator terminal — the AWX namespace is `awx`):

```bash
ssh <ssh-target> 'sudo k3s kubectl get deploy -n awx awx-web -o jsonpath="{.spec.replicas}{\"\n\"}"'
# expect 0 after the grace period; meanwhile:
ssh <ssh-target> 'sudo k3s kubectl get pods -n mxl'
# expect the workloads still Running
```

**7c. Workload independence — the closing line.** With AWX asleep (0 replicas)
and the media workloads still Running, you have shown the whole thesis in one
frame: the platform provisions on demand, attributes and audits every change,
runs the media decoupled from its own control plane, and scales the control
plane to zero when idle — at no cost to what's running.

---

## 8. Known rough edges (so you don't improvise)

These are **known, tracked, and non-fatal**. Knowing them means a hiccup
becomes a footnote instead of a scramble.

| Symptom you might see | What it is | Reference |
|---|---|---|
| The verifier play shows **1 failure** while AWX is asleep: `699-cms-smoke-test` "Verify AWX token is valid…" → **503** | That one task lacks the skip-when-asleep guard its siblings have. It is a **503 *because AWX is asleep***, not a platform fault — it flips to pass in an awake window. Run the verifier §4 *after* a Provision (awake) to see it green. | [dmfdeploy/dmfdeploy#233](https://github.com/dmfdeploy/dmfdeploy/issues/233) |
| Provisioned instances show up **grouped as "Unassigned"** in the grid | Catalog deploys don't yet stamp a `workload:<slug>` tag, so the (correct) grouping logic has nothing to group them by. Cosmetic/legibility only — the workloads are fine. | launcher-stamping follow-up, [dmfdeploy/dmfdeploy#5](https://github.com/dmfdeploy/dmfdeploy/issues/5) |
| The **first Console action right after a cold wake** returns a **5xx** | Possible transient: the first request can hit AWX in the instant before it's fully ready. **Just retry the click** — it succeeds. Defensive retry-on-first-5xx is tracked. | [dmfdeploy/dmfdeploy#134](https://github.com/dmfdeploy/dmfdeploy/issues/134) |
| Someone asks "what if the node dies?" (spot reclaim) | The standing env's addressing is **sslip.io, derived from the node's public IP**, so a reclaimed/replaced node means a new address. **Recovery is restore-from-backup + re-converge** (restore the operator-local package, re-point addressing), not a resume-in-place. A deliberate tradeoff for cheap standing infra, not a bug. | env recovery notes (operator-local) |

> **PRESENTER NOTE — if a beat stalls.** The two beats with real latency are
> the **cold wake** (§3, ~60 s — expected) and the **verifier play** (§4/§8,
> a few minutes — optional). Everything else is interactive. If a click 5xxs,
> retry it (#134). If the verifier shows the single 699 failure, confirm AWX
> is awake (#233). Nothing here should send you off-script.

---

## 9. References

- Bring-up (deploy the standing env): [`dmf-deploy-quickstart.md`](dmf-deploy-quickstart.md)
- Passkey enrollment (full ceremony + pitfalls): [`passkey-enrollment.md`](passkey-enrollment.md)
- Identity & authority chain: [ADR-0028](../decisions/0028-identity-and-authority-chain.md)
- Console passkey-only: [ADR-0015](../decisions/0015-dmf-console-passkey-only.md)
- Intent model (BPMN 2.0): `docs/processes/README.md`
- Demo track / acceptance: [dmfdeploy/dmfdeploy#203](https://github.com/dmfdeploy/dmfdeploy/issues/203)
  (part of [#200](https://github.com/dmfdeploy/dmfdeploy/issues/200))
