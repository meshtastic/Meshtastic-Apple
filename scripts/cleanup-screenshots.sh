#!/usr/bin/env bash
# scripts/cleanup-screenshots.sh
# Removes orphaned screenshots from docs/assets/screenshots/ that are:
#   1. NOT referenced by any markdown file under docs/
#   2. NOT listed in the MANUAL_SCREENSHOTS manifest
#
# Usage: bash scripts/cleanup-screenshots.sh [--dry-run]
#
# With --dry-run, prints what would be deleted without removing anything.

set -euo pipefail

DRY_RUN=false
while [[ $# -gt 0 ]]; do
	case "$1" in
		--dry-run) DRY_RUN=true; shift ;;
		*) echo "Unknown option: $1" >&2; exit 1 ;;
	esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCS_DIR="$REPO_ROOT/docs"
SOURCE_DIR="$DOCS_DIR/assets/screenshots"
MANIFEST="$SOURCE_DIR/MANUAL_SCREENSHOTS"

if [[ ! -d "$SOURCE_DIR" ]]; then
	echo "No screenshots directory found at $SOURCE_DIR"
	exit 0
fi

# Build set of referenced filenames from markdown
referenced=$(grep -roh 'screenshots/[^")*]*\.png' "$DOCS_DIR" --include='*.md' \
	| sed 's|screenshots/||' \
	| sort -u)

# Build set of manually maintained filenames from manifest
manual=""
if [[ -f "$MANIFEST" ]]; then
	manual=$(grep -v '^\s*#' "$MANIFEST" | grep -v '^\s*$' | sort -u)
fi

# Combine into a single keep-list
keep=$(printf '%s\n%s' "$referenced" "$manual" | grep -v '^\s*$' | sort -u)

removed=0
kept=0
for file in "$SOURCE_DIR"/*.png; do
	[[ -f "$file" ]] || continue
	filename=$(basename "$file")
	if echo "$keep" | grep -qx "$filename"; then
		kept=$((kept + 1))
	else
		if $DRY_RUN; then
			echo "Would remove: $filename"
		else
			rm "$file"
			echo "Removed: $filename"
		fi
		removed=$((removed + 1))
	fi
done

if $DRY_RUN; then
	echo ""
	echo "Dry run complete: $removed orphaned, $kept referenced/manual"
else
	echo ""
	echo "Cleanup complete: removed $removed orphaned, kept $kept screenshots"
fi
