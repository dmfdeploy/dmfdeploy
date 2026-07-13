#!/usr/bin/env python3
"""dmf_scan.py — the shared public-safety scan library (R1 spec §5–§6).

One implementation behind every gate entry point. Thin callers (the hooks,
scrub, export-scan, the dmf-env gate) supply only their trust CONTEXT; this
library owns manifest loading, the authorization-gated --public-only opt-out,
ephemeral merged gitleaks configs, pinned-gitleaks resolution, the git-grep
pass runner, worktree-safe repo detection, redacted private output, and the
machine-readable failure classes.

Spec: docs/plans/DMF Public-Safety Pattern Manifest Plan 2026-07-13.md
  §4.2 redaction   §5.1 ephemeral configs   §5.4 opt-out authorization
  §5.5 failure classes   §6 library/callers   §7 worktree detection

Failure classes (§5.5) — every exit is one of:
  0  OK
  1  LEAK_FOUND    a pattern matched scanned content
  3  CONFIG_ERROR  missing/invalid manifest or tool, bad context, or a
                   --public-only opt-out in a disallowed context
  4  DRIFT_ERROR   generated view != on-disk view (check mode)

Invoked via bin/dmf-scan; import-safe for tooling (the §9.1 parity checker
reuses the manifest loader).

NOTE (rollout §9): no production caller is switched to this library yet —
that is the follow-on dispatch, gated on the §9.1 parity report and the
operator's private-manifest bootstrap. Until then the old gates keep running.

CONTEXT IS CALLER-DECLARED, NOT PROVEN (codex P2-1): anyone invoking this CLI
by hand can declare an opt-out-capable context (`ci-public`, `fork`, …) and
run public-only. That is by design for the library layer — the §5.4 guarantee
is that the PRODUCTION WRAPPERS hardcode their own context and never pass
user-controlled context through. At the caller switchover, treat bin/dmf-scan
as a library/debug CLI, never as the authoritative local gate itself.
"""
import argparse
import hashlib
import io
import os
import re
import subprocess
import sys
import tarfile
import tempfile
import tomllib
import urllib.request

OK = 0
LEAK_FOUND = 1
CONFIG_ERROR = 3
DRIFT_ERROR = 4
_CLASS_LABEL = {LEAK_FOUND: "LEAK_FOUND", CONFIG_ERROR: "CONFIG_ERROR", DRIFT_ERROR: "DRIFT_ERROR"}

HERE = os.path.dirname(os.path.abspath(__file__))
UMBRELLA = os.path.dirname(os.path.dirname(HERE))
PUBLIC_MANIFEST = os.path.join(UMBRELLA, "patterns", "public-manifest.toml")
PUBLIC_GITLEAKS_CONFIG = os.path.join(UMBRELLA, ".gitleaks.toml")
PRIVATE_MANIFEST_DEFAULT = os.path.expanduser("~/.dmfdeploy/pattern-manifest.private.toml")

# ── Trust contexts (§5.2, §5.4). private_required: the private manifest MUST
#    load or the run is CONFIG_ERROR. public_only_allowed: the ONLY contexts
#    where the --public-only opt-out is a permitted capability.
CONTEXTS = {
    "pre-commit":                 {"private_required": True,  "public_only_allowed": False},
    "pre-push":                   {"private_required": True,  "public_only_allowed": False},
    "scrub":                      {"private_required": True,  "public_only_allowed": False},
    "export-scan":                {"private_required": True,  "public_only_allowed": False},
    "dmf-env":                    {"private_required": True,  "public_only_allowed": False},
    "ci-public":                  {"private_required": True,  "public_only_allowed": True},
    "fork":                       {"private_required": True,  "public_only_allowed": True},
    "public-acceptance-fixture":  {"private_required": True,  "public_only_allowed": True},
}
# NB: private_required is True even for ci-public/fork — "silence is never an
# opt-out" (§5.3). Their runs must PASS --public-only explicitly; a permitted
# context that omits it and has no private manifest fails CONFIG_ERROR.

