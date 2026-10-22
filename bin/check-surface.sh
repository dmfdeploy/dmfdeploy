#!/usr/bin/env bash
# check-surface.sh — check the working surface of the umbrella repo against its
# size budgets, filename convention and archive-placement rules (hygiene
# enforcement, dmfdeploy/dmfdeploy#617).
#
# Subcommands: size, filenames, placement, statuslog, all (default).
#   size       README.md, AGENTS.md and each ADR stay under a line budget. An
#              ADR in ADR_CEILINGS may not grow past its recorded ceiling.
#   statuslog  STATUS.md stays under its line budget (no long status log).
#   filenames  Live docs use kebab-case names with no spaces and no date.
#              README.md and INDEX.md are allowed anywhere. An upper-case
#              landmark name such as STYLE.md or OPEN-QUESTIONS.md is allowed
#              only directly under the top-level docs/ directory. The docs
#              in PINNED_NAMES keep their names; see the note there.
#   placement  docs/plans/ holds only plans with status active or draft, or
#              plans listed in FROZEN_PLANS, and no live doc links into
#              docs/archive/. An ADR may link to its own extract under
#              docs/archive/decisions/, and the links in ARCHIVE_LINK_EXEMPT
#              are allowed. A full URL is not an archive link, except a URL
#              into this repository's docs/archive/ that names a branch or tag
#              instead of a 40-character commit SHA: only a pinned permalink
#              passes.
#
# Usage:
#   bin/check-surface.sh [--warn|--strict] [SUBCOMMAND] [--root DIR] [--file PATH ...]
#
#   --warn     report findings and exit 0 (default for interactive runs).
#   --strict   exit 1 when there is any finding. CI runs each subcommand in
#              this mode, and the pre-commit hook runs it on staged files.
#   --root DIR scan the tree under DIR instead of the repository root.
#   --file P   check only the named file(s), applying every check that fits
#              the file's location, the same way the tree scan would. A file
#              under tests/surface/good/ or tests/surface/bad/ is a fixture:
#              its checks follow its base name, so tests can check fixtures
#              without depending on the real tree.
#
# The README, AGENTS.md and STATUS.md budgets come from #617. The ADR budget
# is set by #617 and plan answer 6. It holds for every ADR without a ceiling.
# The ADRs that were over it when enforcement started each have a
# shrink-only ceiling in ADR_CEILINGS, and the ADR rewrite trims them while
# showing that every normative sentence survives.
#
# The AGENTS.md budget counts only the lines outside the working-model block:
# the span from the line containing WORKING-MODEL-BLOCK-START to the line
# containing WORKING-MODEL-BLOCK-END, marker lines included, is excluded. That
# block is generated and required by bin/check-working-model-sync.sh. A block
# with a start marker but no end marker excludes nothing.

set -euo pipefail

# ── Budgets (maximum number of lines) ────────────────────────────────────────
BUDGET_README=100
BUDGET_AGENTS=60
BUDGET_ADR=80
BUDGET_STATUS=30

# ADRs that were over the line budget when enforcement started (#617). Each
# line is an ADR path and its ceiling, the line count it had then. The ADR may
# not grow past its ceiling. Ceilings may only go down as ADRs are trimmed:
# the tree scan reports a ceiling above the file's current line count, so
# lower the ceiling in the change that trims the ADR, and remove the entry
# once the ADR fits the budget. Every other ADR keeps BUDGET_ADR.
ADR_CEILINGS='docs/decisions/0011-auto-unseal-tradeoff.md 129
docs/decisions/0012-configure-stage-distinct-from-provision.md 102
docs/decisions/0013-media-function-catalog-model.md 117
docs/decisions/0014-awx-project-layout.md 81
docs/decisions/0015-dmf-console-passkey-only.md 126
docs/decisions/0016-awx-control-node-ssh-via-cloud-init-and-openbao.md 156
docs/decisions/0017-mxl-intra-host-data-plane.md 191
docs/decisions/0018-self-managed-k3s-not-ack.md 107
docs/decisions/0019-tailscale-cgnat-vs-cloud-internal-services.md 113
docs/decisions/0020-deployment-scope-and-regulatory-posture.md 257
docs/decisions/0021-openbao-approle-reconciler-identity.md 85
docs/decisions/0022-flypack-online-thin-edge-agent.md 180
docs/decisions/0023-internal-service-dns-for-cross-app-wiring.md 105
docs/decisions/0024-two-identity-admin-model.md 191
docs/decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md 145
docs/decisions/0026-provider-descriptors.md 100
docs/decisions/0027-catalog-instance-vs-definition-separation.md 122
docs/decisions/0028-identity-and-authority-chain.md 180
docs/decisions/0029-tiered-unseal-posture.md 136
docs/decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md 269
docs/decisions/0032-catalog-launcher-scoped-netbox-writer.md 267
docs/decisions/0034-internal-ansible-collection-source.md 108
docs/decisions/0035-operator-local-self-contained-envs.md 92
docs/decisions/0037-media-workloads-netbox-instance-inventory.md 113
docs/decisions/0038-netbox-driven-dynamic-monitoring.md 365
docs/decisions/0039-environment-identity-netbox-site-cluster.md 92
docs/decisions/0044-dmf-init-stateless-tmpfs-recovery-model.md 130
docs/decisions/0045-media-function-licensing-reservable-resource.md 117
docs/decisions/0046-first-class-media-workload-entity.md 174
docs/decisions/0047-media-function-packaging-catalog-sources-trust-model.md 205'

