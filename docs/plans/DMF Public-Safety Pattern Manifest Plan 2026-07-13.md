---
status: active
date: 2026-07-13
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/212
---
# DMF Public-Safety Pattern Manifest Plan (2026-07-13)

> **STATUS: ACTIVE — SPEC ONLY.** This round delivers the design; it changes no
> scanner, hook, or workflow. Implementation is a separate dispatch after this
> spec is codex-gated. Tracking: [#212](https://github.com/dmfdeploy/dmfdeploy/issues/212)
> (sub-issue of [#206](https://github.com/dmfdeploy/dmfdeploy/issues/206), the
> public-safety-scanning evaluation + its adversarial review).

## 0. Problem in one paragraph

The DMF public-safety gate works, but its pattern definitions are **scattered
across three representations kept in lock-step by hand** — a bug class, not a
config choice. The same operator-private identity/topology literals exist as (a)
shell arrays in `~/.dmfdeploy/scrub-private-patterns.sh` in a fragile
`'PCRE|description'` format, (b) combined ERE regex strings in that *same* file
under different variable names, and (c) TOML rules in the gitignored
`.gitleaks.local.toml`; some secret shapes (SOPS age keys) are *also* duplicated
into the public `bin/scrub-public-repos.sh`. Four entry-point scripts and five
gitleaks invocation contexts consume these with **three different regex engines**
and **inconsistent fail-open/fail-closed behavior**. This plan replaces the
hand-mirroring with a **single partitioned manifest** (public + operator-private)
that generates every downstream view, unifies on fail-closed, and closes a
worktree-detection hole — with no reduction in coverage at any point.

---

## 1. Current-state map (authoritative inventory)

> Line references are against the tip this spec was written on. The implementation
> dispatch must re-confirm them; they are accurate as of 2026-07-13.

### 1.1 The four gate entry points

| Entry point | Role | Pattern source(s) it loads | Regex engine | Missing-private behavior |
|---|---|---|---|---|
| `bin/scrub-public-repos.sh` (274 ln) | Pre-publish sweep, all public repos or `--tree <dir>` | public `SECRET_PATTERNS` (in-script) + private `DMF_PRIVATE_IDENTITY_PATTERNS` / `DMF_PRIVATE_TOPOLOGY_PATTERNS` arrays sourced from the include (L99–108) | `git grep -nP` (PCRE) L190 | **FAIL-OPEN** — warns, runs "generic checks only", topology category prints "(skipped)" (L105–108, L224–227) |
| `bin/export-scan.sh` (152 ln) | Clean-history orphan export of one repo + run every gate on that scratch tree | delegates to the other gates; pins gitleaks | n/a (orchestrator) | inherits scrub's fail-open; pinned-gitleaks **hard-fail** if binary absent (L41,53) |
| `bin/check-public-repo-hygiene.sh` (163 ln) | Artifact-presence gate (LICENSE/NOTICE/VERSION/.gitignore/CODEOWNERS/`.gitleaks.toml`/pre-commit hook) | none (file existence only, L72) | n/a | n/a |
| `bin/dmf-env-public-surface-gate.sh` (155 ln) | Publish-safety gate for the `dmf-env` tree (allowlist + ban-list + content scan) | private `DMF_PRIVATE_IDENTITY_REGEX` / `DMF_PRIVATE_TOPOLOGY_REGEX` **combined-string** vars from the *same* include (L111–114) | `git grep -nIiE` (ERE, case-insensitive) L122,126 | **FAIL-CLOSED** — missing include is a hard fail (L112) |

**Inconsistency #1 (fail-open vs fail-closed):** scrub warns-and-skips; the
env-gate hard-fails. Same missing file, opposite outcome.

**Inconsistency #2 (two private-include contracts in one file):** the include
`~/.dmfdeploy/scrub-private-patterns.sh` must define **four** variables in **two
shapes** — `*_PATTERNS` arrays (`'PCRE|desc'`, for scrub) *and* `*_REGEX`
combined strings (for the env-gate). Nothing enforces that the two shapes agree.

**Inconsistency #3 (three regex engines):** scrub uses PCRE (`grep -P`), the
env-gate uses ERE (`grep -E`), gitleaks uses Go `RE2`. A pattern authored for one
is not guaranteed valid/identical in the others.

### 1.2 Every active public-safety gitleaks invocation context

> Scope: the **active** public-safety path only. Retired/mothballed call sites —
> `bin/sync-to-github.sh` and the `bin/agentic/` hook templates — also invoke
> gitleaks but fail closed behind explicit overrides and are **out of R1 scope**
> (not part of the live gate). They are excluded here deliberately, not missed.

| Context | Command (essence) | Config used | Pinned? | Private rules? | Fail mode if gitleaks missing |
|---|---|---|---|---|---|
| `.githooks/pre-commit` pass 1 | `gitleaks protect --staged` | implicit repo-root `.gitleaks.toml` | no (system) | no | **WARN + skip** (L43) |
| `.githooks/pre-commit` pass 2 | `gitleaks protect --staged --config .gitleaks.local.toml` (only `if [ -f ]`) | `.gitleaks.local.toml` | no | yes, **if present** (silent no-op if absent) | as above |
| `.githooks/pre-push` pass 1 | `gitleaks detect --log-opts=<range>` | implicit `.gitleaks.toml` | no | no | **WARN + skip** |
| `.githooks/pre-push` pass 2 | `... --config .gitleaks.local.toml` (only `if [ -f ]`) | `.gitleaks.local.toml` | no | yes, if present | as above |
| `.github/workflows/guard.yml` tree scan | `gitleaks detect --source . --no-git --config /tmp/gitleaks.toml --exit-code 1` | **BASE-resolved** config (`git show BASE:.gitleaks.toml`, never the PR-controlled file) L21–31 | **yes 8.21.2 + sha256** | **no** (private config never on CI) | job fails (binary is fetched) |
| `guard.yml` history scan | `gitleaks detect --source . --log-opts=<base..head> --config /tmp/gitleaks.toml` | BASE-resolved | yes | no | skipped if no usable range (L61–63) |
| `bin/export-scan.sh` no-git | `cd scratch && gitleaks detect --source . --no-git --config .gitleaks.toml` L109 | public `.gitleaks.toml` (exported tree) | **yes 8.21.2 + sha256** | no | hard-fail |
| `bin/export-scan.sh` log scan | `... --log-opts=main` L110 | public `.gitleaks.toml` | yes | no | hard-fail |
| `bin/dmf-env-public-surface-gate.sh` check 4 | `gitleaks detect --no-git --source .` L133 | **default rules, NO `--config`** | **no (system)** | no | soft (only appends if it errors) |

**Inconsistency #4 (version/config skew):** the pre-publish (`export-scan`) and CI
(`guard.yml`) gates pin gitleaks 8.21.2 + sha and pass an explicit config; the
local hooks use system gitleaks with the implicit config; the env-gate's gitleaks
pass runs **default rules with no config at all**. Three different gitleaks
behaviors gate the same secrets. `export-scan` documents *why* pinning matters:
"default rulesets drift between versions; that skew let private-key placeholders
through on 8.30.1 once" (L36).

**Inconsistency #5 (CI is inherently public-only):** `guard.yml` never has
`.gitleaks.local.toml` (it is gitignored, never pushed). CI therefore enforces
**only** the public rule set. This is correct and unavoidable — but it means the
private identity/topology net exists *only* at local commit/push time and at the
operator's pre-publish sweep. Any design must preserve that: private coverage is a
local/pre-publish responsibility, and public contexts must fail closed on the
public rules while explicitly opting out of the private set.

### 1.3 The pattern definitions today (where each lives)

| Category | Public home (tracked) | Operator-private home (gitignored / operator-local) |
|---|---|---|
| Secrets/credentials | `SECRET_PATTERNS[]` in `bin/scrub-public-repos.sh` (L71–85) + default gitleaks rules + custom rules in `.gitleaks.toml` (dev-changeme, macos-metadata, generic cloud-resource-id shape) | SOPS age keys **duplicated** into `.gitleaks.local.toml` `dmf-private-age-key` (comment: "lock-step mirror") |
| Internal topology | generic shape only (`dmf-cloud-resource-id` in `.gitleaks.toml`) | specific host IPs / CGNAT host octets / cloud resource-ID literals — `.gitleaks.local.toml` `dmf-private-topology` **and** the include's `*_TOPOLOGY_*` vars |
| Operator identity | macOS-metadata rule only (`dmf-macos-metadata`, in-script) | operator names, OpenBao `role_id`/accessor UUIDs, age recipient/secret-key — `.gitleaks.local.toml` + include's `*_IDENTITY_*` vars |
| Operational context | empty array | (none) |

**The lock-step burden** the manifest removes: a single new private topology
literal must today be hand-edited into **three** places in the matching format
(`*_PATTERNS` array entry, `*_REGEX` alternation, `.gitleaks.local.toml` rule),
and an age-key change touches **four** (add the public `SECRET_PATTERNS` mirror).
`.gitleaks.toml` L12–16 and `.gitleaks.local.toml` L1–19 both carry "keep the two
in LOCK-STEP" comments — an admission that the invariant is manual.

### 1.4 The pipe-delimiter hazard (concrete)

`scrub-public-repos.sh` parses each array entry with `rx="${entry%%|*}"` and
`desc="${entry#*|}"` (L187–188). Bash `%%|*` cuts at the **first** literal `|`.
A regex that itself contains an alternation — e.g. any `(a|b)` pattern — silently
truncates: the rule becomes just the text before the first pin, and the rest is
mis-parsed as the description. The gate then runs a **weaker pattern than
intended and still reports green**. (See the umbrella #133 lineage: an
account-fingerprint form was missed by the manual enumeration.) This class of
error must be **impossible or loudly detected** in the new format — the central
constraint on the manifest schema (§4).

### 1.5 The worktree-skip hole

`bin/scrub-public-repos.sh` decides "is this a repo?" with `[ ! -d "$rpath/.git" ]`
(L180, and again L251). In a **git worktree**, `.git` is a *file* (a `gitdir:`
pointer), not a directory — so the test is true and the repo is **silently
`continue`d / skipped**, reporting clean without scanning anything.
`check-public-repo-hygiene.sh` has the same `[ ! -d "$repo_path/.git" ]` test
(L85) but *fails* instead of skipping. `bin/export-scan.sh` **also** rejects a
worktree source via `[ -d "$SRC/.git" ]` (L69–72) — but it too **fails closed**
(refuses to export) rather than silently passing. The hooks already avoid the
problem — they use `git rev-parse --show-toplevel` (`.githooks/pre-commit` L17,
`.githooks/pre-push` L24) — and `dmf-env-public-surface-gate.sh` avoids it too (it
drives everything through `git ls-files` / `git grep` on a `--tree` path). So
there are **three** `-d .git` sites, of **two severities**: one **silent-skip**
coverage gap (`scrub-public-repos.sh` L180/L251 — the dangerous one) and two
**fail-closed** refusals (`check-public-repo-hygiene.sh` L85, `export-scan.sh`
L69–72). §7 unifies all three on one resolver; only the scrub skip is a live
coverage gap. (Corroborated by the standing "scrub gate skips worktree" note.)

---

## 2. Design overview

Four moving parts, each a section below:

1. **One partitioned manifest** — public entries tracked, private entries
   operator-local; the single source of truth for every pattern (§3).
2. **A delimiter-safe, engine-aware schema** — structured fields, no
   `pattern|desc` packing; build-time validation across all three engines (§4).
3. **One scan library/CLI** the four entry points call, generating **ephemeral
   merged configs** per trust context, unified on **fail-closed** with an
   *authorization-gated* opt-out (§5.4) and machine-readable failure classes
   (§5.5) — §5, §6.
4. **Hardening + proof**: worktree-detection fix + wrapper regressions (§7); an
   old→new **structural parity gate** before any caller switch (§9.1); and a
   **trust-context acceptance matrix** of seeded canaries (§8).

---

## 3. The partition: public vs operator-private manifest

**Hard constraint (non-negotiable):** no operator-private pattern literal may
ever appear in any file tracked in a public repo — including the public
`.gitleaks.toml`, the manifest's public half, the scan library, tests, or CI
config. Publishing a protective pattern publishes what it protects.

### 3.1 Two files, one schema

- **Public manifest — tracked at `patterns/public-manifest.toml`** (umbrella root,
  a new tracked path — **decided**, see §11, not an open question). Holds: secret *shapes* (provider
  token formats, PEM headers, embedded-URL creds), the generic topology shapes
  (`dmf-cloud-resource-id`), the macOS-metadata and known-LAN-dev-credential rules
  (`dmf-macos-metadata`, `dmf-dev-changeme`), and the gitleaks tuning (allowlists,
  `useDefault`). Everything here is public-safe by
  construction — it describes *classes*, never operator-specific values.
- **Private manifest — operator-local**, **decision: `~/.dmfdeploy/pattern-manifest.private.toml`**
  (overridable via `DMF_PATTERN_MANIFEST_PRIVATE`). Holds the high-precision
  identity/topology/age literals.

**Location rationale (surveyed):** two operator-private locations exist today —
`~/.dmfdeploy/scrub-private-patterns.sh` (operator-home) and the in-repo,
gitignored `.gitleaks.local.toml`. Keep the **source** under `~/.dmfdeploy/`
because (a) it already holds the private include, (b) ADR-0035 establishes
`~/.dmfdeploy/` as the operator-local state root (nothing per-operator is
committed), and (c) it is physically outside every repo tree, so it *cannot* be
committed by accident. `~/.config/dmf/` (XDG) was considered and rejected: it is a
new location with no precedent here and buys nothing over the established path —
gratuitous churn against the "no weaker window / least migration" rule (§9). The
generated `.gitleaks.local.toml` **stays a gitignored in-repo file** because the
`gitleaks` binary needs an on-disk config the hooks reference by path.

### 3.2 What is a generated view vs a source

Single source → generated views (all regenerated by one generator, `--check`-gated
so drift is impossible, exactly like `generate-plans-index.sh` / `check-working-model-sync.sh`):

| Artifact | Kind | Generated from |
|---|---|---|
| `patterns/public-manifest.toml` | **source** (tracked) | hand-authored |
| `~/.dmfdeploy/pattern-manifest.private.toml` | **source** (operator-local) | hand-authored |
| `.gitleaks.toml` **`[[rules]]` region** (marker-fenced) | **generated view** (tracked) | public manifest |
| `.gitleaks.toml` header prose + `[extend]`/global `[allowlist]` | **hand-authored** (tracked, *outside* the marker) | — |
| `.gitleaks.local.toml` (private rules region) | **generated view** (gitignored) | private manifest |
| scan-library git-grep passes | **read directly** from the manifests at runtime | both manifests |

Note the collapse: the shell `*_PATTERNS`/`*_REGEX` includes **disappear**. The
scan library reads the manifest directly for its `git grep` passes, so there is no
longer a shell-array view to keep in lock-step — only the gitleaks TOML configs
remain as generated views, because gitleaks is a separate binary that requires its
own config file. Three hand-synced representations → one source per trust tier +
mechanically-generated gitleaks rule regions.

**Hybrid (partial-file) generation — the gitleaks configs are NOT whole-file
generated.** Each gitleaks config is split by a marker pair
(`# >>> DMF-GENERATED RULES (do not edit) >>>` … `# <<< DMF-GENERATED RULES <<<`,
mirroring `check-working-model-sync.sh`'s block markers). Everything a human tuned
by hand — the file's prose header, `[extend] useDefault = true`, and the global
`[allowlist]` — lives **above the marker and is never touched by the generator**.
Only the `[[rules]]` region **between** the markers is generated from the manifest,
and `--check` verifies **that region** byte-for-byte (the public file diffs
literally, §4.2). This keeps the prose hand-editable, makes "byte-identical"
well-defined at region scope, and leaves global gitleaks settings to a human.

---

## 4. Manifest schema (delimiter-safe, engine-aware)

TOML (same format the gitleaks configs already use). Each pattern is a table with
**named fields**, never a delimiter-packed string — this makes the §1.4 pipe
truncation *structurally impossible*:

```toml
# patterns/public-manifest.toml  (illustrative shape — made-up XTOK- prefix,
# NO real provider value and NO private value here)
[[pattern]]
id             = "example-provider-token"
category       = "secret"          # secret | topology | identity | context
description    = "example provider token shape"
regex          = '''\bXTOK-[0-9A-Z]{10}\b'''  # TOML literal string: pipes, backslashes safe
engines        = ["re2", "ere", "pcre"]        # engines this pattern must MATCH-agree under
case_sensitive = true              # explicit; generator emits the right flag per engine
severity       = "blocking"        # blocking | informational
positive_canaries = ["XTOK-ABC1234567"]        # MUST match under every listed engine
negative_canaries = ["xtok-lowercased", "XTOK-short"]   # MUST NOT match under any engine

# How this entry maps into the generated gitleaks [[rules]] region (§4.3):
[pattern.gitleaks]
emit                  = true        # false ⇒ covered by the default pack; no explicit rule
kind                  = "custom"    # "custom" (own regex) | "override" (tune a default rule)
tags                  = ["dmf"]
comment               = "rendered verbatim as #-lines above the rule in the region"
allowlist_description = "meta files that intentionally name the pattern"
allowlist_paths       = ['''^\.gitleaks\.toml$''']
```

Private patterns carry the same fields — including their canaries and a
`[pattern.gitleaks]` sub-table where relevant — in the operator-local private
manifest, never here.

Design rules:

1. **`regex` is a first-class field**, TOML triple-single-quoted. A `|` inside it
   is data, never a delimiter. The description is its own field. The old
   `${entry%%|*}` split cannot exist.
2. **Engine *matching* semantics are declared and proven — not just compilation**
   (§4.1). Every pattern carries `case_sensitive` + positive/negative canary
   strings; `--check` runs those canaries as real *match tests* under each listed
   engine (`git grep -P`, `git grep -E`, gitleaks/RE2). A pattern that compiles
   everywhere but *matches* differently — word boundaries, anchors, inline flags,
   case (cf. the env-gate's case-insensitive identity vs case-sensitive topology,
   L119–126) — fails the build. This is what actually proves "coverage ≥ today"
   (Inconsistency #3 closed).
3. **One pattern, many emitted forms.** The generator renders each entry into
   whatever each consumer needs: a gitleaks `[[rules]]` block (public or private
   config by `category`+visibility), and the library's in-memory pass list. No
   consumer re-authors a pattern.
4. **`--check` mode** (CI + pre-commit gate): regenerate the two gitleaks configs
   into temp files and diff against the committed/on-disk views; any drift fails
   with `DRIFT_ERROR` (§5.5). **The public view diffs literally; the private view
   is redacted by default — see §4.2.** This mechanical guarantee replaces the
   manual "keep in lock-step" comments.

**Migration of existing patterns is mechanical**, not a re-derivation: each
current array entry / `.gitleaks.local.toml` rule maps 1:1 to a `[[pattern]]`
table. Private values move from the shell include + `.gitleaks.local.toml` into
`~/.dmfdeploy/pattern-manifest.private.toml` (operator does this once, locally);
the tracked repo never sees them.

### 4.1 Semantic engine validation (match tests, not compilation)

Compilation-parity is necessary but insufficient: a regex can compile under RE2,
ERE, and PCRE and still *match different strings* (anchoring, `\b`, inline flags,
case). So every `[[pattern]]` declares `case_sensitive`, `positive_canaries`
(MUST match), and `negative_canaries` (MUST NOT match). For each engine in
`engines`, `--check`:

1. renders the pattern into that engine's form with the correct case flag
   (`git grep -P`/`-iP`, `git grep -E`/`-iE`, or the gitleaks rule's case setting);
2. asserts **every** positive canary matches and **no** negative canary matches;
3. fails the build with `DRIFT_ERROR` (§5.5) if any engine disagrees.

The default authored subset stays RE2-safe (no backreferences/lookaround) so the
canaries usually agree trivially — the test exists to catch the cases that don't
(the env-gate already relies on per-engine case flags, L119–126). Private-pattern
canaries live in the operator-local private manifest and are **redacted from all
public/CI logs** (§4.2): the pass/fail verdict is public, the canary values and
matched text are not.

### 4.2 Log-safe private checks (redaction)

The §3 hard constraint governs **tooling output**, not only tracked files: a naïve
`diff` of the generated private `.gitleaks.local.toml`, or a private match report,
would print operator-private regexes/descriptions into a terminal or CI log —
today's scanners already surface rule metadata (`dmf-env-...gate.sh` captures
`RuleID:` lines L132–136; `scrub-...` prints private descriptions + matching lines
L204–209). Therefore:

- **Public config/manifest diffs may be literal.**
- **Private config/manifest checks are redacted by default:** emit only category,
  severity, per-rule **counts**, and a **hash of each normalized regex** — never
  regex bodies, private descriptions, or matched text. A mismatch reads
  "private topology: 7 rules, hash mismatch on 1" — enough to act, nothing to leak.
- An opt-in **`--show-private-diff` is a local-only diagnostic**: it prints the
  literal private diff, **refuses to run in CI or hooks** (same context signal as
  the opt-out gate, §5.4), and emits a loud banner. Never the default, never
  available in an automated context.

### 4.3 gitleaks emission: markers, rule kinds, and `useDefault` coverage

Because the gitleaks configs are **partially** generated (§3.2), the manifest→
gitleaks mapping is explicit per entry via `[pattern.gitleaks]`, and the generated
bytes are confined to the marker-fenced `[[rules]]` region:

- **Markers.** The generator only rewrites the bytes between
  `# >>> DMF-GENERATED RULES (do not edit) >>>` and `# <<< DMF-GENERATED RULES <<<`
  in `.gitleaks.toml` / `.gitleaks.local.toml`. The prose header, `[extend]
  useDefault`, and global `[allowlist]` sit above the opening marker and are
  hand-authored. `--check` regenerates the region into a temp file and diffs **only
  the region** (literal for public, redacted for private, §4.2).
- **Per-rule prose is manifest metadata, not free bytes** (codex constraint):
  a rule's explanatory comment lives in `[pattern.gitleaks].comment` and is
  rendered verbatim as `#`-prefixed lines immediately above the rule inside the
  region. Nothing inside the region is hand-typed — so region-level byte-identity
  is well-defined (no stray comment can drift the diff).
- **Three emission modes** (`[pattern.gitleaks].emit` / `.kind`):
  1. `emit = true, kind = "custom"` — a full `[[rules]]` block with the entry's
     `regex`, `description`, rendered `tags`, `comment`, and `[[rules.allowlists]]`.
     (Today: `dmf-dev-changeme`, `dmf-macos-metadata`, `dmf-cloud-resource-id`.)
  2. `emit = true, kind = "override"` — tunes a **default** rule by id, emits
     **no regex**, only `[[rules.allowlists]]`. Reproduces today's `generic-api-key`
     entry exactly. The manifest entry carries no `regex` in this mode.
  3. `emit = false, covered_by = "useDefault"` — the shape is covered by the
     default pack, so **no explicit gitleaks rule is emitted**; the entry still
     exists for the scrub/git-grep pass parity (§9.1). *(Amended 2026-07-13 at
     the fold-in, from the empirical proof this same section demands: only
     `AKIA…`, `ghp_…`, `glpat-…`, `xoxb-…`, and `AGE-SECRET-KEY…` are actually
     default-covered on pinned 8.21.2. PEM **headers** (default `private-key`
     needs the full armored body), embedded-URL creds, `hvs./hvb.` at the
     scrub 20+-char shape (default needs far longer tokens), and the
     `client_token`/`secret_id` literals (`generic-api-key` is entropy-gated —
     a low-entropy real value slips it) are **not**; those carry
     `covered_by = "git-grep"`, meaning the scan library's grep pass is the
     coverage.)*
- **`useDefault` coverage is PROVEN, never assumed** (binding): for every
  `emit = false, covered_by = "useDefault"` entry, `--check`/`--self-test` runs the
  entry's positive canaries (§4.1) through gitleaks configured **with the actual
  merged config's `[extend] useDefault = true`** and asserts they are caught (and
  negative canaries are not). If the default pack does not actually cover the shape,
  the build fails `DRIFT_ERROR` — the entry cannot silently claim default coverage
  it does not have.
- **Sequencing (matches the (b) rollout):** the `emit = false, covered_by =
  "useDefault"` entries — today's default-covered secret *shapes* now living in
  scrub's `SECRET_PATTERNS` — are folded into the manifest **with the scrub caller
  switchover + §9.1 parity landing (follow-on), not step 1.** Step 1 (the
  `.gitleaks.toml` rules region) carries only the entries that emit explicit rules.
  The proof mechanism ships in step 1 — the generator implements the merged-config
  canary test — and simply has no `emit = false` entries to exercise until that
  follow-on. This keeps step 1 a pure `.gitleaks.toml`-region add without importing
  scrub's pattern set early, and closes the contract honestly: the named
  `--check`/`--self-test` proof and the entries it validates land together.

---

## 5. Ephemeral merged configs + fail-closed unification

### 5.1 Ephemeral, never committed

For any context needing both tiers, the scan library composes a **merged gitleaks
config at run time in a temp file** (public generated rules + private generated
rules), invokes gitleaks against it, and deletes it. The merged file is never
written into a repo tree and never committed — same discipline `export-scan`
already uses for `/tmp` scratch and `guard.yml` for `/tmp/gitleaks.toml`. The
git-grep passes similarly load both manifests into memory; nothing private is
materialized in a tracked path.

### 5.2 Trust contexts and what each merges

| Context | Public rules | Private rules | Config trust source |
|---|---|---|---|
| pre-commit (local) | yes | **required** | working-tree manifests |
| pre-push (local) | yes | **required** | working-tree manifests |
| `export-scan` / pre-publish scrub | yes | **required** | working-tree manifests, pinned gitleaks |
| `dmf-env` surface gate | yes | **required** | working-tree manifests, pinned gitleaks |
| CI `guard.yml` | yes | **N/A (absent by design)** | **BASE-resolved** public manifest only (never PR-controlled) |
| CI on a fork / public-only run | yes | **explicitly opted out** | BASE-resolved public manifest |

### 5.3 Fail-closed is the default; opt-out is explicit and logged

Unify every context on **fail-closed**, replacing today's split (scrub fail-open,
env-gate fail-closed, hooks silently skip pass 2):

- A context whose row says "required" **must exit non-zero** if the private
  manifest is missing/unreadable, or if gitleaks is required but absent. No
  warn-and-continue. This upgrades `scrub-public-repos.sh` (Inconsistency #1) and
  the hooks' silent `if [ -f .gitleaks.local.toml ]` no-op to hard failures.
- The **only** way to run without the private tier is the **authorization-gated**
  `--public-only` / `DMF_SCAN_PUBLIC_ONLY=1` opt-out — and **only from a context on
  the allowlist** (§5.4). Logging is not enforcement: local/pre-publish contexts
  must **reject** the flag with `CONFIG_ERROR`, not merely warn. When a permitted
  context uses it, the library prints one line naming the context + authorization +
  reduced coverage (§5.4). Silence is never an opt-out.
- **CI keeps its BASE-ref config resolution** (`guard.yml` L21–31): the merged/
  public config is resolved from the base commit, never from the PR-controlled
  working file, so a malicious PR cannot weaken its own scan. The manifest
  generator's output is subject to the same rule — CI reads the base version.

### 5.4 Opt-out authorization boundary (enforcement, not logging)

`--public-only` must be a **capability**, not a global escape hatch — else a red
local gate is "fixed" by exporting one env var, silently dropping
`.gitleaks.local.toml` coverage (the #212 R7 trap). The library enforces an
allowlist keyed on the **caller-declared context** (each thin caller passes its own
identity — it is *not* sniffed from the environment, so an env var alone cannot
spoof it):

| Context | May use `--public-only`? |
|---|---|
| `ci-public` (CI on the canonical repo; private manifest absent by design) | **yes** |
| `fork` (CI on a fork with no operator manifest) | **yes** |
| `public-acceptance-fixture` (the §8 canary job) | **yes** |
| `pre-commit`, `pre-push`, `export-scan`, `scrub` (pre-publish), `dmf-env` | **NO — rejected with `CONFIG_ERROR`** |

A disallowed context that receives `--public-only`/`DMF_SCAN_PUBLIC_ONLY` **exits
`CONFIG_ERROR` (§5.5)** stating the flag is not permitted there and the private
manifest is required. A permitted context logs one line naming all three facts:
`scan: PUBLIC-ONLY authorized for ci-public; private identity/topology rules absent by design`.

### 5.5 Failure classes (machine-readable)

Every gate exit is one of three stable classes — a distinct exit code + a
`CLASS: …` prefix — so an agent/CI reacts correctly and never "fixes" a config
problem by editing allowlists or deleting content:

| Class | Exit | Meaning | Correct response |
|---|---|---|---|
| `LEAK_FOUND` | 1 | a pattern matched staged/range/tree content | remove the offending value, or (true FP) adjust the manifest allowlist via review |
| `CONFIG_ERROR` | 3 | private manifest missing/unreadable in a required context; gitleaks absent where required; `--public-only` in a disallowed context (§5.4) | fix the environment (install manifest/binary); **never** edit patterns to pass |
| `DRIFT_ERROR` | 4 | generated view ≠ committed/on-disk (`--check`), or a canary match test disagreed across engines (§4.1) | regenerate + commit the view, or fix the pattern |

The acceptance matrix (§8) asserts these explicitly: missing private manifest ⇒
`CONFIG_ERROR`; seeded canary ⇒ `LEAK_FOUND`; hand-edited generated view ⇒
`DRIFT_ERROR`.

---

## 6. One scan library, four thin callers

Collapse the duplicated pattern-loading / config-merging / gitleaks-invocation /
reporting into a **single library + CLI** (`bin/lib/dmf-scan.sh` + `bin/dmf-scan`,
say). Each entry point becomes a thin caller that supplies only its **context**.

**Shared (in the library):** manifest loading (public + private), semantic engine
validation (§4.1), redacted private checks (§4.2), ephemeral merged-config
generation, pinned-gitleaks resolution (one pinned version + sha, shared with
`guard.yml`), the git-grep pass runner, the `git rev-parse` repo/worktree resolver
(§7), the path-allowlist engine, fail-closed policy + the authorization-gated
opt-out (§5.4), and failure-class reporting (§5.5).

**Kept per caller (its context only):**

| Caller | Context it owns | Scan surface |
|---|---|---|
| pre-commit | staged diff | `gitleaks protect --staged` + staged-file grep |
| pre-push | push commit range | `--log-opts=<range>` |
| `scrub-public-repos` | one/all repos or `--tree` | full tracked tree |
| `export-scan` | orphan scratch export tree | full tree + `--log-opts=main`, pinned gitleaks, umbrella extras (STATUS.md no-allowlist, informational sweep) |
| `check-public-repo-hygiene` | artifact presence | unchanged surface, but shares repo/worktree resolution |
| `dmf-env surface gate` | `dmf-env` tree | allowlist + ban-list (kept) + shared content scan |

The callers stop re-implementing "load patterns", "merge config", "run gitleaks",
"resolve repo path". This is where the version/config skew (Inconsistency #4) is
fixed: **one** pinned gitleaks version + config-passing path for every context
that runs gitleaks (the env-gate stops using default-rules-no-config; the hooks
adopt the shared invocation). It also directly serves [#73](https://github.com/dmfdeploy/dmfdeploy/issues/73)
(DRY the cross-repo-identical files) — see §10.

---

## 7. Worktree-detection fix + regression check

- **Fix:** replace every `[ -d "$path/.git" ]` "is this a repo?" test with a
  `git -C "$path" rev-parse --is-inside-work-tree` (or `--git-dir`) check, which is
  true for both normal clones and worktrees. Centralize it in the shared library's
  repo-resolver and route **all three** sites through it:
  `scrub-public-repos.sh` L180/L251 (the **silent-skip** coverage gap),
  `check-public-repo-hygiene.sh` L85, and `export-scan.sh` L69–72 (the latter two
  currently **fail-closed** — no coverage gap, but unify so no caller re-introduces
  the `-d .git` form).
- **Regression checks — name the wrappers, not "the scan"** (the bug is in
  *wrapper-level* repo detection, so the tests must exercise the wrappers):
  (a) `scrub-public-repos.sh` against a **worktree** of a fixture holding a seeded
  canary → assert **caught** (today: silently skipped, green);
  (b) `check-public-repo-hygiene.sh` against a worktree → assert it resolves the
  repo, not `no-repo`;
  (c) `export-scan.sh` from a **worktree source** → assert it exports, not refuses.
  All three join the acceptance matrix (§8) and the test suite so the hole cannot
  silently reopen. (Operator "scrub gate skips worktree" note: verify against a
  real worktree, not a fresh clone.)

---

## 8. Acceptance: a trust-context / caller matrix (not one path)

The gate is only proven if a known-bad value is stopped **in every trust context
and through every caller's argument wiring** — not just one public export path.
Acceptance is a matrix of seeded-canary cases; each asserts an exit **class**
(§5.5), not merely non-zero:

| # | Caller / context | Surface exercised | Canary | Must assert |
|---|---|---|---|---|
| 1 | `pre-commit` caller | staged diff | public canary staged; (local job) private canary staged | `LEAK_FOUND`; private case local-only |
| 2 | `pre-push` caller | commit range (`--log-opts`) | public canary in a pushed commit **and** an operator-local **private** canary in a pushed commit (redacted) | `LEAK_FOUND` for **each** |
| 3 | `scrub-public-repos` (pre-publish) | full tracked tree | public canary in tree **and** operator-local **private** canary in tree (redacted) | `LEAK_FOUND` for **each** |
| 4 | `export-scan` | orphan scratch export tree + `--log-opts=main` | public canary in exported tree **and** operator-local **private** canary (redacted) | `LEAK_FOUND` for **each** |
| 5 | `dmf-env` surface gate | allowlist + content scan | banned path, public content canary, **and** an operator-local **private** identity/topology canary (redacted) | `LEAK_FOUND` for **each** |
| 6 | CI `guard.yml` / `ci-public` | `--public-only`, **BASE-resolved** manifest/config | live: an **existing BASE public rule**; sentinel: `DMF-CANARY` via a **fixture-base** test (BASE already carries the rule) | `LEAK_FOUND`; assert config came from BASE, not the PR |
| 7 | worktree × `scrub-public-repos.sh` | worktree checkout | canary | **caught** (regression for §7 silent-skip) |
| 8 | worktree × `check-public-repo-hygiene.sh` | worktree checkout | — | resolves repo, not `no-repo` |
| 9 | worktree × `export-scan.sh` | worktree source | canary | exports + `LEAK_FOUND`, not refusal |
| 10 | any **required** context | private manifest **absent** | — | `CONFIG_ERROR`, **not** green |
| 11 | `--public-only` in a **disallowed** context (§5.4) | — | — | `CONFIG_ERROR` |
| 12 | hand-edited generated view | `--check` | — | `DRIFT_ERROR` |

**Public/private split of the matrix:** rows run in **public CI use public
canaries only** — a purpose-built `DMF-CANARY-…` sentinel added as a
`category="secret"` public manifest rule, used solely by the fixture (decided,
§11). Every private-requiring caller row (2–5) additionally carries an
**operator-local private canary** case that runs in the **operator-local
acceptance job** (never public CI) with **redacted** output (§4.2), so a cold
implementer cannot satisfy those rows with public canaries alone. Missing-private
⇒ `CONFIG_ERROR` (row 10) likewise runs where the private manifest genuinely
exists. Every canary lives only in the test fixture and is removed from any
shippable path.

**The `DMF-CANARY` sentinel vs BASE-resolved CI config (row 6):** because
`guard.yml` resolves the scan config from BASE and deliberately ignores the
PR-controlled `.gitleaks.toml` (§5.3), the *first* PR that **adds** the sentinel
rule would not see it under BASE. So the live CI assertion uses an **existing BASE
public rule** (guaranteed present under BASE), while the `DMF-CANARY` sentinel is
exercised as a **fixture-base test** — a self-contained fixture repo whose BASE
commit already contains the sentinel rule and config — so the sentinel is never
depended on before it exists in a base tree.

This converts "we ran gitleaks and it was green" into "a known-bad value is
stopped, with the right failure class, in every context and through every caller."

---

## 9. Migration / rollout order + non-goals

**Rollout (each step leaves coverage ≥ today at every moment). Public and private
bootstrap are independent — never let a step expect a private view that does not
exist yet):**

1. **Public bootstrap (pure add).** Land `patterns/public-manifest.toml` + the
   generator/checker; the generator regenerates the **marker-fenced `[[rules]]`
   region** of `.gitleaks.toml` **byte-identical** to today's region (§3.2, §4.3),
   leaving the hand-authored prose header + `[extend] useDefault` + global
   `[allowlist]` above the marker untouched. `--check` verifies the region
   literally. **`.gitleaks.local.toml` is NOT generated here** — its source does
   not exist yet, and no `--check` demands it. No consumer switches; old gates
   still run. (The one-time change to the tracked `.gitleaks.toml` is the
   insertion of the two marker comment lines around the existing, unchanged
   `[[rules]]` — a reviewed no-op to the rules themselves.)
2. **Private bootstrap (operator-local, separate).** The operator authors
   `~/.dmfdeploy/pattern-manifest.private.toml` from the existing shell include +
   `.gitleaks.local.toml`, generates `.gitleaks.local.toml` from it, and confirms
   it matches the existing file via **redacted** parity (§4.2). Only after this
   does any context expect the private generated view; until then, contexts run
   with the still-present old private include.
3. **Structural parity gate (§9.1) green** — a hard precondition to any switch.
4. **Introduce the scan library**; point ONE caller at it (start with
   `scrub-public-repos.sh`) behind a flag for one cycle; verify against the old
   gate by **structural parity + canaries** (not just clean-tree output). Migrate
   the remaining callers one at a time, each verified before its old path is cut.
5. **Flip fail-open → fail-closed** only after every caller reads the manifest and
   the operator confirms the private manifest is in place — so the stricter policy
   never fires spuriously. Retire the shell include + hand-maintained configs last.
6. **Add the acceptance matrix + worktree regressions** (§7, §8) as required checks.

**Non-goals (explicit):**

- **No weakening of any pattern or gate.** Coverage only holds or increases.
- **No dropping `.gitleaks.local.toml` coverage.** It becomes a *generated* view
  of the private manifest; the commit-time second pass it powers stays.
- **The pre-commit / hook split (R7) is downstream and out of scope** — this plan
  makes the hooks *callers* of the shared library but does not restructure the
  hook suite itself; that is [R7's](https://github.com/dmfdeploy/dmfdeploy/issues/206)
  separate dispatch.
- **No new secret-scanning engine.** gitleaks stays; `git grep` stays. This is
  about *where patterns live and how they are loaded*, not the scan tech.
- **No change to the BASE-ref CI trust model** — it is preserved verbatim (§5.3).

### 9.1 Old→new structural parity gate (precondition to any caller switch)

Comparing old vs new scanner **output on a clean tree proves nothing** — both can
report "no hits" while one has a silently weakened pattern. So before any caller
switches, a one-off parity checker must prove **structural** equality:

1. Parse the **old** sources — the shell `DMF_PRIVATE_*_PATTERNS` arrays
   (`'PCRE|desc'`, consumed by scrub), the `DMF_PRIVATE_*_REGEX` combined-ERE
   strings (consumed by the env-gate), the public `SECRET_PATTERNS`, and the two
   `.gitleaks*.toml` rule sets.
2. Normalize each into candidate manifest entries — split the combined-ERE
   alternations back into atoms, and pair each atom with its category, the
   engine(s) it was used under, **and its *effective* case-sensitivity per old
   consumer**. This last field is essential and non-obvious: the env-gate runs
   identity **case-insensitively** (`git grep -nIiE`, L119–122) but topology
   **case-sensitively** (`git grep -nIE`, L123–126), so the *same* regex text was
   effectively matched two different ways depending on the consumer.
3. Compare against the new manifest: **category, per-category count, a hash of each
   normalized regex, the declared `engines`, the effective case flag, *and* the
   recorded gitleaks coverage** (`[pattern.gitleaks]`: explicit `custom`/`override`
   vs `emit = false, covered_by = "useDefault"`, §4.3) must all match. An old atom
   that was case-insensitive whose new `case_sensitive` differs **fails**; so does
   an old shape that the default pack covered but the manifest now records as
   emitting an explicit rule (or vice versa). Otherwise identity coverage could
   silently narrow to case-sensitive, or a `useDefault`-covered shape could be
   dropped, while regex text + engine coverage still "matched".
4. Run each pattern's positive/negative canaries (§4.1) — and for every rule that
   was **case-insensitive** in the old world, the parity canaries **must include
   upper- and lower-case variants** of at least one positive canary, all required
   to match. This makes a case narrowing fail loudly, not silently.

Output is a **redacted** (§4.2) parity report; **green is a hard precondition** to
rollout step 4. This upgrades "byte-identical gitleaks configs" (necessary, but
only covers the two generated TOMLs) into proof that the retired **git-grep**
consumers — including their per-consumer case handling — lost no coverage.

---

## 10. References & overlaps

- **[#212](https://github.com/dmfdeploy/dmfdeploy/issues/212)** — this spec's
  tracking issue; **[#206](https://github.com/dmfdeploy/dmfdeploy/issues/206)** —
  parent public-safety evaluation + adversarial review (source of the hard
  constraints).
- **[#73](https://github.com/dmfdeploy/dmfdeploy/issues/73)** (OPEN, *DRY the
  cross-repo-identical files*) — **overlaps, does not absorb.** #73 owns
  de-duplicating the *replicated per-repo hook/workflow files* via reusable
  workflows + cascading health files. This plan's single scan library reduces the
  logic those replicated files carry (they become thin callers), which *helps*
  #73; but the mechanism for sharing files across repos remains #73's decision.
  The implementation dispatch should coordinate so the shared library is consumed
  in whatever cross-repo distribution #73 lands on.
- **[#133](https://github.com/dmfdeploy/dmfdeploy/issues/133)** — the lineage of
  the private topology/identity rules and the account-fingerprint miss that
  motivates "impossible-to-truncate" pattern storage.
- **`docs/plans/DMF Umbrella Security Audit Remediation Spec 2026-06-15.md`** —
  adjacent hardening spec; the private configs already allowlist it.
- **ADR-0035** — operator-local `~/.dmfdeploy/` state convention (location
  rationale, §3.1). **ADR-0041** — GitHub-canonical-forward / clean-orphan first
  import (why `export-scan` exists).
- **Operator notes corroborated:** "scrub gate skips worktree", "scrub-pattern
  pipe-delimiter gotcha", "scrub gate blind to cloud IPs (#133)".

## 11. Decisions (closed — the implementer needs no further design input)

1. **Tracked public manifest path = `patterns/public-manifest.toml`** (new
   umbrella-root dir). **Decided**, not reopened: one schema across both tiers,
   distinct from the generated `.gitleaks.toml` view.
2. **Language = bash thin callers + a Python generator/checker.** If the shared
   runtime library must parse TOML at scan time, that library is **Python too** —
   implementers do **not** hand-write a TOML parser in shell. (`python3` is present
   in CI; `check-docs.sh` already parses via Python.)
3. **Canary value source = a bespoke `DMF-CANARY-…` sentinel rule** (public
   fixture) plus operator-local sentinels for the private tier — self-contained,
   no dependency on upstream gitleaks test-vector stability.
4. **gitleaks configs are HYBRID (partial-file) generated, not whole-file**
   (amended 2026-07-13, implementer report + codex concur). Only the marker-fenced
   `[[rules]]` region is generated from the manifest; the prose header, `[extend]
   useDefault`, and global `[allowlist]` are hand-authored above the marker.
   Per-rule prose is `[pattern.gitleaks].comment` render metadata (§4.3), so
   region byte-identity is well-defined. `useDefault`-covered secret shapes stay
   manifest entries with `emit = false, covered_by = "useDefault"`, proven by
   canary match tests against the merged `useDefault = true` config; default-rule
   tuning (e.g. `generic-api-key`) uses `kind = "override"` (no regex). This
   resolves the whole-file "byte-identical" over-constraint that the original
   §3.2/§4/§9 wording implied.
