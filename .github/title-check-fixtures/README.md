# title-check fixtures

Data files for the checks that guard titles, issue forms, CODEOWNERS and the
PR template. Run every command from the repository root.

Title check (the same step text the workflow runs). `STRICT=1` makes a bad
title exit 1:

    for f in bad-pr good-pr bad-issue good-issue; do
      yq -r '.jobs.title.steps[0].run' .github/workflows/title-check.yml > /tmp/step.sh
      GITHUB_EVENT_PATH=.github/title-check-fixtures/$f.json STRICT=1 bash /tmp/step.sh
      echo "$f exit $?"
    done

Expected: `bad-*` exit 1, `good-*` exit 0. Without `STRICT=1`, all exit 0
and the bad ones print a warning.

Static checks use `yq` (the jq wrapper) to parse YAML. Run as `python3 -I check.py form|owners|pr FILE`, where
`check.py` is this block saved to a file:

    import re, sys, os, json, subprocess
    kind, path = sys.argv[1], sys.argv[2]
    bad = []
    text = open(path).read()
    if kind == "form":
        ids = {b.get("id"): b for b in json.loads(subprocess.check_output(["yq", ".", path]))["body"]}
        for need in ("component", "workstream"):
            b = ids.get(need)
            if not b or b["type"] != "dropdown" or not (b.get("validations") or {}).get("required"):
                bad.append("missing required dropdown " + need)
    elif kind == "owners":
        for n, line in enumerate(text.splitlines(), 1):
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            pat, *owners = line.split()
            if pat != "*" and not os.path.exists(pat.lstrip("/")):
                bad.append("line %d: path not found %s" % (n, pat))
            if not owners or not all(re.fullmatch(r"@[\w-]+(/[\w-]+)?", o) for o in owners):
                bad.append("line %d: owner not @login" % n)
    elif kind == "pr":
        for word in ("component:*", "workstream:*", "dmfdeploy/dmfdeploy#N", "signed off", "check-docs"):
            if word not in text:
                bad.append("checklist item missing: " + word)
    print("\n".join(bad) or "ok")
    sys.exit(1 if bad else 0)