# Contexts whose tree scan includes a gitleaks pass on top of the grep pass
# (their old surfaces ran gitleaks over an all-tracked scratch tree; scrub's
# surface is the tracked-content grep, gitleaks is export-scan's own step).
GITLEAKS_TREE_CONTEXTS = {"export-scan", "dmf-env", "public-acceptance-fixture", "ci-public", "fork"}

# ── Pinned gitleaks — the ONE version + sha shared by every context (§6,
#    Inconsistency #4). MUST match guard.yml / bin/export-scan.sh.
GITLEAKS_VERSION = "8.21.2"
GITLEAKS_ASSETS = {
    ("Darwin", "arm64"):  ("gitleaks_8.21.2_darwin_arm64.tar.gz",
                           "cad3de5dc9a4d5447d967a70a4d49499c557f04db028274cc324f9ff983f6502"),
    ("Linux", "x86_64"):  ("gitleaks_8.21.2_linux_x64.tar.gz",
                           "5bc41815076e6ed6ef8fbecc9d9b75bcae31f39029ceb55da08086315316e3ba"),
}


# Committed canary values may carry a '~' SPLICE anywhere inside: loaders
# strip it before use. This keeps provider-shaped canaries (ghp_…, xoxb-…,
# hvs.…) from matching provider push-protection scanners on the committed
# manifest — the same "assemble at runtime" discipline the test fixtures use.
CANARY_SPLICE = "~"


def canary_value(stored):
    return stored.replace(CANARY_SPLICE, "")


class ScanError(Exception):
    def __init__(self, cls, msg):
        super().__init__(msg)
        self.cls = cls


def _fail(cls, msg):
    raise ScanError(cls, msg)


# ── manifest loading ──────────────────────────────────────────────────────

def _load_toml(path, what):
    if not os.path.isfile(path):
        _fail(CONFIG_ERROR, f"{what} not found: {path}")
    try:
        with open(path, "rb") as fh:
            return tomllib.load(fh)
    except (tomllib.TOMLDecodeError, OSError) as exc:
        _fail(CONFIG_ERROR, f"cannot parse {what} {path}: {exc}")


def _validate_manifest(manifest, what):
    for entry in manifest.get("pattern", []):
        eid = entry.get("id")
        if not eid:
            _fail(CONFIG_ERROR, f"{what}: entry without id")
        if entry.get("category") not in ("secret", "topology", "identity", "context"):
            _fail(CONFIG_ERROR, f"{what}: {eid}: bad category")
        gl = entry.get("gitleaks", {})
        if gl:
            if gl.get("emit"):
                if gl.get("kind") not in ("custom", "override"):
                    _fail(CONFIG_ERROR, f"{what}: {eid}: emit=true needs kind custom|override")
            elif gl.get("covered_by") not in ("useDefault", "git-grep"):
                _fail(CONFIG_ERROR, f"{what}: {eid}: emit=false needs covered_by useDefault|git-grep")
        if "regex" in entry:
            try:
                re.compile(entry["regex"])
            except re.error as exc:
                _fail(CONFIG_ERROR, f"{what}: {eid}: regex does not compile: {exc}")
    return manifest


def load_public_manifest(path=PUBLIC_MANIFEST):
    return _validate_manifest(_load_toml(path, "public manifest"), "public manifest")


def private_manifest_path():
    return os.environ.get("DMF_PATTERN_MANIFEST_PRIVATE", PRIVATE_MANIFEST_DEFAULT)


def load_private_manifest():
    """Fail-closed: a required context calls this unconditionally (§5.3)."""
    path = private_manifest_path()
    if not os.path.isfile(path):
        _fail(CONFIG_ERROR,
              f"private pattern manifest missing/unreadable: {path} — required in "
              "this context; install it (or, in an authorized public context "
              "only, pass --public-only)")
    return _validate_manifest(_load_toml(path, "private manifest"), "private manifest")


# ── context authorization (§5.4) ──────────────────────────────────────────

