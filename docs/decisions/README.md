# Decisions and the RFC process

This folder holds the architecture decision records (ADRs) for the dmfdeploy
platform. The [decision index](INDEX.md) lists every ADR, marks the core ones
with ★, and names the canonical ADR for each topic.

## Propose a decision with an RFC

A substantial decision that crosses repos starts as an RFC (request for
comments) in GitHub Discussions. The ADR comes after the RFC converges.

1. Open a thread in the
   [RFC category](https://github.com/dmfdeploy/dmfdeploy/discussions/categories/rfc).
   Describe the context, the options, and your recommendation. Most of the
   design debate happens there.
2. When the thread converges, write the ADR. Copy
   [`0000-template.md`](0000-template.md) to `NNNN-kebab-title.md` with the
   next free number, and open a pull request that links the RFC thread.
3. When the ADR merges, post one announcement thread for it in the
   [Announcements category](https://github.com/dmfdeploy/dmfdeploy/discussions/categories/announcements).
   The pinned "Decision record" index thread covers the ADRs that came before
   this rule.

A small decision that affects one repo doesn't need an RFC. Record it in its
issue.

Any change of direction for the project also goes through an RFC first.

## ADR conventions

Every ADR carries these parts:

- A **Rule:** line at the top that states the binding constraint in one
  imperative sentence. A reader gets the obligation without reading the whole
  record.
- An `## Enforcement` section that says how the decision stays true: a
  script, a CI gate, or a skill. When nothing enforces it, the section says
  "discipline only."
- A filename of the form `NNNN-kebab-title.md`, with numbers that only go up,
  and a row in the [index](INDEX.md).

When an ADR supersedes an earlier one, set the earlier one's status to
**Superseded** and link forward. Don't delete the earlier ADR.

The canonical description of how Discussions, issues, and decisions fit
together is in [WORKING-MODEL.md §4](../WORKING-MODEL.md#4-discussions).
