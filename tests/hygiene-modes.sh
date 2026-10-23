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
#                        The pull_request trigger has no path filter, so the
#                        check reports on every PR. The scope step decides
#                        whether the Vale steps run, and each of them carries
#                        exactly the pinned "if:" on its output.
#   title-check.yml      the title job sets STRICT to "1".
#   backlog-hygiene.yml  the self-test runs first, the check has no --warn,
#                        and a later step fails the job on findings.
#
# Each guarded step must run exactly its expected command, with no "if:" that
# can switch it off (the Vale steps' scope condition, the Vale ratchet's and
# the backlog gate's conditions are pinned to their current text), and the
# owning jobs have no "if:". The
# surface and title workflows keep their pull_request trigger. The hook's
# surface guards are pinned line by line, with no exit or return before the
# call. The backlog gate condition and has_findings derivation are pinned.
#
# In all five workflows, no step or job sets continue-on-error, and no run
# line ends in "|| true". The surface fixture suite and the Voice fixture
# checks must stay wired into their workflows.
#
# Naming one risky field at a time never ends, so the test also pins whole
# objects. Every step of the four guarded jobs (surface, title, vale and the
# backlog-hygiene job) must equal an expected mapping written in this file,
# in order: same keys, same values, nothing extra. That includes every
# checkout, setup, install, cache and download step, so a "ref: main" on a
# checkout cannot move the checks off the pull request. Each job must also
# have exactly the expected number of steps, so an added or removed step
# fails. Each owning job may carry only its current keys with their current
# values (steps aside). No workflow or job may set "defaults", and no workflow
# may set a top-level "env". The pre-commit hook's whole surface block is
# pinned as exact text.
#
# What this test guards is an accidental or unreviewed change to how a
# hygiene check runs. This test pins every step of the guarded jobs. A
# deliberate change to any step in those jobs, to a job, or to the hook block
# means editing this test in the same PR, so a reviewer sees it.
#
# The test also pins the four guarded workflows (surface, title-check, vale and
# backlog-hygiene) entire: each parsed document is compared with
# tests/hygiene-modes/expected/<name>.json, and every differing key path is
# printed. So are the hook's surface block (exact text) and the per-check modes
# above. The per-check assertions stay for their readable messages. To update
# the pins on purpose, run "bash tests/hygiene-modes.sh --write-expected".
#
# The workflows are parsed as YAML: with PyYAML when python3 has it, else with
# Ruby's built-in YAML library. If neither is there, the test fails rather
# than skipping. Set HYGIENE_ROOT to check another copy of the tree.
#
# Each assertion prints "ok" or "FAIL: <reason>". The script exits 1 on any
# FAIL.

set -euo pipefail

ROOT="${HYGIENE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

exec python3 -I - "$ROOT" "$@" <<'PY'
import json
import os
import re
import shlex
import subprocess
import sys

root = sys.argv[1]
write_expected = "--write-expected" in sys.argv[2:]
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


def pin_step(rel, steps, name, expected):
    """A guarded step equals its expected mapping: no extra key, no changed value."""
    hit = [s for s in steps if s.get("name") == name]
    if len(hit) != 1:
        fail(f"{rel}: guarded step {name!r} exists once: found {len(hit)}. "
             "If this change is deliberate, update tests/hygiene-modes.sh in the same PR")
        return
    got = hit[0]
    extra = sorted(set(got) - set(expected))
    missing = sorted(set(expected) - set(got))
    changed = sorted(k for k in expected if k in got and got[k] != expected[k])
    check(not (extra or missing or changed),
          f"{rel}: step {name!r} matches its pinned mapping",
          f"extra keys {extra}, missing keys {missing}, changed values {changed}. "
          "This test guards against an accidental or unreviewed change to how a "
          "hygiene check runs. If the change is deliberate, update "
          "tests/hygiene-modes.sh in the same PR")


