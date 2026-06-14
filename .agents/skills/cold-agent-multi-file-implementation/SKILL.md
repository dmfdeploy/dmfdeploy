---
name: cold-agent-multi-file-implementation
description: Procedure for executing a large multi-file feature implementation in an agent-bridge orchestrated workflow with mid-flight review incorporation
source: auto-skill
extracted_at: '2026-06-08T12:02:54.075Z'
---

# Cold Agent Multi-File Implementation

When implementing a large multi-file feature (backend + frontend + tests) in an agent-bridge orchestrated workflow:

## Boot sequence
1. Confirm branch and clean state: `git rev-parse --abbrev-ref HEAD` must print `main`; `git status` must be clean.
2. Read the spec file fully before writing any code.
3. Read all relevant source files in parallel to understand the current state.
4. Create a todo list breaking the work into logical chunks (one per Change, plus review items, plus build/test/commit).

## Implementation order
1. **Backend models/settings first** — change data classes, Pydantic models, and settings before touching routes or views.
2. **Backend routes/endpoints** — update or create API handlers to match the new models.
3. **Backend business logic** — update backup.py, manage.py, etc. to remove deprecated patterns.
4. **Frontend** — remove deprecated components, add new ones, update type imports.
5. **Tests** — update all test files to match new APIs; fix model imports, fixture signatures, and assertion targets.
6. **Build** — run frontend build (`npm run build`), then `pip install .` if needed.
7. **Verify** — run `ruff check src` and `pytest`; fix failures iteratively.

## Mid-flight review incorporation
When a review arrives mid-implementation (P0/P1 items):
- **Do not restart** — fold review items into the existing todo list.
- **P0 items first** — concurrency guards, download safety, filename validation take priority.
- **P1 items next** — TLS hardening, repo trust, upload safety.
- **P2 items last** — metadata, retention notes.
- Apply review items to the same code you're already editing; commit everything together.

## Fix round protocol (post-DONE verification)
After submitting a DONE report, the orchestrator may verify claims and send a fix round:
- The orchestrator will find defects including things your DONE report claimed but did not land.
- You must fix ALL defects and **re-verify every claim with grep output** in the second DONE report.
- Do NOT assert claims — paste actual grep/build output so the orchestrator can re-verify.
- Amend the commit (`git commit --amend`) — do not create a separate fix commit.
- See the `fix-round-verification-protocol` skill for detailed patterns (atomic concurrency guard, path traversal validation, symlink-before-resolve).

## Test update patterns
- When a Pydantic model changes (e.g., `ManageRestoreRequest` loses `dest_remotes`), update ALL test files that construct it.
- When a function signature changes (e.g., `backup()` makes `remotes` optional), callers that still pass it continue to work — only new callers use the simpler signature.
- When `Settings()` gains `tls_enabled=True` default, all test client instantiations need `tls_enabled=False` to avoid Secure cookie issues on HTTP test transport.
- Use `grep -n` to find all occurrences of deprecated symbols across test files before editing.

## Frontend update patterns
- When removing a UI component (e.g., RemoteFieldset), update imports in ALL files that reference it (App.tsx, ManageView.tsx, etc.).
- When removing a prop (e.g., `remotes` from BootstrapView), update both the component definition AND all call sites.
- Build the frontend after each batch of changes to catch TypeScript errors early.

## Common pitfalls
- **Secure cookie on test transport**: `Settings(tls_enabled=True)` makes `SessionMiddleware` set `Secure` cookies, which browsers don't send over HTTP. Tests must use `tls_enabled=False`.
- **Stale imports**: After removing a module symbol (e.g., `RcloneRemoteSpec` from an import), check all files that import it — ruff F401 catches unused imports, F821 catches undefined names.
- **JSX fragment mismatch**: When removing a phase/section from a React component, ensure opening `<></>` and closing `</>` match.
- **Broken JSX after sed**: Avoid bulk `sed` replacements on JSX disabled attributes — they leave trailing `||` operators. Use targeted edits instead.

## Verification checklist
- `ruff check src/dmf_init/` — only pre-existing warnings
- `cd frontend && npm run build` — clean (tsc + vite)
- `pytest tests/` — all pass (skips acceptable for tool-dependent tests)
- `git status` — only expected files modified
- Commit message covers all Changes and review items
