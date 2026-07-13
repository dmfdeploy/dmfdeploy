#!/usr/bin/env python3
"""gen-gitleaks-rules.py — generate the marker-fenced [[rules]] region of a
gitleaks config from patterns/public-manifest.toml (R1 spec §3.2, §4, §4.3).

HYBRID (partial-file) generation: only the bytes between
    # >>> DMF-GENERATED RULES (do not edit) >>>
    # <<< DMF-GENERATED RULES <<<
are owned by this generator. The prose header, `[extend] useDefault`, and the
global `[allowlist]` above the opening marker are hand-authored and never touched.

Modes (per manifest entry's [pattern.gitleaks]):
  - emit=true, kind="custom"   → full [[rules]] block (regex + desc + tags + allowlist)
  - emit=true, kind="override" → tunes a default rule by id, NO regex, allowlist only
  - emit=false, covered_by=... → no gitleaks rule (scrub/git-grep parity only)

Usage:
  bin/gen-gitleaks-rules.py --emit          # rewrite the region in .gitleaks.toml
  bin/gen-gitleaks-rules.py --check         # verify the region matches (no write)
  bin/gen-gitleaks-rules.py --self-test     # engine match-tests + useDefault proof
  bin/gen-gitleaks-rules.py --print         # print the region to stdout

Exit codes / classes (R1 §5.5):
  0            OK
  3 CONFIG_ERROR   manifest missing/unparseable/invalid, or a tool is missing
  4 DRIFT_ERROR    generated region != on-disk region, or a canary match disagreed
"""
import sys
import os
import subprocess
import tomllib

OK = 0
CONFIG_ERROR = 3
DRIFT_ERROR = 4

BEGIN = "# >>> DMF-GENERATED RULES (do not edit — bin/gen-gitleaks-rules.py) >>>"
END = "# <<< DMF-GENERATED RULES <<<"

HERE = os.path.dirname(os.path.abspath(__file__))
UMBRELLA = os.path.dirname(HERE)
MANIFEST = os.path.join(UMBRELLA, "patterns", "public-manifest.toml")
CONFIG = os.path.join(UMBRELLA, ".gitleaks.toml")


def die(cls, msg):
    label = {CONFIG_ERROR: "CONFIG_ERROR", DRIFT_ERROR: "DRIFT_ERROR"}[cls]
    print(f"CLASS: {label}: {msg}", file=sys.stderr)
    sys.exit(cls)


def load_manifest(path):
    if not os.path.isfile(path):
        die(CONFIG_ERROR, f"manifest not found: {path}")
    try:
        with open(path, "rb") as fh:
            manifest = tomllib.load(fh)
    except (tomllib.TOMLDecodeError, OSError) as exc:
        die(CONFIG_ERROR, f"cannot parse {path}: {exc}")
    for entry in manifest.get("pattern", []):
        gl = entry.get("gitleaks", {})
        if gl and not gl.get("emit", False) and \
                gl.get("covered_by") not in ("useDefault", "git-grep"):
            die(CONFIG_ERROR, f"entry {entry.get('id')}: emit=false requires "
                              "covered_by = \"useDefault\" | \"git-grep\"")
    return manifest


def render_paths(paths):
    """Reproduce the hand-formatting: single element => no trailing comma;
    multiple elements => a trailing comma on every line."""
    out = ["paths = ["]
    if len(paths) == 1:
        out.append(f"    '''{paths[0]}'''")
    else:
        for p in paths:
            out.append(f"    '''{p}''',")
    out.append("]")
    return out


def render_rule(entry):
    gl = entry.get("gitleaks", {})
    lines = []
    for cline in gl.get("comment", "").splitlines():
        lines.append(f"# {cline}" if cline else "#")
    lines.append("[[rules]]")
    lines.append(f'id = "{entry["id"]}"')
    kind = gl.get("kind")
    if kind == "custom":
        lines.append(f'description = "{entry["description"]}"')
        lines.append(f"regex = '''{entry['regex']}'''")
        tags = gl.get("tags", [])
        lines.append("tags = [" + ", ".join(f'"{t}"' for t in tags) + "]")
    elif kind != "override":
        die(CONFIG_ERROR, f"entry {entry['id']}: emit=true needs kind custom|override")
    # allowlist (present for both custom and override in the current config)
    if "allowlist_paths" in gl:
        lines.append("[[rules.allowlists]]")
        lines.append(f'description = "{gl["allowlist_description"]}"')
        lines.extend(render_paths(gl["allowlist_paths"]))
    return lines