def pin_all_steps(rel, job, steps, expected):
    """Every step of a guarded job equals its expected mapping, in order.

    This covers the steps around the guarded ones too (checkout, setup,
    install, cache, download), so an edit such as "ref: main" on a checkout
    cannot move the checks off the pull request.
    """
    hint = ("If the change is deliberate, update tests/hygiene-modes.sh "
            "in the same PR")
    check(len(steps) == len(expected),
          f"{rel}: job {job!r} has exactly {len(expected)} steps",
          f"job has {len(steps)} steps, expected {len(expected)}. A step was "
          f"added or removed. {hint}")
    for i, (got, want) in enumerate(zip(steps, expected), 1):
        label = got.get("name") or got.get("uses") or "(unnamed)"
        extra = sorted(set(got) - set(want))
        missing = sorted(set(want) - set(got))
        changed = sorted(k for k in want if k in got and got[k] != want[k])
        check(not (extra or missing or changed),
              f"{rel}: {job} step {i} ({label}) matches its pinned mapping",
              f"extra keys {extra}, missing keys {missing}, changed values "
              f"{changed}. {hint}")


def pin_job(rel, doc, job, expected, top_keys):
    """An owning job has only its current keys (steps aside), with current values."""
    j = (doc.get("jobs") or {}).get(job) or {}
    rest = {k: v for k, v in j.items() if k != "steps"}
    check(rest == expected, f"{rel}: job {job!r} keeps its pinned keys and values",
          f"job has {rest!r}, expected {expected!r}. If the change is "
          "deliberate, update tests/hygiene-modes.sh in the same PR")
    top = sorted("on" if k in (True, "true") else k for k in doc)
    check(top == sorted(top_keys), f"{rel}: workflow keeps its pinned top-level keys",
          f"keys are {top}, expected {sorted(top_keys)}. No workflow-level "
          "'env' or 'defaults' is allowed. If the change is deliberate, update "
          "tests/hygiene-modes.sh in the same PR")
    bad = [n for n, jb in (doc.get("jobs") or {}).items() if "defaults" in jb]
    check(not bad, f"{rel}: no job sets defaults", "defaults set on " + ", ".join(bad))


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


# --- expected steps of the guarded jobs, in order --------------------------
SURFACE_STEPS = [
    {"uses": "actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683", "with": {"persist-credentials": False}},
    {"name": "Fixture tests", "run": "tests/surface/run.sh"},
    {"name": "Size budgets", "run": "bin/check-surface.sh --strict size"},
    {"name": "Filenames", "run": "bin/check-surface.sh --strict filenames"},
    {"name": "Archive placement", "run": "bin/check-surface.sh --strict placement"},
    {"name": "Status log", "run": "bin/check-surface.sh --strict statuslog"},
]

TITLE_STEPS = [
    {"uses": "actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683"},
    {"name": "Check the title", "env": {"STRICT": "1"}, "run": ".github/scripts/hygiene-check.sh title"},
]

# The vale job always runs. Its scope step lists the paths that matter and
# sets "lint"; every later step runs only when lint is "true".
VALE_IF = "steps.scope.outputs.lint == 'true'"
RATCHET_IF = "github.event_name == 'pull_request' && " + VALE_IF
VALE_SCOPE_RUN = (
    "set -euo pipefail\n"
    "# The only list of paths that run the Vale steps on a pull request.\n"
    "paths=(\n"
    "  \"README.md\"\n"
    "  \"**/README.md\"\n"
    "  \"CONTRIBUTING.md\"\n"
    "  \"AGENTS.md\"\n"
    "  \"ROADMAP.md\"\n"
    "  \"docs/decisions/**\"\n"
    "  \"docs/design/**\"\n"
    "  \"docs/THESIS.md\"\n"
    "  \"docs/JOURNEY.md\"\n"
    "  \"docs/WORKING-MODEL.md\"\n"
    "  \"docs/OPEN-QUESTIONS.md\"\n"
    "  \"docs/GLOSSARY.md\"\n"
    "  \"docs/INDEX.md\"\n"
    "  \"docs/STYLE.md\"\n"
    "  \"docs/templates/**\"\n"
    "  \".github/**/*.md\"\n"
    "  \"bin/check-voice*.sh\"\n"
    "  \"bin/mutate-voice.sh\"\n"
    "  \"tests/voice-changed-head.sh\"\n"
    "  \"tests/voice-changed-links.sh\"\n"
    "  \".vale.ini\"\n"
    "  \".vale/**\"\n"
    "  \".github/workflows/vale.yml\"\n"
    ")\n"
    "if [[ \"$GITHUB_EVENT_NAME\" != \"pull_request\" ]]; then\n"
    "  echo \"Not a pull request, so every Vale step runs.\"\n"
    "  echo \"lint=true\" >>\"$GITHUB_OUTPUT\"\n"
    "  exit 0\n"
    "fi\n"
    "# HEAD is the PR merge commit; its first parent is the base branch.\n"
    "changed=\"$(git diff --name-only HEAD^1 HEAD -- \"${paths[@]/#/:(glob)}\")\"\n"
    "if [[ -z \"$changed\" ]]; then\n"
    "  echo \"No Vale path changed in this pull request. Skipping the Vale steps.\"\n"
    "  echo \"lint=false\" >>\"$GITHUB_OUTPUT\"\n"
    "else\n"
    "  echo \"Vale paths changed in this pull request:\"\n"
    "  printf '%s\\n' \"$changed\"\n"
    "  echo \"lint=true\" >>\"$GITHUB_OUTPUT\"\n"
    "fi\n")

