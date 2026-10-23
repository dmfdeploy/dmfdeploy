# ADR-0046 archive: First-class Media Workload entity — a tag-derived assembly of Media Functions

This file holds material moved out of [ADR-0046](../../decisions/0046-first-class-media-workload-entity.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **Catalog-level workload manifest** (declare members in YAML) — richer, but adds
  a new store/authority duplicating NetBox's instance record. Rejected for now.
- **Keep the page as a function inventory** (do nothing) — leaves the
  Function/Workload conflation and gives the lifecycle/switch/budget nowhere to
  live. Rejected.
- **Re-stamp `workload` from the launcher as the authority** (option b) — rejected:
  membership is a workload/design concern, not a per-launcher one; acceptable only
  as a seed/backfill convenience.

## Amendment 1 (2026-08-30): EBU lifecycle stage names keep EBU's own spelling

**Problem.** During the console shell documentation round
(dmfdeploy/dmfdeploy#480), a US-spelling house style was briefly considered
for the console's copy, which would have made `finalizing` "correct" and
this ADR's own `Finalise & Review` (decision 3, and the
[Console Glossary](../../design/DMF%20Console%20Glossary.md)'s stage-names
entry) a defect to fix. **That is backwards**, and needs to be on record
before it recurs: the near-miss is the point — someone who later sees
`Finalise` beside a stray `finalizing` will normalise the *wrong* one
without a written rule to check against (see dmfdeploy#499, a raw lifecycle
token that reached an operator surface with the wrong spelling — a
dmf-cms fix on its own branch, not this amendment, but the kind of drift
this amendment exists to prevent).

**Verification.** Checked against the primary source — the EBU white paper
*The Dynamic Media Facility Reference Architecture* — by text extraction:

| Token | Occurrences |
|---|---|
| `Finalise` | 6 |
| `Finalise & Review` | 2 |
| `Finalize` / `Finalizing` | **0** |

EBU publishes the **'s'** spelling, unambiguously and exclusively.

**Consistency check.** This already matches
[`docs/architecture/DMF EBU Mapping (2026-04-25).md:39`](../../architecture/DMF%20EBU%20Mapping%20(2026-04-25).md),
this ADR's own decision 3 above, the
[Console Glossary](../../design/DMF%20Console%20Glossary.md)'s lifecycle
stage-names entry, and the machine identifiers named above — this amendment
records the rule those already-consistent artifacts were following
implicitly, so a future edit cannot "fix" one of them into inconsistency
with the rest.

## Moved from the ADR on 2026-10-23

### Context (original text)

The EBU DMF Reference Architecture is unambiguous: a **Media Workload** is the
production-level *assembly*, and Media Functions are *combined to implement* it
(Annex B, Figure B1). ADR-0037 knowingly modelled the console's "Media Workloads"
page as a Media *Function* instance inventory and **deferred** the assembly. As
the MXL demo grows past a single function (`mxl-videotestsrc` + `mxl-videotest-view`),
the assembly is the unit the operator reasons about — its lifecycle, its future
switch target, its resource budget — and there is nowhere to hang those. RFC
[#190](https://github.com/dmfdeploy/dmfdeploy/discussions/190) converged on
introducing the entity without new NetBox machinery.

### Decision 5, original text

**5. Console IA + API split.** Reserve **"Media Workloads"** for the assembly;
rename the flat per-function surface to **"Media Functions" / "Function
Instances."** No in-place reshape of `/api/media-workloads`: add the grouped API
first, migrate the UI, then deprecate the flat shape. Target end state:
`/api/media-workloads` = grouped workload-first payload; `/api/media-function-instances`
= flat instance inventory (interim: keep the flat response briefly or expose
`/api/media-workloads/grouped` until the frontend/tests move).

### Decision 6, migration of the MXL entries (original text)

- **Migration of the MXL entries** (only the two that remain — see below):
  - `mxl-videotestsrc` — keep `layer:5`; drop `vertical: media-functions`; add
    `media_function_type: source`.
  - `mxl-videotest-view` — keep `layer:5`; drop `vertical: media-functions`; add
    `media_function_type: view`.
  - `mxl-hello` — **retired** (removed from the catalog), superseded by the
    `videotest` workload; this deletes the anomalous `layer:4` +
    `vertical: media-processing` entry rather than migrating it. Tracked in
    [#193](https://github.com/dmfdeploy/dmfdeploy/issues/193).


### Positive consequences (original text)

- **Positive** — the vocabulary becomes honest; the workload is a real home for
  the lifecycle, the future switch target, and L3 preflight/rollback; the catalog
  stops mis-tagging media-processing functions; minimal new infrastructure (one
  tag, no graph object, no CRD).
