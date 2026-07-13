#!/usr/bin/env python3
"""migrate-private-manifest.py — one-shot §9-step-2 migration (R1 spec).

Mechanically authors the operator-local private manifest
(~/.dmfdeploy/pattern-manifest.private.toml) from the two OLD private
sources — the shell include's arrays/combined-ERE vars and the hand-authored
.gitleaks.local.toml — then (optionally) rewrites .gitleaks.local.toml as the
marker-fenced GENERATED view of that manifest (spec §3.2).

OPERATOR-LOCAL BY DESIGN: this script is public-safe (no pattern literals);
everything it reads and writes stays under ~/.dmfdeploy/ or gitignored paths.
All console output is REDACTED (§4.2): counts, engines, id-hashes — never a
regex body, description, or canary value.

Mapping (spec §4 "migration is mechanical, not a re-derivation"):
  - each include array atom ('PCRE|desc', split at the FIRST pipe exactly as
    the old consumer did) and each top-level alternation branch of the
    combined-ERE vars becomes/joins a [[pattern]] entry keyed by
    (category, normalized regex, effective case);
  - engines = union of the consumers that ran the atom (pcre for the arrays,
    ere for the env-gate vars; identity ran case-INSENSITIVE there, #137);
  - a .gitleaks.local.toml rule with the same regex makes the entry
    emit=true/kind=custom (rule id + allowlists preserved); rules with no
    grep twin get their own re2-only entries; everything else is
    emit=false covered_by="git-grep";
  - positive canaries are SAMPLED from each regex and verified with re;
    case-insensitive entries get upper+lower variant pairs (§9.1 step 4).
    Entries the sampler cannot satisfy are flagged (id-hash) for manual fill.

The final proof is NOT this script: run  bin/check-pattern-parity.py --private
afterwards (the script does it for you unless --skip-parity).

Usage:
  bin/migrate-private-manifest.py                 # write manifest (refuses to overwrite)
  bin/migrate-private-manifest.py --force         # overwrite an existing manifest
  bin/migrate-private-manifest.py --rewrite-legacy  # ALSO rewrite .gitleaks.local.toml
                                                    # as the generated view (back up first)

Exit: 0 OK; 3 CONFIG_ERROR; 4 parity DRIFT_ERROR (when the auto-run fails).
"""
import argparse
import hashlib
import importlib.util
import os
import re
import subprocess
import sys
import tomllib

HERE = os.path.dirname(os.path.abspath(__file__))
UMBRELLA = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(HERE, "lib"))
from dmf_scan import OK, CONFIG_ERROR, ScanError, private_manifest_path  # noqa: E402


def _load_script(name):
    spec = importlib.util.spec_from_file_location(
        name.replace("-", "_"), os.path.join(HERE, name))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


parity = _load_script("check-pattern-parity.py")
gen = _load_script("gen-gitleaks-rules.py")


# ── canary sampling (verified against `re`; failures are flagged, not fatal) ─

