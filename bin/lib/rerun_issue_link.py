#!/usr/bin/env python3
"""Safely rerun failed issue-link suites for the same live pull request head."""

from __future__ import annotations

import json
import os
import re
import sys
import time
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen

from issue_link_gate import evaluate

WORKFLOW_PATH = ".github/workflows/issue-link.yml"
WORKFLOW_FILE = "issue-link.yml"
DEFAULT_REPOSITORY = "dmfdeploy/dmfdeploy"
DEFAULT_BRANCH = "main"
PAGE_SIZE = 100
MAX_RUN_PAGES = 10
MAX_TOTAL_RUNS = 1000
MAX_CANDIDATES = 4
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


def _repository_id(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        raise UnsafeRun(f"{label} repository ID is missing or malformed")
    return value


def _single_pull_request(run: dict[str, Any], label: str) -> dict[str, Any]:
    pull_requests = run.get("pull_requests")
    if not isinstance(pull_requests, list) or len(pull_requests) != 1:
        raise UnsafeRun(f"{label} does not identify exactly one pull request")
    return _mapping(pull_requests[0], f"{label} pull request")


def _compact_pr_association(pr: dict[str, Any], label: str) -> dict[str, Any]:
    """Parse the compact pull_requests projection in Actions run responses.

    This projection carries repository IDs but may omit full_name. Names are
    only checked when present; canonical names and IDs come from the full PR
    returned by the fixed repository endpoint.
    """
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
    identity = {
        "number": number,
        "base_id": _repository_id(base_repo.get("id"), f"{label} base"),
        "base_ref": base_ref,
        "base_sha": base_sha,
        "head_id": _repository_id(head_repo.get("id"), f"{label} head"),
        "head_ref": head_ref,
        "head_sha": head_sha,
    }
    for key, nested in (("base_name", base_repo), ("head_name", head_repo)):
        name = nested.get("full_name")
        if name is not None:
            if not isinstance(name, str) or not name:
                raise UnsafeRun(f"{label} {key.replace('_', ' ')} is malformed")
            identity[key] = name
    return identity


def _full_pr_identity(pr: dict[str, Any], label: str) -> dict[str, Any]:
    """Read identity from a canonical full pull-request API response."""
    number = _pr_number(pr.get("number"), f"{label} number")
    base = _mapping(pr.get("base"), f"{label} base")
    head = _mapping(pr.get("head"), f"{label} head")
    base_repo = _mapping(base.get("repo"), f"{label} base repository")
    head_repo = _mapping(head.get("repo"), f"{label} head repository")
    base_name = base_repo.get("full_name")
    head_name = head_repo.get("full_name")
    if not isinstance(base_name, str) or not base_name:
        raise UnsafeRun(f"{label} canonical base repository name is missing")
    if not isinstance(head_name, str) or not head_name:
        raise UnsafeRun(f"{label} head repository name is missing")
    base_ref = base.get("ref")
    head_ref = head.get("ref")
    if not isinstance(base_ref, str) or not base_ref:
        raise UnsafeRun(f"{label} base ref is missing")
    if not isinstance(head_ref, str) or not head_ref:
        raise UnsafeRun(f"{label} head ref is missing")
    return {
        "number": number,
        "base_id": _repository_id(base_repo.get("id"), f"{label} base"),
        "base_name": base_name,
        "base_ref": base_ref,
        "base_sha": _sha(base.get("sha"), f"{label} base SHA"),
        "head_id": _repository_id(head_repo.get("id"), f"{label} head"),
        "head_name": head_name,
        "head_ref": head_ref,
        "head_sha": _sha(head.get("sha"), f"{label} head SHA"),
    }


def _association_matches_full(association: dict[str, Any], full: dict[str, Any], label: str) -> None:
    for key in ("number", "base_id", "base_ref", "base_sha", "head_id", "head_ref", "head_sha"):
        if association.get(key) != full.get(key):
            raise UnsafeRun(f"{label} pull request association changed")
    for key in ("base_name", "head_name"):
        if key in association and association[key] != full[key]:
            raise UnsafeRun(f"{label} pull request association contradicts canonical repository")


def _run_repository(run: dict[str, Any], canonical_base: dict[str, Any], label: str) -> None:
    repository = _mapping(run.get("repository"), f"{label} repository")
    full_name = repository.get("full_name")
    repository_id = _repository_id(repository.get("id"), label)
    if (full_name != canonical_base["base_name"]
            or repository_id != canonical_base["base_id"]):
        raise UnsafeRun(f"{label} repository does not match canonical PR base")


def _same_compact_association(left: dict[str, Any], right: dict[str, Any], label: str) -> None:
    for key in ("number", "base_id", "base_ref", "base_sha", "head_id", "head_ref", "head_sha"):
        if left.get(key) != right.get(key):
            raise UnsafeRun(f"{label} pull request association changed")
    for key in ("base_name", "head_name"):
        if key in left and key in right and left[key] != right[key]:
            raise UnsafeRun(f"{label} pull request association name changed")


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


def _authoritative_source_run(
    api: Any, repo: str, event_source: dict[str, Any],
) -> tuple[dict[str, Any], int, str, dict[str, Any]]:
    """Expand the workflow_run event with the authoritative Actions-run record.

    Actions run associations are compact projections: repository IDs are
    authoritative there, while canonical names come from the full PR endpoint.
    """
    _event, event_id, event_sha = _validate_source(event_source, "completed")
    source = _mapping(api.get(f"repos/{repo}/actions/runs/{event_id}"),
                      "authoritative source workflow run")
    source_id = source.get("id")
    if isinstance(source_id, bool) or source_id != event_id:
        raise UnsafeRun("authoritative source run ID does not match event")
    for key in ("workflow_id", "event", "status", "conclusion", "run_attempt", "name"):
        if source.get(key) != event_source.get(key):
            raise UnsafeRun(f"authoritative source run {key} does not match event")
    if "path" in event_source and source.get("path") != event_source.get("path"):
        raise UnsafeRun("authoritative source workflow path does not match event")
    if source.get("path") != WORKFLOW_PATH:
        raise UnsafeRun("authoritative source workflow path does not match")
    if _sha(source.get("head_sha"), "authoritative source head SHA") != event_sha:
        raise UnsafeRun("authoritative source head SHA does not match event")
    event_actor = _mapping(event_source.get("actor"), "workflow event actor").get("login")
    source_actor = _mapping(source.get("actor"), "authoritative source actor").get("login")
    if not isinstance(event_actor, str) or not event_actor or source_actor != event_actor:
        raise UnsafeRun("authoritative source actor does not match event")
    event_pr = _compact_pr_association(
        _single_pull_request(event_source, "source run"), "source event PR")
    source_pr = _compact_pr_association(
        _single_pull_request(source, "authoritative source run"), "authoritative source PR")
    _same_compact_association(event_pr, source_pr, "authoritative source")
    return source, event_id, event_sha, event_pr


def _live_pr(api: Any, repo: str, number: int) -> dict[str, Any]:
    pr = _mapping(api.get(f"repos/{repo}/pulls/{number}"), "live pull request")
    if _pr_number(pr.get("number"), "live pull request number") != number:
        raise UnsafeRun("live pull request number does not match")
    if pr.get("state") != "open":
        raise UnsafeRun("pull request is not open")
    return pr


def _validate_live_source(
    api: Any, repo: str, source: dict[str, Any], source_sha: str,
    event_actor: Any, event_association: dict[str, Any],
) -> tuple[dict[str, Any], dict[str, Any], str]:
    associated_pr = _compact_pr_association(
        _single_pull_request(source, "source run"), "source PR")
    number = associated_pr["number"]
    live = _live_pr(api, repo, number)
    identity = _full_pr_identity(live, "live PR")
    _run_repository(source, identity, "source run")
    _association_matches_full(associated_pr, identity, "source run")
    _association_matches_full(event_association, identity, "source event")
    live_user = _mapping(live.get("user"), "live PR author").get("login")
    if identity["base_ref"] != DEFAULT_BRANCH:
        raise UnsafeRun("pull request base or head ref is unsupported")
    if identity["base_name"] != repo:
        raise UnsafeRun("pull request base repository is not canonical")
    if not isinstance(live_user, str) or not live_user:
        raise UnsafeRun("pull request author is missing")
    if not isinstance(event_actor, str) or not event_actor:
        raise UnsafeRun("workflow event actor is missing")

    if source_sha != identity["head_sha"]:
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
    return live, identity, live_user


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
        total_count = result.get("total_count")
        if (isinstance(total_count, bool) or not isinstance(total_count, int)
                or total_count < 0 or total_count >= MAX_TOTAL_RUNS):
            raise UnsafeRun("workflow run history reached the safe result limit")
        batch = result.get("workflow_runs")
        if not isinstance(batch, list) or any(not isinstance(item, dict) for item in batch):
            raise UnsafeRun("workflow run list is malformed")
        runs.extend(batch)
        if len(batch) < PAGE_SIZE:
            return runs
    raise UnsafeRun("workflow run list exceeded the safe page limit")


def _candidate_matches(
    run: dict[str, Any], *, workflow_id: int, source_id: int,
    identity: dict[str, Any], actor: str,
) -> tuple[bool, dict[str, Any]]:
    run_id = run.get("id")
    if isinstance(run_id, bool) or not isinstance(run_id, int) or run_id < 1:
        raise UnsafeRun("candidate run ID is malformed")
    if run_id == source_id:
        return False, {}
    if run.get("workflow_id") != workflow_id:
        return False, {}
    if (run.get("event") != "pull_request_target"
            or run.get("path") != WORKFLOW_PATH
            or run.get("name") != "issue-link"):
        return False, {}
    run_actor = _mapping(run.get("actor"), "candidate actor").get("login")
    if not isinstance(run_actor, str) or run_actor != actor:
        raise UnsafeRun("candidate actor does not match source run")
    if _sha(run.get("head_sha"), "candidate head SHA") != identity["head_sha"]:
        return False, {}
    association = _compact_pr_association(
        _single_pull_request(run, "candidate run"), "candidate PR")
    _run_repository(run, identity, "candidate run")
    for key in ("number", "base_id", "base_ref", "head_id", "head_ref", "head_sha"):
        if association[key] != identity[key]:
            raise UnsafeRun("candidate pull request association changed")
    for name_key in ("base_name", "head_name"):
        if name_key in association and association[name_key] != identity[name_key]:
            raise UnsafeRun("candidate association contradicts canonical repository")
    # A historical base SHA is admitted only after global ancestry preflight.
    if run.get("status") == "completed" and run.get("conclusion") in RERUNNABLE_CONCLUSIONS:
        attempt = run.get("run_attempt")
        if isinstance(attempt, bool) or not isinstance(attempt, int) or not 1 <= attempt <= 50:
            raise UnsafeRun("candidate run attempt is malformed or exhausted")
        return attempt < 50, association
    if run.get("status") not in {"completed", "queued", "in_progress", "waiting", "requested"}:
        raise UnsafeRun("candidate run status is unknown")
    return False, association


def _get_run(api: Any, repo: str, run_id: int) -> dict[str, Any]:
    return _mapping(api.get(f"repos/{repo}/actions/runs/{run_id}"), "candidate run detail")


def _validate_candidate_identity(
    run: dict[str, Any], *, run_id: int, workflow_id: int,
    canonical_identity: dict[str, Any], association_identity: dict[str, Any], actor: str,
) -> None:
    if run.get("id") != run_id or isinstance(run.get("id"), bool):
        raise UnsafeRun("candidate run ID changed")
    if (run.get("workflow_id") != workflow_id
            or run.get("path") != WORKFLOW_PATH
            or run.get("name") != "issue-link"
            or run.get("event") != "pull_request_target"):
        raise UnsafeRun("candidate workflow identity changed")
    run_actor = _mapping(run.get("actor"), "candidate actor").get("login")
    if run_actor != actor:
        raise UnsafeRun("candidate actor changed")
    if _sha(run.get("head_sha"), "candidate head SHA") != canonical_identity["head_sha"]:
        raise UnsafeRun("candidate head SHA changed")
    _run_repository(run, canonical_identity, "candidate run")
    association = _compact_pr_association(
        _single_pull_request(run, "candidate run"), "candidate PR")
    if association != association_identity:
        raise UnsafeRun("candidate pull request association changed")


def _validate_base_ancestry(api: Any, repo: str, candidate_base_sha: str, live_base_sha: str) -> None:
    if candidate_base_sha == live_base_sha:
        return
    result = _mapping(api.get(
        f"repos/{repo}/compare/{candidate_base_sha}...{live_base_sha}"),
        "candidate base ancestry")
    ahead_by = result.get("ahead_by")
    behind_by = result.get("behind_by")
    base_commit = _mapping(result.get("base_commit"), "compare base commit")
    merge_base = _mapping(result.get("merge_base_commit"), "compare merge base")
    if (result.get("status") != "ahead"
            or isinstance(ahead_by, bool) or not isinstance(ahead_by, int) or ahead_by < 1
            or isinstance(behind_by, bool) or not isinstance(behind_by, int) or behind_by != 0
            or base_commit.get("sha") != candidate_base_sha
            or merge_base.get("sha") != candidate_base_sha):
        raise UnsafeRun("candidate base is not a proven ancestor of the live base")


def _wait_for_attempt(
    api: Any, repo: str, run_id: int, old_attempt: int,
    *, expected_workflow_id: int, canonical_identity: dict[str, Any],
    association_identity: dict[str, Any], actor: str,
    timeout_seconds: float, clock=time.monotonic, sleeper=time.sleep,
) -> dict[str, Any]:
    deadline = clock() + timeout_seconds
    while clock() < deadline:
        run = _get_run(api, repo, run_id)
        _validate_candidate_identity(
            run, run_id=run_id, workflow_id=expected_workflow_id,
            canonical_identity=canonical_identity,
            association_identity=association_identity, actor=actor)
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
    event_source = _mapping(event.get("workflow_run"), "source workflow run")
    if event.get("action") != "completed":
        raise UnsafeRun("workflow_run event is not completed")
    source, source_id, source_sha, event_association = _authoritative_source_run(
        api, repository, event_source)
    workflow_id = _validate_workflow(api, repository, source)
    (_live, identity, author) = _validate_live_source(
        api, repository, source, source_sha,
        _mapping(source.get("actor"), "source run actor").get("login"),
        event_association)
    event_actor = _mapping(source.get("actor"), "source run actor").get("login")
    candidates = _list_runs(api, repository, workflow_id, identity["head_sha"])
    matching: list[tuple[dict[str, Any], dict[str, Any]]] = []
    for run in candidates:
        is_candidate, association = _candidate_matches(
            run, workflow_id=workflow_id, source_id=source_id,
            identity=identity, actor=event_actor)
        if is_candidate:
            matching.append((run, association))
    matching.sort(key=lambda item: (
        str(item[0].get("created_at", "")), item[0]["id"]))
    if len(matching) > MAX_CANDIDATES:
        raise UnsafeRun("too many stale issue-link suites for one coordinator run")

    # Validate every historical base before the first write. A later malformed
    # or divergent candidate must never leave a partially rerun set behind.
    ancestry_cache: set[str] = set()
    for _candidate, association in matching:
        candidate_base = association["base_sha"]
        if candidate_base != identity["base_sha"] and candidate_base not in ancestry_cache:
            _validate_base_ancestry(
                api, repository, candidate_base, identity["base_sha"])
            ancestry_cache.add(candidate_base)

    rerun_ids: list[int] = []
    for candidate, association in matching:
        run_id = candidate["id"]
        current = _get_run(api, repository, run_id)
        # Repeat all checks that could have gone stale since the list response.
        _validate_candidate_identity(
            current, run_id=run_id, workflow_id=workflow_id,
            canonical_identity=identity, association_identity=association,
            actor=event_actor)
        if any(current.get(key) != candidate.get(key)
               for key in ("run_attempt", "status", "conclusion")):
            raise UnsafeRun("candidate eligibility changed before rerun")
        is_candidate, current_association = _candidate_matches(
            current, workflow_id=workflow_id, source_id=source_id,
            identity=identity, actor=event_actor)
        if not is_candidate or current_association != association:
            continue
        latest = _live_pr(api, repository, identity["number"])
        if latest.get("state") != "open" or _full_pr_identity(latest, "live PR") != identity:
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
        if not _permission_allows(api, repository, event_actor, author):
            raise UnsafeRun("workflow event actor lost permission before rerun")
        if evaluate(body, labels, repository):
            raise UnsafeRun("live PR body changed and no longer passes issue-link")

        attempt = current.get("run_attempt")
        if isinstance(attempt, bool) or not isinstance(attempt, int) or attempt >= 50:
            raise UnsafeRun("candidate run cannot be safely rerun")
        api.post(f"repos/{repository}/actions/runs/{run_id}/rerun")
        completed = _wait_for_attempt(
            api, repository, run_id, attempt,
            expected_workflow_id=workflow_id, canonical_identity=identity,
            association_identity=association, actor=event_actor,
            timeout_seconds=timeout_per_run, clock=clock, sleeper=sleeper)
        if completed.get("conclusion") != "success":
            raise ApiFailure("rerun did not pass; remaining suites were left untouched")
        rerun_ids.append(run_id)

    return {"rerun_ids": rerun_ids, "pr_number": identity["number"],
            "head_sha": identity["head_sha"]}


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
