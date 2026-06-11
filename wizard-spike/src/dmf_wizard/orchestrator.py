from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

from dmf_wizard.profiles import Profile, Tier
from dmf_wizard.runner import RunSpec, run
from dmf_wizard.state import checksum_inputs, load_state, save_state
from dmf_wizard.types import StepResult, StepStatus, WizardState


class UnknownStep(Exception):
    """Raised when run_step is called with an unregistered step name."""


@dataclass
class Step:
    name: str
    build_runspec: Callable[[dict[str, Any]], RunSpec]
    extract_inputs: Callable[[dict[str, Any]], dict[str, Any]]
    can_run: Callable[[WizardState, dict[str, Any]], bool] | None = None


class Orchestrator:
    def __init__(
        self,
        state_path: Path,
        steps: list[Step],
        env_name: str,
        profile: Profile,
        tier: Tier | None = None,
    ) -> None:
        self._state_path = state_path
        self._steps_by_name: dict[str, Step] = {s.name: s for s in steps}
        self._step_order: list[str] = [s.name for s in steps]
        loaded = load_state(state_path)
        if loaded is None:
            now = datetime.now(timezone.utc)
            self._state = WizardState(
                env_name=env_name,
                profile=profile,
                tier=tier,
                created_at=now,
                updated_at=now,
                steps={},
            )
            save_state(state_path, self._state)
        else:
            self._state = loaded

    @property
    def state(self) -> WizardState:
        return self._state

    def status(self) -> dict[str, StepStatus]:
        """Status for every declared step (PENDING if never attempted)."""
        out: dict[str, StepStatus] = {}
        for name in self._step_order:
            existing = self._state.steps.get(name)
            out[name] = existing.status if existing is not None else StepStatus.PENDING
        return out

    def run_step(
        self,
        name: str,
        context: dict[str, Any],
        force: bool = False,
    ) -> StepResult:
        """Execute one step, honoring checksum caching and can_run gates."""
        step = self._steps_by_name.get(name)
        if step is None:
            raise UnknownStep(name)

        inputs = step.extract_inputs(context)
        digest = checksum_inputs(inputs)

        if step.can_run is not None and not step.can_run(self._state, context):
            result = StepResult(
                name=name,
                status=StepStatus.SKIPPED,
                input_checksum=digest,
            )
            self._state.steps[name] = result
            save_state(self._state_path, self._state)
            return result

        existing = self._state.steps.get(name)
        if (
            not force
            and existing is not None
            and existing.status == StepStatus.COMPLETED
            and existing.input_checksum == digest
        ):
            return existing

        started = datetime.now(timezone.utc)
        in_progress = StepResult(
            name=name,
            status=StepStatus.IN_PROGRESS,
            started_at=started,
            input_checksum=digest,
        )
        self._state.steps[name] = in_progress
        save_state(self._state_path, self._state)

        spec = step.build_runspec(context)
        run_result = run(spec)
        finished = datetime.now(timezone.utc)

        if run_result.exit_code == 0:
            final = StepResult(
                name=name,
                status=StepStatus.COMPLETED,
                started_at=started,
                finished_at=finished,
                exit_code=run_result.exit_code,
                stdout_tail=run_result.stdout_tail,
                stderr_tail=run_result.stderr_tail,
                input_checksum=digest,
            )
        else:
            if run_result.timed_out:
                err = "timed out"
            else:
                err = f"exit {run_result.exit_code}"
            final = StepResult(
                name=name,
                status=StepStatus.FAILED,
                started_at=started,
                finished_at=finished,
                exit_code=run_result.exit_code,
                stdout_tail=run_result.stdout_tail,
                stderr_tail=run_result.stderr_tail,
                input_checksum=digest,
                error=err,
            )

        self._state.steps[name] = final
        save_state(self._state_path, self._state)
        return final

    def resume(self, context: dict[str, Any]) -> list[StepResult]:
        """Run PENDING/FAILED/SKIPPED steps in declared order, stopping on failure.

        SKIPPED steps are re-evaluated via ``can_run`` on every resume call. If
        the gate now passes the step runs and is appended to the executed list;
        if it still fails the SKIPPED result is kept and the step is not
        surfaced (nothing happened, so nothing to report).
        """
        executed: list[StepResult] = []
        for name in self._step_order:
            existing = self._state.steps.get(name)
            status = existing.status if existing is not None else StepStatus.PENDING
            if status not in (
                StepStatus.PENDING,
                StepStatus.FAILED,
                StepStatus.SKIPPED,
            ):
                continue
            step = self._steps_by_name[name]
            if (
                step.can_run is not None
                and not step.can_run(self._state, context)
            ):
                # Gate closed; record/keep SKIPPED but don't surface.
                self.run_step(name, context)
                continue
            result = self.run_step(name, context)
            executed.append(result)
            if result.status == StepStatus.FAILED:
                break
        return executed
