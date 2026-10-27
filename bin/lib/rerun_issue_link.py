#!/usr/bin/env python3
"""Safely rerun failed issue-link suites for the same live pull request head."""

from __future__ import annotations

import json
import os
import re
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen
from typing import Any

from issue_link_gate import evaluate


WORKFLOW_PATH = ".github/workflows/issue-link.yml"
WORKFLOW_FILE = "issue-link.yml"
DEFAULT_REPOSITORY = "dmfdeploy/dmfdeploy"
DEFAULT_BRANCH = "main"
PAGE_SIZE = 100
MAX_RUN_PAGES = 20
MAX_WAIT_SECONDS = 300
POLL_INTERVAL_SECONDS = 2
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
RERUNNABLE_CONCLUSIONS = {
    "failure", "cancelled", "timed_out", "action_required", "startup_failure",
}


class UnsafeRun(ValueError):
    """Input is incomplete, stale, or cannot be tied to the expected PR/run."""


class ApiFailure(RuntimeError):
    """GitHub API failure; messages intentionally omit response bodies."""


class GitHubApi:
    def __init__(self, token: str, api_url: str = "https://api.github.com"):
        if not token:
            raise ApiFailure("GitHub token is missing")
        self._token = token
        self._api_url = api_url.rstrip("/")

    def _request(self, method: str, path: str) -> tuple[Any, Any]:
        req = Request(
            f"{self._api_url}/{path.lstrip('/')}",
            headers={
                "Accept": "application/vnd.github+json",
                "Authorization": f"Bearer {self._token}",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": "dmfdeploy-issue-link-rerun",
            },
            method=method,
        )
        try:
            with urlopen(req, timeout=15) as response:
                raw = response.read()
                payload = json.loads(raw) if raw else {}
                return payload, response.headers
        except HTTPError as exc:
            raise ApiFailure(f"GitHub API returned HTTP {exc.code}") from None
        except (URLError, OSError, TimeoutError, json.JSONDecodeError):
            raise ApiFailure("GitHub API request failed") from None

    def get(self, path: str) -> Any:
        payload, _headers = self._request("GET", path)
        return payload

    def post(self, path: str) -> Any:
        payload, _headers = self._request("POST", path)
        return payload