VALE_STEPS = [
    {"name": "Checkout", "uses": "actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683", "with": {"persist-credentials": False, "fetch-depth": 2}},
    {"name": "Find the changed Vale paths", "id": "scope", "run": VALE_SCOPE_RUN},
    {"name": "Install Vale", "if": VALE_IF, "env": {"VALE_VERSION": "3.25.1"}, "run": (
        "set -euo pipefail\n"
        "url=\"https://github.com/vale-cli/vale/releases/download/v${VALE_VERSION}/vale_${VALE_VERSION}_Linux_64-bit.tar.gz\"\n"
        "sha=\"4bf5c5176b682b1da0830f471584d3494f1c2e27ee3029e1ad6f6661d4962182\"\n"
        "mkdir -p \"$RUNNER_TEMP/vale\"\n"
        "curl -fsSL -o \"$RUNNER_TEMP/vale.tgz\" \"$url\"\n"
        "echo \"$sha  $RUNNER_TEMP/vale.tgz\" | sha256sum -c -\n"
        "tar -xz -C \"$RUNNER_TEMP/vale\" -f \"$RUNNER_TEMP/vale.tgz\" vale\n"
        "echo \"$RUNNER_TEMP/vale\" >> \"$GITHUB_PATH\"\n")},
    {"name": "Sync the Google package", "if": VALE_IF, "run": "vale sync"},
    {"name": "Lint working surfaces (warn mode)", "if": VALE_IF, "run": "vale --no-exit ."},
    {"name": "Enforce Vale on the clean set (error level blocks)", "if": VALE_IF, "run": (
        "set -euo pipefail\n"
        "grep -v -e '^#' -e '^[[:space:]]*$' .vale/clean-set.txt \\\n"
        "  | xargs vale --minAlertLevel=error\n")},
    {"name": "Check the README scope", "if": VALE_IF, "run": ".vale/scope-test.sh"},
    {"name": "Check the fixtures (strict config)", "if": VALE_IF, "run": (
        "set -euo pipefail\n"
        "for bad in .vale/fixtures/bad-*.md; do\n"
        "  good=\"${bad/bad-/good-}\"\n"
        "  if vale --config .vale/strict.ini \"$bad\" >/dev/null; then\n"
        "    echo \"::error::$bad passed but must fail\"; exit 1\n"
        "  fi\n"
        "  vale --config .vale/strict.ini \"$good\" >/dev/null \\\n"
        "    || { echo \"::error::$good must pass\"; exit 1; }\n"
        "done\n")},
    {"name": "Check the Voice fixtures", "if": VALE_IF, "run": "bin/check-voice-fixtures.sh"},
    {"name": "Mutation-test the Voice rules", "if": VALE_IF, "run": "bin/mutate-voice.sh"},
    {"name": "Ratchet the Voice errors in changed files", "if": RATCHET_IF, "run": "bin/check-voice-changed.sh HEAD^1 HEAD"},
    {"name": "Test that the ratchet reads HEAD, not the checkout", "if": VALE_IF, "run": "tests/voice-changed-head.sh"},
    {"name": "Test that the ratchet counts encoded link targets the same way", "if": VALE_IF, "run": "tests/voice-changed-links.sh"},
]

