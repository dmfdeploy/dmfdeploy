#!/usr/bin/env python3
"""check-pattern-parity.py — old→new structural parity gate (R1 spec §9.1).

Proves the manifest fold-in lost no coverage against the OLD pattern sources
— structurally, not by comparing clean-tree scan output (both old and new can
report "no hits" while one silently weakened a pattern).

Old world parsed:
  PUBLIC  (--public, CI-safe, literal output):
    - bin/scrub-public-repos.sh in-script arrays (SECRET/IDENTITY/TOPOLOGY/
      CONTEXT_PATTERNS), each atom taken EXACTLY as the old consumer used it:
      'PCRE|desc' split at the FIRST pipe — the §1.4 truncation included,
      because the truncated regex IS what actually ran.
    - scrub's ALLOWLIST_PATHS vs the manifest's [scan].allowlist_paths
      (the two must stay identical until the caller switchover retires
      scrub's copy).
  PRIVATE (--private, operator-local, REDACTED output §4.2):
    - the operator include's DMF_PRIVATE_{IDENTITY,TOPOLOGY}_PATTERNS arrays
      (PCRE atoms, scrub consumer) and DMF_PRIVATE_{IDENTITY,TOPOLOGY}_REGEX
      combined ERE strings (env-gate consumer; identity ran case-INSENSITIVE
      via `git grep -nIiE`, topology case-sensitive — §9.1 step 2).
    - the hand-authored .gitleaks.local.toml [[rules]] set.

Per old atom the tool requires a manifest entry matching on: category,
normalized regex hash, the consumer's engine in `engines`, and the effective
case flag; old case-insensitive atoms additionally require upper+lower
variants of a positive canary (§9.1 step 4). Grep-participating manifest
entries with NO old counterpart must carry [pattern.parity] status="addition".

Exit: 0 parity green; 4 DRIFT_ERROR on any mismatch; 3 CONFIG_ERROR.
Green in --private mode is the hard precondition to the caller switchover
(rollout §9 step 3).
"""
import argparse
import hashlib
import os
import re
import subprocess
import sys
import tomllib

HERE = os.path.dirname(os.path.abspath(__file__))
UMBRELLA = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(HERE, "lib"))
from dmf_scan import (  # noqa: E402
    OK, CONFIG_ERROR, DRIFT_ERROR, ScanError, canary_value,
    load_public_manifest, load_private_manifest, private_manifest_path,
)

SCRUB = os.path.join(UMBRELLA, "bin", "scrub-public-repos.sh")
PRIVATE_INCLUDE_DEFAULT = os.path.expanduser("~/.dmfdeploy/scrub-private-patterns.sh")
LOCAL_GITLEAKS = os.path.join(UMBRELLA, ".gitleaks.local.toml")

CATEGORY_BY_ARRAY = {
    "SECRET_PATTERNS": "secret",
    "TOPOLOGY_PATTERNS": "topology",
    "IDENTITY_PATTERNS": "identity",
    "CONTEXT_PATTERNS": "context",
}


class Atom:
    """One old-world pattern as one old consumer effectively ran it."""

    def __init__(self, regex, category, engine, case_sensitive, source):
        # Inline (?i) is the scrub arrays' case mechanism — strip it into the
        # flag so the normalized hash compares case-neutrally (§9.1 step 2).
        if regex.startswith("(?i)"):
            regex = regex[4:]
            case_sensitive = False
        self.regex = regex
        self.category = category
        self.engine = engine
        self.case_sensitive = case_sensitive
        self.source = source

    @property
    def digest(self):
        return hashlib.sha256(self.regex.encode("utf-8")).hexdigest()

    def redacted(self):
        return (f"{self.category}/{self.engine}/"
                f"{'cs' if self.case_sensitive else 'ci'}/{self.digest[:12]} "
                f"({self.source})")


# ── old-source parsers ────────────────────────────────────────────────────

def parse_shell_array_literals(script_text, name):
    """Extract the single-quoted literal entries of NAME=( ... ) blocks."""
    if re.search(rf"^{re.escape(name)}=\(\s*\)\s*$", script_text, re.M):
        return []
    m = re.search(rf"^{re.escape(name)}=\(\n(.*?)^\)", script_text,
                  re.M | re.S)
    if not m:
        return None
    entries = []
    for line in m.group(1).splitlines():
        lm = re.match(r"^\s*'(.*)'\s*$", line)
        if lm:
            entries.append(lm.group(1))
    return entries


