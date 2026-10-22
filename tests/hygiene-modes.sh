#!/usr/bin/env bash
# hygiene-modes.sh - pin every hygiene check to its mode (issue #617).
#
# Each hygiene check has a flag that decides whether a finding fails the run or
# only warns. Without this test, a flag could flip back to warn mode and every
# check would still pass. This test reads the workflow files and the
# pre-commit hook and asserts that each check runs in its intended mode:
#
#   surface.yml          the fixture step runs first, then size, filenames,
#                        placement and statuslog each run with --strict in
#                        their own step.
#   pre-commit hook      check-surface runs with --strict on the staged
#                        content, and a failure refuses the commit.
#   vale.yml             the clean-set step fails on errors (no --no-exit),
#                        the changed-files ratchet runs, and the whole-tree
#                        step still warns (--no-exit). That last one is
#                        pinned too, so flipping it is a deliberate edit here.
#   title-check.yml      the title job sets STRICT to "1".
#   backlog-hygiene.yml  the self-test runs first, the check has no --warn,
#                        and a later step fails the job on findings.
#
# In all five workflows, no step or job sets continue-on-error, and no run
# line ends in "|| true". The surface fixture suite and the Voice fixture
# checks must stay wired into their workflows.
#
# The workflows are parsed as YAML: with PyYAML when python3 has it, else with
# Ruby's built-in YAML library. If neither is there, the test fails rather
# than skipping. Set HYGIENE_ROOT to check another copy of the tree.
#
# Each assertion prints "ok" or "FAIL: <reason>". The script exits 1 on any
# FAIL.

set -euo pipefail

ROOT="${HYGIENE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

exec python3 -I - "$ROOT" <<'PY'
import json
import os
import re
import shlex
import subprocess
import sys

root = sys.argv[1]
fails = 0


def ok(msg):
    print(f"ok    {msg}")


def fail(msg):
    global fails
    fails += 1
    print(f"FAIL: {msg}")


def check(cond, msg, reason):
    if cond:
        ok(msg)
    else:
        fail(f"{msg}: {reason}")


def load_yaml(rel):
    path = os.path.join(root, rel)
    try:
        import yaml  # noqa: PLC0415

        with open(path, encoding="utf-8") as fh:
            return yaml.safe_load(fh)
    except ImportError:
        pass
    ruby = (
        "require 'yaml'; require 'json'; "
        "puts JSON.generate(YAML.safe_load(File.read(ARGV[0])))"
    )
    try:
        out = subprocess.run(
            ["ruby", "-e", ruby, path],
            check=True, capture_output=True, text=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError) as exc:
        sys.exit(f"FAIL: cannot parse {rel}: no PyYAML and no working ruby ({exc})")
    return json.loads(out)


def steps_of(doc, job):
    return (doc.get("jobs") or {}).get(job, {}).get("steps") or []


def run_of(step):
    return step.get("run") or ""


def tokens(run):
    try:
        return shlex.split(run, comments=True)
    except ValueError:
        return run.split()


def common_rules(rel, doc):
    """No continue-on-error anywhere; no run line ends in '|| true'."""
    coe = []
    tail = []
    for jname, job in (doc.get("jobs") or {}).items():
        if "continue-on-error" in job:
            coe.append(f"job {jname}")
        for i, step in enumerate(job.get("steps") or []):
            label = f"{jname}/{step.get('name') or i}"
            if "continue-on-error" in step:
                coe.append(label)
            for line in run_of(step).splitlines():
                if re.search(r"\|\|\s*(true|:)\s*(#.*)?$", line.strip()):
                    tail.append(f"{label}: {line.strip()}")
    check(not coe, f"{rel}: no continue-on-error",
          "set on " + ", ".join(coe))
    check(not tail, f"{rel}: no run line ends in '|| true'",
          "; ".join(tail))


# --- surface.yml -----------------------------------------------------------
rel = ".github/workflows/surface.yml"
doc = load_yaml(rel)
common_rules(rel, doc)
steps = steps_of(doc, "surface")
runs = [run_of(s).strip() for s in steps]
fixture_idx = [i for i, r in enumerate(runs) if "tests/surface/run.sh" in r]
check(bool(fixture_idx), f"{rel}: the fixture suite runs (tests/surface/run.sh)",
      "no step runs tests/surface/run.sh")
first_check = None
for sub in ("size", "filenames", "placement", "statuslog"):
    hits = [i for i, r in enumerate(runs)
            if "bin/check-surface.sh" in r and sub in tokens(r)]
    if len(hits) != 1:
        fail(f"{rel}: {sub} runs in its own step: found {len(hits)} steps")
        continue
    t = tokens(runs[hits[0]])
    subs = [x for x in t if x in ("size", "filenames", "placement", "statuslog")]
    check(subs == [sub], f"{rel}: {sub} runs alone in its step",
          f"step runs {subs}")
    check("--strict" in t and "--warn" not in t,
          f"{rel}: {sub} runs with --strict",
          f"step runs '{runs[hits[0]]}'")
    first_check = hits[0] if first_check is None else min(first_check, hits[0])
if fixture_idx and first_check is not None:
    check(fixture_idx[0] < first_check,
          f"{rel}: the fixture step runs before the checks",
          "a surface check step comes before the fixture step")

# --- pre-commit hook -------------------------------------------------------
rel = ".githooks/pre-commit"
with open(os.path.join(root, rel), encoding="utf-8") as fh:
    text = fh.read()
