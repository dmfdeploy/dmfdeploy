# DMF Console — Glossary

**Status:** 🚧 Stub — seed entries only. Owns the procedural detail behind **[UX Constitution](DMF%20Console%20UX%20Constitution%202026-05-25.md) Art. 3** ("Speak the operator's language, and teach the facility's").

## Why this doc exists
Art. 3 splits vocabulary into three tiers. This glossary records, for every term the console might show, **which tier it sits in** and its **one-sentence plain-language definition** (which must itself avoid jargon). The in-place "ⓘ" affordances and any help surface read from here.

Per Art. 12, definitions are **tri-lingual — `en` / `zh-Hans` / `zh-Hant`** (each human-owned; OpenCC may seed the Hant draft for review). Domain *acronyms* (`NMOS`, `PTP`, `ST 2110`) stay Latin in every locale; only their definitions translate.

## Tiers
- **system** — infrastructure/implementation jargon. **Hidden at default**, shown at expert only.
- **industry** — standard broadcast-industry vocabulary. **Kept and explained in place.**
- **dmf-internal** — DMF's own architecture ontology. **Must earn operator-native status** via a real operator workflow; until then treated as expert/internal.

## Seed entries (to validate + expand)

| Term | Tier | Plain definition (draft) |
|---|---|---|
| NMOS | industry | The standard that lets media devices discover and connect to each other over the network. |
| IS-04 / IS-05 | industry | The specific NMOS parts for *finding* devices (04) and *connecting* them (05). |
| PTP | industry | The clock that keeps every device in the facility perfectly in time. |
| ST 2110 | industry | The standard for sending professional video/audio as separate streams over IP. |
| AWX job | system | An automation run on the platform; an implementation detail — surface the *outcome*, not the job. |
| EBU layer / vertical / lifecycle | dmf-internal | DMF's internal architecture map. **Not yet shown to operators** — needs proof it matches their mental model. Where per-entry values must be inspectable (Catalog), they sit behind a collapsed "System details" affordance, never default-level (#173 WP1). |
| Media Function | industry → operator-native (promoting) | One deployable media-processing capability (e.g. a test-pattern source, a viewer). ADR-0037 §6 records the Media Workloads page as the real-workflow evidence promoting this term out of `dmf-internal`. |
| Media Workload | industry → operator-native (promoting) | The set of deployed Media Function instances doing a job — what is running, how many, and where. Page name per ADR-0037; the assembly/graph sense arrives with the runtime flow overlay. |
| Facilities | operator | The sites and rooms the platform manages; nav label (was "Facility", #173 WP1). |
| Media stack (by node) | operator | Plain heading for the per-node view of what is running at each level of a media host — replaces the default-level "EBU DMF layer stack" heading (#173 WP1). |

## Wording-pass log
- **2026-07-04 (#173 WP1):** nav `Facility` → `Facilities`; MxlFlows h1 `EBU DMF layer stack` → `Media stack by node` (+ "6-layer teaching grid" empty-state line neutralized); Catalog per-entry `Layer N · vertical · owner` line demoted into a collapsed "System details" affordance; Catalog hero "lifecycle status" → "deployment status". Row captions inside the (WP4-retiring) MxlFlows grid intentionally untouched (plan OQ-3, minimal-copy call).

## Open questions
- Does any EBU-ontology term ever belong at default level? Requires evidence from a real operator workflow (Art. 3).
- Single source of truth so definitions don't drift between tooltip, glossary, and docs.
