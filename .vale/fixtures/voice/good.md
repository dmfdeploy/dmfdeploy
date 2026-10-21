# Voice fixture, good examples

This page says the same things as the bad fixture, in the project voice. It also
holds the cases that must stay quiet.

## Decision

The review comments below are questions. Each one asks about intent, and none
of them blocks the merge.

The check reads the config and validates every entry. It reports the line
number of each bad entry.

The installer finishes in four minutes. You can roll back each step, and the
log names every step.

Store the token in OpenBao. A local file would leave the token on disk.

## Negative cases

The installer does not read secrets from the environment. The check is not
optional. The agent cannot write to the cluster. The migration is not yet
complete, so the old path still works.

If the check fails, do not merge the change. Whether or not you use the cache,
the build output stays the same.

The installer reads the config before it starts. It writes a log file when it
finishes.

Run the installer first. After that, run the checks.

The installer is fast and predictable.

Requirements:

- **Vale 3.9 or later.** The CI job pins this version.
- A synced copy of the Google package.
- Write access to the `.vale` folder.

## Issue body

The upgrade took four minutes on the test cluster. The cluster restarted once.
To reproduce the result, run `make upgrade` and read the log.

Open an issue if a step fails. Include the log.
