import argparse
import json
import sys
from pathlib import Path
from typing import Any

from dmf_wizard.orchestrator import Orchestrator, Step, UnknownStep
from dmf_wizard.profiles import Profile
from dmf_wizard.runner import RunSpec


def _demo_steps(fixtures_dir: Path) -> list[Step]:
    ok_script = fixtures_dir / "ok.sh"

    def _build(name: str):
        def builder(_context: dict[str, Any]) -> RunSpec:
            return RunSpec(argv=[str(ok_script)])

        return builder

    def _extract(name: str):
        def extractor(_context: dict[str, Any]) -> dict[str, Any]:
            return {"step": name}

        return extractor

    return [
        Step(name="doctor", build_runspec=_build("doctor"), extract_inputs=_extract("doctor")),
        Step(name="init", build_runspec=_build("init"), extract_inputs=_extract("init")),
    ]


def _make_orchestrator(state_path: Path, fixtures_dir: Path) -> Orchestrator:
    steps = _demo_steps(fixtures_dir)
    return Orchestrator(
        state_path=state_path,
        steps=steps,
        env_name="spike-demo",
        profile=Profile.CLOUD,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="dmf-wizard-spike")
    parser.add_argument(
        "--fixtures-dir",
        type=Path,
        default=Path("./tests/fixtures"),
        help="Directory containing fixture scripts.",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_status = sub.add_parser("status", help="Print step status as JSON.")
    p_status.add_argument("state_path", type=Path)

    p_run = sub.add_parser("run", help="Run a single step by name.")
    p_run.add_argument("state_path", type=Path)
    p_run.add_argument("step_name")
    p_run.add_argument("--force", action="store_true")

    p_resume = sub.add_parser("resume", help="Run all pending/failed steps in order.")
    p_resume.add_argument("state_path", type=Path)

    args = parser.parse_args(argv)

    orch = _make_orchestrator(args.state_path, args.fixtures_dir)

    if args.cmd == "status":
        statuses = {name: s.value for name, s in orch.status().items()}
        print(json.dumps(statuses, indent=2))
        return 0

    if args.cmd == "run":
        try:
            result = orch.run_step(args.step_name, {}, force=args.force)
        except UnknownStep as e:
            print(f"unknown step: {e}", file=sys.stderr)
            return 2
        print(result.model_dump_json(indent=2))
        return 0 if result.status.value in ("completed", "skipped") else 1

    if args.cmd == "resume":
        results = orch.resume({})
        print(json.dumps([r.model_dump(mode="json") for r in results], indent=2, default=str))
        if any(r.status.value == "failed" for r in results):
            return 1
        return 0

    return 2


if __name__ == "__main__":
    sys.exit(main())
