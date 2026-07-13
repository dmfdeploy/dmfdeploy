#!/usr/bin/env python3
"""dmf_scan_selftest.py — fixture-based self-test for the scan library.

Covers the acceptance-matrix rows implementable before any caller switches
(R1 spec §8): the §5.4 opt-out authorization boundary (row 11), fail-closed
missing-private-manifest (row 10), seeded-canary LEAK_FOUND through the tree/
staged/range surfaces, worktree scanning (row 7 at library level), §4.2
redaction of private-tier hits, and ephemeral merged-config cleanup (§5.1).

HERMETIC: every case pins DMF_PATTERN_MANIFEST_PRIVATE explicitly (to a
fixture or to a missing path) so the operator's real private manifest is
never read. Canary values are ASSEMBLED AT RUNTIME from parts so no committed
file carries a literal that matches a rule (same discipline as
tests/worktree-regression.sh).
"""
import glob
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CLI = os.path.join(os.path.dirname(HERE), "dmf-scan")
MISSING = "/nonexistent/dmf-pattern-manifest.private.toml"

# Assembled at runtime — the committed source never holds a matching literal.
PUBLIC_CANARY = "DMF-CANARY-" + "0123456789" + "AB"
PRIVATE_MARK = "FIXTURE-PRIVATE-" + "31" + "4159"

PRIVATE_FIXTURE_MANIFEST = """\
# Synthetic PRIVATE-tier fixture manifest (self-test only — not operator data).
[[pattern]]
id = "fixture-private-marker"
category = "topology"
description = "fixture private topology marker (synthetic)"
regex = 'FIXTURE-PRIVATE-[0-9]{6}'
engines = ["pcre", "re2", "ere"]
case_sensitive = true
positive_canaries = ["%s"]
negative_canaries = ["FIXTURE-PRIVATE-x"]
[pattern.gitleaks]
emit = true
kind = "custom"
tags = ["fixture"]
""" % PRIVATE_MARK

# Python-`re`-valid but RE2-INVALID (lookahead) — the codex P1-1 reproduction:
# gitleaks' panic on this regex must never be relayed verbatim.
PRIVATE_BADREGEX_MANIFEST = """\
[[pattern]]
id = "fixture-private-badregex"
category = "topology"
description = "fixture RE2-invalid private regex (synthetic)"
regex = 'FIXTURE-PRIVATE-[0-9]{6}(?=X)'
engines = ["pcre"]
case_sensitive = true
positive_canaries = ["%sX"]
[pattern.gitleaks]
emit = true
kind = "custom"
tags = ["fixture"]
""" % PRIVATE_MARK

# Old-world private include fixture for the parity P2-2 regression.
PRIVATE_FIXTURE_INCLUDE = """\
DMF_PRIVATE_IDENTITY_PATTERNS=()
DMF_PRIVATE_TOPOLOGY_PATTERNS=('FIXTURE-PRIVATE-[0-9]{6}|fixture marker')
DMF_PRIVATE_IDENTITY_REGEX=''
DMF_PRIVATE_TOPOLOGY_REGEX='FIXTURE-PRIVATE-[0-9]{6}'
"""


