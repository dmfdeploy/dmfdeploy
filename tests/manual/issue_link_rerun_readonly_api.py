#!/usr/bin/env python3
"""Review-only current GitHub REST exercise; all rerun requests are blocked."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "bin" / "lib"))
import rerun_issue_link as rerun

REPOSITORY = rerun.DEFAULT_REPOSITORY
SOURCE_RUN_ID = 40529641530
ALLOWED_GET_PREFIXES = (
    f"repos/{REPOSITORY}/actions/runs/",
    f"repos/{REPOSITORY}/actions/workflows/",
    f"repos/{REPOSITORY}/pulls/",
    f"repos/{REPOSITORY}/collaborators/",
    f"repos/{REPOSITORY}/compare/",
)


class WriteBlocked(RuntimeError):
    """Raised before an attempted rerun can reach GitHub."""


class ReadOnlyGh:
    def __init__(self) -> None:
        self.get_paths: list[str] = []
        self.blocked_posts: list[str] = []

    def get(self, path: str):
        if not path.startswith(ALLOWED_GET_PREFIXES):
            raise RuntimeError("read-only adapter refused an unexpected endpoint")
        self.get_paths.append(path)
        response = subprocess.run(
            ["gh", "api", "--method", "GET", path],
            check=True, capture_output=True, text=True)
        return json.loads(response.stdout)

    def post(self, path: str):
        self.blocked_posts.append(path)
        raise WriteBlocked("blocked by read-only adapter")


def main() -> int:
    api = ReadOnlyGh()
    source_projection = api.get(
        f"repos/{REPOSITORY}/actions/runs/{SOURCE_RUN_ID}")
    # The runner-local workflow_run webhook was not available. This wrapper is
    # synthesized from the actual REST run identity and is labelled as such.
    event = {"action": "completed", "workflow_run": source_projection}
    source, source_id, source_sha, event_association = rerun._authoritative_source_run(
        api, REPOSITORY, source_projection)
    workflow_id = rerun._validate_workflow(api, REPOSITORY, source)
    _live, identity, _author = rerun._validate_live_source(
        api, REPOSITORY, source, source_sha,
        source["actor"]["login"], event_association)
    runs = rerun._list_runs(api, REPOSITORY, workflow_id, identity["head_sha"])
    eligible: list[tuple[dict, dict]] = []
    actor = source["actor"]["login"]
    for run in runs:
        matches, association = rerun._candidate_matches(
            run, workflow_id=workflow_id, source_id=source_id,
            identity=identity, actor=actor)
        if matches:
            eligible.append((run, association))
    eligible.sort(key=lambda pair: (str(pair[0].get("created_at", "")), pair[0]["id"]))
    if len(eligible) > rerun.MAX_CANDIDATES:
        raise RuntimeError("eligible candidate cap exceeded")

    comparisons: set[str] = set()
    for _run, association in eligible:
        candidate_base = association["base_sha"]
        if candidate_base != identity["base_sha"] and candidate_base not in comparisons:
            rerun._validate_base_ancestry(
                api, REPOSITORY, candidate_base, identity["base_sha"])
            comparisons.add(candidate_base)

    try:
        rerun.rerun_stale_suites(event, api, repository=REPOSITORY)
    except WriteBlocked:
        pass
    else:
        raise RuntimeError("helper did not reach the blocked rerun boundary")

    blocked_ids = [int(path.split("/")[-2]) for path in api.blocked_posts]
    eligible_ids = [run["id"] for run, _association in eligible]
    if not blocked_ids or blocked_ids[0] not in eligible_ids:
        raise RuntimeError("blocked write was not for a selected failed candidate")
    print(json.dumps({
        "event_provenance": "synthetic wrapper from actual REST source; raw webhook unavailable",
        "source_run_id": source_id,
        "pr_number": identity["number"],
        "workflow_history_run_ids": sorted(run["id"] for run in runs),
        "eligible_failed_candidate_run_ids": eligible_ids,
        "historical_base_compare_gets": [
            path for path in api.get_paths if "/compare/" in path],
        "blocked_would_be_rerun_paths": api.blocked_posts,
        "writes_sent": 0,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
