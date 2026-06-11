# DMF Console Fresh Session Handoff Prompt — 2026-04-26

Paste this into a fresh Codex session.

---

You are resuming work on the DMF Console implementation in `<repos>/dmf-cms`.

Read these first:
- [DMF Console Initial Implementation Plan 2026-04-26.md](<note-store>/DMF%20Console%20Initial%20Implementation%20Plan%202026-04-26.md)
- [DMF Session Handoff 2026-04-24.md](<note-store>/DMF%20Session%20Handoff%202026-04-24.md)
- [README.md](<repos>/dmf-cms/README.md)
- [CLAUDE.md](<repos>/dmf-cms/CLAUDE.md)

Current repo state:
- Branch: `feature/dmf-console-release-0-bootstrap`
- Latest commit on branch: `c194c6a` `feat: support console path deployments`
- Branch is pushed and tracking `origin/feature/dmf-console-release-0-bootstrap`
- Verification currently passes: `4 passed`

What is already implemented:
- FastAPI app scaffold with session-based login flow
- repo-backed app contract fixture at `config/app-contracts.yaml`
- Jinja templates and operational UI shell
- base-path rewriting so the app can run at `/` or `/console`
- health endpoint at `/healthz`
- Dockerfile that builds a real app image
- Helm chart skeleton with deployment, service, ingress, and env wiring

Important product decisions already locked:
- Canonical public URL: `console.<domain>`
- Path-based fallback: `/console` for environments without DNS control
- Release-0 database recommendation: dedicated console-owned Postgres unless a hardened external platform service already exists
- App contract source: versioned YAML in `dmf-cms`, with generated runtime artifacts derived from it
- First AWX workflows: `stack-verify`, `endpoint-certificate-verify`, `eso-openbao-health-check`, `netbox-registration-dry-run`
- Alert acknowledgements: console-local first, Alertmanager silences later

Current code details:
- `src/dmf_cms/main.py` contains the app factory, routing, login/logout, and base-path middleware
- `src/dmf_cms/contracts.py` loads the YAML app contract
- `src/dmf_cms/security.py` handles local/dev identity and OIDC helper functions
- `charts/dmf-cms/values.yaml` still defaults to host-based `console.dmf.example.com`, but the app supports `/console`
- `tests/test_base_path.py` proves the prefixed route behavior

Do next, in this order:
1. Add proper CI/build checks for the feature branch so scaffold regressions are caught automatically.
2. Tighten real Authentik OIDC configuration for non-local environments and keep dev-login local-only.
3. Decide whether the Helm chart should expose a first-class `/console` ingress path value or keep that as an environment-specific override.
4. Start release-1 work for live app health adapters and degraded-state reporting.

Working rules:
- Do not restate the product plan from scratch.
- Do not ask the user to re-explain context that is already in the plan or handoff.
- Prefer small, verified changes over broad refactors.
- Before marking anything done, run the relevant tests.
- If you correct a mistake, update the operator's lessons file with the prevention rule.
- If you add task items, update the operator's todo file.

Useful command context:
- `cd <repos>/dmf-cms`
- `pytest -q -o cache_dir=/tmp/dmf-cms-pytest-cache`
- `python -m compileall src tests`

If you need a single sentence summary of the current state:
- The DMF Console release-0 scaffold is in place, path-aware for `/console`, verified by tests, and ready for CI and real OIDC hardening before merge.
