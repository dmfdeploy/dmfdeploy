# docs/design — operator console design

Design source-of-truth for the DMF operator console (`dmf-cms`).

**Start here:**
- **[DMF Console UX Constitution 2026-05-25.md](DMF%20Console%20UX%20Constitution%202026-05-25.md)** — the overarching goal: North Star + 15 articles, the operator model (role × level × locale — English + Chinese `zh-Hans`/`zh-Hant` co-equal), and the binding **§3 hard-gate subset** (advisory otherwise, per ADR-0004 experiment phase). Deployment posture (China / air-gap) in ADR-0030.

**Downstream specs it points to** (stubs — procedural detail lives here so the constitution stays principled, not procedural):
- **[Alarm Philosophy](DMF%20Console%20Alarm%20Philosophy.md)** — alarm classes + lifecycle (Art. 4; ISA-18.2-style).
- **[Dangerous-Action Spec](DMF%20Console%20Dangerous-Action%20Spec.md)** — consequence → friction matrix (Art. 7; ADR-0028-aligned).
- **[Audit / Event-Log Spec](DMF%20Console%20Audit%20and%20Event-Log%20Spec.md)** — the see/do/did record schema (Arts. 2/10; ADR-0028-aligned).
- **[Glossary](DMF%20Console%20Glossary.md)** — plain-language definitions + vocabulary tier per term (Art. 3).

**Provenance:** drafted from a live console UX evaluation (2026-05-25), grounded in ISA-101 / EEMUA-191 / ISA-18.2 / Google SRE / GOV.UK / NN/G, then reviewed by Codex and the sibling Claude pane (ADR-0028 reconciliation — "one accountability chain across four authority planes").
