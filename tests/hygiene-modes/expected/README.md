# Expected workflow documents

These four files are the parsed form of the guarded workflows, stored as
canonical JSON: `surface.json`, `title-check.json`, `vale.json` and
`backlog-hygiene.json`. `tests/hygiene-modes.sh` loads each workflow in
`.github/workflows/`, renames the YAML `on` key to the string `"on"`, and
compares the whole document with the matching file here. A difference prints
the key path, such as `on.pull_request.types`.

When you change one of these workflows on purpose, regenerate the files in the
same PR so a reviewer sees the change:

```sh
bash tests/hygiene-modes.sh --write-expected
```

The flag refuses to run when `CI` or `GITHUB_ACTIONS` is set.