def sample_regex(rx):
    """Build one string the regex matches, by walking Python's sre parse tree."""
    parser = getattr(re, "_parser", None)
    if parser is None:  # pragma: no cover — very old Python
        return None
    try:
        tree = parser.parse(rx)
    except re.error:
        return None

    def walk(items):
        out = []
        for op, av in items:
            op = str(op)
            if op == "LITERAL":
                out.append(chr(av))
            elif op == "NOT_LITERAL":
                out.append("a" if chr(av) != "a" else "b")
            elif op == "IN":
                out.append(_sample_class(av))
            elif op == "ANY":
                out.append("a")
            elif op in ("MAX_REPEAT", "MIN_REPEAT"):
                lo, _hi, item = av
                out.append(walk(item) * max(lo, 1 if lo else 0))
            elif op == "SUBPATTERN":
                out.append(walk(av[3]))
            elif op == "BRANCH":
                out.append(walk(av[1][0]))
            elif op == "AT":
                pass  # anchors / \b — rely on neighbours, verify below
            elif op in ("ASSERT", "ASSERT_NOT"):
                pass
            elif op == "CATEGORY":  # inside IN handled separately
                pass
            else:
                raise ValueError(op)
        return "".join(out)

    def _sample_class(av):
        pool = "a0A _-."
        negated = av and str(av[0][0]) == "NEGATE"
        if negated:
            neg_rx = re.compile(_class_to_rx(av))
            for c in pool + "zZ9~":
                if neg_rx.match(c):
                    return c
            return "q"
        for op, val in av:
            op = str(op)
            if op == "LITERAL":
                return chr(val)
            if op == "RANGE":
                return chr(val[0])
            if op == "CATEGORY":
                cat = str(val)
                if "DIGIT" in cat:
                    return "0"
                if "SPACE" in cat:
                    return " "
                return "a"
        return "a"

    def _class_to_rx(av):
        # crude re-render of a negated class for probing
        parts = []
        for op, val in av[1:]:
            op = str(op)
            if op == "LITERAL":
                parts.append(re.escape(chr(val)))
            elif op == "RANGE":
                parts.append(f"{re.escape(chr(val[0]))}-{re.escape(chr(val[1]))}")
            elif op == "CATEGORY":
                cat = str(val)
                parts.append("\\d" if "DIGIT" in cat else "\\s" if "SPACE" in cat else "\\w")
        return "[^" + "".join(parts) + "]"

    try:
        cand = walk(tree)
    except ValueError:
        return None
    return cand if cand and re.search(rx, cand) else None


def canaries_for(rx, case_sensitive):
    cand = sample_regex(rx)
    if cand is None:
        return None
    if case_sensitive:
        return [cand]
    flags = re.IGNORECASE
    variants = []
    for v in (cand.upper(), cand.lower()):
        if v not in variants and re.search(rx, v, flags):
            variants.append(v)
    return variants if len(variants) >= 2 else None


# ── entry building ────────────────────────────────────────────────────────

def toml_str(s):
    if "'" not in s:
        return f"'{s}'"
    if "'''" not in s and not s.endswith("'"):
        return f"'''{s}'''"
    import json
    return json.dumps(s)


def slug(text, taken):
    base = "private-" + re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-",
                                                  text.lower())).strip("-")[:40]
    out, n = base, 1
    while out in taken:
        n += 1
        out = f"{base}-{n}"
    taken.add(out)
    return out


def _infer_category(rule):
    """Category for a gitleaks-only legacy rule, from id AND description
    (codex P2: id-substring alone misfiled an identity rule as topology).
    Category affects reporting/parity counts, never whether the regex runs;
    conflicting or absent signals are flagged (redacted) and default topology."""
    text = (rule.get("id", "") + " " + rule.get("description", "")).lower()
    is_ident, is_topo = "identity" in text, "topology" in text
    if is_ident and not is_topo:
        return "identity"
    if is_topo and not is_ident:
        return "topology"
    h = hashlib.sha256(rule.get("id", "").encode()).hexdigest()[:12]
    print(f"  ! rule id-hash={h}: category signal "
          f"{'conflicting' if is_ident else 'absent'} — defaulting to "
          "'topology'; adjust the entry by hand if wrong")
    return "topology"


