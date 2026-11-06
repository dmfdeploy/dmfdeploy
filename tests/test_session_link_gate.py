import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "bin" / "lib"))
import issue_link_gate as gate

REPO = "dmfdeploy/dmfdeploy"
# Built from parts so this file never holds a real session URL.
LINK = "https://claude.ai/" + "code/session_" + "01Example"


class SessionLinkTest(unittest.TestCase):
    def errors(self, body, labels=()):
        return gate.evaluate(body, list(labels), REPO)

    def test_clean_body_passes(self):
        self.assertEqual(self.errors("Closes dmfdeploy/dmfdeploy#838"), [])

    def test_link_fails(self):
        errs = self.errors(f"Closes dmfdeploy/dmfdeploy#838\n\n{LINK}\n")
        self.assertEqual(errs, ["PR body links to an agent session"])

    def test_link_fails_with_no_issue_label(self):
        errs = self.errors(f"Trivial.\n{LINK}", labels=["no-issue"])
        self.assertEqual(errs, ["PR body links to an agent session"])

    def test_other_claude_links_pass(self):
        body = "Refs dmfdeploy/dmfdeploy#838 see https://claude.ai/docs"
        self.assertEqual(self.errors(body), [])


if __name__ == "__main__":
    unittest.main()
