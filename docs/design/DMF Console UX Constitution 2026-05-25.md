# DMF Console — UX Constitution

**Date:** 2026-05-25 · **Last revised:** 2026-05-25 (second pass, after Codex review)
**Status:** **Advisory north-star**, with a small **hard-gate subset** that is binding now (see §3). Consistent with ADR-0004 (experiment phase): we gate only the trust/safety core and let the rest guide rather than block, hardening as the console matures.
**Applies to:** `dmf-cms` (the operator console) and any future operator-facing surface of the DMF Platform.
**Audience:** every agent and human who designs, builds, reviews, or words any part of the console.

---

## 0. The reframe — why this document exists

The DMF Console is **a control room, not a SaaS app.**

Most "dashboard design" advice optimises for analysts exploring data at leisure. An operator console for a live broadcast facility is a different animal: it exists so that someone responsible for things that are *happening right now* can understand state and act under time pressure. The right precedents therefore come less from web-app fashion and more from forty years of **industrial HMI**, **alarm management**, and **public-sector plain-language** practice — disciplines that already solved most of our problems.

This document is the overarching goal all future work moves toward. It states **principles**; procedural detail lives in dedicated downstream docs (see §6) so the constitution stays principled and ages well rather than rotting into a spec.

> **North Star**
> *An operator who knows nothing about Kubernetes, Ansible, or NMOS internals can look at the console and always know three things: **is the facility healthy, what just changed, and what — if anything — they need to do.***

---

## 1. Who we design for — the operator model

We design for **many roles, at two levels of depth, across cultures.** Three independent axes; keeping them separate is what stops the design from sprawling.

### Role — *what you are here to do* (scopes capability)
Role decides **which surfaces and actions exist for you at all.** A media operator does not see cluster-bootstrap controls hidden behind "advanced" — those are simply **not in their world.** Roles are a small, bounded set derived from **human identity / RBAC (OIDC groups, via Authentik)**, so "what I can see / do / did" all trace back to one human (see Art. 10 — the *executor* of an action is often a per-app service account, kept distinct from the requesting human; and identity scopes *visibility*, not the *truth* of state, which comes from the observed systems per Art. 1).

### Level — *how much detail you want* (scopes disclosure)
Within the surfaces your role already has, level decides depth: **default ↔ expert.**
- **Default** speaks the operator's language, hides system internals, and **must stand entirely on its own.**
- **Expert** reveals implementation detail (job IDs, logs, layers, raw status) for those who want it — **more resolution, not more noise**; it still obeys every other article.
- **Exactly two levels.** Resist a third. Level is a **persisted per-user preference**, never a per-page toggle that resets.

### Locale & culture — *who you are and where you are* (scopes expression)
Dates, time, number formats, and the meaning of colour all vary. The console ships **three co-equal locales — `en`, `zh-Hans`, `zh-Hant`** — from day one (Chinese is core, not an add-on; Arts. 11–12, ADR-0030), and must run **air-gapped in China** with no external dependency (Art. 15).

> **Discipline that keeps this linear, not combinatorial:** *every state is designed at **default** first.* Expert detail and locale formatting are transforms layered on top — never the primary design.

---

## 2. The Articles

Each article is a principle, the reason it holds, and what it means in practice. Articles marked **【GATE】** are binding now (§3); **【GATE: near-term】** is binding soon. Articles that own procedural detail point to a downstream doc with **→ detail:**.

### Art. 1 — Never present uncertainty as certainty **【GATE】**
In a distributed control plane the UI rarely knows *the* truth — it knows **observed** state (possibly stale), **requested/desired** state, **last-known**, or **cached** state. The console must never render any of these as confirmed-current truth. State carries its **provenance**: source, freshness, confidence, and **observed-vs-requested** (the same split as Kubernetes `status` vs `spec`).
*Why:* an operator who can't tell live from stale, or actual from desired, has no basis to act. Hiding uncertainty is the subtlest way the screen lies. (Nielsen heuristic #1, extended for distributed state.)
*In practice:* "last updated 4s ago"; a value that failed to refresh is visibly stale, not silently frozen; "requested: torn down · observed: still running" when they disagree.