# Plans whose status is not active or draft but that stay in docs/plans/
# because readers outside this tree pin their paths (#617). The list is
# shrink-only: a plan leaves it when it moves to docs/archive/plans/, and no
# plan joins it. The tree scan reports an entry whose file is gone or whose
# status is active or draft again.
FROZEN_PLANS='docs/plans/AWX NetBox Inventory Sync Fix 2026-05-04.md
docs/plans/DMF AWX On-Demand Scale-to-Zero Plan 2026-06-18.md
docs/plans/DMF Agentic Harness Plan 2026-05-11.md
docs/plans/DMF App Admin Account Drift Audit and Realignment Plan 2026-05-14.md
docs/plans/DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md
docs/plans/DMF Console Initial Implementation Plan 2026-04-26.md
docs/plans/DMF Console UI Round Plan 2026-08-21.md
docs/plans/DMF Deployment Workflow and Manifest Plan.md
docs/plans/DMF In-Cluster Ansible Runner Pod Implementation Plan 2026-05-14.md
docs/plans/DMF Init Bootstrap Container Plan 2026-06-02.md
docs/plans/DMF Move 1 Path A Reset 2026-05-12.md
docs/plans/DMF NMOS Crosspoint Media Function Plan 2026-06-21.md
docs/plans/DMF Orchestrator and Renumbering Plan 2026-04-22.md
docs/plans/DMF Per-App Identity Feasibility Survey 2026-05-24.md
docs/plans/DMF Pre-Release Compliance Readiness Plan 2026-05-11.md
docs/plans/DMF Public Container Registry Publishing Plan 2026-05-19.md
docs/plans/DMF Secret Ownership and OpenBao Migration Plan.md
docs/plans/DMF v0.2b Multi-Source Switch Spec 2026-07-15.md
docs/plans/Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md
docs/plans/canonical-cross-agent-skills.md
docs/plans/dmf-adr-0025-lane-b-implementation-plan.md
docs/plans/dmf-bootstrap-pre-seed-blocker-fix-implementation-plan.md
docs/plans/dmf-bootstrap-provision-configure-split-plan.md
docs/plans/dmf-console-arc-4-visual-pass-plan.md
docs/plans/dmf-console-durable-action-history-plan.md
docs/plans/dmf-console-shell-round-plan.md
docs/plans/dmf-dynamic-netbox-driven-monitoring-plan.md
docs/plans/dmf-env-lifecycle-refactor-plan.md
docs/plans/dmf-improvement-run-plan.md
docs/plans/dmf-init-long-run-re-entry-and-resume-hardening-plan.md
docs/plans/dmf-init-wizard-expansion-survey.md
docs/plans/dmf-internal-service-dns-migration-survey.md
docs/plans/dmf-marketplace-resource-model-and-placement-grounded-roadmap.md
docs/plans/dmf-multi-provider-resource-selection-future-direction.md
docs/plans/dmf-mxl-on-demand-media-function-cycle-plan.md
docs/plans/dmf-oss-v0-1-contributor-replicability-premise-pass.md
docs/plans/dmf-oss-v0-1-release-mission.md
docs/plans/dmf-oss-v0-1-wp0-release-contract-and-profile-matrix.md
docs/plans/dmf-platform-move-1-task.md
docs/plans/dmf-platform-move-2-task.md
docs/plans/dmf-pre-bao-bootstrap-secrets-design.md
docs/plans/dmf-public-repo-identity-leak-sweep.md
docs/plans/dmf-public-safety-pattern-manifest-plan.md
docs/plans/dmf-release-and-contribution-model-implementation-plan.md
docs/plans/dmf-rpi-flypack-appliance-implementation-plan.md
docs/plans/dmf-unified-app-admin-helper-plan.md
docs/plans/dmf-unseal-posture-tiered-framework-plan.md
docs/plans/dmf-v0-1-commitment-and-30-day-focus-cut-plan.md
docs/plans/dmf-v0-2-ebu-facility-orchestration-re-anchor-plan.md
docs/plans/dmf-v0-2-presentable-journey-execution-plan.md
docs/plans/dmf-vendor-multi-tenancy-vision.md
docs/plans/dmf-workstream-a-ci-recovery-fix-spec.md
docs/plans/dmf-workstream-a-clean-history-import-and-canonical-flip-execution-spec.md
docs/plans/dmf-workstream-a-pre-a-tooling-implementation-spec.md
docs/plans/dmf-workstream-b-dmf-env-public-surface-scrub-spec.md
docs/plans/dmf-workstream-d-github-first-governance-execution-spec.md
docs/plans/dmf-workstream-e1-pr-gate-ci-execution-spec.md
docs/plans/dmf-zot-machine-identity-service-account-plan.md
docs/plans/llm-restricted-git-pipeline-dev-testing-production-isolation-plan.md
docs/plans/move-1-gate-2-trials-and-tribulations.md'

