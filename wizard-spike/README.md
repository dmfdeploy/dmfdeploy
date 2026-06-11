# dmf-wizard-spike

> **Architectural spike, not production code.** Validates three patterns for
> the init-wizard rewrite; do not deploy or extend as the production wizard.

Architectural spike for the Python rewrite of the DMF init-wizard
(`dmf-env/bin/init-wizard.sh`, 661 lines of bash). This package validates
three patterns *only*; it is not the production wizard.

## What it proves

1. **Library-shaped orchestration core.** `Orchestrator` plus `Step` exposes a
   small surface that a CLI, TUI, or other front-end can sit on top of. No
   imperative script glue inside the library.
2. **State-persistent resume semantics.** Wizard state is a Pydantic model
   serialized atomically to a JSON file. `resume()` walks declared step order
   skipping already-completed work, stopping on the first failure, and an
   `input_checksum` per step lets cached runs short-circuit cleanly.
3. **Shamir-safe subprocess wrapping.** The `runner` module accepts a
   `stdin_secret: bytes | None` and pipes it via stdin only. Secrets never
   appear in argv, env, /tmp, or the returned `RunResult` (ADR-0007). The
   default env is a minimal allowlist; operator env is not inherited.

All tests run against fixture shell scripts under `tests/fixtures/`. No live
infrastructure is touched.

## Run

```sh
cd wizard-spike
uv sync
uv run pytest -v
```

Without `uv`, fall back to:

```sh
python -m venv .venv
.venv/bin/pip install -e '.[dev]'
.venv/bin/pytest -v
```

## What's new in step 5a

- **Typed `Profile` / `Tier` enums** (`profiles.py`) replace string literals on
  `WizardState` and `Orchestrator.__init__`. No more `# type: ignore` at the
  profile boundary.
- **Canonical `(profile, tier)` defaults table** (`PRESET_DEFAULTS`,
  `get_defaults`) — eventual home is `dmf-infra`, parked here for the spike.
  Deep-copy guarantees so callers can't poison the table.
- **Discriminated-union `Manifest` pydantic model** with `CloudManifest`,
  `FlypackOfflineManifest`, `FlypackOnlineManifest` variants and a
  ruamel.yaml-based deterministic emitter (`dump_yaml` / `load_yaml`). Round-
  trips through YAML with stable key ordering.
- **Spec-gap fixes** for the six items flagged in Step 4 of the survey:
  - Timeout sets `exit_code = None` + `timed_out = True` (was `-1`).
  - `runner.run()` scrubs `stdin_secret` byte sequences from stdout/stderr
    tails by default (`scrub_secret=True`); opt-out for testing only.
  - `atomic_write_text` `os.fsync`s the parent directory after `os.replace`.
  - `Orchestrator.resume()` re-evaluates `can_run` for SKIPPED steps; flips
    to COMPLETED if the gate has opened, otherwise keeps SKIPPED silently.
  - Typed `profile: Profile` (+ optional `tier: Tier | None`) on
    `Orchestrator.__init__`.
  - `WizardState.profile` is the `Profile` enum, not a `Literal[...]` of
    strings.

## Explicitly NOT in this spike

- Wrapping the real bash scripts (`tf-apply.sh`, `run-playbook.sh`,
  `unseal-openbao.sh`, ...). The runner is generic; step glue lands later.
- The full env-manifest schema with provider/region/profile branches.
- A TUI or operator-facing rich UI. The CLI is a thin demo only.
- Lane-conditional prompts (cloud / flypack-offline / flypack-online).
- Concurrency, parallel steps, or step dependency graphs beyond linear order.

Those are step 5 of the rewrite.

## See also

- `docs/plans/DMF Init Wizard Expansion Survey 2026-05-13.md` (round 2 step 2)
- `docs/decisions/0022-flypack-online-thin-edge-agent.md`
