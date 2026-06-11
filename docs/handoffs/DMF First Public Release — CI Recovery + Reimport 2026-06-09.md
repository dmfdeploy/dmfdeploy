# DMF First Public Release — CI Recovery + Reimport (2026-06-09)

> **Recovery event, recorded per codex guardrail #1.** Not hidden history churn — an
> explicit, authorized delete+reimport of the 7 clean-import public repos to fix CI
> workflow bugs + one operator-identity miss that landed in the initial public commits.

## Why

The 7 clean-import repos were flipped public on 2026-06-09, then their CI went red.
Root causes (codex-confirmed, no real secret leaked):

1. **Harness non-authoritative (version skew):** `bin/export-scan.sh` ran the operator's
   **system gitleaks 8.30.1**; `guard.yml` pins **8.21.2** — different default rulesets.
   So export-scan missed what guard catches. Re-scan with pinned 8.21.2: only **dmf-infra**
   had extra findings = 3 `private-key` **placeholders** in the upstream Forgejo Helm chart
   (`charts/forgejo/{README.md,values.yaml}` — example/commented `privateKey:` blocks with
   `...` bodies). **No real key.** Other 6 clean under 8.21.2.
2. **actionlint sha256 wrong** (qwen's pin `...effaecb2b73cc44584f5`; real
   `...effaecce67290e7e0757`) → `guard` actionlint job failed on all repos.
3. **dmf-cms operator-identity miss:** `docs/DEVELOPMENT-AND-BUILD-RULES.md:437` =
   `**Owner:** Loz` reached the public commit (that doc path is allowlisted in the gitleaks
   operator-identity rule). Not a credential, but violates the no-operator-identity invariant
   → in the public history → reimport required.
4. **Per-stack CI bugs** (E1 workflows never run on real runners until now): ansible
   `yamllint -s` (real errors: document-start/line-length/truthy/braces); dmf-cms trivy
   **react-router 7.14.2 CVE-2026-42342** (fixed 7.15.0) + pytest missing `src/dmf_cms/static`;
   dmf-init pytest needs `age` on the runner; dmf-env `tofu fmt` (main.tf) + `sops` not in
   apt + `shellcheck` too broad.

## Pre-recovery public state snapshot (all 0 forks/stars/subs/issues → reimport-safe)

| repo | HEAD (pre) | tag | guard | ci |
|---|---|---|---|---|
| dmf-central | 7a9906f0eff8 | v0.1.0 | fail | fail |
| dmf-cms | dd52b8be31d0 | v0.10.0 | fail | fail |
| dmf-infra | ff60263085c4 | v0.1.0 | fail | fail |
| dmf-media | 91ce47e2df97 | v0.1.0 | fail | fail |
| dmf-init | e3c0df6895b1 | v0.1.2 | fail | fail |
| dmf-env | 0d12d9e5d8a7 | v0.1.0 | fail | fail |
| dmf-promsd | 9f6a0dd271e4 | v0.1.3 | fail | ci ok |

## Plan (operator-approved 2026-06-09; codex qualified-AGREE on option i)

1. **Harness:** `export-scan.sh` downloads+verifies+version-asserts pinned **gitleaks 8.21.2**
   (no system fallback); corrected actionlint sha256 in all `guard.yml`.
2. **CI/content fixes** (codex D1-D7) committed to each repo's local main.
3. **dmf-cms:** fix `Owner: Loz`.
4. **Re-verify** each with the corrected harness (pinned 8.21.2) + local actionlint.
5. **Per repo (guardrails 2-5):** re-check 0 external activity → delete → recreate →
   push corrected orphan → flip public → re-harden (rebase-only + 3 rulesets + secret
   scanning, bypass_actors empty) → independent re-verify (fresh clone, refs, gitleaks 8.21.2,
   identity grep, settings, rulesets, first Actions).
6. **dmf-runbooks:** NOT reimported (release-forward) — fixes via its **PR #1** (now mergeable:
   `lkirc` joined the maintainers team, so a CODEOWNER approval is available).

## Notes
- `lkirc` added to `dmfdeploy/maintainers` (2026-06-09) → PR review now possible; future
  contributions + PR #1 merge unblocked.
- The maintainers team (all-repo Write) now has 2 members; reimport flips keep the
  flip→ruleset window tight. Rulesets bind everyone (no bypass).