def scrub_atoms():
    with open(SCRUB, "r", encoding="utf-8") as fh:
        text = fh.read()
    atoms = []
    for array, category in CATEGORY_BY_ARRAY.items():
        entries = parse_shell_array_literals(text, array)
        if entries is None:
            raise ScanError(CONFIG_ERROR, f"cannot find {array} in {SCRUB}")
        for entry in entries:
            # Faithful to the old parser: rx="${entry%%|*}" (first pipe).
            regex = entry.split("|", 1)[0]
            atoms.append(Atom(regex, category, "pcre", True,
                              f"scrub:{array}"))
    return atoms


def scrub_allowlist():
    with open(SCRUB, "r", encoding="utf-8") as fh:
        text = fh.read()
    entries = parse_shell_array_literals(text, "ALLOWLIST_PATHS")
    if entries is None:
        raise ScanError(CONFIG_ERROR, f"cannot find ALLOWLIST_PATHS in {SCRUB}")
    return entries


def _bash_array(include, var):
    r = subprocess.run(
        ["bash", "-c", f'set -u; . "$1" || exit 3; '
                       f'if [ "${{#{var}[@]}}" -gt 0 ]; then printf "%s\\0" "${{{var}[@]}}"; fi',
         "-", include],
        capture_output=True, text=True)
    if r.returncode != 0:
        raise ScanError(CONFIG_ERROR, f"cannot source {var} from the private include")
    return [e for e in r.stdout.split("\0") if e]


def _bash_scalar(include, var):
    r = subprocess.run(
        ["bash", "-c", f'set -u; . "$1" || exit 3; printf "%s" "${{{var}}}"',
         "-", include],
        capture_output=True, text=True)
    if r.returncode != 0:
        raise ScanError(CONFIG_ERROR, f"cannot source {var} from the private include")
    return r.stdout


def split_top_level_alternation(regex):
    """Split a combined ERE on top-level '|' only (paren-depth aware)."""
    atoms, depth, cur, esc = [], 0, [], False
    for ch in regex:
        if esc:
            cur.append(ch)
            esc = False
            continue
        if ch == "\\":
            cur.append(ch)
            esc = True
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        elif ch == "|" and depth == 0:
            atoms.append("".join(cur))
            cur = []
            continue
        cur.append(ch)
    atoms.append("".join(cur))
    return [a for a in atoms if a]


def private_atoms(include):
    if not os.path.isfile(include):
        raise ScanError(CONFIG_ERROR,
                        f"private include not found: {include} (private parity "
                        "runs on the operator machine)")
    atoms = []
    for var, category in (("DMF_PRIVATE_IDENTITY_PATTERNS", "identity"),
                          ("DMF_PRIVATE_TOPOLOGY_PATTERNS", "topology")):
        for entry in _bash_array(include, var):
            regex = entry.split("|", 1)[0]
            atoms.append(Atom(regex, category, "pcre", True, f"include:{var}"))
    # env-gate consumers: identity ran case-INSENSITIVE (git grep -nIiE),
    # topology case-sensitive (git grep -nIE) — §1.1 / §9.1 step 2.
    for var, category, cs in (("DMF_PRIVATE_IDENTITY_REGEX", "identity", False),
                              ("DMF_PRIVATE_TOPOLOGY_REGEX", "topology", True)):
        combined = _bash_scalar(include, var)
        for part in split_top_level_alternation(combined):
            atoms.append(Atom(part, category, "ere", cs, f"include:{var}"))
    return atoms


def gitleaks_local_rules(path, allow_missing):
    """Fail-closed (codex P2-2): the old private gitleaks rule set is one of
    the required §9.1 sources — a silently-missing file would let the private
    migration pass without proving `.gitleaks.local.toml` coverage. Skipping
    it must be an explicit, reviewed choice (--no-legacy-gitleaks)."""
    if not os.path.isfile(path):
        if allow_missing:
            return None
        raise ScanError(CONFIG_ERROR,
                        f"legacy private gitleaks config not found: {path} — "
                        "required for private parity; pass --no-legacy-gitleaks "
                        "ONLY if no old private gitleaks source ever existed")
    with open(path, "rb") as fh:
        return tomllib.load(fh).get("rules", [])


