# DMF Diagram Design Guide

**Audience:** AI agents creating technical diagrams for the DMF platform
**Scope:** Excalidraw `.excalidraw` files under `docs/diagrams/`
**Standard:** ISO 5807 flowchart symbols + Excalidraw "Architect" mode

---

## 1. Excalidraw Architect Mode — appState Settings

All Excalidraw diagrams for DMF must use **Architect mode** — crisp, straight
lines with clean typography. Never use the default "Artist" mode (hand-drawn
wobble, Virgil font, hachure fills).

Set these in the `.excalidraw` file's `appState` object:

```

### PNG Export (Pixel-Perfect)

For presentations where font rendering consistency is critical, export via
Excalidraw's own canvas renderer using `excalidraw-cli` + Puppeteer:

```bash
# 1. Get shareable URL
excalidraw-cli export docs/diagrams/dmf-bootstrap-flow.excalidraw
# → https://excalidraw.com/#json=...,Z...

# 2. Screenshot via Puppeteer (load URL, hide UI, capture)
# See /tmp/render-shareable.mjs for the script
```

This produces pixel-perfect output matching exactly what Excalidraw renders
in the browser — no font metric mismatches, no SVG viewBox issues.

json
{
  "appState": {
    "currentItemSloppiness": "architect",
    "currentItemFontFamily": 2,
    "currentItemStrokeStyle": "solid",
    "currentItemStrokeWidth": 1,
    "currentItemFillStyle": "solid",
    "currentItemRoughness": 0,
    "currentItemLinearStrokeSharpness": "sharp",
    "currentItemOpacity": 100,
    "theme": "light",
    "viewBackgroundColor": "#ffffff",
    "gridModeEnabled": false
  }
}
```

### Property Reference

| Key | Value | Meaning |
|---|---|---|
| `currentItemSloppiness` | `"architect"` | Disables hand-drawn wobble — perfectly straight lines |
| `currentItemFontFamily` | `2` | `1`=Virgil (hand-drawn), `2`=Nunito (clean sans), `3`=Cascadia Code, `4`=Comic Shanns |
| `currentItemStrokeStyle` | `"solid"` | `"solid"`, `"dashed"`, `"dotted"` |
| `currentItemStrokeWidth` | `1` | `1`, `2`, `4` |
| `currentItemFillStyle` | `"solid"` | `"solid"`, `"hachure"`, `"cross-hatch"`, `"zigzag"` |
| `currentItemRoughness` | `0` | `0–9`; `0` = perfectly crisp edges |
| `currentItemLinearStrokeSharpness` | `"sharp"` | `"sharp"` or `"round"` for line endpoints |

### Per-Element Overrides

Even with `appState` defaults, each element must have explicit overrides to
survive the `@excalidraw/utils` export pipeline:

```python
for el in d['elements']:
    if el['type'] in ('rectangle', 'diamond', 'arrow', 'ellipse'):
        el['strokeStyle'] = 'solid'
        el['fillStyle'] = 'solid'
        el['roughness'] = 0
    if el['type'] == 'text':
        el['fontFamily'] = 2  # Nunito
        el['roughness'] = 0
    if el['type'] == 'arrow':
        el['strokeWidth'] = 2
```

---

## 2. ISO 5807 Flowchart Symbol Reference

Use standard ISO 5807 shapes for semantic meaning. Do not invent custom shapes.

| Shape | ISO Name | Meaning | Use For |
|---|---|---|---|
| **Oval / Pill** | Terminator | Start or end point | Bootstrap start, "STOP HERE" gates |
| **Rectangle** | Process | Action, operation, or sub-process | Install plays, provision steps, configure stages |
| **Diamond** | Decision | Branching point with conditions | Collision policy (same/missing/differ), assertion gates |
| **Parallelogram** | Input/Output | Data entering or leaving the system | Bundle decryption, seed export, token flow |
| **Cylinder** | Database | Structured data store | OpenBao paths, ESO secrets, NetBox SoT |
| **Document** (wavy bottom) | Document | Printed or generated document | ConfigMaps, manifests, inventory files |
| **Trapezoid** | Manual Operation | Human-performed step | `seed-bao`, operator-initiated unseal |
| **Double-sided rectangle** | Predefined Process | Subroutine referenced elsewhere | `lifecycle-provision.yml` wrapper, known playbook |
| **Circle** | Connector | Flow continues at another point | Cross-page references (rare in our diagrams) |
| **D-Shape** | Delay | Scheduled wait or blocking point | "STOP HERE" before seed boundary |

---

## 3. Color Convention

| Zone | Fill | Stroke | Purpose |
|---|---|---|---|
| Operator-local (sidebar) | `#d0ebff` (light blue) | `#1971c2` | Trust root material, keys, Shamir shares |
| Pre-seed cluster | `#d3f9d8` (light green) | `#2b8a3e` | Layer 2/3 install, OpenBao+ESO readiness |
| Seed boundary | `#fff4e6` (light orange) | `#e8590c` | `seed-bao` script, collision policy, ADRs |
| Post-seed cluster | `#a5d8ff` (blue) | `#1971c2` | Monitoring, Layer 6 vanilla apps |
| Configure stage | `#e5dbff` (purple) | `#7950f2` | OIDC wiring, SoT, CMS integration |
| Verify stage | `#d3f9d8` (light green) | `#2b8a3e` | Readiness gates |
| Workload boundary | `#ffe8cc` (orange) | `#e8590c` | Beyond bootstrap — dmf-runbooks scope |
| Legend | `#f8f9fa` (grey) | `#868e96` | Legend box |
| Shamir / ADR-0009 | `#fff3bf` (amber) | `#e67700` | Security custody callouts |
| ADR-0007 rule | `#ffe3e3` (red tint) | `#c92a2a` | Hard security rules |