def authorize(context, public_only):
    if context not in CONTEXTS:
        _fail(CONFIG_ERROR, f"unknown scan context '{context}' — "
                            f"known: {', '.join(sorted(CONTEXTS))}")
    ctx = CONTEXTS[context]
    if public_only and not ctx["public_only_allowed"]:
        _fail(CONFIG_ERROR,
              f"--public-only/DMF_SCAN_PUBLIC_ONLY is not permitted in context "
              f"'{context}' — the private manifest is required here (§5.4)")
    if public_only:
        print(f"scan: PUBLIC-ONLY authorized for {context}; private "
              "identity/topology rules absent by design")
    return ctx


# ── repo/worktree detection (§7 — Python mirror of bin/lib/dmf-repo-detect.sh)

def is_repo_root(path):
    """True iff path is the top of its own work tree (clone OR linked worktree)."""
    try:
        r = subprocess.run(["git", "-C", path, "rev-parse", "--show-toplevel"],
                           capture_output=True, text=True)
    except FileNotFoundError:
        _fail(CONFIG_ERROR, "git not found — required for repo detection")
    if r.returncode != 0 or not r.stdout.strip():
        return False
    return os.path.realpath(r.stdout.strip()) == os.path.realpath(path)


# ── pinned gitleaks (§6: one pinned version + sha for every context) ─────

def resolve_pinned_gitleaks():
    key = (os.uname().sysname, os.uname().machine)
    if key not in GITLEAKS_ASSETS:
        _fail(CONFIG_ERROR, f"no pinned gitleaks {GITLEAKS_VERSION} for {key[0]}/{key[1]}")
    asset, sha256 = GITLEAKS_ASSETS[key]
    cache = os.path.join(tempfile.gettempdir(), f"dmf-gitleaks-{GITLEAKS_VERSION}")
    binary = os.path.join(cache, "gitleaks")
    if not os.access(binary, os.X_OK):
        os.makedirs(cache, exist_ok=True)
        url = (f"https://github.com/gitleaks/gitleaks/releases/download/"
               f"v{GITLEAKS_VERSION}/{asset}")
        try:
            with urllib.request.urlopen(url, timeout=60) as resp:
                blob = resp.read()
        except OSError as exc:
            _fail(CONFIG_ERROR, f"pinned gitleaks download failed: {exc}")
        if hashlib.sha256(blob).hexdigest() != sha256:
            _fail(CONFIG_ERROR, f"pinned gitleaks {GITLEAKS_VERSION} sha256 mismatch")
        with tarfile.open(fileobj=io.BytesIO(blob), mode="r:gz") as tar:
            member = tar.getmember("gitleaks")
            tar.extract(member, cache)
        os.chmod(binary, 0o755)
    r = subprocess.run([binary, "version"], capture_output=True, text=True)
    if r.returncode != 0 or r.stdout.strip() != GITLEAKS_VERSION:
        _fail(CONFIG_ERROR,
              f"pinned gitleaks is not {GITLEAKS_VERSION} (got: {r.stdout.strip()!r})")
    return binary


# ── ephemeral merged config (§5.1) ────────────────────────────────────────

def _gen_module():
    import importlib.util
    gen_path = os.path.join(UMBRELLA, "bin", "gen-gitleaks-rules.py")
    spec = importlib.util.spec_from_file_location("gen_gitleaks_rules", gen_path)
    gen = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gen)
    return gen


def _render_rule_blocks(entries):
    """Render entries as [[rules]] blocks, reusing the public generator's
    renderer so the views cannot diverge."""
    gen = _gen_module()
    return "\n\n".join("\n".join(gen.render_rule(e)) for e in entries)


def _render_private_rules(private_manifest):
    return _render_rule_blocks([e for e in private_manifest.get("pattern", [])
                                if e.get("gitleaks", {}).get("emit", False)])