# ── matching ──────────────────────────────────────────────────────────────

def manifest_entry_key(entry):
    rx = entry.get("regex", "")
    if rx.startswith("(?i)"):
        rx = rx[4:]
    return hashlib.sha256(rx.encode("utf-8")).hexdigest()


def match_atoms(atoms, manifest, redact, problems):
    """Map every old atom onto a manifest entry; return matched entry ids."""
    entries = manifest.get("pattern", [])
    by_digest = {}
    for e in entries:
        if "regex" in e:
            by_digest.setdefault(manifest_entry_key(e), []).append(e)
    matched_ids = set()
    for atom in atoms:
        label = atom.redacted() if redact else f"/{atom.regex}/ ({atom.source})"
        candidates = [e for e in by_digest.get(atom.digest, [])
                      if e.get("category") == atom.category]
        if not candidates:
            problems.append(f"old atom has NO manifest entry: {label}")
            continue
        entry = candidates[0]
        matched_ids.add(entry["id"])
        eid = entry["id"] if not redact else f"entry:{manifest_entry_key(entry)[:12]}"
        if atom.engine not in entry.get("engines", []):
            problems.append(f"{eid}: engines {entry.get('engines')} missing old "
                            f"consumer engine '{atom.engine}' for {label}")
        if entry.get("case_sensitive", True) != atom.case_sensitive:
            problems.append(f"{eid}: case_sensitive={entry.get('case_sensitive', True)} "
                            f"but the old consumer ran "
                            f"{'case-sensitively' if atom.case_sensitive else 'case-INSENSITIVELY'}"
                            f" for {label}")
        if not atom.case_sensitive:
            pos = [canary_value(v) for v in entry.get("positive_canaries", [])]
            variant_pair = any(a != b and a.lower() == b.lower()
                               for a in pos for b in pos)
            if not variant_pair:
                problems.append(f"{eid}: old atom was case-insensitive but the entry "
                                "has no upper/lower variant pair among its positive "
                                "canaries (§9.1 step 4)")
    return matched_ids


def check_additions(atoms_matched_ids, manifest, problems):
    """Grep-participating entries with no old counterpart need the marker."""
    for entry in manifest.get("pattern", []):
        if "regex" not in entry or "pcre" not in entry.get("engines", []):
            continue  # gitleaks-only entries: continuity is gen --check's job
        if entry["id"] in atoms_matched_ids:
            continue
        parity = entry.get("parity", {})
        if parity.get("status") != "addition":
            problems.append(f"entry {entry['id']}: grep-participating, maps to no "
                            "old atom, and carries no [pattern.parity] "
                            'status="addition" marker')


def check_gitleaks_rules(rules, manifest, redact, problems, what):
    """Hand-authored gitleaks rules (private tier) must map 1:1 onto emit=true
    manifest entries: same id, same kind (regex vs override), same regex hash."""
    emitted = {e["id"]: e for e in manifest.get("pattern", [])
               if e.get("gitleaks", {}).get("emit", False)}
    for rule in rules:
        rid = rule.get("id", "?")
        label = rid if not redact else f"rule:{hashlib.sha256(rid.encode()).hexdigest()[:12]}"
        entry = emitted.get(rid)
        if entry is None:
            problems.append(f"{what}: rule {label} has no emit=true manifest entry")
            continue
        has_regex = "regex" in rule
        kind = entry["gitleaks"].get("kind")
        if has_regex != (kind == "custom"):
            problems.append(f"{what}: rule {label} kind mismatch (rule "
                            f"{'has' if has_regex else 'lacks'} a regex, entry kind={kind})")
            continue
        if has_regex:
            rule_hash = hashlib.sha256(rule["regex"].encode("utf-8")).hexdigest()
            if rule_hash != manifest_entry_key(entry):
                problems.append(f"{what}: rule {label} regex hash mismatch vs entry")


# ── modes ─────────────────────────────────────────────────────────────────