HYGIENE_STEPS = [
    {"name": "Checkout", "uses": "actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683", "with": {"persist-credentials": False}},
    {"name": "Self-test the freshness rules", "run": "bin/check-backlog-hygiene.sh --self-test"},
    {"name": "Run backlog-hygiene check", "env": {"GH_TOKEN": "${{ secrets.GITHUB_TOKEN }}"}, "id": "hygiene_run", "run": (
        "# pipefail so rc reflects the checker, not tee\n"
        "set +e\n"
        "set -o pipefail\n"
        "bin/check-backlog-hygiene.sh 2>&1 | tee /tmp/report.txt\n"
        "rc=$?\n"
        "set -e\n"
        "last=\"$(grep -v '^[[:space:]]*$' /tmp/report.txt | tail -1 || true)\"\n"
        "if [ \"$rc\" -eq 0 ] && [ \"$last\" = \"backlog-hygiene: OK (0 findings)\" ]; then\n"
        "  has=false\n"
        "else\n"
        "  has=true\n"
        "fi\n"
        "echo \"has_findings=$has\" >> \"$GITHUB_OUTPUT\"\n")},
    {"name": "Manage report issue", "env": {"GH_TOKEN": "${{ secrets.GITHUB_TOKEN }}", "HAS_FINDINGS": "${{ steps.hygiene_run.outputs.has_findings }}"}, "run": (
        "set -euo pipefail\n"
        "\n"
        "# The report issue carries hygiene-exempt so the checker never\n"
        "# flags its own report (no milestone/workstream by design).\n"
        "existing=\"$(gh issue list \\\n"
        "  --repo dmfdeploy/dmfdeploy \\\n"
        "  --search \"Backlog hygiene report in:title\" \\\n"
        "  --state open \\\n"
        "  --label component:cross-repo \\\n"
        "  --json number --jq '.[0].number // empty' 2>/dev/null || true)\"\n"
        "\n"
        "# An incomplete or crashed run keeps the issue open and says so,\n"
        "# because its findings list may be missing checks.\n"
        "last=\"$(grep -v '^[[:space:]]*$' /tmp/report.txt | tail -1 || true)\"\n"
        "{\n"
        "  printf '## Backlog hygiene report — %s\\n\\n' \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"\n"
        "  case \"$last\" in\n"
        "    \"backlog-hygiene: INCOMPLETE\"*)\n"
        "      printf '**The run was incomplete:** at least one check could not read its input (see SKIPPED below), so findings may be missing.\\n\\n' ;;\n"
        "    \"backlog-hygiene: \"*) ;;\n"
        "    *)\n"
        "      printf '**The run did not finish:** the checker printed no summary line.\\n\\n' ;;\n"
        "  esac\n"
        "  printf '```\\n'\n"
        "  cat /tmp/report.txt\n"
        "  printf '```\\n'\n"
        "} > /tmp/body.md\n"
        "\n"
        "if [ \"${HAS_FINDINGS:-true}\" = \"true\" ]; then\n"
        "  if [ -n \"$existing\" ]; then\n"
        "    gh issue edit \"$existing\" \\\n"
        "      --repo dmfdeploy/dmfdeploy \\\n"
        "      --body-file /tmp/body.md\n"
        "    echo \"Updated report issue #$existing\"\n"
        "  else\n"
        "    gh issue create \\\n"
        "      --repo dmfdeploy/dmfdeploy \\\n"
        "      --title \"Backlog hygiene report\" \\\n"
        "      --label component:cross-repo \\\n"
        "      --label hygiene-exempt \\\n"
        "      --body-file /tmp/body.md\n"
        "    echo \"Created report issue\"\n"
        "  fi\n"
        "else\n"
        "  if [ -n \"$existing\" ]; then\n"
        "    gh issue close \"$existing\" \\\n"
        "      --repo dmfdeploy/dmfdeploy \\\n"
        "      --comment \"Clean run — no findings.\" \\\n"
        "      --reason completed\n"
        "    echo \"Closed report issue #$existing (clean run)\"\n"
        "  else\n"
        "    echo \"No findings, no open report issue — nothing to do\"\n"
        "  fi\n"
        "fi\n")},
    {"name": "Fail on findings", "if": "always()", "env": {"HAS_FINDINGS": "${{ steps.hygiene_run.outputs.has_findings }}"}, "run": (
        "if [ \"${HAS_FINDINGS:-}\" != \"false\" ]; then\n"
        "  echo \"::error::backlog-hygiene found drift or did not finish; see the report issue\"\n"
        "  exit 1\n"
        "fi\n")},
]