### Art. 2 — Close every loop **【GATE】**
Every operator action produces a visible, unambiguous outcome — **success, failure, or in-progress** — anchored where the action was taken. Nothing vanishes into the void.
*Why:* feedback is the basis of agency (Norman). An action with no observable consequence teaches the operator the console is unreliable.
*In practice:* a teardown click resolves to a clear success or a **persistent** failure state on that card — never a badge that quietly disappears.
→ detail: Audit / Event-Log spec (the durable record behind the transient outcome).

### Art. 3 — Speak the operator's language, and teach the facility's
Split vocabulary in three, not two:
- **System / infrastructure jargon** (`k8s`, `Ansible`, `AWX job #168`, exit codes, tracebacks) → **hidden at default, revealed at expert.** This is *our* implementation leaking.
- **Industry-standard domain vocabulary** (`NMOS`, `IS-04/05`, `PTP`, `ST 2110`) → **kept and explained in place.** This is the operator's actual profession; hiding it is condescending.
- **DMF-internal architecture ontology** (the EBU **layer / vertical / lifecycle** taxonomy) → **treated as suspect.** It must **earn** operator-native status by appearing in a real operator workflow; until then it is expert/internal, not default vocabulary. Do not assume our architecture map is the operator's mental model.

*Why:* plain language is faster for everyone, including experts; codes don't reach non-developers (GOV.UK). And our own ontology is the easiest jargon to mistake for the user's.
*In practice:* domain terms carry a tappable info affordance (not hover-only) giving a one-sentence plain definition. **Never define jargon with more jargon.**
→ detail: Glossary (plain-language definitions + which tier each term sits in).

### Art. 4 — Alarms are classified, and have a lifecycle **【GATE: see Art. 8 for the error half】**
"Calm by default; loud only when it matters" — but *loud* is not binary. Conditions are classified by **severity and required response**, not merely "actionable / not." Some conditions can't be fixed by the operator yet still demand a response: **escalate, acknowledge, suppress-during-maintenance, watch a degradation, call engineering.** Each class carries a defined response and a **lifecycle**: acknowledge, shelve, suppress-by-design, out-of-service, expiry.
*Why:* ISA-101 keeps ~90% of the screen neutral so real problems pop; EEMUA 191 / ISA-18.2 demand alarms be necessary, unique, and rationalised to prevent the "alarm flood" that trains operators to ignore the system; Google SRE: an unactionable page is noise.
*In practice:* normal state is visually quiet; no console-error spam, no perpetual retry against a dead endpoint, no "notifications" that aren't a classified condition. A severity that can't be silenced or acted on shouldn't be an alarm.
→ detail: **Alarm Philosophy doc** (the class taxonomy, priorities, lifecycle rules — ISA-18.2 explicitly mandates such a document).

### Art. 5 — The screen is still unless the world moved **【GATE: near-term】**
Live data updates **in place.** No full-page refresh, flash, reflow, or lost scroll/selection. When semantic state hasn't changed, **nothing moves.**
*Why:* a list that collapses and rebuilds on every poll (measured on `/changes`: 0 of 10 DOM nodes survive an identical-data refresh) is **false motion** — it destroys situational awareness, not just polish. Modern data layers (stale-while-revalidate, keyed reconciliation, optimistic updates) make in-place patching the default. *Near-term rather than day-one only because it's more implementation-sensitive than the trust/safety gates.*
*In practice:* updates patch only changed rows; previous data stays visible during revalidation; the list never collapses-and-rebuilds.

### Art. 6 — Right information, right moment (just-in-time)
Overview answers *"are we OK?"* at a glance; detail is one deliberate step away; configuration takes deliberate intent. Don't make the operator hunt; don't drown them.
*Why:* progressive disclosure reduces error and load (Nielsen) — **with the caveat** that operational monitoring sometimes *needs* density, so we never hide what live awareness genuinely requires.
*In practice:* a top layer shows facility health; drilling in reveals the device/flow/job detail behind any status.

