import copy
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "bin" / "lib"))

import rerun_issue_link as rerun

REPO = "dmfdeploy/dmfdeploy"
REPO_ID = 1265239865
WORKFLOW_ID = 395989901
FIXTURE_DIR = Path(__file__).parent / "fixtures" / "issue_link_rerun"
SOURCE_FIXTURE = json.loads((FIXTURE_DIR / "source-run-40529641530-rest-identity.json").read_text())
CANDIDATE_FIXTURE = json.loads((FIXTURE_DIR / "candidate-run-40525522991-rest-identity.json").read_text())
SOURCE_ID = SOURCE_FIXTURE["id"]
PR_NUMBER = SOURCE_FIXTURE["pull_requests"][0]["number"]
HEAD_SHA = SOURCE_FIXTURE["head_sha"]
BASE_SHA = SOURCE_FIXTURE["pull_requests"][0]["base"]["sha"]
HEAD_REF = SOURCE_FIXTURE["pull_requests"][0]["head"]["ref"]


def full_pr(*, base_sha=BASE_SHA, head_sha=HEAD_SHA, body="Refs dmfdeploy/dmfdeploy#758"):
    """Full PR projection used by the canonical GET /pulls/{number} endpoint."""
    return {
        "number": PR_NUMBER, "state": "open", "body": body,
        "user": {"login": "pr-author"}, "labels": [],
        "head": {
            "sha": head_sha, "ref": HEAD_REF,
            "repo": {"id": REPO_ID, "full_name": REPO},
        },
        "base": {
            "sha": base_sha, "ref": "main",
            "repo": {"id": REPO_ID, "full_name": REPO},
        },
    }


def synthetic_event(source=None):
    """Synthetic workflow_run wrapper around REST identity projection; no webhook fixture exists."""
    return {"action": "completed", "workflow_run": copy.deepcopy(source or SOURCE_FIXTURE)}


def api_run(run_id, *, base_sha=BASE_SHA, attempt=1, status="completed", conclusion="failure"):
    """Construct a compact Actions run association, like the exact REST fixtures."""
    item = copy.deepcopy(CANDIDATE_FIXTURE)
    item.update({
        "id": run_id, "run_attempt": attempt, "status": status,
        "conclusion": conclusion, "created_at": f"2026-10-27T00:00:{run_id % 60:02d}Z",
    })
    item["pull_requests"][0]["base"]["sha"] = base_sha
    return item


class FakeApi:
    def __init__(self, runs=None, pr=None):
        self.pr = copy.deepcopy(pr or full_pr())
        self.runs = {item["id"]: copy.deepcopy(item) for item in (runs or [])}
        self.source = copy.deepcopy(SOURCE_FIXTURE)
        self.posts = []
        self.get_pr_count = 0
        self.pr_hook = None
        self.run_hook = None
        self.compare_results = {}
        self.compare_calls = []
        self.fail_ids = set()
        self.jump_ids = set()
        self.stuck_ids = set()
        self.poll_id_override = {}
        self.total_count_override = None

    def get(self, path):
        if path == f"repos/{REPO}/actions/workflows/issue-link.yml":
            return {"id": WORKFLOW_ID, "path": rerun.WORKFLOW_PATH, "state": "active"}
        if path == f"repos/{REPO}/pulls/{PR_NUMBER}":
            self.get_pr_count += 1
            if self.pr_hook:
                self.pr_hook(self, self.get_pr_count)
            return copy.deepcopy(self.pr)
        if path.startswith(f"repos/{REPO}/actions/workflows/{WORKFLOW_ID}/runs?"):
            total = len(self.runs) if self.total_count_override is None else self.total_count_override
            return {"total_count": total,
                    "workflow_runs": [copy.deepcopy(item) for item in self.runs.values()]}
        if path.startswith(f"repos/{REPO}/compare/"):
            self.compare_calls.append(path)
            return copy.deepcopy(self.compare_results[path])
        if path.startswith(f"repos/{REPO}/actions/runs/"):
            run_id = int(path.rsplit("/", 1)[1])
            if run_id == SOURCE_ID:
                return copy.deepcopy(self.source)
            if self.run_hook:
                self.run_hook(self, run_id)
            response_id = self.poll_id_override.get(run_id, run_id)
            item = copy.deepcopy(self.runs[run_id])
            if item.get("run_attempt", 1) > 1:
                item["id"] = response_id
            return item
        if path == f"repos/{REPO}/collaborators/maintainer/permission":
            return {"user": {"login": "maintainer"}, "permission": "write"}
        if path == f"repos/{REPO}/collaborators/outsider/permission":
            return {"user": {"login": "outsider"}, "permission": "read"}
        raise AssertionError(f"unexpected GET {path}")

    def post(self, path):
        self.posts.append(path)
        run_id = int(path.split("/")[-2])
        self.runs[run_id]["run_attempt"] += 2 if run_id in self.jump_ids else 1
        if run_id in self.stuck_ids:
            self.runs[run_id]["status"] = "in_progress"
            self.runs[run_id]["conclusion"] = None
        else:
            self.runs[run_id]["status"] = "completed"
            self.runs[run_id]["conclusion"] = "failure" if run_id in self.fail_ids else "success"
        return {}


