#!/usr/bin/env bash
# scripts/cut-release-docs.sh
# Rebuilds in-app HTML docs without the pre-release banner, commits, and tags.
# Usage: bash scripts/cut-release-docs.sh <version>
# See specs/013-docs-release-versioning/contracts/script-contract.md for full interface.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ── Output helpers ─────────────────────────────────────────────────────────────
info()  { printf '\033[0;32m✓ %s\033[0m\n' "$*"; }
warn()  { printf '\033[0;33mwarning: %s\033[0m\n' "$*" >&2; }
error() { printf '\033[0;31merror: %s\033[0m\n' "$*" >&2; exit 1; }

# ── Usage ──────────────────────────────────────────────────────────────────────
usage() {
    printf 'Usage: bash scripts/cut-release-docs.sh <version>\n' >&2
    printf '\n' >&2
    printf '  <version>   Semantic version matching MARKETING_VERSION in project.pbxproj\n' >&2
    printf '              Format: X.Y.Z (digits only, e.g. 2.7.14)\n' >&2
    printf '\n' >&2
    printf 'Example:\n' >&2
    printf '  bash scripts/cut-release-docs.sh 2.7.14\n' >&2
    if [[ -n "${1:-}" ]]; then
        printf '\nerror: %s\n' "$1" >&2
    fi
    exit 1
}

# ── Argument parsing ───────────────────────────────────────────────────────────
[[ $# -eq 0 ]] && usage "version argument is required"
[[ $# -gt 1 ]] && usage "too many arguments (expected exactly one)"
VERSION="$1"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage "invalid version '$VERSION' — expected X.Y.Z (e.g. 2.7.14)"

# ── Pre-flight: MARKETING_VERSION consistency & match ─────────────────────────
check_marketing_version() {
    local pbxproj="$REPO_ROOT/Meshtastic.xcodeproj/project.pbxproj"
    [[ -f "$pbxproj" ]] || error "project.pbxproj not found at $pbxproj"

    mapfile -t versions < <(grep -E 'MARKETING_VERSION = [0-9]' "$pbxproj" \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -u)

    if [[ ${#versions[@]} -eq 0 ]]; then
        error "no MARKETING_VERSION entries found in project.pbxproj"
    fi

    if [[ ${#versions[@]} -gt 1 ]]; then
        error "inconsistent MARKETING_VERSION values in project.pbxproj: ${versions[*]}"
    fi

    if [[ "${versions[0]}" != "$VERSION" ]]; then
        error "argument '$VERSION' does not match MARKETING_VERSION '${versions[0]}' in project.pbxproj"
    fi
}

# ── Pre-flight: git tag availability ──────────────────────────────────────────
check_tag_available() {
    local existing
    existing="$(git -C "$REPO_ROOT" tag -l "v${VERSION}")"
    if [[ -n "$existing" ]]; then
        error "tag 'v${VERSION}' already exists — delete it first with: git tag -d v${VERSION}"
    fi
}

# ── Pre-flight: docs-related paths are clean ──────────────────────────────────
check_docs_clean() {
    local dirty
    dirty="$(git -C "$REPO_ROOT" status --porcelain \
        -- docs/ Meshtastic/Resources/docs/ scripts/ \
        | grep -v '^?' || true)"
    if [[ -n "$dirty" ]]; then
        error "$(printf 'docs-related paths have uncommitted changes:\n%s' "$dirty")"
    fi
}

# ── Stale PNG warning ──────────────────────────────────────────────────────────
warn_stale_pngs() {
    local screenshots_dir="$REPO_ROOT/Meshtastic/Resources/docs/assets/screenshots"
    [[ -d "$screenshots_dir" ]] || return 0

    # Find newest .md modification time
    local newest_md
    newest_md="$(find "$REPO_ROOT/docs" -name '*.md' -print0 \
        | xargs -0 stat -f '%m %N' 2>/dev/null \
        | sort -rn | head -1 | awk '{print $2}')"
    [[ -n "$newest_md" ]] || return 0

    # Find all PNGs older than the newest .md
    local stale_pngs=()
    while IFS= read -r -d '' png; do
        if [[ "$newest_md" -nt "$png" ]]; then
            stale_pngs+=("$(basename "$png")")
        fi
    done < <(find "$screenshots_dir" -name '*.png' -print0)

    if [[ ${#stale_pngs[@]} -gt 0 ]]; then
        warn "the following doc screenshots may be stale (newer .md exists):"
        for f in "${stale_pngs[@]}"; do
            warn "  $f"
        done
        warn "run snapshot tests and copy-snapshots.sh before submitting to App Store"
    fi
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
    # Pre-flight checks (all read-only — no files modified on failure)
    check_marketing_version
    check_tag_available
    check_docs_clean
    info "All pre-flight checks passed (version: $VERSION)"

    # Rebuild in-app docs without --beta
    info "Rebuilding in-app docs without pre-release banner..."
    bash "$REPO_ROOT/scripts/build-docs.sh" --output "$REPO_ROOT/Meshtastic/Resources/docs"

    # Copy doc-referenced screenshots
    info "Copying doc screenshots..."
    bash "$REPO_ROOT/scripts/copy-snapshots.sh" \
        --output "$REPO_ROOT/Meshtastic/Resources/docs/assets/screenshots"

    # Warn on stale PNGs (non-blocking)
    warn_stale_pngs

    # Stage and commit
    info "Staging Meshtastic/Resources/docs/..."
    git -C "$REPO_ROOT" add Meshtastic/Resources/docs/
    git -C "$REPO_ROOT" commit -m "docs: rebuild for v${VERSION} release"
    local short_sha
    short_sha="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"

    # Count changed HTML files for summary
    local changed_count
    changed_count="$(git -C "$REPO_ROOT" diff-tree --no-commit-id -r --name-only HEAD \
        | grep -c '\.html$' || true)"

    # Create annotated tag
    git -C "$REPO_ROOT" tag -a "v${VERSION}" -m "Release v${VERSION}"

    # Success summary
    echo ""
    info "Rebuilt in-app docs without pre-release banner"
    info "${changed_count} HTML file(s) changed in commit ${short_sha}"
    info "Tag v${VERSION} created → ${short_sha}"
    echo ""
    printf 'Next steps:\n'
    printf '  git push origin %s\n' "$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
    printf '  git push origin v%s\n' "$VERSION"
}

main