### Art. 7 — Safe things easy, dangerous things deliberate **【GATE】**
Match friction to consequence; a single confirmation dialog everywhere just becomes muscle memory. Classify actions: **reversible · disruptive · destructive · security-sensitive.** Friction is graduated to fit — and the most effective guard is **preflight impact preview** ("this stops 3 live flows"), not a yes/no. Consequential actions capture the ADR-0028 **C5 quartet — actor, role, request-id, reason** (which is in fact baseline for *every* DMF-initiated automated action, not just dangerous ones); heavier classes may add typed confirmation, **re-authentication / fresh OIDC assurance or stronger RBAC** (per C1 — *never* a local/break-glass admin), a stated rollback, or two-step execution.
*Why:* error prevention beats error messages (Nielsen); habituated confirmation prevents nothing; a destructive control with zero friction is an incident waiting to happen (observed: teardown fires on a single click).
*In practice:* "Tear down NMOS Registry? Media flows that depend on it will stop routing." with the concrete impact enumerated.
→ detail: **Dangerous-Action spec** (the consequence-class → friction matrix, ADR-0028-aligned).

### Art. 8 — Errors are content, not exceptions **【GATE】**
Raw/system errors never leak at default. Every default error tells the operator three things: **what happened, what it means for the facility, and what to do next** (or who to call). Raw detail is available at expert level only.
*Why:* GOV.UK — error messages describe what happened and how to fix it; codes and jargon don't reach non-developers.
*In practice:* `"Failed to fetch commits: slice(None, 5, None)"` becomes "Recent changes are temporarily unavailable. Retrying… — [Retry now]". The traceback lives behind expert level.

### Art. 9 — Design the unhappy path first
Loading, empty, partial, failed, stale, **degraded-network, offline** — these are the operator's *everyday* reality in a control plane, and they are **first-class designed states**, not accidents. (Degraded/offline is not a separate scenario article: its visible state is designed here; its *meaning* — stale vs unknown — is carried by Art. 1's provenance.)
*Why:* in operations the happy path is the rare path; an undesigned failure state is where trust dies.
*In practice:* every panel ships its loading / empty / partial / failed / stale / disconnected designs **before** its "all good" state.

### Art. 10 — One accountability chain across four authority planes
**What you see** (Art. 1/6), **what you can do** (Art. 7), and **what you did** are linked through the ADR-0028 authority chain — not three divergent sources. Concretely: **Authentik** scopes the human and role; **dmf-cms** records the human *request*; **service accounts** execute downstream; **all records correlate by `request_id`.** The chain captures *who **requested*** an action (actor · role · request-id · reason) even though the executor at the leaf is usually a **per-app service account**, not the human — so requester and executor stay **distinct.**
*This is an accountability chain, not one credential.* ADR-0028 deliberately keeps **four linked planes**: human identity (Authentik), machine/service identity (per-app), secret custody (OpenBao), and audit (dmf-cms request log + downstream correlation). So authorization and accountability **share a human-identity root but are different mechanisms** — and, tying back to Art. 1, **identity scopes what you may *see*, but it does not make state *true*; provenance comes from the observed systems.** **Break-glass** is the *designed, sanctioned* exception (emergency / bootstrap only, audited under C4/D8); an *unsanctioned* local/shadow account acting is a **drift/security finding, not a valid path** — audit must tell the two apart.
*Why:* if capability, visibility, and audit drift apart, the system lies by omission and incidents can't be reconstructed.
*In practice:* the action that fired a teardown, who *requested* it, under which session, why, which service account *ran* it, and how it ended are one record correlated by `request_id`; the UI's "what changed" view is a read of that same history.
*Current-phase footnotes:* multi-user is deferred (ADR-0028 / Identity Model §1) — today `ops-admin` is single-member and undifferentiated. ADR-0028 **C5** binds the actor/role/request-id/reason quartet for **every** DMF-initiated automated action (not only dangerous ones). D6 attestation is **experiment-phase dmf-cms attestation, not cryptographic non-repudiation.**
→ detail: **[Audit / Event-Log Spec](DMF%20Console%20Audit%20and%20Event-Log%20Spec.md)** (record schema; ADR-0028-aligned).