def _mapping(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise UnsafeRun(f"{label} is missing or malformed")
    return value


def _sha(value: Any, label: str) -> str:
    if not isinstance(value, str) or not SHA_RE.fullmatch(value):
        raise UnsafeRun(f"{label} is missing or malformed")
    return value


def _pr_number(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        raise UnsafeRun(f"{label} is missing or malformed")
    return value


def _single_pull_request(run: dict[str, Any], label: str) -> dict[str, Any]:
    pull_requests = run.get("pull_requests")
    if not isinstance(pull_requests, list) or len(pull_requests) != 1:
        raise UnsafeRun(f"{label} does not identify exactly one pull request")
    return _mapping(pull_requests[0], f"{label} pull request")


def _pr_repo_info(pr: dict[str, Any], label: str) -> tuple[int, str, str, str, str, str]:
    number = _pr_number(pr.get("number"), f"{label} number")
    base = _mapping(pr.get("base"), f"{label} base")
    head = _mapping(pr.get("head"), f"{label} head")
    base_ref = base.get("ref")
    head_ref = head.get("ref")
    if not isinstance(base_ref, str) or not base_ref:
        raise UnsafeRun(f"{label} base ref is missing")
    if not isinstance(head_ref, str) or not head_ref:
        raise UnsafeRun(f"{label} head ref is missing")
    base_sha = _sha(base.get("sha"), f"{label} base SHA")
    head_sha = _sha(head.get("sha"), f"{label} head SHA")
    base_repo = _mapping(base.get("repo"), f"{label} base repository")
    head_repo = _mapping(head.get("repo"), f"{label} head repository")
    base_name = base_repo.get("full_name")
    head_name = head_repo.get("full_name")
    if not isinstance(base_name, str) or not base_name:
        raise UnsafeRun(f"{label} base repository name is missing")
    if not isinstance(head_name, str) or not head_name:
        raise UnsafeRun(f"{label} head repository name is missing")
    return number, base_ref, base_sha, head_ref, head_sha, f"{base_name}|{head_name}"


def _same_pr_association(
    run: dict[str, Any],
    *,
    number: int,
    base_ref: str,
    base_sha: str,
    head_ref: str,
    head_sha: str,
    repo_pair: str,
    label: str,
) -> None:
    pr = _single_pull_request(run, label)
    (got_number, got_base_ref, got_base_sha,
     got_head_ref, got_head_sha, got_repo_pair) = _pr_repo_info(pr, label)
    if (got_number, got_base_ref, got_base_sha, got_head_ref, got_head_sha, got_repo_pair) != (
            number, base_ref, base_sha, head_ref, head_sha, repo_pair):
        raise UnsafeRun(f"{label} pull request association changed")


def _permission_allows(api: Any, repo: str, actor: str, author: str) -> bool:
    if actor == author:
        return True
    path = f"repos/{repo}/collaborators/{quote(actor, safe='')}/permission"
    try:
        result = _mapping(api.get(path), "actor permission")
    except ApiFailure as exc:
        if "HTTP 404" in str(exc):
            return False
        raise
    user = _mapping(result.get("user"), "permission user")
    if user.get("login") != actor:
        raise UnsafeRun("actor permission response does not match event actor")
    permission = result.get("permission")
    role_name = result.get("role_name")
    return permission in {"write", "admin"} or role_name in {
        "triage", "write", "maintain", "admin", "owner",
    }


def _validate_workflow(api: Any, repo: str, source: dict[str, Any]) -> int:
    workflow = _mapping(api.get(f"repos/{repo}/actions/workflows/{WORKFLOW_FILE}"),
                         "trusted workflow")
    workflow_id = workflow.get("id")
    if isinstance(workflow_id, bool) or not isinstance(workflow_id, int) or workflow_id < 1:
        raise UnsafeRun("trusted workflow ID is missing")
    if workflow.get("path") != WORKFLOW_PATH or workflow.get("state") != "active":
        raise UnsafeRun("trusted workflow path or state does not match")
    source_id = source.get("workflow_id")
    if isinstance(source_id, bool) or source_id != workflow_id:
        raise UnsafeRun("source run belongs to another workflow")
    if source.get("name") != "issue-link":
        raise UnsafeRun("source run name does not match the required check")
    return workflow_id


def _validate_source(source: Any, event_action: Any) -> tuple[dict[str, Any], int, str]:
    source = _mapping(source, "source workflow run")
    if event_action != "completed":
        raise UnsafeRun("workflow_run event is not completed")
    if source.get("event") != "pull_request_target":
        raise UnsafeRun("source event is not pull_request_target")
    if source.get("status") != "completed" or source.get("conclusion") != "success":
        raise UnsafeRun("source issue-link check did not pass")
    attempt = source.get("run_attempt")
    if isinstance(attempt, bool) or attempt != 1:
        raise UnsafeRun("source run is not its first attempt")
    source_id = source.get("id")
    if isinstance(source_id, bool) or not isinstance(source_id, int) or source_id < 1:
        raise UnsafeRun("source workflow run ID is missing")
    head_sha = _sha(source.get("head_sha"), "source run head SHA")
    return source, source_id, head_sha


def _live_pr(api: Any, repo: str, number: int) -> dict[str, Any]:
    pr = _mapping(api.get(f"repos/{repo}/pulls/{number}"), "live pull request")
    if _pr_number(pr.get("number"), "live pull request number") != number:
        raise UnsafeRun("live pull request number does not match")
    if pr.get("state") != "open":
        raise UnsafeRun("pull request is not open")
    return pr


def _validate_live_source(
    api: Any, repo: str, source: dict[str, Any], source_sha: str,
    event_actor: Any,
) -> tuple[dict[str, Any], int, str, str, str, str, str, str]:
    associated_pr = _single_pull_request(source, "source run")
    (number, associated_base_ref, associated_base_sha, associated_head_ref,
     associated_head_sha, associated_repo_pair) = _pr_repo_info(associated_pr, "source PR")
    live = _live_pr(api, repo, number)
    live_user = _mapping(live.get("user"), "live PR author").get("login")
    live_head = _mapping(live.get("head"), "live PR head")
    live_base = _mapping(live.get("base"), "live PR base")
    live_base_repo = _mapping(live_base.get("repo"), "live PR base repository")
    live_head_repo = _mapping(live_head.get("repo"), "live PR head repository")
    live_head_sha = _sha(live_head.get("sha"), "live PR head SHA")
    live_base_sha = _sha(live_base.get("sha"), "live PR base SHA")
    live_base_ref = live_base.get("ref")
    live_head_ref = live_head.get("ref")
    if live_base_ref != DEFAULT_BRANCH or not isinstance(live_head_ref, str):
        raise UnsafeRun("pull request base or head ref is unsupported")
    if live_base_repo.get("full_name") != repo:
        raise UnsafeRun("pull request base repository is not canonical")
    live_head_repo_name = live_head_repo.get("full_name")
    if not isinstance(live_head_repo_name, str) or not live_head_repo_name:
        raise UnsafeRun("pull request head repository is missing")
    if not isinstance(live_user, str) or not live_user:
        raise UnsafeRun("pull request author is missing")
    if not isinstance(event_actor, str) or not event_actor:
        raise UnsafeRun("workflow event actor is missing")

    live_repo_pair = f"{repo}|{live_head_repo_name}"
    if (source_sha != live_head_sha
            or associated_head_sha != live_head_sha
            or associated_base_ref != live_base_ref
            or associated_base_sha != live_base_sha
            or associated_head_ref != live_head_ref
            or associated_repo_pair != live_repo_pair):
        raise UnsafeRun("source run no longer matches the live PR head/base")
    if not _permission_allows(api, repo, event_actor, live_user):
        raise UnsafeRun("workflow event actor is not authorized for this PR")
    if not isinstance(live.get("body"), (str, type(None))):
        raise UnsafeRun("live PR body is malformed")
    labels_raw = live.get("labels")
    if not isinstance(labels_raw, list):
        raise UnsafeRun("live PR labels are malformed")
    labels = []
    for label_obj in labels_raw:
        label = _mapping(label_obj, "live PR label")
        name = label.get("name")
        if not isinstance(name, str):
            raise UnsafeRun("live PR label name is malformed")
        labels.append(name)
    errors = evaluate(live.get("body") or "", labels, repo)
    if errors:
        raise UnsafeRun("live PR body no longer passes issue-link")
    return (live, number, live_head_sha, live_base_sha, live_base_ref,
            live_head_ref, live_head_repo_name, live_user)


def _list_runs(api: Any, repo: str, workflow_id: int, head_sha: str) -> list[dict[str, Any]]:
    runs: list[dict[str, Any]] = []
    for page in range(1, MAX_RUN_PAGES + 1):
        query = urlencode({
            "event": "pull_request_target",
            "head_sha": head_sha,
            "per_page": PAGE_SIZE,
            "page": page,
        })
        result = _mapping(api.get(
            f"repos/{repo}/actions/workflows/{workflow_id}/runs?{query}"),
            "workflow run list")
        batch = result.get("workflow_runs")
        if not isinstance(batch, list) or any(not isinstance(item, dict) for item in batch):
            raise UnsafeRun("workflow run list is malformed")
        runs.extend(batch)
        if len(batch) < PAGE_SIZE:
            return runs
    raise UnsafeRun("workflow run list exceeded the safe page limit")


def _candidate_matches(
    run: dict[str, Any], *, workflow_id: int, source_id: int, head_sha: str,
    number: int, base_ref: str, base_sha: str, head_ref: str,
    repo_pair: str,
) -> bool:
    run_id = run.get("id")
    if isinstance(run_id, bool) or not isinstance(run_id, int) or run_id < 1:
        raise UnsafeRun("candidate run ID is malformed")
    if run_id == source_id:
        return False
    if run.get("workflow_id") != workflow_id:
        return False
    if run.get("event") != "pull_request_target":
        return False
    if _sha(run.get("head_sha"), "candidate head SHA") != head_sha:
        return False
    assoc = _single_pull_request(run, "candidate run")
    _same_pr_association(
        {"pull_requests": [assoc]},
        number=number,
        base_ref=base_ref,
        base_sha=base_sha,
        head_ref=head_ref,
        head_sha=head_sha,
        repo_pair=repo_pair,
        label="candidate run",
    )
    if run.get("status") == "completed" and run.get("conclusion") in RERUNNABLE_CONCLUSIONS:
        attempt = run.get("run_attempt")
        if isinstance(attempt, bool) or not isinstance(attempt, int) or not 1 <= attempt <= 50:
            raise UnsafeRun("candidate run attempt is malformed or exhausted")
        return attempt < 50
    if run.get("status") not in {"completed", "queued", "in_progress", "waiting", "requested"}:
        raise UnsafeRun("candidate run status is unknown")
    return False


def _get_run(api: Any, repo: str, run_id: int) -> dict[str, Any]:
    return _mapping(api.get(f"repos/{repo}/actions/runs/{run_id}"), "candidate run detail")


def _wait_for_attempt(
    api: Any, repo: str, run_id: int, old_attempt: int,
    *, timeout_seconds: float, clock=time.monotonic, sleeper=time.sleep,
) -> dict[str, Any]:
    deadline = clock() + timeout_seconds
    while clock() < deadline:
        run = _get_run(api, repo, run_id)
        attempt = run.get("run_attempt")
        if isinstance(attempt, bool) or not isinstance(attempt, int):
            raise UnsafeRun("rerun attempt metadata is malformed")
        if attempt > old_attempt:
            if attempt != old_attempt + 1:
                raise UnsafeRun("candidate run changed through another rerun")
            if run.get("status") == "completed":
                return run
        elif attempt < old_attempt or run.get("status") not in {
                "completed", "queued", "in_progress", "waiting", "requested"}:
            raise UnsafeRun("candidate run changed unexpectedly")
        sleeper(POLL_INTERVAL_SECONDS)
    raise ApiFailure("candidate rerun did not complete before timeout")


def rerun_stale_suites(
    event: Any,
    api: Any,
    *,
    repository: str = DEFAULT_REPOSITORY,
    timeout_per_run: float = MAX_WAIT_SECONDS,
    clock=time.monotonic,
    sleeper=time.sleep,
) -> dict[str, Any]:
    """Rerun every proven failed issue-link suite for one live PR head.

    All GET/POST calls go through ``api`` so fixture tests exercise the exact
    selector and mutation boundary without making network requests.
    """
    if repository != DEFAULT_REPOSITORY:
        raise UnsafeRun("repository is not the canonical umbrella")
    event = _mapping(event, "workflow_run webhook")
    source, source_id, source_sha = _validate_source(
        event.get("workflow_run"), event.get("action"))
    workflow_id = _validate_workflow(api, repository, source)
    (live, number, head_sha, base_sha, base_ref, head_ref,
     head_repo_name, _author) = _validate_live_source(
        api, repository, source, source_sha,
        _mapping(source.get("actor"), "source run actor").get("login"))
    event_actor = _mapping(source.get("actor"), "source run actor").get("login")
    repo_pair = f"{repository}|{head_repo_name}"
    candidates = _list_runs(api, repository, workflow_id, head_sha)
    matching = [
        run for run in candidates
        if _candidate_matches(
            run, workflow_id=workflow_id, source_id=source_id, head_sha=head_sha,
            number=number, base_ref=base_ref, base_sha=base_sha,
            head_ref=head_ref, repo_pair=repo_pair)
    ]
    matching.sort(key=lambda item: (str(item.get("created_at", "")), item["id"]))

    rerun_ids: list[int] = []
    for candidate in matching:
        run_id = candidate["id"]
        current = _get_run(api, repository, run_id)
        # Repeat all checks that could have gone stale since the list response.
        if not _candidate_matches(
                current, workflow_id=workflow_id, source_id=source_id,
                head_sha=head_sha, number=number, base_ref=base_ref,
                base_sha=base_sha, head_ref=head_ref, repo_pair=repo_pair):
            continue
        latest = _live_pr(api, repository, number)
        live_now = _mapping(latest.get("head"), "live PR head")
        live_base_now = _mapping(latest.get("base"), "live PR base")
        latest_head_repo = _mapping(live_now.get("repo"), "live PR head repository")
        latest_base_repo = _mapping(live_base_now.get("repo"), "live PR base repository")
        if (latest.get("state") != "open"
                or live_now.get("sha") != head_sha
                or live_now.get("ref") != head_ref
                or latest_head_repo.get("full_name") != head_repo_name
                or live_base_now.get("ref") != base_ref
                or live_base_now.get("sha") != base_sha
                or latest_base_repo.get("full_name") != repository):
            raise UnsafeRun("live PR changed before rerun; no further suites will be touched")
        labels_obj = latest.get("labels")
        if not isinstance(labels_obj, list):
            raise UnsafeRun("live PR labels changed to malformed data")
        labels = [_mapping(label, "live PR label").get("name") for label in labels_obj]
        if any(not isinstance(name, str) for name in labels):
            raise UnsafeRun("live PR label name changed to malformed data")
        body = latest.get("body")
        if body is None:
            body = ""
        if not isinstance(body, str):
            raise UnsafeRun("live PR body changed to malformed data")
        if not _permission_allows(api, repository, event_actor, _author):
            raise UnsafeRun("workflow event actor lost permission before rerun")
        if evaluate(body, labels, repository):
            raise UnsafeRun("live PR body changed and no longer passes issue-link")

        attempt = current.get("run_attempt")
        if isinstance(attempt, bool) or not isinstance(attempt, int) or attempt >= 50:
            raise UnsafeRun("candidate run cannot be safely rerun")
        api.post(f"repos/{repository}/actions/runs/{run_id}/rerun")
        completed = _wait_for_attempt(
            api, repository, run_id, attempt,
            timeout_seconds=timeout_per_run, clock=clock, sleeper=sleeper)
        if completed.get("conclusion") != "success":
            raise ApiFailure("rerun did not pass; remaining suites were left untouched")
        rerun_ids.append(run_id)

    return {"rerun_ids": rerun_ids, "pr_number": number, "head_sha": head_sha}


def main() -> int:
    try:
        with open(os.environ["GITHUB_EVENT_PATH"], encoding="utf-8") as event_file:
            event = json.load(event_file)
        api = GitHubApi(
            os.environ.get("GITHUB_TOKEN", ""),
            os.environ.get("GITHUB_API_URL", "https://api.github.com"),
        )
        result = rerun_stale_suites(
            event, api,
            repository=os.environ.get("GITHUB_REPOSITORY", ""),
        )
    except (OSError, json.JSONDecodeError, ApiFailure, UnsafeRun) as exc:
        print(f"issue-link rerun refused: {exc}", file=sys.stderr)
        return 1
    if result["rerun_ids"]:
        print(f"issue-link reruns passed for {len(result['rerun_ids'])} prior suite(s)")
    else:
        print("issue-link rerun: no matching stale failed suites")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