def compare_response(old_sha, new_sha, *, status="ahead", ahead_by=1, behind_by=0,
                     base_sha=None, merge_sha=None):
    return {
        "status": status, "ahead_by": ahead_by, "behind_by": behind_by,
        "base_commit": {"sha": base_sha or old_sha},
        "merge_base_commit": {"sha": merge_sha or old_sha},
    }


class RerunTests(unittest.TestCase):
    def test_exact_rest_compact_source_and_candidate_associations_are_accepted(self):
        api = FakeApi([copy.deepcopy(CANDIDATE_FIXTURE)])
        result = rerun.rerun_stale_suites(synthetic_event(), api)
        self.assertEqual(result, {"rerun_ids": [CANDIDATE_FIXTURE["id"]],
                                  "pr_number": PR_NUMBER, "head_sha": HEAD_SHA})
        self.assertEqual(api.posts, [
            f"repos/{REPO}/actions/runs/{CANDIDATE_FIXTURE['id']}/rerun"])

    def test_source_event_association_must_match_authoritative_rest_run(self):
        api = FakeApi([api_run(10)])
        source = copy.deepcopy(SOURCE_FIXTURE)
        source["pull_requests"][0]["base"]["repo"]["id"] += 1
        with self.assertRaisesRegex(rerun.UnsafeRun, "association changed"):
            rerun.rerun_stale_suites(synthetic_event(source), api)
        self.assertEqual(api.posts, [])

    def test_optional_association_name_cannot_contradict_canonical_pr(self):
        api = FakeApi([api_run(10)])
        source = copy.deepcopy(SOURCE_FIXTURE)
        source["pull_requests"][0]["base"]["repo"]["full_name"] = "attacker/other"
        with self.assertRaisesRegex(rerun.UnsafeRun, "contradicts canonical"):
            rerun.rerun_stale_suites(synthetic_event(source), api)
        self.assertEqual(api.posts, [])

    def test_compact_identity_requires_positive_integer_ids_not_bool_or_string(self):
        for nested in ("base", "head"):
            for malformed in (True, 0, "1265239865", None):
                with self.subTest(nested=nested, malformed=malformed):
                    api = FakeApi([api_run(10)])
                    api.runs[10]["pull_requests"][0][nested]["repo"]["id"] = malformed
                    with self.assertRaises(rerun.UnsafeRun):
                        rerun.rerun_stale_suites(synthetic_event(), api)
                    self.assertEqual(api.posts, [])

    def test_api_run_repository_must_match_canonical_base_name_and_id(self):
        for repository in ({"full_name": REPO, "id": REPO_ID + 1},
                           {"full_name": "fork/dmfdeploy", "id": REPO_ID}):
            with self.subTest(repository=repository):
                api = FakeApi([api_run(10)])
                api.runs[10]["repository"] = repository
                with self.assertRaisesRegex(rerun.UnsafeRun, "repository does not match"):
                    rerun.rerun_stale_suites(synthetic_event(), api)
                self.assertEqual(api.posts, [])

    def test_fork_head_with_distinct_positive_repository_id_is_supported(self):
        api = FakeApi([api_run(10)])
        api.pr["head"]["repo"] = {"id": 90001, "full_name": "contributor/dmfdeploy"}
        api.source["pull_requests"][0]["head"]["repo"]["id"] = 90001
        api.runs[10]["pull_requests"][0]["head"]["repo"]["id"] = 90001
        api.runs[10]["pull_requests"][0]["head"]["repo"]["name"] = "dmfdeploy"
        api.runs[10]["pull_requests"][0]["head"]["repo"]["full_name"] = "contributor/dmfdeploy"
        result = rerun.rerun_stale_suites(synthetic_event(api.source), api)
        self.assertEqual(result["rerun_ids"], [10])

    def test_historical_candidate_base_ancestor_is_checked_before_rerun(self):
        live_base = "03491b5352970aac82d503fb11ba1f23b6753940"
        # Synthetic candidate/live pairing: the raw REST fixtures both have
        # BASE_SHA, while this case models BASE_SHA as an ancestor of this main tip.
        old_base = BASE_SHA
        source = copy.deepcopy(SOURCE_FIXTURE)
        source["pull_requests"][0]["base"]["sha"] = live_base
        api = FakeApi([api_run(10, base_sha=old_base)], pr=full_pr(base_sha=live_base))
        api.source["pull_requests"][0]["base"]["sha"] = live_base
        compare_path = f"repos/{REPO}/compare/{old_base}...{live_base}"
        api.compare_results[compare_path] = compare_response(old_base, live_base)
        result = rerun.rerun_stale_suites(synthetic_event(source), api)
        self.assertEqual(result["rerun_ids"], [10])
        self.assertEqual(api.compare_calls, [compare_path])
        self.assertEqual(len(api.posts), 1)

    def test_historical_compare_is_cached_for_matching_candidate_bases(self):
        live_base = "03491b5352970aac82d503fb11ba1f23b6753940"
        source = copy.deepcopy(SOURCE_FIXTURE)
        source["pull_requests"][0]["base"]["sha"] = live_base
        api = FakeApi([api_run(10), api_run(11)], pr=full_pr(base_sha=live_base))
        api.source["pull_requests"][0]["base"]["sha"] = live_base
        compare_path = f"repos/{REPO}/compare/{BASE_SHA}...{live_base}"
        api.compare_results[compare_path] = compare_response(BASE_SHA, live_base)
        result = rerun.rerun_stale_suites(synthetic_event(source), api)
        self.assertEqual(result["rerun_ids"], [10, 11])
        self.assertEqual(api.compare_calls, [compare_path])

    def test_invalid_later_historical_candidate_prevents_every_rerun(self):
        live_base = "d" * 40
        valid_old = BASE_SHA
        invalid_old = "e" * 40
        source = copy.deepcopy(SOURCE_FIXTURE)
        source["pull_requests"][0]["base"]["sha"] = live_base
        first = api_run(10, base_sha=valid_old)
        second = api_run(11, base_sha=invalid_old)
        api = FakeApi([first, second], pr=full_pr(base_sha=live_base))
        api.source["pull_requests"][0]["base"]["sha"] = live_base
        api.compare_results[f"repos/{REPO}/compare/{valid_old}...{live_base}"] = compare_response(valid_old, live_base)
        api.compare_results[f"repos/{REPO}/compare/{invalid_old}...{live_base}"] = compare_response(
            invalid_old, live_base, status="diverged", ahead_by=1, behind_by=1,
            merge_sha="f" * 40)
        with self.assertRaisesRegex(rerun.UnsafeRun, "not a proven ancestor"):
            rerun.rerun_stale_suites(synthetic_event(source), api)
        self.assertEqual(len(api.compare_calls), 2)
        self.assertEqual(api.posts, [])

    def test_historical_compare_shape_is_strict(self):
        live_base = "d" * 40
        old_base = BASE_SHA
        source = copy.deepcopy(SOURCE_FIXTURE)
        source["pull_requests"][0]["base"]["sha"] = live_base
        api = FakeApi([api_run(10, base_sha=old_base)], pr=full_pr(base_sha=live_base))
        api.source["pull_requests"][0]["base"]["sha"] = live_base
        compare_path = f"repos/{REPO}/compare/{old_base}...{live_base}"
        api.compare_results[compare_path] = compare_response(
            old_base, live_base, ahead_by=True)
        with self.assertRaisesRegex(rerun.UnsafeRun, "not a proven ancestor"):
            rerun.rerun_stale_suites(synthetic_event(source), api)
        self.assertEqual(api.posts, [])

    def test_base_movement_before_write_aborts(self):
        api = FakeApi([api_run(10)])
        api.pr_hook = lambda fake, count: fake.pr["base"].update(sha="d" * 40) if count >= 2 else None
        with self.assertRaisesRegex(rerun.UnsafeRun, "live PR changed before rerun"):
            rerun.rerun_stale_suites(synthetic_event(), api)
        self.assertEqual(api.posts, [])

    def test_candidate_identity_movement_before_write_aborts(self):
        api = FakeApi([api_run(10)])
        changed = [False]
        def change_candidate(fake, run_id):
            if run_id == 10 and not changed[0]:
                fake.runs[10]["pull_requests"][0]["head"]["repo"]["id"] += 1
                changed[0] = True
        api.run_hook = change_candidate
        with self.assertRaisesRegex(rerun.UnsafeRun, "association changed"):
            rerun.rerun_stale_suites(synthetic_event(), api)
        self.assertEqual(api.posts, [])

    def test_candidate_attempt_movement_before_write_aborts(self):
        api = FakeApi([api_run(10)])
        changed = [False]
        def rerun_candidate_elsewhere(fake, run_id):
            if run_id == 10 and not changed[0]:
                fake.runs[10]["run_attempt"] = 2
                changed[0] = True
        api.run_hook = rerun_candidate_elsewhere
        with self.assertRaisesRegex(rerun.UnsafeRun, "eligibility changed"):
            rerun.rerun_stale_suites(synthetic_event(), api)
        self.assertEqual(api.posts, [])

    def test_poll_binds_the_requested_run_id(self):
        api = FakeApi([api_run(10)])
        api.poll_id_override[10] = 11
        with self.assertRaisesRegex(rerun.UnsafeRun, "run ID changed"):
            rerun.rerun_stale_suites(synthetic_event(), api)
        self.assertEqual(len(api.posts), 1)

    def test_body_fix_without_push_retries_failures_sequentially(self):
        api = FakeApi([api_run(10), api_run(11, attempt=3),
                       api_run(12, status="in_progress", conclusion=None),
                       api_run(13, conclusion="success"), api_run(SOURCE_ID)])
        result = rerun.rerun_stale_suites(synthetic_event(), api)
        self.assertEqual(result["rerun_ids"], [10, 11])

    def test_current_body_failing_means_no_rerun(self):
        api = FakeApi([api_run(10)], pr=full_pr(body="No tracking issue"))
        with self.assertRaises(rerun.UnsafeRun):
            rerun.rerun_stale_suites(synthetic_event(), api)
        self.assertEqual(api.posts, [])

    def test_body_changing_back_before_rerun_means_no_rerun(self):
        api = FakeApi([api_run(10)])
        api.pr_hook = lambda fake, count: fake.pr.update(body="No tracking issue") if count >= 2 else None
        with self.assertRaises(rerun.UnsafeRun):
            rerun.rerun_stale_suites(synthetic_event(), api)
        self.assertEqual(api.posts, [])

    def test_unauthorized_actor_means_no_rerun(self):
        api = FakeApi([api_run(10)])
        api.source["actor"]["login"] = "outsider"
        with self.assertRaisesRegex(rerun.UnsafeRun, "not authorized"):
            rerun.rerun_stale_suites(synthetic_event(api.source), api)
        self.assertEqual(api.posts, [])

    def test_authorized_maintainer_repairs_a_suite_that_the_author_failed(self):
        # The author opened the failing run; a maintainer's edit produced the
        # passing source run. Identity binds to PR, workflow, head SHA and
        # repository, so the differing run actors must not block the rerun.
        failed = api_run(10)
        self.assertEqual(failed["actor"]["login"], "pr-author")
        api = FakeApi([failed])
        api.source["actor"]["login"] = "maintainer"
        event = synthetic_event(api.source)
        result = rerun.rerun_stale_suites(event, api)
        self.assertEqual(result["rerun_ids"], [10])
        self.assertEqual(api.posts, [f"repos/{REPO}/actions/runs/10/rerun"])

    def test_unauthorized_source_actor_is_rejected_even_with_matching_candidate(self):
        api = FakeApi([api_run(10)])
        api.source["actor"]["login"] = "outsider"
        with self.assertRaisesRegex(rerun.UnsafeRun, "not authorized"):
            rerun.rerun_stale_suites(synthetic_event(api.source), api)
        self.assertEqual(api.posts, [])

    def test_maintainer_source_still_rejects_candidate_for_another_head_sha(self):
        other = api_run(10)
        other["head_sha"] = "c" * 40
        api = FakeApi([other])
        api.source["actor"]["login"] = "maintainer"
        result = rerun.rerun_stale_suites(synthetic_event(api.source), api)
        self.assertEqual(result["rerun_ids"], [])
        self.assertEqual(api.posts, [])

    def test_maintainer_source_still_rejects_candidate_for_another_workflow(self):
        other = api_run(10)
        other["workflow_id"] += 1
        api = FakeApi([other])
        api.source["actor"]["login"] = "maintainer"
        result = rerun.rerun_stale_suites(synthetic_event(api.source), api)
        self.assertEqual(result["rerun_ids"], [])
        self.assertEqual(api.posts, [])

    def test_maintainer_source_still_rejects_candidate_for_another_pr(self):
        bad = api_run(10)
        bad["pull_requests"][0]["number"] += 1
        api = FakeApi([bad])
        api.source["actor"]["login"] = "maintainer"
        with self.assertRaisesRegex(rerun.UnsafeRun, "association changed"):
            rerun.rerun_stale_suites(synthetic_event(api.source), api)
        self.assertEqual(api.posts, [])

    def test_maintainer_source_still_rejects_candidate_from_another_repository(self):
        bad = api_run(10)
        bad["repository"] = {"full_name": "fork/dmfdeploy", "id": REPO_ID}
        api = FakeApi([bad])
        api.source["actor"]["login"] = "maintainer"
        with self.assertRaisesRegex(rerun.UnsafeRun, "repository does not match"):
            rerun.rerun_stale_suites(synthetic_event(api.source), api)
        self.assertEqual(api.posts, [])

    def test_live_head_change_stops_without_mutation(self):
        api = FakeApi([api_run(10)])
        api.pr["head"]["sha"] = "c" * 40
        with self.assertRaisesRegex(rerun.UnsafeRun, "association changed"):
            rerun.rerun_stale_suites(synthetic_event(), api)
        self.assertEqual(api.posts, [])

    def test_candidate_for_another_pr_fails_closed(self):
        bad = api_run(10)
        bad["pull_requests"][0]["number"] += 1
        api = FakeApi([bad])
        with self.assertRaisesRegex(rerun.UnsafeRun, "association changed"):
            rerun.rerun_stale_suites(synthetic_event(), api)
        self.assertEqual(api.posts, [])

    def test_candidate_overflow_fails_before_ancestry_or_rerun(self):
        runs = [api_run(i, base_sha="d" * 40) for i in range(10, 15)]
        api = FakeApi(runs)
        with self.assertRaisesRegex(rerun.UnsafeRun, "too many stale"):
            rerun.rerun_stale_suites(synthetic_event(), api)
        self.assertEqual(api.compare_calls, [])
        self.assertEqual(api.posts, [])

    def test_workflow_history_limit_fails_before_any_rerun(self):
        api = FakeApi([api_run(10)])
        api.total_count_override = 1000
        with self.assertRaisesRegex(rerun.UnsafeRun, "history reached"):
            rerun.rerun_stale_suites(synthetic_event(), api)
        self.assertEqual(api.posts, [])

    def test_unexpected_attempt_jump_stops_after_one_post(self):
        api = FakeApi([api_run(10), api_run(11)])
        api.jump_ids.add(10)
        with self.assertRaisesRegex(rerun.UnsafeRun, "another rerun"):
            rerun.rerun_stale_suites(synthetic_event(), api)
        self.assertEqual(len(api.posts), 1)

    def test_poll_timeout_stops_before_remaining_candidates(self):
        api = FakeApi([api_run(10), api_run(11)])
        api.stuck_ids.add(10)
        now = [0.0]
        def clock():
            return now[0]
        def sleeper(seconds):
            now[0] += seconds
        with self.assertRaisesRegex(rerun.ApiFailure, "did not complete"):
            rerun.rerun_stale_suites(
                synthetic_event(), api, timeout_per_run=3, clock=clock, sleeper=sleeper)
        self.assertEqual(len(api.posts), 1)

    def test_required_check_and_coordinator_permissions_are_narrow(self):
        root = Path(__file__).resolve().parents[1]
        checker = (root / ".github/workflows/issue-link.yml").read_text()
        coordinator = (root / ".github/workflows/issue-link-rerun.yml").read_text()
        self.assertIn("name: issue-link", checker)
        self.assertIn("permissions: {}", checker)
        self.assertIn("group: issue-link-${{ github.run_id }}-${{ github.run_attempt }}", checker)
        self.assertIn("workflows: [issue-link]", coordinator)
        self.assertIn("permissions: {}", coordinator)
        self.assertIn("actions: write", coordinator)
        self.assertIn("github.event.workflow_run.run_attempt == 1", coordinator)
        self.assertIn("ref: main", coordinator)
        self.assertNotIn("pull_request_target:", coordinator)
        self.assertNotIn("github.event.workflow_run.head_branch", coordinator)


if __name__ == "__main__":
    unittest.main()
