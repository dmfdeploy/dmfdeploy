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
# Each guarded step must run exactly its expected command, with no "if:" that
# can switch it off (the Vale ratchet's and the backlog gate's conditions are
# pinned to their current text), and the owning jobs have no "if:". The
# surface and title workflows keep their pull_request trigger. The hook's
# surface guards are pinned line by line, with no exit or return before the
# call. The backlog gate condition and has_findings derivation are pinned.
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


def on_of(doc):
    """The trigger map. PyYAML and Ruby parse a bare 'on' key as true."""
    on = None
    for key in ("on", True, "true"):  # Ruby's JSON turns true into "true"
        if key in doc:
            on = doc[key]
            break
    return on if isinstance(on, dict) else {}


def no_if(rel, what, node):
    """A guarded step or job has no 'if:' that could switch it off."""
    check("if" not in node, f"{rel}: {what} has no 'if:'",
          f"it has if: {node.get('if')!r}")


def exact_if(rel, what, node, expected):
    check(node.get("if") == expected, f"{rel}: {what} 'if:' is unchanged",
          f"if is {node.get('if')!r}, expected {expected!r}")


def exact_run(rel, what, step, expected):
    got = run_of(step).strip()
    check(got == expected, f"{rel}: {what} runs exactly the expected command",
          f"run is {got!r}, expected {expected!r}")


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
check("pull_request" in on_of(doc), f"{rel}: keeps its pull_request trigger",
      "the 'on' block has no pull_request")
no_if(rel, "the surface job", (doc.get("jobs") or {}).get("surface") or {})
steps = steps_of(doc, "surface")
runs = [run_of(s).strip() for s in steps]
fixture_idx = [i for i, r in enumerate(runs) if r == "tests/surface/run.sh"]
check(len(fixture_idx) == 1,
      f"{rel}: the fixture suite runs exactly 'tests/surface/run.sh'",
      f"found {len(fixture_idx)} steps with that exact run")
for i in fixture_idx:
    no_if(rel, "the fixture step", steps[i])
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
    exact_run(rel, f"the {sub} step", steps[hits[0]],
              f"bin/check-surface.sh --strict {sub}")
    no_if(rel, f"the {sub} step", steps[hits[0]])
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
hook_lines = text.splitlines()
GATE = ("if gate_on '^(README\\.md|AGENTS\\.md|STATUS\\.md|docs/"
        "|bin/check-surface\\.sh$|tests/surface/)' \\")
GATE2 = '        && [ -x "$REPO_ROOT/bin/check-surface.sh" ]; then'
COUNT = "    if [ ${#SURFACE_PATHS[@]} -gt 0 ]; then"
pos = {}
for name, want in (("gate", GATE), ("gate2", GATE2), ("count", COUNT)):
    idx = [i for i, ln in enumerate(hook_lines) if ln == want]
    check(len(idx) == 1, f"{rel}: the surface block {name} line is pinned",
          f"expected exactly one line {want!r}, found {len(idx)}")
    if idx:
        pos[name] = idx[0]
call_idx = [i for i, ln in enumerate(hook_lines)
            if 'bin/check-surface.sh" --strict' in ln and "refuse" not in ln
            and not ln.lstrip().startswith("#")
            and "--root" in ln and ">/dev/null" in ln]
check(len(call_idx) == 1, f"{rel}: one check-surface call in the block",
      f"found {len(call_idx)}")
if len(pos) == 3 and call_idx:
    check(pos["gate"] + 1 == pos["gate2"] < pos["count"] < call_idx[0],
          f"{rel}: the guards come before the call, in order",
          "gate, gate2, count and call are out of order")
    between = [ln for ln in hook_lines[pos["gate"]:call_idx[0]]
               if not ln.lstrip().startswith("#")]
    bad = [ln.strip() for ln in between
           if re.search(r"(^|[;&|{(\s])(exit|return)\b", ln)]
    check(not bad, f"{rel}: nothing exits before the check-surface call",
          "; ".join(bad))
check('git checkout-index --prefix="$SURFACE_TMP/"' in text,
      f"{rel}: the scan root holds the staged blobs",
      "no checkout-index into $SURFACE_TMP")

