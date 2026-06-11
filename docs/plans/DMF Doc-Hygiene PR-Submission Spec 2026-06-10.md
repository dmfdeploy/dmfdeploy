---
status: executed
date: 2026-06-10
executed: 2026-06-10
---
# DMF Doc-Hygiene — PR-Submission Spec for qwen — 2026-06-10

Submit the doc-hygiene PRs for 4 repos. The edits are ALREADY staged (unstaged
working-tree changes) in the **GitHub clones** at `~/repos/dmfgithub/dmfdeploy/<repo>`.
PR #1 (dmf-runbooks) already merged via this exact flow — replicate it.

## Hard rules
- Work ONLY in `~/repos/dmfgithub/dmfdeploy/<repo>` (origin = `git@github.com:dmfdeploy/...`).
  NEVER touch `~/repos/dmfdeploy/<repo>` (that's the LAN clone).
- Do each repo fully, then move to the next. If ANY step errors, STOP that repo and
  report BLOCKED with the error — do NOT use `--force`, `--no-verify`, or `--admin`.
- Author/committer = `<handle> <6800371+<handle>@users.noreply.github.com>`. Sign off every commit (`-s`).
- Do NOT merge anything. Just create the PRs (operator + lkirc review/merge).
- Branch name (all repos): `<handle>/public-doc-cleanup`.
- **Attribution:** the operator (`<handle>`) is the commit author. Do **not** add a
  `Co-Authored-By: Claude` / "Generated with Claude Code" trailer to commits or PR
  bodies — the lifting agent does not claim authorship over the operator's work.

## Authentication — act as `<handle>`

You push and open PRs **as the GitHub user `<handle>`**. On this machine that
identity is already wired up; confirm it first:

```bash
gh auth status        # MUST show: Logged in to github.com account <handle> (keyring)
```

- If it shows `<handle>` (keyring) — you're done. `gh` commands run as <handle>, and
  `git push` uses <handle>'s SSH key (origin is `git@github.com:...`). Just proceed.
- If it does NOT show <handle> (not logged in / wrong account), authenticate with the
  Personal Access Token stored in the macOS Keychain (service `ghcr.io`, account
  `<handle>` — note: account is the **username**, not an email):

  ```bash
  export GH_TOKEN="$(security find-generic-password -s ghcr.io -a <handle> -w)"
  gh auth status        # re-check; should now be <handle>
  ```

  Treat that token as a secret: never echo it, paste it into a file, a commit, a PR
  body, or your reply. Use it only as the `GH_TOKEN` env var for `gh`.
- The commit author/committer is set explicitly per repo below
  (`<handle> <6800371+<handle>@users.noreply.github.com>`), independent of gh auth.

## Per-repo procedure (run for each repo R below)

```bash
cd ~/repos/dmfgithub/dmfdeploy/<R>
git config user.name "<handle>"
git config user.email "6800371+<handle>@users.noreply.github.com"
git status --short                      # sanity: shows the expected modified files, nothing else
git switch -c <handle>/public-doc-cleanup
git add -A
git commit -s -F /tmp/commitmsg-<R>.txt # message body provided per-repo below — write it to that file first
git push -u origin <handle>/public-doc-cleanup
gh pr create -R dmfdeploy/<R> --base main --head <handle>/public-doc-cleanup \
  --title "<TITLE>" --body-file /tmp/prbody-<R>.txt
gh pr checks <PR#> -R dmfdeploy/<R>      # report results
```

Write each commit message to `/tmp/commitmsg-<R>.txt` and each PR body to
`/tmp/prbody-<R>.txt` (so quoting is safe), using the exact text below.

---

### R = dmf-central   (expected files: CLAUDE.md, QWEN.md, README.md)
TITLE: `docs: future-proof repo count and fix stale dmf-env description`
commitmsg + PR body:
```
docs: future-proof repo count and fix stale dmf-env description

- Agent files: "all 6 repos" -> "all repos" (a hardcoded count re-stales).
- README: dmf-env is generic env provisioning/bootstrap tooling now (ADR-0035),
  not "environment-specific inventory".```
(Use the commit body above as the PR body — no extra trailer.)

---

### R = dmf-media   (expected files: CLAUDE.md, QWEN.md, README.md)
TITLE: `docs: future-proof repo count and fix stale dmf-env description`
Same commit body + PR body as dmf-central (the changes are the same class).

---

### R = dmf-cms   (expected files: AGENTS.md, CLAUDE.md, QWEN.md, docs/DEVELOPMENT-AND-BUILD-RULES.md, docs/IMPLEMENTATION-STRATEGY.md)
TITLE: `docs: future-proof repo count and neutralize operator-local paths`
commit body:
```
docs: future-proof repo count and neutralize operator-local paths

- Agent files: "all 6 repos" -> "all repos".
- Docs: replace operator-local "~/repos/..." paths with "$DMFDEPLOY_UMBRELLA/...".```
PR body = same as the commit body — no extra trailer.

---

### R = dmf-infra   (expected ~16 files: README.md, CLAUDE.md, AGENTS.md, QWEN.md, docs/SECURITY-REMEDIATION-GUIDE.md, k3s-lab-bootstrap/{roles,ee}/README.md, and k3s-lab-bootstrap/docs/{repo-strategy,dmf-platform-plan,forgejo,integration-sot,cluster-ready,awx-integration-plan,ci-cd-proposal,hardening,openbao-policy-reconciliation-agent-prompt}.md)
TITLE: `docs: correct GitHub org/repo model and refresh stale docs`
commit body:
```
docs: correct GitHub org/repo model and refresh stale docs

- Fix wrong GitHub owner lkirc -> dmfdeploy (README + repo-strategy).
- Rewrite the "Two-Repo Model" section as "Part of the DMF Platform":
  dmf-env is public generic tooling; per-env state is operator-local (ADR-0035).
- Fix the Project Structure tree: drop non-existent vertical-control, add
  vertical-resilience, bump the playbook range to 699, add the bootstrap-*
  chain / lifecycle-configure / charts / ee / providers / tests.
- ADR-0025 note -> past tense (the EE pipeline landed).
- Add HISTORICAL/SUPERSEDED banners to the pre-migration planning docs and
  numbering-historical banners to the stale k3s-lab-bootstrap/docs guides.
- Fix broken intra-repo links and the 698->699 cms-smoke-test playbook name.
- Neutralize operator-local "~/repos/..." paths; clarify Loki has no web UI;
  use the dmf.example.com placeholder domain.```
PR body = same as the commit body — no extra trailer.

---

## Report
When all 4 PRs are open, reply to claude (`%3`) via agent-bridge with the 4 PR URLs
and each one's check status (green/pending/fail), or BLOCKED + which repo + the error:
`~/.claude/skills/agent-bridge/bin/agent-bridge send %3 -- "<report>"`