### Art. 11 — Accessible by default (perception & input)
Independent of language or locale, the console must be **perceivable and operable by everyone, hands-or-not:**
- **Colour is never the only signal.** Red-means-danger isn't universal and ~8% of men are red-green colourblind, so every status is **redundantly encoded**: colour **+** shape/icon **+** text **+** position, legible with colour stripped entirely (WCAG; also solves the cross-cultural colour problem).
- **Contrast and legibility** suited to long shifts and varied lighting.
- **Keyboard / no-mouse operation** is first-class — a control room may be operated by keyboard, gloves, or a panel, not a trackpad. Every action reachable and visible focus throughout.
- **Motion respects `prefers-reduced-motion`** and is functional only (see Art. 13).
*Why:* accessibility here is operability under real control-room conditions, not a compliance checkbox.

### Art. 12 — Multilingual and culture-safe (English + Chinese, co-equal)
Chinese is a **core** language, not a later add-on. The console ships **three co-equal locales — `en`, `zh-Hans` (Simplified), `zh-Hant` (Traditional)** — none privileged, user-switchable via a persisted preference (same mechanism as level, §1), designed and tested in all three from day one.
- **Separate catalogs, ICU/CLDR throughout.** `zh-Hant` is *not* code-derivable from `zh-Hans` (vocabulary differs, not just glyphs) — each is human-owned; **OpenCC** (offline) may seed a Hant draft for review. Chinese has a single plural category, so any `count === 1 ? … : …` is a bug — use ICU MessageFormat.
- **Community translation via git PRs, all in-cluster.** Catalogs are **PO files in the repo**; contributors open **pull requests against the self-hosted Forgejo** (never GitHub); a **self-hosted Weblate** syncs that repo. Machine-translation, if any, is **offline/self-hosted** (LibreTranslate / Argos) — never DeepL/Google (blocked in China, dead in air-gap).
- **CJK fonts are first-class assets (Art. 14):** self-host **Noto Sans SC + TC** (region subsets, not the super-font), **baked into the image** and served from the cluster — no Google Fonts CDN (blocked + air-gap). Apply font + line-break rules per `:lang`.
- **Time/number/sort are locale-aware, never ambiguous** — native `Intl` for dates (年月日), relative time ("2分钟前"), and `Collator` (pinyin/stroke). Never `5/23/2026`.
- **Inputs handle IME composition** (Pinyin / Bopomofo / Cangjie) — text fields survive `compositionstart/end`.
- **Backend emits codes, not prose.** All human-facing text localizes in the frontend (ties Art. 8); the API returns machine codes + structured data, so there is no second, un-localized copy of the truth.
- **Domain acronyms stay, definitions localize** (ties Art. 3): `NMOS`/`PTP`/`ST 2110` remain Latin; their plain-language glossary definitions are translated.
- RTL is **not** required (English + Chinese are both LTR); keep logical-properties discipline only as cheap insurance for a future RTL language.
*Why:* Chinese users are first-class operators; a missing locale or ambiguous format is a truth failure (Art. 1), not polish.
→ detail: **[Glossary](DMF%20Console%20Glossary.md)** (tri-lingual term definitions) · ADR-0030 (i18n + air-gap deployment posture).