# Join backslash continuations so each command is one logical line.
logical = re.sub(r"\\\n\s*", " ", text).splitlines()
calls = [ln.strip() for ln in logical
         if re.match(r'\s*"\$REPO_ROOT/bin/check-surface\.sh"\s', ln)]
check(bool(calls), f"{rel}: the hook calls bin/check-surface.sh",
      "no command line starts with \"$REPO_ROOT/bin/check-surface.sh\"")
for c in calls:
    head = c.split("||", 1)[0]
    check("--strict" in head.split() and "--warn" not in head.split(),
          f"{rel}: check-surface runs with --strict", f"call is '{head.strip()}'")
    check('--root "$SURFACE_TMP"' in head,
          f"{rel}: check-surface scans the staged export",
          "call does not pass --root \"$SURFACE_TMP\"")
    check(not re.search(r"\|\|\s*(true|:)(\s|$)", c),
          f"{rel}: a check-surface failure is not swallowed",
          "the call is followed by '|| true'")
    check(re.search(r"\|\|\s*refuse\b", c) is not None,
          f"{rel}: a check-surface failure refuses the commit",
          "the call is not followed by '|| refuse'")
check('git checkout-index --prefix="$SURFACE_TMP/"' in text,
      f"{rel}: the scan root holds the staged blobs",
      "no checkout-index into $SURFACE_TMP")

# --- vale.yml --------------------------------------------------------------
rel = ".github/workflows/vale.yml"
doc = load_yaml(rel)
common_rules(rel, doc)
steps = steps_of(doc, "vale")
runs = [run_of(s) for s in steps]
clean = [r for r in runs if ".vale/clean-set.txt" in r]
check(len(clean) == 1, f"{rel}: one step reads .vale/clean-set.txt",
      f"found {len(clean)}")
for r in clean:
    t = tokens(r)
    check("vale" in t, f"{rel}: the clean-set step runs Vale", "no vale call")
    check("--no-exit" not in t, f"{rel}: the clean-set step fails on errors",
          "it passes --no-exit")
whole = [r for r in runs
         if (t := tokens(r)) and t[0] == "vale" and t[-1] == "."]
check(len(whole) == 1, f"{rel}: one step lints the whole tree",
      f"found {len(whole)} steps running 'vale ... .'")
for r in whole:
    check("--no-exit" in tokens(r),
          f"{rel}: the whole-tree step still warns (--no-exit)",
          "--no-exit is gone; if the sweep is done, update this test on purpose")
check(any("bin/check-voice-changed.sh" in r for r in runs),
      f"{rel}: the changed-files ratchet runs",
      "no step calls bin/check-voice-changed.sh")
check(any("bin/check-voice-fixtures.sh" in r for r in runs),
      f"{rel}: the Voice fixture checks run",
      "no step calls bin/check-voice-fixtures.sh")

# --- title-check.yml -------------------------------------------------------
rel = ".github/workflows/title-check.yml"
doc = load_yaml(rel)
common_rules(rel, doc)
job = (doc.get("jobs") or {}).get("title") or {}
title_steps = [s for s in job.get("steps") or []
               if "hygiene-check.sh title" in run_of(s)]
check(len(title_steps) == 1, f"{rel}: the title job runs the title check",
      f"found {len(title_steps)}")
for s in title_steps:
    env = {}
    env.update(doc.get("env") or {})
    env.update(job.get("env") or {})
    env.update(s.get("env") or {})
    val = env.get("STRICT")
    check(isinstance(val, str) and val == "1",
          f"{rel}: the title check runs with STRICT \"1\"",
          f"STRICT is {val!r}")

# --- backlog-hygiene.yml ---------------------------------------------------
rel = ".github/workflows/backlog-hygiene.yml"
doc = load_yaml(rel)
common_rules(rel, doc)
steps = steps_of(doc, "hygiene")
runs = [run_of(s) for s in steps]
self_idx = [i for i, r in enumerate(runs)
            if "bin/check-backlog-hygiene.sh --self-test" in r]
chk_idx = [i for i, r in enumerate(runs)
           if "bin/check-backlog-hygiene.sh" in r and "--self-test" not in r]
check(len(self_idx) == 1, f"{rel}: the self-test runs",
      f"found {len(self_idx)} self-test steps")
check(len(chk_idx) == 1, f"{rel}: the check runs", f"found {len(chk_idx)} steps")
if self_idx and chk_idx:
    check(self_idx[0] < chk_idx[0], f"{rel}: the self-test runs first",
          "the check runs before the self-test")
if chk_idx:
    cstep = steps[chk_idx[0]]
    check("--warn" not in tokens(run_of(cstep)) and "--warn" not in run_of(cstep),
          f"{rel}: the check runs without --warn", "the check passes --warn")
    sid = cstep.get("id")
    gate = [s for s in steps[chk_idx[0] + 1:]
            if str(s.get("if", "")).replace(" ", "") == "always()"
            and re.search(r"\bexit 1\b", run_of(s))
            and sid
            and f"steps.{sid}.outputs.has_findings"
            in json.dumps(s.get("env") or {}) + run_of(s)]
    check(bool(gate), f"{rel}: a later step fails the job on findings",
          "no 'if: always()' step after the check exits 1 on its has_findings")

# --- fixture suites exist --------------------------------------------------
for rel in ("tests/surface/run.sh", "bin/check-voice-fixtures.sh"):
    p = os.path.join(root, rel)
    check(os.path.isfile(p) and os.access(p, os.X_OK), f"{rel} is executable",
          "missing or not executable")

if fails:
    print(f"hygiene-modes: {fails} FAIL")
    sys.exit(1)
print("hygiene-modes: all checks pinned to their modes")
PY