---

## 4. SVG Export Pipeline — Known Defects & Fixes

The `@excalidraw/utils` `exportToSvg()` function produces SVG with **four known
defects** that require post-processing:

1. **Duplicate `xmlns`** on root `<svg>` — invalid XML
2. **Virgil font `@font-face`** — references Excalidraw CDN, fails offline
3. **Empty `<mask/>` tags** — export artifacts, no functional purpose
4. **`<!-- svg-source:excalidraw -->`** comment — unnecessary metadata

### Post-Processing Script

```python
import re

# 1. Fix duplicate xmlns
svg = svg.replace(
    '<svg xmlns="..." version="1.1" xmlns="..."',
    '<svg xmlns="http://www.w3.org/2000/svg" version="1.1"'
)

# 2. Remove @font-face CDN blocks, replace with system fonts
svg = re.sub(
    r'<style class="style-fonts">.*?</style>',
    '<style class="style-fonts"><![CDATA[ /* system fonts only */ ]]></style>',
    svg, flags=re.DOTALL
)
svg = svg.replace(
    'font-family="Virgil,[^"]*"',
    'font-family="Nunito, Segoe UI, Helvetica, Arial, sans-serif"'
)

# 3. Remove empty <mask/> tags
svg = svg.replace('<mask/>', '')

# 4. Remove svg-source comment
svg = svg.replace('<!-- svg-source:excalidraw -->', '')
```

### Validation Checklist

```python
assert svg.count('xmlns=') == 1, "Duplicate xmlns"
assert 'Virgil' not in svg, "Virgil font still present"
assert '@font-face' not in svg, "CDN font-face still present"
assert '<mask/>' not in svg, "Empty mask tags still present"
```

### PNG Export (Pixel-Perfect)

For presentations where font rendering consistency is critical, export via
Excalidraw's own canvas renderer using `excalidraw-cli` + Puppeteer:

```bash
# 1. Get shareable URL
excalidraw-cli export docs/diagrams/dmf-bootstrap-flow.excalidraw
# → https://excalidraw.com/#json=...,Z...

# 2. Screenshot via Puppeteer (load URL, hide UI, capture)
# See /tmp/render-shareable.mjs for the script
```

This produces pixel-perfect output matching exactly what Excalidraw renders
in the browser — no font metric mismatches, no SVG viewBox issues.



### PNG Export (Pixel-Perfect)

For presentations where font rendering consistency is critical, export via
Excalidraw's own canvas renderer using `excalidraw-cli` + Puppeteer:

```bash
# 1. Get shareable URL
excalidraw-cli export docs/diagrams/dmf-bootstrap-flow.excalidraw
# → https://excalidraw.com/#json=...,Z...

# 2. Screenshot via Puppeteer (load URL, hide UI, capture)
# See /tmp/render-shareable.mjs for the script
```

This produces pixel-perfect output matching exactly what Excalidraw renders
in the browser — no font metric mismatches, no SVG viewBox issues.



---

## 5. Diagram Layout Principles

1. **Left-to-right flow** — operator-local on the left, workload boundary on
   the right. Time flows left → right, dependency depth flows top → bottom.
2. **Group by zone** — use dashed-border rectangles to group related steps.
   Each zone gets a distinct color (see §3 Color Convention).
3. **Label every arrow** — no unlabeled flow lines. Every arrow should say
   what is being passed (e.g., `export-vars →`, `seed-bao →`).
4. **Seed boundary as visual focal point** — use a thick vertical bar or
   distinct color to mark the trust boundary between operator-local and
   cluster-side operations.
5. **Legend on the right** — always include a legend mapping colors to zones.
   Keep it outside the main flow area.
6. **Favor clarity over completeness** — if a step would require 3 nested
   sub-boxes, split into a separate diagram. Reference it by name.
7. **No default passwords in diagrams** — even placeholder `changeme` or
   `admin` in a diagram box is an ADR-0007 violation. Use variable names
   like `vault_bootstrap_admin_password` instead.

---

## 6. File Conventions

| File | Location | Purpose |
|---|---|---|
| `*.excalidraw` | `docs/diagrams/` | Editable source — source of truth |
| `*.svg` | `docs/diagrams/` | Rendered export — for slides, READMEs, docs |
| `diagram-design-guide.md` | `docs/` | This document |

**Naming convention:** `<repo>-<concept>-flow.excalidraw`
(e.g., `dmf-bootstrap-flow.excalidraw`, `cms-oidc-wiring-flow.excalidraw`).

---

## 7. Agent Workflow Checklist

When an agent is asked to create or modify a diagram:

1. [ ] Read this guide.
2. [ ] Open the relevant `.excalidraw` file or create a new one.
3. [ ] Set `appState` defaults from §1 before placing any elements.
4. [ ] Use ISO 5807 shapes from §2 for semantic correctness.
5. [ ] Apply per-element overrides from §1 after placing elements.
6. [ ] Export SVG via `@excalidraw/utils` + post-processing from §4.
7. [ ] Validate: no Virgil font refs, no duplicate xmlns, no `<mask/>`, no
     hardcoded secrets, all arrows labeled.
8. [ ] Commit both `.excalidraw` and `.svg` — the `.svg` is the presentation
     artifact, the `.excalidraw` is the editable source.

---

## 8. Related Documents

- `feedback_excalidraw_svg_export.md` — memory on SVG export defects
- `docs/decisions/INDEX.md` — ADRs referenced in diagrams
- `docs/architecture/DMF EBU Mapping (2026-04-25).md` — layer/vertical vocabulary
- `docs/plans/DMF Bootstrap Provision Configure Split Plan 2026-05-07.md` — bootstrap flow
