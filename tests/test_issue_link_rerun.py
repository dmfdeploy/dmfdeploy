import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "bin" / "lib"))
import rerun_issue_link as rerun


SHA = "a" * 40
BASE_SHA = "b" * 40
OTHER_SHA = "c" * 40
REPO = "dmfdeploy/dmfdeploy"


def pull_request(head_sha=SHA, body="Refs #758"):
    return {
        "number": 758,
        "state": "open",
        "body": body,
        "user": {"login": "author"},
        "labels": [],
        "head": {
            "sha": head_sha, "ref": "fix/body",
            "repo": {"full_name": "fork/repo"},
        },
        "base": {
            "sha": BASE_SHA, "ref": "main",
            "repo": {"full_name": REPO},
        },
    }


def run(run_id, *, head_sha=SHA, attempt=1, status="completed", conclusion="failure"):
    return {
        "id": run_id, "workflow_id": 395989901, "event": "pull_request_target",
        "head_sha": head_sha, "run_attempt": attempt, "status": status,
        "conclusion": conclusion, "created_at": f"2026-10-27T00:00:{run_id % 60:02d}Z",
        "pull_requests": [pull_request(head_sha)],
    }


def source_run():
    return {
        "id": 900, "workflow_id": 395989901, "name": "issue-link",
        "path": ".github/workflows/issue-link.yml",
        "event": "pull_request_target", "status": "completed",
        "conclusion": "success", "run_attempt": 1, "head_sha": SHA,
        "actor": {"login": "author"},
        "pull_requests": [pull_request()],
    }


def event(source=None):
    return {"action": "completed", "workflow_run": source or source_run()}


class FakeApi:
    def __init__(self, runs=None, pr=None):
        self.pr = copy.deepcopy(pr or pull_request())
        self.runs = {item["id"]: copy.deepcopy(item) for item in (runs or [])}
        self.posts = []
        self.get_pr_count = 0
        self.pr_hook = None
        self.workflow_path = ".github/workflows/issue-link.yml"
        self.fail_ids = set()

    def get(self, path):
        if path == f"repos/{REPO}/actions/workflows/issue-link.yml":
            return {"id": 395989901, "path": self.workflow_path, "state": "active"}
        if path == f"repos/{REPO}/pulls/758":
            self.get_pr_count += 1
            if self.pr_hook:
                self.pr_hook(self, self.get_pr_count)
            return copy.deepcopy(self.pr)
        if path.startswith(f"repos/{REPO}/actions/workflows/395989901/runs?"):
            return {"workflow_runs": [copy.deepcopy(item) for item in self.runs.values()]}
        if path.startswith(f"repos/{REPO}/actions/runs/"):
            run_id = int(path.rsplit("/", 1)[1])
            return copy.deepcopy(self.runs[run_id])
        if path == f"repos/{REPO}/collaborators/editor/permission":
            return {"user": {"login": "editor"}, "permission": "write"}
        if path == f"repos/{REPO}/collaborators/outsider/permission":
            return {"user": {"login": "outsider"}, "permission": "read"}
        raise AssertionError(f"unexpected GET {path}")

    def post(self, path):
        self.posts.append(path)
        run_id = int(path.split("/")[-2])
        self.runs[run_id]["run_attempt"] += 1
        self.runs[run_id]["status"] = "completed"
        self.runs[run_id]["conclusion"] = "failure" if run_id in self.fail_ids else "success"
        return {}


class RerunTests(unittest.TestCase):
    def test_body_fix_without_push_retries_all_matching_failures_including_old_retry(self):
        api = FakeApi([
            run(10), run(11, attempt=3), run(12, status="in_progress", conclusion=None),
            run(13, head_sha=OTHER_SHA), run(14, conclusion="success"), run(900),
        ])
        result = rerun.rerun_stale_suites(event(), api)
        self.assertEqual(result["rerun_ids"], [10, 11])
        self.assertEqual([path.rsplit("/", 2)[1] for path in api.posts], ["10", "11"])

    def test_current_body_failing_means_no_rerun(self):
        api = FakeApi([run(10)], pr=pull_request(body="No tracking issue"))
        with self.assertRaises(rerun.UnsafeRun):
            rerun.rerun_stale_suites(event(), api)
        self.assertEqual(api.posts, [])

    def test_body_changing_back_before_rerun_means_no_rerun(self):
        api = FakeApi([run(10)])
        api.pr_hook = lambda fake, count: fake.pr.update(body="No tracking issue") if count >= 2 else None
        with self.assertRaises(rerun.UnsafeRun):
            rerun.rerun_stale_suites(event(), api)
        self.assertEqual(api.posts, [])

    def test_unauthorized_actor_means_no_rerun(self):
        src = source_run()
        src["actor"] = {"login": "outsider"}
        api = FakeApi([run(10)])
        with self.assertRaises(rerun.UnsafeRun):
            rerun.rerun_stale_suites(event(src), api)
        self.assertEqual(api.posts, [])

    def test_rerun_generated_event_is_not_recursive(self):
        src = source_run()
        src["run_attempt"] = 2
        api = FakeApi([run(10)])
        with self.assertRaises(rerun.UnsafeRun):
            rerun.rerun_stale_suites(event(src), api)
        self.assertEqual(api.posts, [])

    def test_live_head_change_stops_without_mutation(self):
        api = FakeApi([run(10)])
        api.pr["head"]["sha"] = OTHER_SHA
        with self.assertRaises(rerun.UnsafeRun):
            rerun.rerun_stale_suites(event(), api)
        self.assertEqual(api.posts, [])

    def test_base_retarget_during_selection_stops_without_mutation(self):
        api = FakeApi([run(10)])
        api.pr_hook = lambda fake, count: fake.pr["base"].update(sha=OTHER_SHA) if count >= 2 else None
        with self.assertRaises(rerun.UnsafeRun):
            rerun.rerun_stale_suites(event(), api)
        self.assertEqual(api.posts, [])

    def test_candidate_for_another_pr_fails_closed(self):
        bad = run(10)
        bad["pull_requests"][0]["number"] = 759
        api = FakeApi([bad])
        with self.assertRaises(rerun.UnsafeRun):
            rerun.rerun_stale_suites(event(), api)
        self.assertEqual(api.posts, [])

    def test_wrong_workflow_path_fails_closed(self):
        api = FakeApi([run(10)])
        api.workflow_path = ".github/workflows/other.yml"
        with self.assertRaises(rerun.UnsafeRun):
            rerun.rerun_stale_suites(event(), api)
        self.assertEqual(api.posts, [])

    def test_failed_rerun_stops_before_touching_remaining_failures(self):
        api = FakeApi([run(10), run(11)])
        api.fail_ids.add(10)
        with self.assertRaises(rerun.ApiFailure):
            rerun.rerun_stale_suites(event(), api)
        self.assertEqual(len(api.posts), 1)
        self.assertIn("/10/rerun", api.posts[0])

    def test_malformed_run_association_fails_closed(self):
        bad = run(10)
        bad["pull_requests"] = []
        api = FakeApi([bad])
        with self.assertRaises(rerun.UnsafeRun):
            rerun.rerun_stale_suites(event(), api)
        self.assertEqual(api.posts, [])

    def test_gate_matches_negated_closing_keyword_behavior(self):
        self.assertTrue(rerun.evaluate("This does not close #758", [], REPO))

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
