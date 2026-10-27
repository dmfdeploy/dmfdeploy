#!/usr/bin/env python3
"""Evaluate the trusted issue-link gate against body and label data."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

from closing_refs import find_negated


ISSUE_REF = re.compile(
    r"(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?|refs?)[\s:]+"
    r"(?:(?:dmfdeploy/dmfdeploy)?#[0-9]+|"
    r"https://github\.com/dmfdeploy/dmfdeploy/issues/[0-9]+)",
    re.IGNORECASE,
)


def evaluate(body: Any, labels: Any, default_repo: Any) -> list[str]:
    """Return safe, non-sensitive gate errors for API-supplied PR data."""
    if not isinstance(body, str):
        return ["PR body is missing or malformed"]
    if (not isinstance(labels, list)
            or any(not isinstance(label, str) for label in labels)):
        return ["PR labels are missing or malformed"]
    if default_repo != "dmfdeploy/dmfdeploy":
        return ["default repository is not the canonical backlog"]

    errors: list[str] = []
    if find_negated(body):
        errors.append("PR body pairs a closing keyword with a negation")
    if "no-issue" not in labels and not ISSUE_REF.search(body):
        errors.append("PR body does not reference a canonical-backlog issue")
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--body-file", required=True)
    parser.add_argument("--labels-file", required=True)
    parser.add_argument("--default-repo", required=True)
    args = parser.parse_args(argv)
    try:
        body = Path(args.body_file).read_text(encoding="utf-8")
        labels = json.loads(Path(args.labels_file).read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        print("issue-link: cannot read validated PR body/labels", file=sys.stderr)
        return 2

    errors = evaluate(body, labels, args.default_repo)
    if errors:
        for error in errors:
            print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print("OK: issue-link policy passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