def _git(*args, cwd=None):
    subprocess.run(["git", *args], cwd=cwd, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _make_repo(path, content=None):
    os.makedirs(path, exist_ok=True)
    _git("init", "-q", "-b", "main", cwd=path)
    with open(os.path.join(path, "note.txt"), "w", encoding="utf-8") as fh:
        fh.write(content if content is not None else "benign fixture content\n")
    _git("add", "-A", cwd=path)
    _git("-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid",
         "commit", "-q", "-m", "fixture", cwd=path)


def _run(argv, private_manifest=MISSING, cwd=None):
    env = dict(os.environ)
    env["DMF_PATTERN_MANIFEST_PRIVATE"] = private_manifest
    env.pop("DMF_SCAN_PUBLIC_ONLY", None)
    env.pop("DMF_SCAN_NO_ALLOWLIST", None)
    return subprocess.run([sys.executable, CLI, *argv], env=env, cwd=cwd,
                          capture_output=True, text=True)


def _merged_leftovers():
    return set(glob.glob(os.path.join(tempfile.gettempdir(), "dmf-scan-merged-*")))


def run_self_test(skip_gitleaks=False):
    passed = failed = 0

    def check(cond, label):
        nonlocal passed, failed
        if cond:
            passed += 1
            print(f"  ✓ {label}")
        else:
            failed += 1
            print(f"  ✗ {label}", file=sys.stderr)

    before_tmp = _merged_leftovers()

    with tempfile.TemporaryDirectory(prefix="dmf-scan-st.") as work:
        priv = os.path.join(work, "private-fixture.toml")
        with open(priv, "w", encoding="utf-8") as fh:
            fh.write(PRIVATE_FIXTURE_MANIFEST)

        clean = os.path.join(work, "clean")
        _make_repo(clean)
        leaky = os.path.join(work, "leaky")
        _make_repo(leaky, f"config token = {PUBLIC_CANARY}\n")
        privleak = os.path.join(work, "privleak")
        _make_repo(privleak, f"host marker {PRIVATE_MARK} here\n")

        # ── §5.4 authorization boundary (row 11) ──
        r = _run(["tree", clean, "--context", "scrub", "--public-only"])
        check(r.returncode == 3 and "CONFIG_ERROR" in r.stderr,
              "row 11: --public-only in disallowed context 'scrub' → CONFIG_ERROR")
        r = _run(["tree", clean, "--context", "no-such-context", "--public-only"])
        check(r.returncode == 3 and "CONFIG_ERROR" in r.stderr,
              "unknown context → CONFIG_ERROR (not argparse rc 2)")

        # ── fail-closed missing private manifest (row 10) ──
        r = _run(["tree", clean, "--context", "scrub"], private_manifest=MISSING)
        check(r.returncode == 3 and "CONFIG_ERROR" in r.stderr,
              "row 10: required context + missing private manifest → CONFIG_ERROR")
        r = _run(["tree", clean, "--context", "ci-public"], private_manifest=MISSING)
        check(r.returncode == 3 and "CONFIG_ERROR" in r.stderr,
              "opt-out-capable context WITHOUT --public-only stays fail-closed")

        # ── public sentinel through the tree surface ──
        if not skip_gitleaks:
            r = _run(["tree", leaky, "--context", "public-acceptance-fixture",
                      "--public-only"])
            check(r.returncode == 1 and "LEAK_FOUND" in r.stderr,
                  "seeded public sentinel in tree → LEAK_FOUND")
            r = _run(["tree", clean, "--context", "public-acceptance-fixture",
                      "--public-only"])
            check(r.returncode == 0, "clean tree → OK (public-only authorized)")
        else:
            # grep-only variant still proves the sentinel path sans gitleaks:
            # use a private-required context with the fixture manifest.
            pass

        # ── private tier: caught AND redacted (§4.2) ──
        r = _run(["tree", privleak, "--context", "scrub"], private_manifest=priv)
        out = r.stdout + r.stderr
        check(r.returncode == 1 and "LEAK_FOUND" in r.stderr,
              "seeded private marker in tree → LEAK_FOUND")
        check("FIXTURE-PRIVATE" not in out and PRIVATE_MARK not in out,
              "private hit output is redacted (no value, no regex)")
        check("private/topology" in out, "private hit names only category + location")

        r = _run(["tree", clean, "--context", "scrub"], private_manifest=priv)
        check(r.returncode == 0, "clean tree with private tier loaded → OK")

        # ── worktree (row 7, library level) ──
        wt = os.path.join(work, "wt")
        _git("worktree", "add", "-q", "--detach", wt, "main", cwd=privleak)
        try:
            r = _run(["tree", wt, "--context", "scrub"], private_manifest=priv)
            check(r.returncode == 1 and "LEAK_FOUND" in r.stderr,
                  "worktree checkout is scanned, canary caught (not skipped)")
        finally:
            _git("worktree", "remove", "--force", wt, cwd=privleak)

        # ── codex P1-2 regression: private value in a tracked FILENAME ──
        nameleak = os.path.join(work, "nameleak")
        os.makedirs(nameleak)
        _git("init", "-q", "-b", "main", cwd=nameleak)
        with open(os.path.join(nameleak, f"{PRIVATE_MARK}.txt"), "w",
                  encoding="utf-8") as fh:
            fh.write(f"marker {PRIVATE_MARK} in a file named after it\n")
        _git("add", "-A", cwd=nameleak)
        _git("-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid",
             "commit", "-q", "-m", "fixture", cwd=nameleak)
        r = _run(["tree", nameleak, "--context", "scrub"], private_manifest=priv)
        out = r.stdout + r.stderr
        check(r.returncode == 1 and "LEAK_FOUND" in r.stderr,
              "private value in tracked filename → still LEAK_FOUND")
        check(PRIVATE_MARK not in out,
              "P1-2: private-hit locations are redacted (filename never printed)")
        env_ci = dict(os.environ, CI="1",
                      DMF_PATTERN_MANIFEST_PRIVATE=priv)
        r = subprocess.run([sys.executable, CLI, "tree", nameleak, "--context",
                            "scrub", "--show-private-hits"], env=env_ci,
                           capture_output=True, text=True)
        check(r.returncode == 3 and "CONFIG_ERROR" in r.stderr,
              "--show-private-hits refuses under CI")

        # ── codex P2-2 regression: private parity needs the legacy source ──
        inc = os.path.join(work, "fixture-include.sh")
        with open(inc, "w", encoding="utf-8") as fh:
            fh.write(PRIVATE_FIXTURE_INCLUDE)
        parity = os.path.join(os.path.dirname(HERE), "check-pattern-parity.py")
        r = subprocess.run(
            [sys.executable, parity, "--private", "--include", inc,
             "--legacy-gitleaks", "/nonexistent/gitleaks.local.toml"],
            env=dict(os.environ, DMF_PATTERN_MANIFEST_PRIVATE=priv),
            capture_output=True, text=True)
        check(r.returncode == 3 and "CONFIG_ERROR" in r.stderr,
              "private parity without the legacy gitleaks source → CONFIG_ERROR")
        r = subprocess.run(
            [sys.executable, parity, "--private", "--include", inc,
             "--legacy-gitleaks", "/nonexistent/gitleaks.local.toml",
             "--no-legacy-gitleaks"],
            env=dict(os.environ, DMF_PATTERN_MANIFEST_PRIVATE=priv),
            capture_output=True, text=True)
        check(r.returncode == 0,
              "private parity with the explicit --no-legacy-gitleaks opt-out → OK")

        # ── staged + range surfaces (need the pinned gitleaks binary) ──
        if not skip_gitleaks:
            staged = os.path.join(work, "staged")
            _make_repo(staged)
            with open(os.path.join(staged, "new.txt"), "w", encoding="utf-8") as fh:
                fh.write(f"marker {PRIVATE_MARK}\n")
            _git("add", "new.txt", cwd=staged)
            r = _run(["staged", "--repo", staged, "--context", "pre-commit"],
                     private_manifest=priv)
            out = r.stdout + r.stderr
            check(r.returncode == 1 and "LEAK_FOUND" in r.stderr,
                  "staged private marker → LEAK_FOUND (pre-commit surface)")
            check(PRIVATE_MARK not in out, "staged private hit is redacted")

            ranged = os.path.join(work, "ranged")
            _make_repo(ranged)
            with open(os.path.join(ranged, "later.txt"), "w", encoding="utf-8") as fh:
                fh.write(f"token = {PUBLIC_CANARY}\n")
            _git("add", "-A", cwd=ranged)
            _git("-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid",
                 "commit", "-q", "-m", "leaky commit", cwd=ranged)
            r = _run(["range", "main~1..main", "--repo", ranged,
                      "--context", "public-acceptance-fixture", "--public-only"])
            check(r.returncode == 1 and "LEAK_FOUND" in r.stderr,
                  "public sentinel in commit range → LEAK_FOUND (pre-push surface)")

            # ── codex P1-1 regression: RE2-invalid private regex must fail
            #    CONFIG_ERROR with the regex REDACTED (gitleaks panics quote
            #    config content verbatim; that output must never be relayed).
            badpriv = os.path.join(work, "private-badregex.toml")
            with open(badpriv, "w", encoding="utf-8") as fh:
                fh.write(PRIVATE_BADREGEX_MANIFEST)
            r = _run(["tree", clean, "--context", "export-scan"],
                     private_manifest=badpriv)
            out = r.stdout + r.stderr
            check(r.returncode == 3 and "CONFIG_ERROR" in r.stderr,
                  "P1-1: RE2-invalid private rule → CONFIG_ERROR (redacted validation)")
            check("(?=" not in out and "FIXTURE-PRIVATE" not in out,
                  "P1-1: the invalid private regex body never reaches output")

    leftovers = _merged_leftovers() - before_tmp
    check(not leftovers, "no ephemeral merged configs left behind (§5.1)")
    for path in leftovers:
        os.unlink(path)

    print(f"dmf-scan self-test: {passed} passed, {failed} failed"
          + (" (gitleaks cases skipped)" if skip_gitleaks else ""))
    return 0 if failed == 0 else 4