def build_entries(include, legacy_rules):
    atoms = parity.private_atoms(include)
    # also carry the array descriptions (the parity Atom drops them — re-parse)
    descs = {}
    for var, category in (("DMF_PRIVATE_IDENTITY_PATTERNS", "identity"),
                          ("DMF_PRIVATE_TOPOLOGY_PATTERNS", "topology")):
        for raw in parity._bash_array(include, var):
            rx, _, d = raw.partition("|")
            if rx.startswith("(?i)"):
                rx = rx[4:]
            descs[(category, rx)] = d or "private pattern"

    merged = {}  # (category, regex, case) -> entry dict
    order = []
    for atom in atoms:
        key = (atom.category, atom.regex, atom.case_sensitive)
        if key not in merged:
            merged[key] = {
                "category": atom.category,
                "regex": atom.regex,
                "case_sensitive": atom.case_sensitive,
                "engines": [],
                "description": descs.get((atom.category, atom.regex),
                                         "private pattern"),
            }
            order.append(key)
        if atom.engine not in merged[key]["engines"]:
            merged[key]["engines"].append(atom.engine)

    # attach legacy gitleaks rules by regex digest; leftovers become re2 entries
    by_digest = {}
    for key in order:
        d = hashlib.sha256(merged[key]["regex"].encode()).hexdigest()
        by_digest.setdefault(d, []).append(key)
    unmatched_rules = []
    for rule in legacy_rules:
        if "regex" not in rule:
            unmatched_rules.append(rule)
            continue
        rrx = rule["regex"]
        rrx_n = rrx[4:] if rrx.startswith("(?i)") else rrx
        d = hashlib.sha256(rrx_n.encode()).hexdigest()
        keys = by_digest.get(d, [])
        if keys:
            e = merged[keys[0]]
            e["gitleaks_rule"] = rule
            if "re2" not in e["engines"]:
                e["engines"].append("re2")
        else:
            unmatched_rules.append(rule)
    for rule in unmatched_rules:
        key = (_infer_category(rule), rule.get("regex", ""), True)
        merged[key] = {
            "category": key[0],
            "regex": rule.get("regex", ""),
            "case_sensitive": not rule.get("regex", "").startswith("(?i)"),
            "engines": ["re2"],
            "description": rule.get("description", "private rule"),
            "gitleaks_rule": rule,
        }
        order.append(key)
    return [merged[k] for k in order]


def render_manifest(entries):
    taken = set()
    flagged = []
    out = [
        "# DMF public-safety pattern manifest — OPERATOR-PRIVATE tier.",
        "# Generated by bin/migrate-private-manifest.py (R1 spec §9 step 2)",
        "# from the legacy include + .gitleaks.local.toml. NEVER commit this",
        "# file or paste its contents anywhere tracked or logged.",
        "",
    ]
    for e in entries:
        rule = e.get("gitleaks_rule")
        eid = rule["id"] if rule else slug(e["description"], taken)
        e["id"] = eid
        cans = canaries_for(e["regex"], e["case_sensitive"])
        if cans is None:
            flagged.append(eid)
            cans = []
        out += [
            "[[pattern]]",
            f'id = "{eid}"',
            f'category = "{e["category"]}"',
            f"description = {toml_str(e['description'])}",
            f"regex = {toml_str(e['regex'])}",
            "engines = [" + ", ".join(f'"{x}"' for x in e["engines"]) + "]",
            f"case_sensitive = {'true' if e['case_sensitive'] else 'false'}",
            "positive_canaries = [" + ", ".join(toml_str(c) for c in cans) + "]"
            + ("" if cans else "  # FILL-ME: sampler could not derive one"),
            "[pattern.gitleaks]",
        ]
        if rule:
            out.append("emit = true")
            out.append('kind = "custom"')
            allow = rule.get("allowlists") or []
            if len(allow) > 1:
                # Fail closed rather than silently truncate (codex P3): the
                # manifest schema carries ONE allowlist block per entry.
                raise ScanError(CONFIG_ERROR,
                                f"legacy rule '{rule.get('id')}' has "
                                f"{len(allow)} allowlist blocks; merge them "
                                "by hand before migrating")
            if allow:
                a = allow[0]
                out.append("allowlist_description = "
                           + toml_str(a.get("description", "meta files")))
                out.append("allowlist_paths = [")
                for p in a.get("paths", []):
                    out.append(f"    {toml_str(p)},")
                out.append("]")
        else:
            out.append("emit = false")
            out.append('covered_by = "git-grep"')
        out.append("")
    return "\n".join(out) + "\n", flagged


