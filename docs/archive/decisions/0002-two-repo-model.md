# ADR-0002 archive: Two-repo model — generic playbooks vs private inventory

This file holds material moved out of [ADR-0002](../../decisions/0002-two-repo-model.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **Single private repo.** Simpler tooling, defeats the credibility/OSS goals.
- **Single public repo with secrets in OpenBao only.** All references would need
  to be runtime-resolved; some structural config (real ingress URLs in
  `external_base_url`) is awkward to fully externalize. Two-repo model is more
  practical.
