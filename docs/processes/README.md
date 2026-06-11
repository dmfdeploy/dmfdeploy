# DMF Process Documentation Standard

**Canonical notation:** BPMN 2.0 (ISO/IEC 19510)
**Status:** Draft — first process docs being authored 2026-05-09

---

## 1. Purpose

This directory holds normative process definitions for the DMF platform.
Each process describes *who does what, when, and under what conditions* —
independent of the implementation tooling (Ansible, Terraform, kubectl, etc.).

BPMN 2.0 is the canonical notation because it is an ISO standard (ISO/IEC 19510),
has mature tooling (Camunda Modeler, bpmn.io), and supports executable process
semantics where needed.

---

## 2. Repository Layout

```
docs/processes/
  README.md                    ← this file
  <process-name>.md            ← process documentation page
  diagrams/
    <process-name>.bpmn        ← canonical BPMN 2.0 XML source
    <process-name>.svg         ← rendered diagram (derived artifact)
```

**File naming convention:**
- Use kebab-case for process names: `dmf-bootstrap-flow.bpmn`, not `DMF Bootstrap Flow.bpmn`
- The `.bpmn` file is the **source of truth**. SVG/PNG are derived.
- Never edit SVG directly — always regenerate from `.bpmn`.

---

## 3. BPMN 2.0 Modeling Rules

### 3.1 Structural rules

| Rule | Requirement |
|---|---|
| Pools and lanes | Use for organizational or system responsibility boundaries |
| Start events | Every process must have at least one start event |
| End events | Every process must have at least one end event |
| Sequence flows | Use **only within a single pool** — never across pools |
| Message flows | Use for cross-pool communication |
| Named tasks | Every task must have a verb-object name |
| Gateway labels | Gateways must be named as questions (e.g., "Seed complete?") |
| Gateway merge | Every split gateway must have a corresponding merge gateway |
| Exception paths | Must terminate or return to a defined point |
| Subprocesses | Split large diagrams into subprocesses rather than one oversized model |

### 3.2 Task types

| BPMN element | Use when |
|---|---|
| **User Task** | A human operator performs the action (e.g., "Approve change request") |
| **Service Task** | An automated system performs the action (e.g., "Deploy k3s cluster") |
| **Manual Task** | Work done outside managed systems (e.g., "Insert USB key") |
| **Script Task** | Inline code execution (rare in DMF — prefer service tasks) |
| **Receive Task** | Waiting for an external message/event |
| **Send Task** | Sending a message to another pool/system |

### 3.3 Naming conventions

- **Tasks:** Verb-object phrasing — `"Deploy k3s cluster"`, not `"Deployment"` or `"k3s"`
- **Gateways:** Questions — `"Bootstrap admin seeded?"`, not `"Admin check"`
- **Events:** Descriptive — `"OpenBao unsealed"`, not `"Event"`
- **Avoid vague labels:** Never use `"Handle issue"`, `"Process data"`, or `"Do task"`

### 3.4 Visual quality

- **Flow direction:** Left-to-right (unless the existing repo convention differs)
- **Alignment:** Related tasks aligned horizontally
- **Crossings:** Avoid crossing lines where practical
- **Balance:** Keep diagrams balanced and reviewable
- **No decorative styling:** Avoid colors, icons, or styling that reduces semantic clarity

---

## 4. When to Use Other Notations

| Notation | Use for | Not for |
|---|---|---|
| **BPMN 2.0** | Normative process definitions with actors, decisions, and system interactions | Architecture diagrams, data models |
| **Mermaid** | Lightweight flow explanations embedded in Markdown when BPMN is overkill | Processes requiring ISO compliance or executable semantics |
| **D2** | Infrastructure and architecture diagrams | Process workflows |
| **Excalidraw** | Conceptual sketches, hand-drawn explanations, slide diagrams | Normative process documentation |
| **PlantUML** | Sequence diagrams for API/integration flows | Business process definitions |

**Rule of thumb:** If the diagram describes *who does what in what order with decisions*, use BPMN. If it describes *how systems connect*, use D2. If it describes *message ordering between services*, use PlantUML sequence diagrams. If it's a *conceptual sketch for a presentation*, use Excalidraw.

---

## 5. Validation Expectations

Every `.bpmn` file must pass these checks:

1. **Valid BPMN 2.0 XML** — parseable by `bpmn-moddle` or Camunda Modeler
2. **At least one start event**
3. **At least one end event**
4. **All tasks named** (no empty label fields)
5. **Valid sequence flows** — no orphaned nodes, no dead-end branches (unless intentionally terminal)
6. **No cross-pool sequence flows** — only message flows cross pools
7. **Clear gateway labels** — every exclusive/parallel gateway has a name
8. **Every split has a merge** — unless the process intentionally terminates on different paths

### Validation tooling

Currently no automated validation script exists. Manual validation steps:

1. Open the `.bpmn` file in [bpmn.io demo](https://demo.bpmn.io/) or Camunda Modeler
2. Verify the diagram renders without errors
3. Check the validation rules above
4. Verify SVG export matches the BPMN source

**Future work:** Add a lightweight Python validation script using `bpmn-moddle` or `lxml` to automate checks 1–8 above.

---

## 6. Markdown Integration

Process Markdown pages should:

1. **Embed rendered SVGs** — not screenshots or raw BPMN XML
2. **Link to the canonical `.bpmn` source** — e.g.:

   > Canonical source: `diagrams/dmf-bootstrap-flow.bpmn`. Rendered diagram is derived from the BPMN source.

3. **Explain the process** in prose — the diagram supplements the text, it doesn't replace it.

### Rendering pipeline

Generate the SVG via the repo wrapper — never call `bpmn-to-image` directly:

```bash
bin/render-bpmn.sh docs/processes/diagrams/<process-name>.bpmn
```

The wrapper runs `npx bpmn-to-image --no-footer` and injects the shared
[`diagrams/_styles.css`](diagrams/_styles.css) stylesheet (typography, pool
colors, exception-end highlighting). Element IDs in the `.bpmn` must follow
the naming conventions documented at the top of `_styles.css` for the
styling to apply (`Pool_*`, `Task_*`, `GW_*`, `Start_*`, `End_*`, `MF_*`).

### Known visual limitations

The current pipeline is **post-process restyling**: bpmn-js renders the SVG
with its own defaults, then we inject CSS. This produces correct, valid
output but two visual issues persist:

1. **Text overflow on labels.** bpmn-js measures text in **Arial 12px** at
   layout time and sizes shapes accordingly. The stylesheet then swaps to
   Inter, which is wider per glyph at the same point size — labels can
   exceed shape boundaries. This is a metric mismatch, not a styling bug.
2. **Visual cohesion is bounded by the BPMN visual language.** Diamond
   gateways, rounded-rect tasks, circular events, and dashed message flows
   are spec-mandated; the diagram cannot be made to feel like a hand-drawn
   infographic without leaving BPMN.

These limitations are tolerable for engineering and audit consumption.
They are **not** acceptable for end-user tutorials or marketing material.

### Improving presentation (future work)

Three options, in increasing investment:

- **Move font choice into the render step.** Replace `bpmn-to-image` with a
  thin Puppeteer wrapper that loads Inter into the bpmn.io page *before*
  bpmn-js measures text. Eliminates overflow without changing the static
  artifact format. Roughly half a day of work.
- **Live bpmn-js viewer for tutorials.** Ship the canonical `.bpmn` plus a
  small embed (`<BpmnViewer src="…">`) themed with `_styles.css`. Solves
  metrics (renders client-side with the right font), enables zoom/pan on
  large diagrams, and supports `bpmn-js-overlays` for numbered step
  callouts and phase-by-phase reveal. The right pattern for any
  documentation site that uses BPMN. Roughly one day for a working
  prototype.
- **Two-artifact pattern.** Keep BPMN as the canonical/normative artifact
  and ship a parallel D2, Mermaid, or Excalidraw companion for tutorial
  and marketing surfaces. This is what most organizations ultimately do;
  BPMN is rarely shown to end users.

The current static-SVG pipeline is sufficient for normative process
documentation. Pick one of the above when a process needs to appear in
end-user-facing material.

### Required sections in process Markdown files

Every process documentation page must include:

| Section | Content |
|---|---|
| **Purpose** | Why this process exists |
| **Scope** | What is in/out of scope |
| **Actors / Roles** | Who participates (human and system) |
| **Trigger event** | What starts the process |
| **Normal path** | The happy-path sequence of steps |
| **Exception paths** | What happens when things go wrong |
| **Inputs** | What the process consumes |
| **Outputs** | What the process produces |
| **Systems touched** | Which systems are modified |
| **Controls / approvals** | Gates, checks, and authorization points |
| **Related runbooks** | Links to operational procedures |

---

## 7. Example: Minimal BPMN Process

The file `diagrams/example-hello.bpmn` contains a minimal "Hello World" BPMN
process demonstrating the required structure. It models a simple greeting
process with one user task and one service task.

**Key elements demonstrated:**
- Pool with a single lane
- Start event → User Task → Service Task → End event
- Named tasks with verb-object phrasing
- Valid sequence flows
- Clean left-to-right layout

Use this as a template when creating new process diagrams.

---

## 8. Related Documents

| Document | Purpose |
|---|---|
| `../diagram-design-guide.md` | Excalidraw diagram styling and export conventions |
| `../decisions/INDEX.md` | Architecture decisions that constrain process design |
| `../architecture/DMF Platform Plan.md` | Platform context for process scope |
| `../handoffs/` | Session handoffs that may reference process changes |

---

## 9. Changelog

| Date | Change |
|---|---|
| 2026-05-09 | Initial draft — BPMN 2.0 standard established |
