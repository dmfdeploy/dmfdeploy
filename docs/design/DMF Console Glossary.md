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
| EBU layer / vertical / lifecycle | dmf-internal | DMF's internal architecture map. **Not yet shown to operators** — needs proof it matches their mental model. |

## Open questions
- Does any EBU-ontology term ever belong at default level? Requires evidence from a real operator workflow (Art. 3).
- Single source of truth so definitions don't drift between tooltip, glossary, and docs.
