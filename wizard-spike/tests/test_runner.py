import os
from pathlib import Path

import pytest

from dmf_wizard.runner import RunSpec, run


FIXTURES = Path(__file__).parent / "fixtures"


def test_ok_script_returns_zero() -> None:
    result = run(RunSpec(argv=[str(FIXTURES / "ok.sh")]))
    assert result.exit_code == 0
    assert "ok" in result.stdout_tail


def test_fail_script_returns_nonzero_with_stderr() -> None:
    result = run(RunSpec(argv=[str(FIXTURES / "fail.sh")]))
    assert result.exit_code == 7
    assert "boom" in result.stderr_tail


def test_stdin_secret_is_piped() -> None:
    secret = b"shamir-share-3"
    result = run(
        RunSpec(
            argv=[str(FIXTURES / "echo_stdin.sh")],
            stdin_secret=secret,
            scrub_secret=False,
        )
    )
    assert result.exit_code == 0
    assert "shamir-share-3" in result.stdout_tail
    serialized = result.model_dump_json()
    assert "stdin_secret" not in serialized


def test_clean_env_excludes_leaks(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("LEAK", "bad")
    result = run(RunSpec(argv=[str(FIXTURES / "env_check.sh")]))
    assert result.exit_code == 0


def test_explicit_env_preserved(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("LEAK", "bad")
    result = run(
        RunSpec(
            argv=[str(FIXTURES / "env_check.sh")],
            env={"LEAK": "bad", "PATH": os.environ["PATH"]},
        )
    )
    assert result.exit_code == 1


def test_timeout_returns_timed_out() -> None:
    result = run(RunSpec(argv=["sleep", "5"], timeout_s=0.1))
    assert result.timed_out is True
    assert result.exit_code is None


def test_missing_binary_raises_filenotfound() -> None:
    with pytest.raises(FileNotFoundError):
        run(RunSpec(argv=["/nonexistent/cmd"]))


def test_secret_scrubbed_from_stdout() -> None:
    secret = b"hunter2"
    result = run(
        RunSpec(argv=[str(FIXTURES / "echo_stdin.sh")], stdin_secret=secret)
    )
    assert result.exit_code == 0
    assert "hunter2" not in result.stdout_tail
    assert "[REDACTED]" in result.stdout_tail


def test_scrub_disabled_leaves_secret() -> None:
    secret = b"hunter2"
    result = run(
        RunSpec(
            argv=[str(FIXTURES / "echo_stdin.sh")],
            stdin_secret=secret,
            scrub_secret=False,
        )
    )
    assert result.exit_code == 0
    assert "hunter2" in result.stdout_tail
