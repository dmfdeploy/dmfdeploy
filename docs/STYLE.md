# Project voice

This page describes the dmfdeploy voice. It builds on the [Google developer
documentation style guide](https://developers.google.com/style), and Vale
enforces both. The `Voice` package flags habits that read as generated.

Write like a knowledgeable colleague who states the fact and names the actor.
Then stop.
Run `bin/check-voice.sh FILE` on a draft. An error-level alert blocks the change.

## Contrast

Level: error. The shapes `A, not B` and `not only A but B` answer a claim nobody made.

```text
Before: We offer these as questions, not as change requests.
After:  These are questions. Each one asks about intent.
```

## Soft contrast

Level: warning. Keep `rather than` and `instead of` for a real comparison.

```text
Before: Use the vault rather than environment variables.
After:  Store the token in the vault. Environment variables leak into logs.
```

## Vocabulary

Level: warning. Words such as `leverage`, `robust` and `seamless` say little.
The project vocabulary accepts `harness`, `journey`, `realm` and `ensure`,
because each one is a real term here.

```text
Before: The installer leverages a robust pipeline.
After:  The installer retries each step three times.
```

## Stock phrases

Level: warning. Openers and closers such as `it's worth noting` add no fact.

```text
Before: It's worth noting that the cluster restarts after the upgrade.
After:  The cluster restarts after the upgrade.
```

## Openers

Level: suggestion. Start with the subject. Skip transition words.

```text
Before: Additionally, the installer writes a log file.
After:  The installer also writes a log file.
```

## Em dashes

Level: error. Use a period, a comma, a colon, or parentheses.

```text
Before: The installer runs first — then the checks run.
After:  The installer runs first. Then the checks run.
```

## Bold-lead bullets

Level: warning. One bold-lead bullet is fine. Three in a row read as a template.

```text
Before: - **Speed:** Four minutes.  - **Safety:** Rollback.  - **Clarity:** A log.
After:  The installer finishes in four minutes, supports rollback, and logs each step.
```

## Label-style headings

Level: warning. A heading is a short phrase in sentence case.

```text
Before: ## Status: ready
After:  ## Release status
```

## Triads

Level: suggestion, low confidence. Keep a list of three only for three real items.

```text
Before: The installer is fast, reliable, and predictable.
After:  The installer finishes in four minutes and gives the same result each run.
```
