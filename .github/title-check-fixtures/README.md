# title-check fixtures

Data files for the checks that guard titles, issue forms, CODEOWNERS and the
PR template. The checker is `.github/scripts/hygiene-check.sh`, and the
`title-check` workflow runs it on every pull request. Run every command from
the repository root.

Check the real files, then assert the fixtures behave:

    .github/scripts/hygiene-check.sh real
    .github/scripts/hygiene-check.sh fixtures

Every `bad-*` fixture must make the checker exit 1 and every `good-*` twin
must exit 0. The `fixtures` command exits 1 if any fixture behaves otherwise.

Run one check by hand:

    .github/scripts/hygiene-check.sh form   .github/title-check-fixtures/bad-form.yml
    .github/scripts/hygiene-check.sh owners .github/title-check-fixtures/bad-codeowners-path
    .github/scripts/hygiene-check.sh pr     .github/title-check-fixtures/bad-pr-template.md
    GITHUB_EVENT_PATH=.github/title-check-fixtures/bad-pr.json STRICT=1 \
      .github/scripts/hygiene-check.sh title

The `title-check` workflow sets `STRICT=1`, so a bad title fails the job.
Without `STRICT=1` the title check always exits 0 and prints a warning for a
bad title.

The form check parses YAML with `ruby` and queries it with `jq`. Both are
installed on ubuntu-24.04 runners and on macOS.