# --- vale.yml --------------------------------------------------------------
rel = ".github/workflows/vale.yml"
doc = load_yaml(rel)
common_rules(rel, doc)
steps = steps_of(doc, "vale")
runs = [run_of(s) for s in steps]
no_if(rel, "the vale job", (doc.get("jobs") or {}).get("vale") or {})
RATCHET_IF = "github.event_name == 'pull_request'"
VALE_EXACT = {
    "bin/check-voice-changed.sh": "bin/check-voice-changed.sh HEAD^1 HEAD",
    "bin/check-voice-fixtures.sh": "bin/check-voice-fixtures.sh",
    ".vale/clean-set.txt": (
        "set -euo pipefail\n"
        "grep -v -e '^#' -e '^[[:space:]]*$' .vale/clean-set.txt \\\n"
        "  | xargs vale --minAlertLevel=error"),
    "--config .vale/strict.ini": (
        "set -euo pipefail\n"
        "for bad in .vale/fixtures/bad-*.md; do\n"
        "  good=\"${bad/bad-/good-}\"\n"
        "  if vale --config .vale/strict.ini \"$bad\" >/dev/null; then\n"
        "    echo \"::error::$bad passed but must fail\"; exit 1\n"
        "  fi\n"
        "  vale --config .vale/strict.ini \"$good\" >/dev/null \\\n"
        "    || { echo \"::error::$good must pass\"; exit 1; }\n"
        "done"),
    "vale --no-exit .": "vale --no-exit .",
}
for key, want in VALE_EXACT.items():
    hit = [s for s in steps if key in run_of(s)]
    check(len(hit) == 1, f"{rel}: one step matches {key!r}",
          f"found {len(hit)}")
    for s in hit:
        exact_run(rel, f"the {key!r} step", s, want)
        if key == "bin/check-voice-changed.sh":
            exact_if(rel, "the ratchet step", s, RATCHET_IF)
        else:
            no_if(rel, f"the {key!r} step", s)
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
check("pull_request" in on_of(doc), f"{rel}: keeps its pull_request trigger",
      "the 'on' block has no pull_request")
job = (doc.get("jobs") or {}).get("title") or {}
no_if(rel, "the title job", job)
title_steps = [s for s in job.get("steps") or []
               if "hygiene-check.sh title" in run_of(s)]
check(len(title_steps) == 1, f"{rel}: the title job runs the title check",
      f"found {len(title_steps)}")
for s in title_steps:
    exact_run(rel, "the title step", s, ".github/scripts/hygiene-check.sh title")
    no_if(rel, "the title step", s)
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
no_if(rel, "the hygiene job", (doc.get("jobs") or {}).get("hygiene") or {})
for i in self_idx:
    exact_run(rel, "the self-test step", steps[i],
              "bin/check-backlog-hygiene.sh --self-test")
    no_if(rel, "the self-test step", steps[i])
DERIVE = [
    'if [ "$rc" -eq 0 ] && [ "$last" = "backlog-hygiene: OK (0 findings)" ]; then',
    "has=false",
    "else",
    "has=true",
    "fi",
    'echo "has_findings=$has" >> "$GITHUB_OUTPUT"',
]
for i in chk_idx:
    no_if(rel, "the check step", steps[i])
    lines = [ln.strip() for ln in run_of(steps[i]).splitlines()]
    n = len(DERIVE)
    check(any(lines[j:j + n] == DERIVE[:-1] + [DERIVE[-1]]
              for j in range(len(lines))),
          f"{rel}: the has_findings derivation is pinned",
          "the if/else/fi block that sets has_findings changed")
    check("bin/check-backlog-hygiene.sh 2>&1 | tee /tmp/report.txt" in lines,
          f"{rel}: the check call is pinned",
          "the checker line changed")
if self_idx and chk_idx:
    check(self_idx[0] < chk_idx[0], f"{rel}: the self-test runs first",
          "the check runs before the self-test")
if chk_idx:
    cstep = steps[chk_idx[0]]
    check("--warn" not in tokens(run_of(cstep)) and "--warn" not in run_of(cstep),
          f"{rel}: the check runs without --warn", "the check passes --warn")
    sid = cstep.get("id")
    gate = [s for s in steps[chk_idx[0] + 1:]
            if s.get("if") == "always()"
            and re.search(r"\bexit 1\b", run_of(s))
            and sid
            and f"steps.{sid}.outputs.has_findings"
            in json.dumps(s.get("env") or {}) + run_of(s)]
    check(bool(gate), f"{rel}: a later step fails the job on findings",
          "no 'if: always()' step after the check exits 1 on its has_findings")
    GATE_COND = 'if [ "${HAS_FINDINGS:-}" != "false" ]; then'
    check(any(GATE_COND in [ln.strip() for ln in run_of(g).splitlines()]
              for g in gate),
          f"{rel}: the gate condition is pinned",
          f"no gate step has the line {GATE_COND!r}")

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
