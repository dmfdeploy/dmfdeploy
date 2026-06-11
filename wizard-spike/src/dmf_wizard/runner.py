"""Subprocess runner for the DMF wizard spike.

ADR-0007 compliance: ``stdin_secret`` is the only channel for secret input. It
is never logged, never serialized into RunResult, and never passed via argv or
env. The default env is a minimal allowlist — operator env is not inherited.

Conventions:
- Timeout sets ``exit_code = None`` and ``timed_out = True``. Callers must check
  ``timed_out`` rather than relying on a sentinel exit code.
- When ``scrub_secret`` is true (default) and ``stdin_secret`` is set, any byte
  occurrence of the secret in captured stdout/stderr is replaced with
  ``[REDACTED]`` before decoding.
"""

import os
import subprocess
import time
from pathlib import Path

from pydantic import BaseModel


TAIL_BYTES = 4096
REDACTED = b"[REDACTED]"


class RunSpec(BaseModel):
    argv: list[str]
    env: dict[str, str] | None = None
    cwd: Path | None = None
    stdin_secret: bytes | None = None
    timeout_s: float | None = None
    scrub_secret: bool = True
    model_config = {"arbitrary_types_allowed": True}


class RunResult(BaseModel):
    exit_code: int | None
    stdout_tail: str
    stderr_tail: str
    duration_s: float
    timed_out: bool = False


def _scrub(buf: bytes | None, secret: bytes | None) -> bytes | None:
    if buf is None or not secret:
        return buf
    return buf.replace(secret, REDACTED)


def _tail(buf: bytes | None) -> str:
    if not buf:
        return ""
    return buf[-TAIL_BYTES:].decode("utf-8", errors="replace")


def _clean_env() -> dict[str, str]:
    return {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": os.environ.get("HOME", "/tmp"),
        "USER": os.environ.get("USER", "nobody"),
        "LANG": "C.UTF-8",
    }


def run(spec: RunSpec) -> RunResult:
    """Run a subprocess per RunSpec; secret stdin never leaks into the result."""
    env = _clean_env() if spec.env is None else spec.env
    cwd = str(spec.cwd) if spec.cwd is not None else None
    secret = spec.stdin_secret if spec.scrub_secret else None
    start = time.monotonic()
    try:
        completed = subprocess.run(
            spec.argv,
            env=env,
            cwd=cwd,
            input=spec.stdin_secret,
            capture_output=True,
            timeout=spec.timeout_s,
        )
    except subprocess.TimeoutExpired as e:
        duration = time.monotonic() - start
        out = e.stdout if isinstance(e.stdout, bytes) else None
        err = e.stderr if isinstance(e.stderr, bytes) else None
        return RunResult(
            exit_code=None,
            stdout_tail=_tail(_scrub(out, secret)),
            stderr_tail=_tail(_scrub(err, secret)),
            duration_s=duration,
            timed_out=True,
        )
    duration = time.monotonic() - start
    return RunResult(
        exit_code=completed.returncode,
        stdout_tail=_tail(_scrub(completed.stdout, secret)),
        stderr_tail=_tail(_scrub(completed.stderr, secret)),
        duration_s=duration,
        timed_out=False,
    )