# Links into docs/archive/ that live docs keep on purpose. Each line is a
# file path, " -> ", and the exact link target. docs/INDEX.md and
# docs/OPEN-QUESTIONS.md map the docs tree, so they point readers at the
# archive.
ARCHIVE_LINK_EXEMPT='docs/INDEX.md -> archive/questions/
docs/INDEX.md -> archive/audits/
docs/INDEX.md -> archive/baselines/
docs/INDEX.md -> archive/inventory/
docs/INDEX.md -> archive/README.md
docs/OPEN-QUESTIONS.md -> archive/questions/'

# Entries that only the fixtures under tests/surface/ use. They stand in for
# the real lists above, so the tests do not depend on the real tree.
FIXTURE_ADR_CEILINGS='docs/decisions/9999-ceiling-fixture.md 90'
FIXTURE_FROZEN_PLANS='docs/plans/frozen-fixture-plan.md'

# Trees that are never "live": the archive and the frozen trees.
EXCLUDED_RE='(^|/)docs/(archive|handoffs|agentic)/'
# Conventional upper-case names that the filename rule allows.
ALLOWED_NAMES_RE='^(README|INDEX)\.md$'
# Upper-case landmark names (JOURNEY.md, OPEN-QUESTIONS.md) that the filename
# rule allows only for a file that sits directly under docs/.
LANDMARK_NAMES_RE='^[A-Z][A-Z0-9]*(-[A-Z0-9]+)*\.md$'
# Live docs that keep a name the filename rule rejects. Each entry is an
# exact path relative to the repository root, one per line. A file leaves its
# list, and gets a kebab-case name, when the reader that pins it moves.

# These files keep their names because a reader outside the docs links to
# them or reads them by path. Rename each one when those links move.
PINNED_BY_COMPONENT_LINKS='docs/architecture/DMF EBU Mapping (2026-04-25).md
docs/architecture/DMF Function Catalog Model.md
docs/architecture/DMF Platform Plan.md
docs/architecture/DMF Provider Descriptor Model.md
docs/design/DMF Console Glossary.md
docs/plans/AWX NetBox Inventory Sync Fix 2026-05-04.md
docs/plans/DMF AWX On-Demand Scale-to-Zero Plan 2026-06-18.md
docs/plans/DMF App Admin Account Drift Audit and Realignment Plan 2026-05-14.md
docs/plans/DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md
docs/plans/DMF Console Initial Implementation Plan 2026-04-26.md
docs/plans/DMF Console UI Round Plan 2026-08-21.md
docs/plans/DMF Deployment Workflow and Manifest Plan.md
docs/plans/DMF In-Cluster Ansible Runner Pod Implementation Plan 2026-05-14.md
docs/plans/DMF Init Bootstrap Container Plan 2026-06-02.md
docs/plans/DMF Move 1 Path A Reset 2026-05-12.md
docs/plans/DMF NMOS Crosspoint Media Function Plan 2026-06-21.md
docs/plans/DMF Orchestrator and Renumbering Plan 2026-04-22.md
docs/plans/DMF Per-App Identity Feasibility Survey 2026-05-24.md
docs/plans/DMF Pre-Release Compliance Readiness Plan 2026-05-11.md
docs/plans/DMF Public Container Registry Publishing Plan 2026-05-19.md
docs/plans/DMF Secret Ownership and OpenBao Migration Plan.md
docs/plans/DMF v0.2b Multi-Source Switch Spec 2026-07-15.md
docs/plans/Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md'

