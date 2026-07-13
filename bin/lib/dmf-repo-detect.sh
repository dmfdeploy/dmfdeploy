#!/usr/bin/env bash
# dmf-repo-detect.sh — shared repo/worktree detection for the public-safety gates.
#
# Replaces the `[ -d "$path/.git" ]` "is this a repo?" test, which is FALSE for a
# git worktree (there `.git` is a *file* — a `gitdir:` pointer — not a directory).
# The old test silently skips worktrees, so the pre-publish scrub reports clean
# without scanning anything. See the R1 spec §7:
#   docs/plans/DMF Public-Safety Pattern Manifest Plan 2026-07-13.md
#
# This is a sourced library, not an executable — it defines a function and returns.
#
# dmf_is_repo_root <path>
#   Exit 0 iff <path> is the top of its OWN git work tree — a normal clone OR a
#   linked worktree. Exit 1 otherwise. A subdirectory nested inside a repo returns
#   1 (its work-tree top is not itself), preserving the original "is this a repo
#   root, not just some path under one" intent.

dmf_is_repo_root() {
    local path="$1" top real_path real_top
    [ -n "$path" ] || return 1
    # rev-parse resolves the enclosing work tree for both clones and worktrees.
    top="$(git -C "$path" rev-parse --show-toplevel 2>/dev/null)" || return 1
    [ -n "$top" ] || return 1
    # Require <path> to BE that top, not merely sit under it. Compare physical
    # paths so symlinked temp roots (e.g. /tmp -> /private/tmp on macOS) and
    # trailing-slash differences don't cause false negatives.
    real_path="$(cd "$path" 2>/dev/null && pwd -P)" || return 1
    real_top="$(cd "$top" 2>/dev/null && pwd -P)" || return 1
    [ "$real_path" = "$real_top" ]
}