def rewrite_legacy(legacy_path, manifest_path):
    """Rewrite .gitleaks.local.toml: hand prose header + marker-fenced region
    rendered from the new private manifest (same renderer as dmf-scan check)."""
    import dmf_scan
    with open(legacy_path, "r", encoding="utf-8") as fh:
        old = fh.read()
    # Idempotent: on an already-fenced file the header is everything above the
    # existing BEGIN marker (else a second marker pair would nest inside).
    if gen.BEGIN in old:
        header = old[:old.find(gen.BEGIN)].rstrip("\n")
    else:
        idx = old.find("[[rules]]")
        header = old[:idx].rstrip("\n") if idx > 0 else "# operator-private gitleaks rules"
    with open(manifest_path, "rb") as fh:
        manifest = tomllib.load(fh)
    region = dmf_scan._render_private_rules(manifest)
    new = f"{header}\n\n{gen.BEGIN}\n{region}\n{gen.END}\n"
    tomllib.loads(new)  # must stay valid TOML for the pre-commit second pass
    with open(legacy_path, "w", encoding="utf-8") as fh:
        fh.write(new)


def main(argv):
    ap = argparse.ArgumentParser(prog="migrate-private-manifest")
    ap.add_argument("--include", default=os.environ.get(
        "DMF_SCRUB_PRIVATE_PATTERNS",
        os.path.expanduser("~/.dmfdeploy/scrub-private-patterns.sh")))
    ap.add_argument("--legacy-gitleaks",
                    default=os.path.join(UMBRELLA, ".gitleaks.local.toml"))
    ap.add_argument("--out", default=None,
                    help="output manifest path (default: the runtime private "
                         "manifest path, honoring DMF_PATTERN_MANIFEST_PRIVATE)")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--rewrite-legacy", action="store_true",
                    help="also rewrite .gitleaks.local.toml as the generated "
                         "view (make a backup outside the repo FIRST)")
    ap.add_argument("--skip-parity", action="store_true")
    args = ap.parse_args(argv)
    out_path = args.out or private_manifest_path()

    try:
        if os.path.exists(out_path) and not args.force:
            raise ScanError(CONFIG_ERROR, f"refusing to overwrite {out_path} "
                                          "(pass --force)")
        if not os.path.isfile(args.legacy_gitleaks):
            raise ScanError(CONFIG_ERROR,
                            f"legacy gitleaks config not found: {args.legacy_gitleaks}")
        with open(args.legacy_gitleaks, "rb") as fh:
            legacy_rules = tomllib.load(fh).get("rules", [])
        entries = build_entries(args.include, legacy_rules)
        text, flagged = render_manifest(entries)
        tomllib.loads(text)
        with open(out_path, "w", encoding="utf-8") as fh:
            os.fchmod(fh.fileno(), 0o600)
            fh.write(text)

        # ── redacted summary only ──
        cats = {}
        for e in entries:
            cats[e["category"]] = cats.get(e["category"], 0) + 1
        emitted = sum(1 for e in entries if e.get("gitleaks_rule"))
        print(f"wrote {out_path} (0600): "
              + ", ".join(f"{k}:{v}" for k, v in sorted(cats.items()))
              + f"; {emitted} gitleaks-emitting, "
                f"{len(entries) - emitted} git-grep-only")
        for eid in flagged:
            h = hashlib.sha256(eid.encode()).hexdigest()[:12]
            print(f"  ! entry id-hash={h}: no auto canary — fill "
                  "positive_canaries by hand (upper+lower pair if "
                  "case-insensitive)")

        # Parity runs BEFORE any legacy rewrite: it must compare the manifest
        # against the ORIGINAL hand-authored rule set, not a generated view of
        # itself (that comparison would be vacuous).
        if not args.skip_parity:
            r = subprocess.run([sys.executable,
                                os.path.join(HERE, "check-pattern-parity.py"),
                                "--private", "--include", args.include,
                                "--legacy-gitleaks", args.legacy_gitleaks],
                               env=dict(os.environ,
                                        DMF_PATTERN_MANIFEST_PRIVATE=out_path))
            if r.returncode != 0:
                return r.returncode

        if args.rewrite_legacy:
            rewrite_legacy(args.legacy_gitleaks, out_path)
            print(f"rewrote {args.legacy_gitleaks} as the marker-fenced "
                  "generated view")
    except ScanError as exc:
        print(f"CLASS: CONFIG_ERROR: {exc}", file=sys.stderr)
        return exc.cls
    return OK


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