# This file keeps its name because the umbrella allowlists in .gitleaks.toml
# and patterns/public-manifest.toml match its exact path. Rename the file
# together with those entries.
PINNED_BY_UMBRELLA_ALLOWLISTS='docs/architecture/DMF Release and Contribution Model.md'

# These files keep their names because an in-repo reader pins the path.
# The agentic scripts under bin/agentic/ read the harness plan; it moves when
# those readers migrate. bin/render-bpmn.sh reads the BPMN stylesheet, and
# docs/processes/ stays in place.
PINNED_BY_IN_REPO_READERS='docs/plans/DMF Agentic Harness Plan 2026-05-11.md
docs/processes/diagrams/_styles.css'

PINNED_NAMES="$PINNED_BY_COMPONENT_LINKS
$PINNED_BY_UMBRELLA_ALLOWLISTS
$PINNED_BY_IN_REPO_READERS"

MODE="warn"
SUB="all"
ROOT=""
FILES=()

while [ $# -gt 0 ]; do
    case "$1" in
        --warn) MODE="warn" ;;
        --strict) MODE="strict" ;;
        --root) ROOT="${2:?--root needs a directory}"; shift ;;
        --file) FILES+=("${2:?--file needs a path}"); shift ;;
        size|statuslog|filenames|placement|all) SUB="$1" ;;
        -h|--help)
            sed -n '/^# check-surface/,/^$/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "check-surface: unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ -z "$ROOT" ]; then
    ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi
# Use absolute physical paths for the root and for --file arguments, so that
# ./docs/x.md, docs/x.md and an absolute path all give the same result.
ROOT="$(cd "$ROOT" 2>/dev/null && pwd -P)" \
    || { echo "check-surface: no such directory: $ROOT" >&2; exit 2; }

FINDINGS=0
finding() {
    FINDINGS=$((FINDINGS + 1))
    printf 'check-surface: %s\n' "$*"
}

wants() { [ "$SUB" = all ] || [ "$SUB" = "$1" ]; }

is_excluded() { printf '%s\n' "$1" | grep -qE "$EXCLUDED_RE"; }

line_count() { wc -l < "$1" | tr -d ' '; }

# Number of lines outside the working-model block (marker lines excluded from
# the count). Without a complete START..END span, this is the whole file.
lines_outside_block() {
    awk '
        { total++ }
        s == 0 && /WORKING-MODEL-BLOCK-START/ { s = NR }
        s > 0 && e == 0 && /WORKING-MODEL-BLOCK-END/ { e = NR }
        END { if (s > 0 && e >= s) total -= (e - s + 1); print total + 0 }
    ' "$1"
}

# check_size FILE LABEL BUDGET [outside-block]
check_size() {
    local n
    if [ "${4:-}" = outside-block ]; then
        n="$(lines_outside_block "$1")"
    else
        n="$(line_count "$1")"
    fi
    if [ "$n" -gt "$3" ]; then
        finding "$2: $n lines, budget is $3 ($1)"
    fi
}

# Path relative to the scanned root. A fixture tree under tests/surface/good
# or tests/surface/bad acts as its own root.
rel_path() {
    local p="$1"
    p="${p#"$ROOT"/}"
    p="${p#tests/surface/good/}"
    p="${p#tests/surface/bad/}"
    printf '%s\n' "$p"
}

# A fixture is a file under tests/surface/good/ or tests/surface/bad/.
is_fixture() {
    printf '%s\n' "${1#"$ROOT"/}" | grep -qE '(^|/)tests/surface/(good|bad)/'
}