def render_region(manifest):
    blocks = []
    for entry in manifest.get("pattern", []):
        gl = entry.get("gitleaks", {})
        if not gl.get("emit", False):
            continue
        blocks.append("\n".join(render_rule(entry)))
    # rules separated by a single blank line, matching the hand-authored file
    return "\n\n".join(blocks)


def split_config(text):
    """Return (prefix_incl_begin_marker, region, suffix_incl_end_marker) or None."""
    lines = text.split("\n")
    try:
        b = next(i for i, ln in enumerate(lines) if ln.strip() == BEGIN)
        e = next(i for i, ln in enumerate(lines) if ln.strip() == END)
    except StopIteration:
        return None
    if e <= b:
        die(CONFIG_ERROR, "END marker precedes BEGIN marker in .gitleaks.toml")
    region = "\n".join(lines[b + 1:e])
    return lines[:b + 1], region, lines[e:]


def read_config():
    if not os.path.isfile(CONFIG):
        die(CONFIG_ERROR, f".gitleaks.toml not found: {CONFIG}")
    with open(CONFIG, "r", encoding="utf-8") as fh:
        return fh.read()


def cmd_print(manifest):
    print(render_region(manifest))
    return OK


def cmd_check(manifest):
    parts = split_config(read_config())
    if parts is None:
        die(CONFIG_ERROR, "no DMF-GENERATED RULES markers in .gitleaks.toml — run --emit once")
    _, on_disk, _ = parts
    want = render_region(manifest)
    if on_disk.strip("\n") != want.strip("\n"):
        die(DRIFT_ERROR, ".gitleaks.toml rules region is out of sync with the manifest "
                         "(run bin/gen-gitleaks-rules.py --emit and commit)")
    print("OK: .gitleaks.toml rules region matches the manifest")
    return OK


def cmd_emit(manifest):
    parts = split_config(read_config())
    if parts is None:
        die(CONFIG_ERROR, "no DMF-GENERATED RULES markers in .gitleaks.toml — add them once")
    prefix, _, suffix = parts
    region = render_region(manifest)
    new = "\n".join(prefix + [region] + suffix)
    with open(CONFIG, "w", encoding="utf-8") as fh:
        fh.write(new)
    print("wrote .gitleaks.toml rules region from the manifest")
    return OK


# ── self-test: prove match SEMANTICS per declared engine (R1 §4.1, §4.3) ──