# --- surface.yml -----------------------------------------------------------
rel = ".github/workflows/surface.yml"
doc = load_yaml(rel)
common_rules(rel, doc)
check("pull_request" in on_of(doc), f"{rel}: keeps its pull_request trigger",
      "the 'on' block has no pull_request")
no_if(rel, "the surface job", (doc.get("jobs") or {}).get("surface") or {})
steps = steps_of(doc, "surface")
pin_job(rel, doc, "surface", {"runs-on": "ubuntu-24.04", "timeout-minutes": 5},
        ["name", "on", "permissions", "concurrency", "jobs"])
pin_all_steps(rel, "surface", steps, SURFACE_STEPS)
pin_step(rel, steps, "Fixture tests",
         {"name": "Fixture tests", "run": "tests/surface/run.sh"})
for _n, _sub in (("Size budgets", "size"), ("Filenames", "filenames"),
                 ("Archive placement", "placement"), ("Status log", "statuslog")):
    pin_step(rel, steps, _n, {"name": _n,
                              "run": f"bin/check-surface.sh --strict {_sub}"})
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
HOOK_BLOCK = r'''if gate_on '^(README\.md|AGENTS\.md|STATUS\.md|docs/|bin/check-surface\.sh$|tests/surface/)' \
        && [ -x "$REPO_ROOT/bin/check-surface.sh" ]; then
    # Check the staged content, not the working-tree copy: export the staged
    # blobs to a temp dir and use that dir as the scan root, so each file keeps
    # its repo-relative path.
    SURFACE_ARGS=()
    SURFACE_PATHS=()
    while IFS= read -r p; do
        if git cat-file -e ":$p" 2>/dev/null; then SURFACE_PATHS+=("$p"); fi
    done < <(printf '%s\n' "$STAGED_PATHS" | grep -E '^(README\.md|AGENTS\.md|STATUS\.md|docs/)' || true)
    if [ ${#SURFACE_PATHS[@]} -gt 0 ]; then
        SURFACE_TMP="$(mktemp -d)"
        trap 'rm -rf "$SURFACE_TMP"' EXIT
        git checkout-index --prefix="$SURFACE_TMP/" -- "${SURFACE_PATHS[@]}"
        for p in "${SURFACE_PATHS[@]}"; do SURFACE_ARGS+=(--file "$SURFACE_TMP/$p"); done
        "$REPO_ROOT/bin/check-surface.sh" --strict --root "$SURFACE_TMP" "${SURFACE_ARGS[@]}" >/dev/null 2>&1 \
            || refuse "check-surface: staged files break a surface rule" \
                      "see findings above (budgets, filenames, archive placement)" \
                      "$REPO_ROOT/bin/check-surface.sh" --strict --root "$SURFACE_TMP" "${SURFACE_ARGS[@]}"
    fi
fi
'''
start = [i for i, ln in enumerate(hook_lines) if ln == GATE]
block = None
if len(start) == 1:
    for j in range(start[0] + 1, len(hook_lines)):
        if hook_lines[j] == "fi":
            block = "\n".join(hook_lines[start[0]:j + 1]) + "\n"
            break