# adr_ceiling REL [fixture]: the ceiling recorded for an ADR, or nothing.
adr_ceiling() {
    local list="$ADR_CEILINGS"
    [ "${2:-}" = fixture ] && list="$FIXTURE_ADR_CEILINGS"
    printf '%s\n' "$list" | awk -v p="$1" '$1 == p { print $2; exit }'
}

# Run the size or status check that fits a file. A fixture is classified by
# its base name. A file in the real tree is checked only when the tree scan
# would check it: the top-level README.md, AGENTS.md and STATUS.md, and the
# ADRs directly under docs/decisions/.
check_file_size() {
    local path="$1" base lower rel kind="" ceiling
    base="$(basename "$path")"
    rel="$(rel_path "$path")"
    if is_fixture "$path"; then
        kind=fixture
    else
        printf '%s\n' "$rel" \
            | grep -qE '^((README|AGENTS|STATUS)\.md|docs/decisions/[0-9]{4}-[^/]*\.md)$' \
            || return 0
    fi
    lower="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in
        status*)
            wants statuslog && check_size "$path" "status log" "$BUDGET_STATUS" ;;
        readme*)
            wants size && check_size "$path" "README" "$BUDGET_README" ;;
        agents*)
            wants size && check_size "$path" "AGENTS.md" "$BUDGET_AGENTS" outside-block ;;
        adr-*|[0-9][0-9][0-9][0-9]-*)
            case "$lower" in 0000-*) return 0 ;; esac
            wants size || return 0
            ceiling="$(adr_ceiling "$rel" "$kind")"
            if [ -n "$ceiling" ]; then
                check_size "$path" "ADR (shrink-only ceiling)" "$ceiling"
            else
                check_size "$path" "ADR" "$BUDGET_ADR"
            fi
            ;;
    esac
    return 0
}

# The filename rule applies to files under a docs/ directory.
check_file_name() {
    local path="$1" base rel
    rel="$(rel_path "$path")"
    base="$(basename "$path")"
    wants filenames || return 0
    printf '%s\n' "$path" | grep -qE '(^|/)docs/' || return 0
    is_excluded "$path" && return 0
    printf '%s\n' "$base" | grep -qE "$ALLOWED_NAMES_RE" && return 0
    printf '%s\n' "$rel" | grep -qxF -e "$PINNED_NAMES" && return 0
    if printf '%s\n' "$rel" | grep -qE '^docs/[^/]+$' \
        && printf '%s\n' "$base" | grep -qE "$LANDMARK_NAMES_RE"; then
        return 0
    fi
    if printf '%s\n' "$base" | grep -q ' '; then
        finding "filename has a space: $path"
    elif printf '%s\n' "$base" | grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}'; then
        finding "filename has a date: $path"
    elif ! printf '%s\n' "$base" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*(\.[a-z0-9]+)+$'; then
        finding "filename is not kebab-case: $path"
    fi
    return 0
}

