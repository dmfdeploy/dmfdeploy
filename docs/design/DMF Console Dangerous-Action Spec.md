# DMF Console — Dangerous-Action Spec

**Status:** 🚧 Stub — to be written. Owns the procedural detail behind **[UX Constitution](DMF%20Console%20UX%20Constitution%202026-05-25.md) Art. 7** ("Safe things easy, dangerous things deliberate").
**Aligned with:** ADR-0028 (identity/authority chain — actor · role · request-id · reason metadata).

## Why this doc exists
The constitution states the principle — friction graduated to consequence, led by impact preview, not a habituated confirmation dialog. The consequence-class → friction **matrix** lives here.

## To define
- **Consequence taxonomy** — `reversible` · `disruptive` · `destructive` · `security-sensitive` (an action may carry more than one tag).
- **Friction matrix** — what each class requires:

  | Class | Friction (draft — to validate) |
  |---|---|
  | reversible | none / inline undo |
  | disruptive | **impact preview** (what stops) + single confirm |
  | destructive | impact preview + **typed confirmation** + stated rollback |
  | security-sensitive | + **RBAC elevation** / re-auth, possibly two-step / second approver |

- **Impact preview** — the required content ("this stops N live flows / affects services X, Y"); where it's computed; what happens when impact can't be determined (fail safe → treat as higher class).
- **Metadata capture** — the ADR-0028 **C5 quartet: actor · role · request-id · reason** (free-text reason where warranted). C5 makes this quartet **baseline for *every* DMF-initiated automated action**, not just dangerous ones — dangerous actions layer stronger reason/impact/approval on top. The *requester* (human) and *executor* (per-app service account) are recorded **distinctly** in the audit log (`actor` vs `executed_as`).
- **Elevation, not break-glass** — where a class needs elevation, use **re-authentication / fresh Authentik (OIDC) assurance or stronger RBAC**, *never* a local/break-glass admin (ADR-0028 **C1**: steady-state human authority is Authentik; routine dangerous actions must not require break-glass).
- **Two-step / approval** — when an action needs a second human.

## Worked example
- **Teardown NMOS Registry** → `destructive` + `disruptive`: impact preview ("media flows depending on NMOS will stop routing"), typed confirm, reason capture, rollback note. (Today it fires on a single click — constitution §4.)