def _validate_private_rules(private_manifest):
    """REDACTED RE2 validation of private rules (codex P1-1): Python `re` is
    not RE2, so a private regex can compile here yet make gitleaks panic —
    and the panic message quotes the literal regex. Probe each config against
    an empty tree BEFORE any real scan and report failures by category +
    id-hash only, never the regex body."""
    entries = [e for e in private_manifest.get("pattern", [])
               if e.get("gitleaks", {}).get("emit", False)]
    if not entries:
        return
    binary = resolve_pinned_gitleaks()

    def probe(subset):
        fd, cfg = tempfile.mkstemp(prefix="dmf-scan-probe-", suffix=".toml",
                                   dir=tempfile.gettempdir())
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                fh.write(_render_rule_blocks(subset))
            with tempfile.TemporaryDirectory() as empty:
                r = subprocess.run([binary, "detect", "--no-git", "--source", empty,
                                    "--config", cfg, "--no-banner"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return r.returncode in (0, 1)
        finally:
            os.unlink(cfg)

    if probe(entries):
        return
    for i, entry in enumerate(entries):
        if not probe([entry]):
            id_hash = hashlib.sha256(entry.get("id", "").encode("utf-8")).hexdigest()[:12]
            _fail(CONFIG_ERROR,
                  f"private rule #{i} (category={entry.get('category')}, "
                  f"id-hash={id_hash}) fails gitleaks/RE2 validation — regex "
                  "redacted (§4.2); fix it in the private manifest")
    _fail(CONFIG_ERROR, "private rules fail gitleaks validation in combination "
                        "(regexes redacted §4.2); fix the private manifest")


def write_merged_config(base_config_path, private_manifest):
    """Compose base public config + private rules into a temp file OUTSIDE any
    repo tree. Caller must delete (scan_* wrap this in try/finally). Private
    rules are RE2-validated (redacted) first — see _validate_private_rules."""
    if not os.path.isfile(base_config_path):
        _fail(CONFIG_ERROR, f"gitleaks config not found: {base_config_path}")
    if private_manifest is not None:
        _validate_private_rules(private_manifest)
    with open(base_config_path, "r", encoding="utf-8") as fh:
        text = fh.read()
    if private_manifest is not None:
        text += ("\n# >>> DMF EPHEMERAL PRIVATE RULES (merged at run time, never "
                 "committed) >>>\n")
        text += _render_private_rules(private_manifest)
        text += "\n# <<< DMF EPHEMERAL PRIVATE RULES <<<\n"
    fd, path = tempfile.mkstemp(prefix="dmf-scan-merged-", suffix=".toml",
                                dir=tempfile.gettempdir())
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)
    return path


# ── the git-grep pass runner ──────────────────────────────────────────────

def _grep_entries(manifest, private):
    """Entries this manifest contributes to the grep pass: everything with a
    regex declared for the grep engine (pcre). Tag each with its tier."""
    out = []
    for entry in manifest.get("pattern", []):
        if "regex" in entry and "pcre" in entry.get("engines", []):
            out.append((entry, private))
    return out


def _scan_allowlist(*manifests):
    pats = []
    for m in manifests:
        if m:
            pats.extend(m.get("scan", {}).get("allowlist_paths", []))
    return pats


def _is_allowlisted(path, global_patterns, entry_patterns):
    for pat in list(global_patterns) + list(entry_patterns):
        if re.search(pat, path):
            return True
    return False


def _git_grep(tree, regex, ignore_case, cached=False, pathspecs=None):
    cmd = ["git", "-C", tree, "grep", "-nI"]
    cmd.append("-iP" if ignore_case else "-P")
    if cached:
        cmd.append("--cached")
    cmd += ["-e", regex]
    if pathspecs:
        cmd += ["--"] + pathspecs
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode not in (0, 1):
        # Loud, never a silent false-negative (same posture as the generator).
        _fail(CONFIG_ERROR, f"git grep failed (rc={r.returncode}) in {tree}: "
                            f"{r.stderr.strip()[:200]}")
    return [ln for ln in r.stdout.splitlines() if ln]


def grep_pass(tree, entries, allowlist, no_allowlist, strict, cached=False,
              pathspecs=None, show_private_hits=False):
    """Run every entry over the tree's tracked content. Returns (blocking_hits,
    lines_to_print) with private-entry hits REDACTED (§4.2)."""
    blocking = 0
    lines = []
    for entry, private in entries:
        hits = _git_grep(tree, entry["regex"],
                         not entry.get("case_sensitive", True),
                         cached=cached, pathspecs=pathspecs)
        entry_allow = entry.get("gitleaks", {}).get("allowlist_paths", [])
        kept = []
        for hit in hits:
            fname = hit.split(":", 1)[0]
            if not no_allowlist and _is_allowlisted(fname, allowlist, entry_allow):
                continue
            kept.append(hit)
        if not kept:
            continue
        informational = entry.get("severity", "blocking") == "informational" and not strict
        if not informational:
            blocking += len(kept)
        if private:
            # §4.2 + codex P1-2: never print private regex bodies,
            # descriptions, matched text — or LOCATIONS. A tracked filename
            # can itself contain the private value, so raw paths leak. The
            # default is category + count only; --show-private-hits is a
            # LOCAL-ONLY diagnostic (refused under CI, see main()).
            lines.append(f"  [private/{entry['category']}] {len(kept)} match(es) "
                         "(locations redacted — re-run locally with "
                         "--show-private-hits to inspect)")
            if show_private_hits:
                for hit in kept[:5]:
                    lines.append(f"      {hit}")
                if len(kept) > 5:
                    lines.append(f"      ... ({len(kept) - 5} more)")
            continue
        label = "informational" if informational else "BLOCKING"
        lines.append(f"  [{entry['id']}] {entry.get('description', '')} — "
                     f"{len(kept)} match(es) ({label})")
        for hit in kept[:5]:
            lines.append(f"      {hit}")
        if len(kept) > 5:
            lines.append(f"      ... ({len(kept) - 5} more)")
    return blocking, lines


# ── gitleaks passes ───────────────────────────────────────────────────────

def _run_gitleaks(args, cwd=None, private=False):
    binary = resolve_pinned_gitleaks()
    r = subprocess.run([binary, *args], cwd=cwd, capture_output=True, text=True)
    if r.returncode == 0:
        return False
    # gitleaks exits 1 on findings; anything else is a tool error → fail loud.
    if r.returncode != 1:
        if private:
            # codex P1-1: gitleaks tool/parse errors quote config content
            # verbatim (e.g. a regexp panic prints the literal regex) and
            # --redact does NOT cover them. With private rules in the merged
            # config, NEVER relay raw tool output — the redacted per-rule
            # validation (_validate_private_rules) names the culprit safely.
            _fail(CONFIG_ERROR,
                  f"gitleaks failed (rc={r.returncode}) with a private-rules "
                  "merged config — tool output suppressed (§4.2)")
        _fail(CONFIG_ERROR, f"gitleaks failed (rc={r.returncode}): "
                            f"{(r.stderr or r.stdout).strip()[:300]}")
    return True


# ── scan surfaces (§6 caller table) ───────────────────────────────────────

def _load_tiers(context_name, public_only):
    ctx = authorize(context_name, public_only)
    public = load_public_manifest()
    private = None
    if not public_only:
        # Fail-closed for every context that did not explicitly opt out —
        # including the opt-out-capable ones (§5.3 "silence is never an opt-out").
        if ctx["private_required"]:
            private = load_private_manifest()
    return public, private


def scan_tree(tree, context_name, public_only, no_allowlist=False, strict=False,
              show_private_hits=False):
    public, private = _load_tiers(context_name, public_only)
    if not is_repo_root(tree):
        _fail(CONFIG_ERROR, f"not a git repo root (clone or worktree): {tree}")
    entries = _grep_entries(public, private=False)
    if private:
        entries += _grep_entries(private, private=True)
    allowlist = _scan_allowlist(public, private)
    blocking, lines = grep_pass(tree, entries, allowlist, no_allowlist, strict,
                                show_private_hits=show_private_hits)
    for ln in lines:
        print(ln)
    leaked = blocking > 0
    if context_name in GITLEAKS_TREE_CONTEXTS:
        merged = write_merged_config(_tree_config(tree), private)
        try:
            if _run_gitleaks(["detect", "--no-git", "--source", ".", "--config", merged,
                              "--no-banner", "--redact", "--exit-code", "1"],
                             cwd=tree, private=private is not None):
                print("  [gitleaks] findings in tree (redacted; re-run gitleaks -v to inspect)")
                leaked = True
        finally:
            os.unlink(merged)
    if leaked:
        _fail(LEAK_FOUND, f"tree scan found blocking matches in {tree}")
    print(f"OK: tree scan clean ({tree})")
    return OK


def _tree_config(tree):
    own = os.path.join(tree, ".gitleaks.toml")
    return own if os.path.isfile(own) else PUBLIC_GITLEAKS_CONFIG


def scan_staged(context_name, public_only, repo=".", no_allowlist=False, strict=False,
                show_private_hits=False):
    public, private = _load_tiers(context_name, public_only)
    r = subprocess.run(["git", "-C", repo, "diff", "--cached", "--name-only",
                        "--diff-filter=ACMRT", "-z"], capture_output=True, text=True)
    if r.returncode != 0:
        _fail(CONFIG_ERROR, f"not a git repo: {repo}")
    staged = [p for p in r.stdout.split("\0") if p]
    if not staged:
        print("OK: nothing staged")
        return OK
    entries = _grep_entries(public, private=False)
    if private:
        entries += _grep_entries(private, private=True)
    allowlist = _scan_allowlist(public, private)
    blocking, lines = grep_pass(repo, entries, allowlist, no_allowlist, strict,
                                cached=True, pathspecs=staged,
                                show_private_hits=show_private_hits)
    for ln in lines:
        print(ln)
    leaked = blocking > 0
    merged = write_merged_config(_tree_config(repo), private)
    try:
        if _run_gitleaks(["protect", "--staged", "--config", merged,
                          "--no-banner", "--redact"], cwd=repo,
                         private=private is not None):
            print("  [gitleaks] findings in staged changes (redacted)")
            leaked = True
    finally:
        os.unlink(merged)
    if leaked:
        _fail(LEAK_FOUND, "staged changes contain blocking matches")
    print("OK: staged changes clean")
    return OK


def scan_range(log_opts, context_name, public_only, repo="."):
    public, private = _load_tiers(context_name, public_only)
    del public  # range surface is gitleaks-only (old pre-push parity)
    merged = write_merged_config(_tree_config(repo), private)
    try:
        if _run_gitleaks(["detect", "--source", ".", f"--log-opts={log_opts}",
                          "--config", merged, "--no-banner", "--redact",
                          "--exit-code", "1"], cwd=repo,
                         private=private is not None):
            _fail(LEAK_FOUND, f"commit range {log_opts} contains blocking matches")
    finally:
        os.unlink(merged)
    print(f"OK: commit range clean ({log_opts})")
    return OK


# ── check mode (§4 drift; private region only once migrated to markers) ──

def check_views():
    r = subprocess.run([sys.executable, os.path.join(UMBRELLA, "bin", "gen-gitleaks-rules.py"),
                        "--check"], capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    sys.stderr.write(r.stderr)
    if r.returncode != 0:
        raise SystemExit(r.returncode)  # class line already printed by the generator
    priv_path = private_manifest_path()
    local_cfg = os.path.join(UMBRELLA, ".gitleaks.local.toml")
    if os.path.isfile(priv_path) and os.path.isfile(local_cfg):
        with open(local_cfg, "r", encoding="utf-8") as fh:
            text = fh.read()
        # Only check once the local config is generator-managed (has markers) —
        # pre-migration hand-authored files are the old world, checked by the
        # §9.1 parity tool instead.
        begin = "# >>> DMF-GENERATED RULES (do not edit — bin/gen-gitleaks-rules.py) >>>"
        end = "# <<< DMF-GENERATED RULES <<<"
        if begin in text and end in text:
            region = text.split(begin, 1)[1].split(end, 1)[0].strip("\n")
            want = _render_private_rules(load_private_manifest()).strip("\n")
            if _redacted_digest(region) != _redacted_digest(want):
                # §4.2: never diff private content literally.
                _fail(DRIFT_ERROR, ".gitleaks.local.toml rules region is out of sync "
                                   "with the private manifest (redacted comparison; "
                                   "regenerate locally)")
            print("OK: .gitleaks.local.toml rules region matches the private manifest")
    return OK


def _redacted_digest(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


# ── CLI ───────────────────────────────────────────────────────────────────

def main(argv):
    ap = argparse.ArgumentParser(
        prog="dmf-scan",
        description="DMF public-safety scan library CLI (R1 spec §6). "
                    "Exit classes: 0 OK, 1 LEAK_FOUND, 3 CONFIG_ERROR, 4 DRIFT_ERROR.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    def add_common(p):
        # No argparse choices=: an unknown context must exit CONFIG_ERROR (3)
        # with a CLASS line (§5.5), not argparse's usage error (2).
        p.add_argument("--context", required=True,
                       help="caller-declared trust context (§5.2)")
        p.add_argument("--public-only", action="store_true",
                       default=os.environ.get("DMF_SCAN_PUBLIC_ONLY") == "1",
                       help="authorized public-tier-only run (§5.4 allowlist enforced)")
        p.add_argument("--no-allowlist", action="store_true",
                       default=os.environ.get("DMF_SCAN_NO_ALLOWLIST") == "1",
                       help="disable path allowlists (raw sweep)")
        p.add_argument("--strict", action="store_true",
                       help="informational-severity entries also block")
        p.add_argument("--show-private-hits", action="store_true",
                       help="LOCAL-ONLY diagnostic: print private-hit locations "
                            "(refused under CI — §4.2)")

    p_tree = sub.add_parser("tree", help="scan a repo/worktree's tracked content")
    p_tree.add_argument("path")
    add_common(p_tree)

    p_staged = sub.add_parser("staged", help="scan staged changes (pre-commit surface)")
    p_staged.add_argument("--repo", default=".")
    add_common(p_staged)

    p_range = sub.add_parser("range", help="scan a commit range (pre-push surface)")
    p_range.add_argument("log_opts", metavar="LOG_OPTS", help="e.g. main..HEAD")
    p_range.add_argument("--repo", default=".")
    add_common(p_range)

    sub.add_parser("check", help="generated-view drift check (public literal, private redacted)")

    p_st = sub.add_parser("self-test", help="fixture-based self-test (rows 10/11 + canaries)")
    p_st.add_argument("--skip-gitleaks", action="store_true",
                      help="skip cases needing the pinned gitleaks binary")

    args = ap.parse_args(argv)
    try:
        if getattr(args, "show_private_hits", False) and (
                os.environ.get("CI") or os.environ.get("GITHUB_ACTIONS")):
            _fail(CONFIG_ERROR, "--show-private-hits refuses to run in CI (§4.2)")
        if args.cmd == "tree":
            return scan_tree(args.path, args.context, args.public_only,
                             args.no_allowlist, args.strict,
                             show_private_hits=args.show_private_hits)
        if args.cmd == "staged":
            return scan_staged(args.context, args.public_only, args.repo,
                               args.no_allowlist, args.strict,
                               show_private_hits=args.show_private_hits)
        if args.cmd == "range":
            return scan_range(args.log_opts, args.context, args.public_only, args.repo)
        if args.cmd == "check":
            return check_views()
        if args.cmd == "self-test":
            from dmf_scan_selftest import run_self_test
            return run_self_test(skip_gitleaks=args.skip_gitleaks)
    except ScanError as exc:
        print(f"CLASS: {_CLASS_LABEL[exc.cls]}: {exc}", file=sys.stderr)
        return exc.cls
    return CONFIG_ERROR


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
