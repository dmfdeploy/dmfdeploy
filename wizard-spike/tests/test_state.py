from datetime import datetime, timezone
from pathlib import Path

import pytest

from dmf_wizard.state import (
    StateCorrupt,
    checksum_inputs,
    load_state,
    save_state,
)
from dmf_wizard.profiles import Profile
from dmf_wizard.types import StepResult, StepStatus, WizardState


def _make_state() -> WizardState:
    now = datetime.now(timezone.utc)
    return WizardState(
        env_name="spike-test",
        profile=Profile.CLOUD,
        created_at=now,
        updated_at=now,
        steps={
            "doctor": StepResult(name="doctor", status=StepStatus.COMPLETED, exit_code=0)
        },
    )


def test_load_missing_returns_none(tmp_path: Path) -> None:
    assert load_state(tmp_path / "missing.json") is None


def test_save_and_load_roundtrip(tmp_path: Path) -> None:
    path = tmp_path / "state.json"
    original = _make_state()
    save_state(path, original)
    loaded = load_state(path)
    assert loaded is not None
    assert loaded.env_name == original.env_name
    assert loaded.profile == original.profile
    assert set(loaded.steps.keys()) == {"doctor"}
    assert loaded.steps["doctor"].status == StepStatus.COMPLETED


def test_corrupt_state_raises(tmp_path: Path) -> None:
    path = tmp_path / "state.json"
    path.write_text('{"garbage": true}', encoding="utf-8")
    with pytest.raises(StateCorrupt):
        load_state(path)


def test_schema_version_mismatch_raises(tmp_path: Path) -> None:
    path = tmp_path / "state.json"
    now = datetime.now(timezone.utc).isoformat()
    payload = (
        '{"schema_version": 99, "env_name": "x", "profile": "cloud",'
        f' "created_at": "{now}", "updated_at": "{now}", "steps": {{}}}}'
    )
    path.write_text(payload, encoding="utf-8")
    with pytest.raises(StateCorrupt):
        load_state(path)


def test_checksum_stable_across_dict_ordering() -> None:
    assert checksum_inputs({"a": 1, "b": 2}) == checksum_inputs({"b": 2, "a": 1})


def test_checksum_changes_on_input_change() -> None:
    assert checksum_inputs({"a": 1}) != checksum_inputs({"a": 2})


def test_atomic_save_does_not_leave_tmp(tmp_path: Path) -> None:
    path = tmp_path / "state.json"
    save_state(path, _make_state())
    tmp_sibling = path.with_suffix(path.suffix + ".tmp")
    assert not tmp_sibling.exists()
    assert path.exists()
