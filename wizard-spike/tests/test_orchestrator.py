from pathlib import Path
from typing import Any

import pytest

from dmf_wizard.orchestrator import Orchestrator, Step, UnknownStep
from dmf_wizard.profiles import Profile
from dmf_wizard.runner import RunSpec
from dmf_wizard.types import StepStatus, WizardState


FIXTURES = Path(__file__).parent / "fixtures"


def _ok_step(name: str) -> Step:
    return Step(
        name=name,
        build_runspec=lambda _ctx: RunSpec(argv=[str(FIXTURES / "ok.sh")]),
        extract_inputs=lambda _ctx: {"step": name},
    )


def _fail_step(name: str) -> Step:
    return Step(
        name=name,
        build_runspec=lambda _ctx: RunSpec(argv=[str(FIXTURES / "fail.sh")]),
        extract_inputs=lambda _ctx: {"step": name},
    )


def _skip_step(name: str) -> Step:
    return Step(
        name=name,
        build_runspec=lambda _ctx: RunSpec(argv=[str(FIXTURES / "ok.sh")]),
        extract_inputs=lambda _ctx: {"step": name},
        can_run=lambda _state, _ctx: False,
    )


def _make_orch(tmp_path: Path, steps: list[Step]) -> Orchestrator:
    return Orchestrator(
        state_path=tmp_path / "state.json",
        steps=steps,
        env_name="spike-test",
        profile=Profile.CLOUD,
    )


def test_status_empty_at_init(tmp_path: Path) -> None:
    orch = _make_orch(tmp_path, [_ok_step("a"), _ok_step("b")])
    statuses = orch.status()
    assert statuses == {"a": StepStatus.PENDING, "b": StepStatus.PENDING}


def test_run_step_marks_completed_on_success(tmp_path: Path) -> None:
    orch = _make_orch(tmp_path, [_ok_step("doctor")])
    result = orch.run_step("doctor", {})
    assert result.status == StepStatus.COMPLETED
    assert result.input_checksum is not None
    assert orch.status()["doctor"] == StepStatus.COMPLETED


def test_run_step_marks_failed_on_nonzero(tmp_path: Path) -> None:
    orch = _make_orch(tmp_path, [_fail_step("boom")])
    result = orch.run_step("boom", {})
    assert result.status == StepStatus.FAILED
    assert result.error is not None
    assert "exit 7" in result.error


def test_run_step_skipped_if_can_run_false(tmp_path: Path) -> None:
    orch = _make_orch(tmp_path, [_skip_step("skipme")])
    result = orch.run_step("skipme", {})
    assert result.status == StepStatus.SKIPPED


def test_resume_runs_pending_in_order(tmp_path: Path) -> None:
    orch = _make_orch(tmp_path, [_ok_step("a"), _ok_step("b")])
    results = orch.resume({})
    assert [r.name for r in results] == ["a", "b"]
    assert all(r.status == StepStatus.COMPLETED for r in results)


def test_resume_stops_on_failure(tmp_path: Path) -> None:
    orch = _make_orch(
        tmp_path, [_ok_step("a"), _fail_step("b"), _ok_step("c")]
    )
    results = orch.resume({})
    assert [r.name for r in results] == ["a", "b"]
    assert results[0].status == StepStatus.COMPLETED
    assert results[1].status == StepStatus.FAILED
    assert orch.status()["c"] == StepStatus.PENDING


def test_run_step_cached_on_checksum_match(tmp_path: Path) -> None:
    orch = _make_orch(tmp_path, [_ok_step("doctor")])
    first = orch.run_step("doctor", {})
    second = orch.run_step("doctor", {})
    assert first.started_at == second.started_at
    assert first.input_checksum == second.input_checksum


def test_force_reruns_completed_step(tmp_path: Path) -> None:
    orch = _make_orch(tmp_path, [_ok_step("doctor")])
    first = orch.run_step("doctor", {})
    second = orch.run_step("doctor", {}, force=True)
    assert second.status == StepStatus.COMPLETED
    assert second.started_at is not None and first.started_at is not None
    assert second.started_at != first.started_at


def test_unknown_step_raises(tmp_path: Path) -> None:
    orch = _make_orch(tmp_path, [_ok_step("a")])
    with pytest.raises(UnknownStep):
        orch.run_step("nonexistent", {})


def test_orchestrator_accepts_profile_enum(tmp_path: Path) -> None:
    orch = _make_orch(tmp_path, [_ok_step("a")])
    assert orch.state.profile == Profile.CLOUD


def test_resume_reevaluates_skipped(tmp_path: Path) -> None:
    gate = {"open": False}

    def can_run(_state: WizardState, _ctx: dict[str, Any]) -> bool:
        return gate["open"]

    gated_step = Step(
        name="gated",
        build_runspec=lambda _ctx: RunSpec(argv=[str(FIXTURES / "ok.sh")]),
        extract_inputs=lambda _ctx: {"step": "gated"},
        can_run=can_run,
    )
    orch = _make_orch(tmp_path, [gated_step])

    first = orch.resume({})
    # Gate closed: step is SKIPPED, but resume doesn't surface it.
    assert first == []
    assert orch.status()["gated"] == StepStatus.SKIPPED

    gate["open"] = True
    second = orch.resume({})
    assert [r.name for r in second] == ["gated"]
    assert second[0].status == StepStatus.COMPLETED
    assert orch.status()["gated"] == StepStatus.COMPLETED
