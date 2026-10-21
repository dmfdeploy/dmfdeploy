# ADR-0030 archive: DMF Console i18n + air-gap / China deployment posture

This file holds material moved out of [ADR-0030](../../decisions/0030-console-i18n-and-airgap-posture.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **Switch frameworks for Chinese (Vue + vue-i18n, etc.).** Rejected: the hard CJK problems (IME, line-breaking, fonts, plural rules, collation) are browser/CSS/ICU concerns, largely framework-agnostic; the only framework lever is library ecosystem, where React (React Aria, Lingui, FormatJS) is deepest. Abandoning a working React prototype buys little.
- **System CJK font stack (PingFang/YaHei) instead of self-hosting.** Rejected as the *primary* path: the air-gapped flypack/OB-truck hardware can't be assumed to ship CJK fonts. Self-host as the guarantee; a system stack may layer on top where the OS is controlled.
- **react-i18next (JSON) over Lingui (PO).** Rejected for this goal: PO/gettext is the OSS translation lingua franca, is what Weblate round-trips, and is what community translators expect; Lingui is PO-native and ICU-correct.
- **Keep Radix/shadcn.** Rejected for the input/i18n surface: Radix is not IME/i18n-aware and its cadence slowed post-WorkOS acquisition; React Aria covers IME + AAA a11y + i18n. (shadcn-on-Base-UI remains a viable pragmatic accelerator for non-input chrome.)
