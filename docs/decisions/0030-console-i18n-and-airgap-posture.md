# ADR-0030: DMF Console i18n + air-gap / China deployment posture

**Status:** Proposed
**Date:** 2026-05-25
**Deciders:** @<handle>, claude-bottom (console UX evaluation + constitution), with Codex + claude-umbrella review on the ADR-0028 coupling

## Context

The DMF Console (`dmf-cms`) framework was chosen (`IMPLEMENTATION-STRATEGY.md`, 2026-04-28: React 19 + Vite + FastAPI BFF) on criteria — hiring pool, ops-proven, bundle size — that **never included internationalization, accessibility, or offline operation**. Two requirements now make those first-class: (1) **Chinese is a core language**, both Simplified (`zh-Hans`) and Traditional (`zh-Hant`), co-equal with English; (2) the platform must run **in China without reliable Google/GitHub access** and on a **fully air-gapped flypack / OB-truck** lane. The real tension is not "add a language" — it is that the network assumptions baked into a normal web build (CDN fonts, GitHub-hosted translations, DeepL/Google MT, npm/PyPI/Docker Hub at build time, GHCR-canonical images per ADR-0025) are **unavailable or hostile** in the target environments, while the OSS-first goal wants community translation contributions via ordinary git pull requests.

## Decision

The console ships **three co-equal locales — `en`, `zh-Hans`, `zh-Hant`** — none privileged, user-switchable via a persisted preference, designed and tested in all three from day one. Concretely:

- **Catalogs are PO files in the repo.** Community contributes translations via **pull requests to the self-hosted Forgejo** (never GitHub); a **self-hosted, in-cluster Weblate** syncs that repo. The message layer is **LinguiJS** (PO-native, ICU/CLDR plurals — Chinese has a single plural category). `zh-Hant` is a human-owned catalog, **not** code-derived from `zh-Hans`; **OpenCC** (offline) may seed a draft for review. Machine-translation, if used, is **offline/self-hosted** (LibreTranslate / Argos) — never DeepL/Google.
- **Locale-aware formatting uses native `Intl`** (dates 年月日, `RelativeTimeFormat`, pinyin `Collator`); inputs handle **IME composition**. To satisfy IME + AAA accessibility + i18n in one well-maintained dependency, **re-open the Radix/shadcn primitive choice in favour of React Aria Components (Adobe)** — see §Alternatives ("Keep Radix/shadcn", rejected) and the Downstream note below. *(2026-05-30: corrected a dangling "see ADR-0028 coupling below" pointer — no such section existed; ADR-0028 is the Identity & Authority Chain, unrelated to UI primitives. The React Aria re-open is tracked as `dmf-cms` work, not by ADR-0028.)*
- **Fonts self-hosted, baked into the image.** **Noto Sans SC + TC** (region subsets, not the super-font), served from the cluster, selected per-`:lang`. No Google Fonts CDN.
- **The runtime makes zero external network calls** (UX Constitution Art. 15): no CDN, no SaaS telemetry, no external auth/MT. The image is **fully self-contained** — all three catalogs + fonts bake in; every feature works with the internet unplugged. External services exist only in *connected-site authoring* tooling (Weblate, MT seeding), never in the runtime path.
- **Backend emits codes, not prose.** All human-facing localization happens in the frontend; the API returns machine codes + structured data, so there is no second, un-localized copy of the truth.

## Consequences

- **Positive** — Console runs in China and on the air-gapped truck with no behavioural change; community can contribute translations through a familiar PR flow on infra we control; ICU plurals and `Intl` make CJK correct by construction; React Aria fixes IME + accessibility + i18n together; "works offline" becomes a testable property (Art. 15).
- **Negative** — Three catalogs to keep in sync (en/Hans/Hant are separately human-owned); CJK fonts add image weight (mitigated: LAN/in-cluster served, never external); re-opening the Radix/shadcn choice is migration work; build-time dependency sourcing must change (below).
- **Neutral** — RTL is explicitly **not** required (both languages LTR); logical-properties discipline kept only as cheap future insurance. The framework headline (React + Vite + FastAPI BFF, TanStack Query, Tailwind) is **unchanged** — and arguably reinforced, since React has the deepest i18n/a11y/real-time ecosystem.

## Build-time posture (flagged, not resolved here)

Runtime image pull is already air-gap-safe (cluster **Zot** mirror, ADR-0025). The remaining exposure is **build-time**: `npm ci` / `pip` / base images (`node`, `python`) fetch from sources throttled or blocked in China, and **GHCR-canonical** (ADR-0025) assumes a build host that can reach GitHub. A China-built or truck-bound image needs **registry/package mirrors or a fully offline dependency cache**, producing a self-contained artifact. This is an infrastructure decision that belongs to **ADR-0020 (deployment scope / regulatory posture)** and **ADR-0025 (registry canonicality)**; ADR-0030 only asserts the *outcome* (self-contained image) the console depends on.

## Alternatives considered

- **Switch frameworks for Chinese (Vue + vue-i18n, etc.).** Rejected: the hard CJK problems (IME, line-breaking, fonts, plural rules, collation) are browser/CSS/ICU concerns, largely framework-agnostic; the only framework lever is library ecosystem, where React (React Aria, Lingui, FormatJS) is deepest. Abandoning a working React prototype buys little.
- **System CJK font stack (PingFang/YaHei) instead of self-hosting.** Rejected as the *primary* path: the air-gapped flypack/OB-truck hardware can't be assumed to ship CJK fonts. Self-host as the guarantee; a system stack may layer on top where the OS is controlled.
- **react-i18next (JSON) over Lingui (PO).** Rejected for this goal: PO/gettext is the OSS translation lingua franca, is what Weblate round-trips, and is what community translators expect; Lingui is PO-native and ICU-correct.
- **Keep Radix/shadcn.** Rejected for the input/i18n surface: Radix is not IME/i18n-aware and its cadence slowed post-WorkOS acquisition; React Aria covers IME + AAA a11y + i18n. (shadcn-on-Base-UI remains a viable pragmatic accelerator for non-input chrome.)

## Enforcement

- **UX Constitution** Arts. 12 (multilingual) + 15 (self-contained/air-gap) are the principle source; Art. 15's "no runtime external call" is testable (network-cut smoke test; CSP with no external origins).
- **Discipline + CI (to build):** a locale-completeness check across en/zh-Hans/zh-Hant; a build/runtime guard that fails on any external-origin fetch (font, script, API); `@axe-core/playwright` for the accessibility slice (Playwright already wired).
- **Downstream:** build-time mirror/offline-cache strategy tracked under ADR-0020 / ADR-0025; React Aria migration tracked as `dmf-cms` work, not started by this ADR.