def _regex_matches(pattern, text, ignore_case, extended):
    """True iff the regex matches text under the SAME engine the gates use:
    `git grep -P` (PCRE — also validates RE2-safe patterns) or `git grep -E`
    (ERE). `git grep --no-index` ships PCRE on macOS + Linux (unlike BSD grep,
    which lacks -P). Run with cwd=tempdir + a RELATIVE path: an absolute pathspec
    trips a `git grep --no-index` bug ('environment hasn't been setup')."""
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        with open(os.path.join(d, "probe.txt"), "w", encoding="utf-8") as fh:
            fh.write(text + "\n")
        flags = ["-q", "--no-index"]
        flags.append("-E" if extended else "-P")
        if ignore_case:
            flags.append("-i")
        try:
            r = subprocess.run(["git", "grep", *flags, "-e", pattern, "--", "probe.txt"],
                               cwd=d, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except FileNotFoundError:
            die(CONFIG_ERROR, "git not found — required for engine match-tests")
        # 0 = match, 1 = no match; anything else is a tool/engine error — fail
        # LOUD rather than silently returning "no match" (the false-negative trap).
        if r.returncode not in (0, 1):
            die(CONFIG_ERROR,
                f"git grep failed (rc={r.returncode}) validating /{pattern}/ — "
                "engine unavailable; cannot prove match semantics")
        return r.returncode == 0


def _gitleaks_catches(value, config_path):
    """True iff gitleaks (with the given config) flags `value` in a temp tree.
    The probe line is keyword-NEUTRAL ('x = ...') so entropy/keyword-gated
    default rules (generic-api-key) can't piggyback on the probe's own wording
    — the useDefault proof must hold on the bare value shape."""
    gl = _which_gitleaks()
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        with open(os.path.join(d, "probe.txt"), "w", encoding="utf-8") as fh:
            fh.write(f'x = "{value}"\n')
        r = subprocess.run([gl, "detect", "--no-git", "--source", d,
                            "--config", config_path, "--no-banner", "--redact",
                            "--exit-code", "1"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return r.returncode != 0


def _which_gitleaks():
    """The PINNED gitleaks (one version + sha for every context, R1 §6) via
    the scan library's resolver — never an unpinned system binary (default
    rulesets drift between versions; that skew let placeholders through once)."""
    sys.path.insert(0, os.path.join(HERE, "lib"))
    try:
        from dmf_scan import resolve_pinned_gitleaks, ScanError
    except ImportError as exc:
        die(CONFIG_ERROR, f"cannot import bin/lib/dmf_scan.py: {exc}")
    try:
        return resolve_pinned_gitleaks()
    except ScanError as exc:
        die(exc.cls, str(exc))


def cmd_self_test(manifest):
    """Run each entry's canaries under its declared engines. custom entries with a
    regex are validated with grep engines (pcre/ere) + gitleaks (re2). emit=false
    covered_by=useDefault entries are proven against the real merged config."""
    passed = failed = 0

    def check(cond, label):
        nonlocal passed, failed
        if cond:
            passed += 1
        else:
            failed += 1
            print(f"  ✗ {label}", file=sys.stderr)

    for entry in manifest.get("pattern", []):
        gl = entry.get("gitleaks", {})
        eid = entry["id"]
        engines = entry.get("engines", [])
        # Stored canaries may carry the '~' splice (defeats provider
        # push-protection matching on the committed manifest) — strip it.
        pos = [v.replace("~", "") for v in entry.get("positive_canaries", [])]
        neg = [v.replace("~", "") for v in entry.get("negative_canaries", [])]
        cs = entry.get("case_sensitive", True)

        if "regex" in entry:
            if not pos:
                check(False, f"{eid}: custom entry has a regex but no positive_canaries")
            rx = entry["regex"]
            for eng in engines:
                if eng == "re2":
                    # RE2 ~ PCRE for these shapes; validate via grep -P.
                    for v in pos:
                        check(_regex_matches(rx, v, not cs, False),
                              f"{eid}: positive '{v}' should match under re2")
                    for v in neg:
                        check(not _regex_matches(rx, v, not cs, False),
                              f"{eid}: negative '{v}' should NOT match under re2")
                elif eng == "pcre":
                    for v in pos:
                        check(_regex_matches(rx, v, not cs, False),
                              f"{eid}: positive '{v}' should match under pcre")
                    for v in neg:
                        check(not _regex_matches(rx, v, not cs, False),
                              f"{eid}: negative '{v}' should NOT match under pcre")
                elif eng == "ere":
                    for v in pos:
                        check(_regex_matches(rx, v, not cs, True),
                              f"{eid}: positive '{v}' should match under ere")
                    for v in neg:
                        check(not _regex_matches(rx, v, not cs, True),
                              f"{eid}: negative '{v}' should NOT match under ere")
                else:
                    check(False, f"{eid}: unknown engine '{eng}'")

        # useDefault coverage proof: prove the DEFAULT pack catches the shape
        # (positives caught, negatives NOT) against the real merged config.
        if gl.get("emit") is False and gl.get("covered_by") == "useDefault":
            for v in pos:
                check(_gitleaks_catches(v, CONFIG),
                      f"{eid}: useDefault should catch '{v}' but did not")
            for v in neg:
                check(not _gitleaks_catches(v, CONFIG),
                      f"{eid}: negative '{v}' should NOT be caught under useDefault")

    print(f"gen-gitleaks-rules self-test: {passed} passed, {failed} failed")
    return OK if failed == 0 else DRIFT_ERROR


def main(argv):
    if len(argv) != 1 or argv[0] not in ("--emit", "--check", "--print", "--self-test"):
        print(__doc__)
        return CONFIG_ERROR
    manifest = load_manifest(MANIFEST)
    return {
        "--emit": cmd_emit,
        "--check": cmd_check,
        "--print": cmd_print,
        "--self-test": cmd_self_test,
    }[argv[0]](manifest)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