check(block == HOOK_BLOCK, f"{rel}: the whole surface block is pinned verbatim",
      "the block from the gate_on line to its closing 'fi' changed. This test "
      "guards against an accidental or unreviewed change to how the surface "
      "check runs. If the change is deliberate, update HOOK_BLOCK in "
      "tests/hygiene-modes.sh in the same PR")
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
pin_job(rel, doc, "vale", {"runs-on": "ubuntu-24.04", "timeout-minutes": 10},
        ["name", "on", "permissions", "jobs"])
pin_all_steps(rel, "vale", steps, VALE_STEPS)
pr = on_of(doc).get("pull_request", "absent")
check(pr is None or (isinstance(pr, dict) and not ({"paths", "paths-ignore"} & set(pr))),
      f"{rel}: the pull_request trigger has no path filter",
      f"pull_request is {pr!r}. A path filter means a PR that changes no "
      "listed file never gets the vale check, and a required check that never "
      "reports blocks the merge. Filter inside the job (the scope step)")
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
for _name, _step in (
    ("Find the changed Vale paths",
     {"id": "scope", "run": VALE_SCOPE_RUN}),
    ("Lint working surfaces (warn mode)",
     {"if": VALE_IF, "run": "vale --no-exit ."}),
    ("Enforce Vale on the clean set (error level blocks)",
     {"if": VALE_IF, "run": VALE_EXACT[".vale/clean-set.txt"] + "\n"}),
    ("Check the fixtures (strict config)",
     {"if": VALE_IF, "run": VALE_EXACT["--config .vale/strict.ini"] + "\n"}),
    ("Check the Voice fixtures",
     {"if": VALE_IF, "run": "bin/check-voice-fixtures.sh"}),
    ("Ratchet the Voice errors in changed files",
     {"if": RATCHET_IF, "run": "bin/check-voice-changed.sh HEAD^1 HEAD"}),
):
    pin_step(rel, steps, _name, {"name": _name, **_step})
for key, want in VALE_EXACT.items():
    hit = [s for s in steps if key in run_of(s)]
    check(len(hit) == 1, f"{rel}: one step matches {key!r}",
          f"found {len(hit)}")
    for s in hit:
        exact_run(rel, f"the {key!r} step", s, want)
        if key == "bin/check-voice-changed.sh":
            exact_if(rel, "the ratchet step", s, RATCHET_IF)
        else:
            exact_if(rel, f"the {key!r} step", s, VALE_IF)
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
pin_job(rel, doc, "title",
        {"runs-on": "ubuntu-24.04", "timeout-minutes": 2,
         "permissions": {"contents": "read"}},
        ["name", "on", "permissions", "jobs"])
pin_all_steps(rel, "title", job.get("steps") or [], TITLE_STEPS)
pin_step(rel, job.get("steps") or [], "Check the title",
         {"name": "Check the title", "env": {"STRICT": "1"},
          "run": ".github/scripts/hygiene-check.sh title"})
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
CHECK_RUN = """\
# pipefail so rc reflects the checker, not tee
set +e
set -o pipefail
bin/check-backlog-hygiene.sh 2>&1 | tee /tmp/report.txt
rc=$?
set -e
last="$(grep -v '^[[:space:]]*$' /tmp/report.txt | tail -1 || true)"
if [ "$rc" -eq 0 ] && [ "$last" = "backlog-hygiene: OK (0 findings)" ]; then
  has=false
else
  has=true
fi
echo "has_findings=$has" >> "$GITHUB_OUTPUT"
"""
GATE_RUN = """\
if [ "${HAS_FINDINGS:-}" != "false" ]; then
  echo "::error::backlog-hygiene found drift or did not finish; see the report issue"
  exit 1
fi
"""
rel = ".github/workflows/backlog-hygiene.yml"
doc = load_yaml(rel)
common_rules(rel, doc)
steps = steps_of(doc, "hygiene")
runs = [run_of(s) for s in steps]
pin_job(rel, doc, "hygiene", {"runs-on": "ubuntu-24.04", "timeout-minutes": 10},
        ["name", "on", "permissions", "jobs"])