def run_public():
    problems = []
    manifest = load_public_manifest()
    atoms = scrub_atoms()
    matched = match_atoms(atoms, manifest, redact=False, problems=problems)
    check_additions(matched, manifest, problems)
    old_allow = scrub_allowlist()
    new_allow = manifest.get("scan", {}).get("allowlist_paths", [])
    if set(old_allow) != set(new_allow):
        gone = sorted(set(old_allow) - set(new_allow))
        added = sorted(set(new_allow) - set(old_allow))
        problems.append("grep allowlist drift between scrub ALLOWLIST_PATHS and "
                        f"manifest [scan]: missing={gone} extra={added}")
    cats = {}
    for a in atoms:
        cats[a.category] = cats.get(a.category, 0) + 1
    summary = ", ".join(f"{k}:{v}" for k, v in sorted(cats.items())) or "none"
    return problems, f"public tier: {len(atoms)} old atoms ({summary}), " \
                     f"{len(matched)} manifest entries matched"


def run_private(include, show_diff, legacy_gitleaks, no_legacy_gitleaks):
    if show_diff and (os.environ.get("CI") or os.environ.get("GITHUB_ACTIONS")):
        raise ScanError(CONFIG_ERROR,
                        "--show-private-diff refuses to run in CI (§4.2)")
    redact = not show_diff
    problems = []
    manifest = load_private_manifest()
    atoms = private_atoms(include)
    matched = match_atoms(atoms, manifest, redact=redact, problems=problems)
    check_additions(matched, manifest, problems)
    rules = gitleaks_local_rules(legacy_gitleaks, no_legacy_gitleaks)
    if rules is None:
        print("  (legacy gitleaks source skipped by explicit --no-legacy-gitleaks)")
    else:
        check_gitleaks_rules(rules, manifest, redact, problems,
                             ".gitleaks.local.toml")
    cats = {}
    for a in atoms:
        cats[a.category] = cats.get(a.category, 0) + 1
    summary = ", ".join(f"{k}:{v}" for k, v in sorted(cats.items())) or "none"
    return problems, f"private tier: {len(atoms)} old atoms ({summary}), " \
                     f"{len(matched)} manifest entries matched (redacted report)" \
        if redact else f"private tier: {len(atoms)} old atoms ({summary})"


def main(argv):
    ap = argparse.ArgumentParser(
        prog="check-pattern-parity",
        description="§9.1 old→new structural parity gate. Exit: 0 green, "
                    "4 DRIFT_ERROR, 3 CONFIG_ERROR.")
    ap.add_argument("--public", action="store_true",
                    help="public tier: scrub in-script arrays vs the public manifest (CI-safe)")
    ap.add_argument("--private", action="store_true",
                    help="private tier: operator include + .gitleaks.local.toml vs the "
                         "private manifest (operator-local; redacted output)")
    ap.add_argument("--include", default=os.environ.get(
                        "DMF_SCRUB_PRIVATE_PATTERNS", PRIVATE_INCLUDE_DEFAULT),
                    help="private include path (default: the scrub include)")
    ap.add_argument("--show-private-diff", action="store_true",
                    help="LOCAL-ONLY literal private report (refuses in CI)")
    ap.add_argument("--legacy-gitleaks", default=LOCAL_GITLEAKS,
                    help="path of the old private gitleaks config (default: "
                         "umbrella .gitleaks.local.toml)")
    ap.add_argument("--no-legacy-gitleaks", action="store_true",
                    help="explicit, reviewed opt-out when no old private "
                         "gitleaks source ever existed (otherwise a missing "
                         "file is CONFIG_ERROR)")
    args = ap.parse_args(argv)
    if not args.public and not args.private:
        args.public = True

    try:
        all_problems = []
        for enabled, runner in ((args.public, run_public),
                                (args.private,
                                 lambda: run_private(args.include, args.show_private_diff,
                                                     args.legacy_gitleaks,
                                                     args.no_legacy_gitleaks))):
            if not enabled:
                continue
            problems, summary = runner()
            print(f"── {summary}")
            for p in problems:
                print(f"  ✗ {p}", file=sys.stderr)
            all_problems.extend(problems)
    except ScanError as exc:
        print(f"CLASS: {'CONFIG_ERROR' if exc.cls == CONFIG_ERROR else 'DRIFT_ERROR'}: {exc}",
              file=sys.stderr)
        return exc.cls
    if all_problems:
        print(f"CLASS: DRIFT_ERROR: {len(all_problems)} parity problem(s) — the "
              "old→new migration would lose or change coverage", file=sys.stderr)
        return DRIFT_ERROR
    print("OK: structural parity holds")
    return OK


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