frontmatter_status() {
    awk '
        NR == 1 { if ($0 != "---") exit; next }
        /^---[ \t]*$/ { exit }
        /^status:/ { sub(/^status:[ \t]*/, ""); gsub(/["\047]/, ""); sub(/[ \t].*$/, ""); print; exit }
    ' "$1"
}

# Link targets in a file that point into an archive/ directory. A trailing
# #anchor is dropped. A target with a URL scheme is not an in-repo link and is
# skipped, with one exception: a URL into docs/archive/ of this repository
# (github.com/dmfdeploy/dmfdeploy/blob/REF/docs/archive/...) is skipped only
# when REF is a 40-character commit SHA. A moving ref such as main is reported.
archive_link_targets() {
    local t
    grep -oE '\]\([^)]*archive/[^)]*\)' "$1" \
        | sed -E 's/^\]\(//; s/\)$//; s/#.*$//' \
        | while IFS= read -r t; do
            if printf '%s\n' "$t" | grep -qE '^[a-zA-Z][a-zA-Z0-9+.-]*:'; then
                printf '%s\n' "$t" | grep -qE '^https?://github\.com/dmfdeploy/dmfdeploy/blob/[^/]+/docs/archive/' \
                    || continue
                printf '%s\n' "$t" | grep -qE '^https?://github\.com/dmfdeploy/dmfdeploy/blob/[0-9a-f]{40}/docs/archive/' \
                    && continue
            fi
            printf '%s\n' "$t"
        done || true
}

# archive_link_allowed REL TARGET: an ADR may link to its own extract under
# docs/archive/decisions/, and the entries in ARCHIVE_LINK_EXEMPT stand.
archive_link_allowed() {
    local rel="$1" target="$2"
    if printf '%s\n' "$rel" | grep -qE '^docs/decisions/[^/]+\.md$' \
        && [ "$target" = "../archive/decisions/$(basename "$rel")" ]; then
        return 0
    fi
    printf '%s\n' "$ARCHIVE_LINK_EXEMPT" | grep -qxF -e "$rel -> $target"
}

check_file_placement() {
    local path="$1" base st rel frozen="$FROZEN_PLANS" target
    base="$(basename "$path")"
    rel="$(rel_path "$path")"
    wants placement || return 0
    is_excluded "$path" && return 0
    case "$path" in *.md) ;; *) return 0 ;; esac
    if is_fixture "$path"; then
        frozen="$FIXTURE_FROZEN_PLANS"
    else
        # The tree scan covers docs/ only.
        case "$rel" in docs/*) ;; *) return 0 ;; esac
    fi
    # A plan sits in a directory named plans (docs/plans/ in the real tree).
    if printf '%s\n' "$path" | grep -qE '(^|/)plans/[^/]+$' && [ "$base" != INDEX.md ]; then
        st="$(frontmatter_status "$path")"
        case "$st" in
            active|draft) ;;
            "") finding "plan has no status in its frontmatter: $path" ;;
            *)
                printf '%s\n' "$frozen" | grep -qxF -e "$rel" \
                    || finding "plan status is '$st', docs/plans/ holds only active or draft: $path" ;;
        esac
    fi
    # A live doc must not link into the archive.
    while IFS= read -r target; do
        [ -n "$target" ] || continue
        archive_link_allowed "$rel" "$target" && continue
        finding "live doc links into docs/archive/: $path -> $target"
    done < <(archive_link_targets "$path")
    return 0
}

# Tree scan only: report list entries that no longer match the tree, so the
# ADR_CEILINGS and FROZEN_PLANS lists only shrink.
check_list_entries() {
    local p c n st
    if wants size; then
        while read -r p c; do
            [ -n "$p" ] || continue
            if [ ! -f "$p" ]; then
                finding "ADR_CEILINGS entry has no file, remove it: $p"
                continue
            fi
            n="$(line_count "$p")"
            if [ "$n" -le "$BUDGET_ADR" ]; then
                finding "ADR fits the budget now, remove its ADR_CEILINGS entry: $p"
            elif [ "$n" -lt "$c" ]; then
                finding "ADR shrank to $n lines, lower its ceiling from $c to $n: $p"
            fi
        done <<< "$ADR_CEILINGS"
    fi
    if wants placement; then
        while IFS= read -r p; do
            [ -n "$p" ] || continue
            if [ ! -f "$p" ]; then
                finding "FROZEN_PLANS entry has no file, remove it: $p"
                continue
            fi
            st="$(frontmatter_status "$p")"
            case "$st" in
                active|draft) finding "plan is $st again, remove its FROZEN_PLANS entry: $p" ;;
            esac
        done <<< "$FROZEN_PLANS"
    fi
    return 0
}

check_one() {
    check_file_size "$1"
    check_file_name "$1"
    check_file_placement "$1"
}

if [ ${#FILES[@]} -gt 0 ]; then
    for f in "${FILES[@]}"; do
        [ -f "$f" ] || { echo "check-surface: no such file: $f" >&2; exit 2; }
        f="$(cd "$(dirname "$f")" && pwd -P)/$(basename "$f")"
        check_one "$f"
    done
else
    cd "$ROOT"
    # Top-level budgeted files.
    for f in README.md AGENTS.md STATUS.md; do
        [ -f "$f" ] && check_file_size "$f"
    done
    # ADRs.
    if [ -d docs/decisions ]; then
        for f in docs/decisions/[0-9][0-9][0-9][0-9]-*.md; do
            [ -f "$f" ] && check_file_size "$f"
        done
    fi
    # Every file under docs/ (names), plus plans and links (markdown).
    if [ -d docs ]; then
        while IFS= read -r f; do
            check_file_name "$f"
            check_file_placement "$f"
        done < <(find docs -type f | LC_ALL=C sort)
    fi
    check_list_entries
fi

if [ "$FINDINGS" -gt 0 ]; then
    echo "check-surface: $FINDINGS finding(s) ($MODE mode)"
    [ "$MODE" = strict ] && exit 1
else
    echo "check-surface: clean"
fi
exit 0
