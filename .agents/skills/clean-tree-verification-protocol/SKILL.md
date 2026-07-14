---
name: clean-tree-verification-protocol
description: Verify build-fallback code paths from a clean export scratch, not the dirty working tree where ignored build artifacts mask the fallback
source: auto-skill
extracted_at: '2026-06-09T21:05:30.932Z'
type: durable-pattern
scope: verification
owner: operator
review_by: '2027-01-14'
---

# Clean-Tree Verification Protocol

When a repo ships without built artifacts (e.g., React SPA, compiled frontend, generated code) and has a **fallback code path** that triggers when the built artifact is missing, you MUST verify from a **clean export scratch**, not the dirty working tree.

## Why

The working tree often has ignored built artifacts (`static/app/index.html`, `dist/`, `build/`) that mask the fallback path. Tests pass locally because the artifact exists, but fail on CI/clean trees because the fallback is broken.

## The procedure

1. **Export tracked files only** to a scratch directory:

   ```bash
   rm -rf /tmp/repo-clean && mkdir -p /tmp/repo-clean
   cd /path/to/repo
   git ls-tree -r --name-only HEAD | while read f; do
     mkdir -p "$(dirname "/tmp/repo-clean/$f")"
     git show HEAD:"$f" > "/tmp/repo-clean/$f"
   done
   ```

2. **Apply modified source files** to the scratch (copy your changed .py files over):

   ```bash
   cp /path/to/repo/src/module/changed.py /tmp/repo-clean/src/module/changed.py
   ```

3. **Confirm the artifact is absent** in the scratch:

   ```bash
   ls /tmp/repo-clean/src/package/static/app/index.html 2>/dev/null
   # Should say "NOT FOUND" — clean tree confirmed
   ```

4. **Install and run tests** from the scratch:

   ```bash
   python3.12 -m venv /tmp/test-venv
   /tmp/test-venv/bin/pip install -e '/tmp/repo-clean[dev]'
   /tmp/test-venv/bin/pytest tests/ -v
   ```

5. **Test both Python versions** if the CI matrix covers multiple versions. Note if a version is not available locally — flag it.

## Common fallback patterns to fix

### SPA/React clean-tree fallback HTML

When `static/app/index.html` is missing, the app should still render a meaningful shell. Fix the fallback HTML to include all key product identifiers (e.g., both "DMF Console" AND "App Catalog").

### base_path-aware redirects

When the app runs under a prefix (e.g., `/console/`), login/logout redirects must respect that prefix:

```python
def _base_path_url(path: str, settings: Settings) -> str:
    """Prefix a local path with base_path; leave absolute URLs untouched."""
    if path.startswith(("http://", "https://", "//")):
        return path
    bp = settings.base_path.rstrip("/")
    if not bp or bp == "/":
        return path
    return bp + path
```

Apply to all **local** redirect paths (dev login, post-auth callback). Leave **absolute** OIDC provider URLs unchanged — they are browser-facing and derive from `issuer_url`, not `base_path`.

### Verification checklist for base_path redirect fix

- `client.get("/console/auth/login", follow_redirects=False).headers["location"]` ends with `/console/`
- `client.get("/auth/login", follow_redirects=False).headers["location"]` with OIDC settings starts with the provider URL (e.g., `https://auth.example.invalid/...`)
- `_base_path_url` unit tests: absolute URLs untouched, local paths prefixed, `/` base_path is no-op
- Existing OIDC tests still pass (callback URL, PKCE verifier, redirect_uri encoding)

## What NOT to do

- Do NOT test from the dirty working tree where `git ls-files --others --ignored` shows the artifact
- Do NOT build the frontend to "fix" the test — the fallback is a real public runtime path
- Do NOT relax test assertions to make them pass on clean tree
- Do NOT modify tests unless making them *more precise* about intended behavior