### Art. 13 — Tone proportional to the moment
Warmth is welcome — but tone must **track operational severity.** In calm states the console may be humane, unhurried, even quietly pleasing ("all systems nominal"; "nothing to do here — that's good"), which lowers intimidation for users to whom a clinical tone reads as cold or threatening. **In an incident, tone shifts to gravity and concision** — cheerful copy during a facility-down event is not delightful, it undermines urgency and is a *safety* problem.
*Why:* delight is earned on a foundation of truth/calm/safety, not peer to it (Walter's hierarchy puts the pleasurable layer last); and the deepest delight in a control room is **competence felt** — "a knowledgeable assistant that hands the right instrument exactly when needed." **No gamification** — no streaks, badges, confetti, or anything that trivialises a live facility or rewards the wrong instinct.
*In practice:* the same console reads as a calm colleague at rest and a terse, focused one under alarm — never a kernel panic, never a party.

### Art. 14 — Performant and responsive *(advisory)*
The console feels immediate: fast first meaningful paint, no jank, motion in the 150–300ms band, work off the main thread where it matters.
*Advisory, deliberately un-numbered:* concrete latency budgets are set **per real surface** once those surfaces exist — we don't invent target numbers in the abstract, because meaningless budgets are worse than none. Promote to a gate per-surface when a budget is real and measured.

### Art. 15 — Self-contained and air-gap-ready
The console makes **zero runtime dependency on any external network** — no CDN fonts or scripts, no SaaS telemetry, no external auth or translation services. All assets, fonts, and locale catalogs are served from the cluster and **bake into the image**; every feature must work with the internet unplugged.
*Why:* the platform's reach makes "works offline" a **correctness property, not an optimization** — it must run in **China without Google/GitHub**, and on the **air-gapped flypack / OB-truck** lane with no internet at all. External services may appear only in *connected-site authoring* tooling (e.g. Weblate, machine-translation seeding), **never in the runtime path**.
*In practice:* fonts self-hosted (Art. 12), no `<script src="cdn…">`, no runtime telemetry beacon; a feature that can't survive the network being cut is not done. (Build-time dependency sourcing — npm/pip/base images — is an infra concern: see ADR-0030 and the ADR-0020/0025 build-posture tension.)

---

## 3. Hard gates (binding now)

Everything above guides; these **block**. A change that reintroduces a violation is not done.

**Day-one gates** — the trust & safety core:
1. **No uncertainty presented as certainty.** State shows provenance/freshness; stale ≠ live; requested ≠ observed. *(Art. 1)*
2. **Every operator action closes its loop at the point of action.** *(Art. 2)*
3. **Dangerous actions require graduated friction + impact preview**, with the actor/role/request-id/reason quartet captured per ADR-0028 (C5 baseline for *all* automated actions; elevation via re-auth, never a local admin). *(Art. 7)*
4. **Raw/system errors never leak at default;** default error content says what happened, facility meaning, and next step. *(Art. 8)*

**Near-term gate** — binding soon, held off pass-one only for implementation sensitivity:
5. **No disruptive refresh/reflow of live operational lists when semantic state hasn't changed.** *(Art. 5)*

Performance/latency is **not** a gate yet (Art. 14) — advisory until real surfaces and measured budgets exist.

---

## 4. Anti-patterns we have actually measured

Worked examples observed on the live console (testlab, 2026-05-25) — the regression bar.

| What we saw | Articles violated |
|---|---|
| A **failed teardown** rendered as an unchanged green "active" card — no toast, no error, no notification, no log. The only place it surfaced was a *different page*. | 1, 2, 8 |
| `/changes` **polls every 30s and rebuilds the entire list** even when data is byte-identical (0 of 10 DOM nodes survive; list collapses to ~1 row then refills → visible flash). | 5 |
| Two endpoints **500 forever**, polled twice per tick with no backoff → 116+ console errors; the "Notifications" bell is an unrelated Prometheus feed, not classified conditions. | 4 |
| UI shows **`Layer 5 · orchestration · configure`** to an operator and leaks **`slice(None, 5, None)`** from the backend. | 3, 8 |
| Timestamps shown as **`5/23/2026`** (ambiguous outside the US). | 12 |
| **Teardown fires on a single click** with no confirmation or impact preview. | 7 |

---

## 5. The disciplines we borrow from

- **Industrial HMI / situational awareness** — ISA-101 High-Performance HMI: grayscale-normal, colour = abnormal, layered overview→detail.
- **Alarm management** — EEMUA 191 / ISA-18.2 / IEC 62682: alarms necessary, unique, actionable; classes + lifecycle; no alarm floods.
- **Reliability alerting** — Google SRE: symptom-based, every page actionable, automate away noise.
- **Plain-language content design** — GOV.UK Design System & content guidance: write for users not experts; errors say what happened and how to fix it.
- **Dashboards & disclosure** — Nielsen Norman Group: operational vs. analytical dashboards, information hierarchy, progressive disclosure (and its limits).
- **Real-time UI** — stale-while-revalidate, keyed reconciliation, optimistic updates with rollback (e.g. React Query / `useOptimistic`).
- **Emotional design & motion** — Aarron Walter's hierarchy of user needs; NN/G theory of delight; functional-animation timing and `prefers-reduced-motion`.
- **Accessibility** — WCAG (colour not the sole signal, contrast, keyboard operability, focus visibility).

(Full source links accompany the evaluation that produced this document, 2026-05-25.)

---

## 6. Downstream docs this constitution points to

The constitution states principles; these own the procedural detail (stubbed now, ADR-0028-aligned where identity/audit is involved):

- **[Alarm Philosophy](DMF%20Console%20Alarm%20Philosophy.md)** — alarm classes, priorities, and lifecycle (Art. 4).
- **[Dangerous-Action Spec](DMF%20Console%20Dangerous-Action%20Spec.md)** — consequence-class → friction matrix (Art. 7).
- **[Audit / Event-Log Spec](DMF%20Console%20Audit%20and%20Event-Log%20Spec.md)** — the attributable see/do/did record schema (Arts. 2, 10).
- **[Glossary](DMF%20Console%20Glossary.md)** — plain-language definitions + vocabulary tier per term (Art. 3).

---

## 7. How to use this document

- **Building a surface?** Design the default level first, the unhappy path first, and check the result against every article — and against the §3 gates specifically.
- **Reviewing a change?** §3 gates block; the §4 anti-pattern table is the regression bar.
- **Tempted by an exception?** Exceptions outside the gates are allowed but must be *named* — say which article you're trading against and why. Silent drift is what this document exists to prevent.

### Open questions (next)
1. The concrete **role set** and its OIDC-group mapping (feeds Arts. 1, 7, 10).
2. Authoring the four §6 downstream docs.
3. When each near-term/advisory item is ready to promote to a hard gate.

---

### Revision history
- **2026-05-25 (pass 1)** — initial draft: North Star, operator model, 12 articles, anti-patterns.
- **2026-05-25 (pass 2, after Codex review)** — Art. 1 reframed to uncertainty/provenance; Art. 3 three-tier vocabulary (EBU ontology demoted to "earn it"); Art. 4 reframed to alarm classes + lifecycle; Art. 7 reframed to consequence taxonomy + impact preview; Art. 9 names degraded/offline as first-class; old Art. 10 repurposed to the see/do/did identity chain; Art. 11 split into Accessibility (11) + Localisation (12); delight reframed to "tone proportional to the moment" (13); Performance added as advisory (14). Authority resolved: advisory + a 4 day-one / 1 near-term hard-gate subset. §6 downstream-doc pointers added.
- **2026-05-25 (pass 3, ADR-0028 reconciliation — claude umbrella pane + Codex)** — Art. 10 reframed from "one identity chain" to **"one accountability chain across four authority planes"** (Authentik human-identity / per-app machine-identity / OpenBao custody / dmf-cms audit); requester-vs-executor split made explicit; `request_id` named as the correlation key; "identity scopes visibility, not truth" tied to Art. 1. Art. 7 + gate #3 sharpened to the C5 quartet (actor/role/request-id/reason — baseline for *all* automated actions), elevation via re-auth not break-glass. Audit/Event-Log stub schema expanded (structured actor, actor_type, role_snapshot, executed_as, session_id, attestation_kind, posture, structured downstream_refs, WORM/D7 streaming export); break-glass classified (sanctioned vs unsanctioned-shadow-finding).
- **2026-05-25 (pass 4, China / air-gap + Chinese-core)** — Art. 12 rewritten from generic "localised" to **English + Chinese (`zh-Hans` + `zh-Hant`) co-equal**: PO catalogs + community git PRs against self-hosted Forgejo, in-cluster Weblate, OpenCC/LibreTranslate offline MT, self-hosted vendored Noto SC/TC, IME composition, backend-emits-codes, ICU plurals. New **Art. 15 — self-contained & air-gap-ready** (zero runtime external deps; runs in China without Google/GitHub and on the air-gapped flypack/OB-truck). §1 locale axis names the three co-equal locales. Decisions recorded in **ADR-0030** (skipping 0029, earmarked for tiered-unseal posture).