pin_all_steps(rel, "hygiene", steps, HYGIENE_STEPS)
pin_step(rel, steps, "Self-test the freshness rules",
         {"name": "Self-test the freshness rules",
          "run": "bin/check-backlog-hygiene.sh --self-test"})
pin_step(rel, steps, "Run backlog-hygiene check",
         {"name": "Run backlog-hygiene check", "id": "hygiene_run",
          "env": {"GH_TOKEN": "${{ secrets.GITHUB_TOKEN }}"},
          "run": CHECK_RUN})
pin_step(rel, steps, "Fail on findings",
         {"name": "Fail on findings", "if": "always()",
          "env": {"HAS_FINDINGS": "${{ steps.hygiene_run.outputs.has_findings }}"},
          "run": GATE_RUN})
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

# --- whole-document pin ----------------------------------------------------
# Each guarded workflow is compared as a whole against its expected parsed
# document, so any edit (a trigger type, a branch filter, a new top-level key)
# shows up with its key path, not only the fields named above.
GUARDED = ("surface", "title-check", "vale", "backlog-hygiene")
EXPECTED_DIR = os.path.join(root, "tests", "hygiene-modes", "expected")


def normalise(doc):
    """Rename the top-level 'on' key. PyYAML parses it as True; Ruby's JSON
    turns that into "true"."""
    out = {}
    for key, val in doc.items():
        out["on" if key in ("on", True, "true") else key] = val
    return out


def canonical(doc):
    return json.dumps(doc, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


MISSING = object()


def diff_paths(exp, act, path=""):
    """Yield (key path, expected, actual) for each difference."""
    if isinstance(exp, dict) and isinstance(act, dict):
        for key in sorted(set(exp) | set(act), key=str):
            sub = f"{path}.{key}" if path else str(key)
            yield from diff_paths(exp.get(key, MISSING), act.get(key, MISSING), sub)
    elif isinstance(exp, list) and isinstance(act, list):
        for i in range(max(len(exp), len(act))):
            e = exp[i] if i < len(exp) else MISSING
            a = act[i] if i < len(act) else MISSING
            yield from diff_paths(e, a, f"{path}[{i}]")
    elif exp != act or type(exp) is not type(act):
        yield path, exp, act


def show(val):
    return "<absent>" if val is MISSING else json.dumps(val)


if write_expected:
    if os.environ.get("CI") or os.environ.get("GITHUB_ACTIONS"):
        sys.exit("FAIL: --write-expected is for deliberate local use, not CI")
    os.makedirs(EXPECTED_DIR, exist_ok=True)
    for name in GUARDED:
        wf = normalise(load_yaml(f".github/workflows/{name}.yml"))
        with open(os.path.join(EXPECTED_DIR, f"{name}.json"), "w",
                  encoding="utf-8") as fh:
            fh.write(canonical(wf))
    print(f"hygiene-modes: wrote {len(GUARDED)} expected files to {EXPECTED_DIR}")
    sys.exit(0)

for name in GUARDED:
    rel = f".github/workflows/{name}.yml"
    exp_path = os.path.join(EXPECTED_DIR, f"{name}.json")
    try:
        with open(exp_path, encoding="utf-8") as fh:
            exp = json.load(fh)
    except (OSError, ValueError) as exc:
        fail(f"{rel}: whole-document pin: cannot read {exp_path}: {exc}")
        continue
    act = normalise(load_yaml(rel))
    diffs = list(diff_paths(exp, act))
    if not diffs:
        ok(f"{rel}: the whole document matches its pin")
        continue
    fail(f"{rel}: the whole document differs from its pin ({len(diffs)} keys)")
    for path, e, a in diffs:
        print(f"      {path}: expected {show(e)}, actual {show(a)}")
    print("      A deliberate change means updating the expected JSON in the "
          "same PR (tests/hygiene-modes.sh --write-expected).")

if fails:
    print(f"hygiene-modes: {fails} FAIL")
    sys.exit(1)
print("hygiene-modes: all checks pinned to their modes")
PY
