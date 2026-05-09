#!/usr/bin/env bash
# scripts/copy-snapshots.sh
# Copies only doc-referenced snapshot PNGs into the bundled docs output directory.
# Usage: bash scripts/copy-snapshots.sh --output Meshtastic/Resources/docs/assets/screenshots
# See specs/003-app-docs-markdown/contracts/ci-workflow-contract.md for full interface.

set -euo pipefail

OUTPUT_DIR=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--output) OUTPUT_DIR="$2"; shift 2 ;;
		*) echo "Unknown option: $1" >&2; exit 1 ;;
	esac
done

if [[ -z "$OUTPUT_DIR" ]]; then
	echo "Usage: $0 --output <dir>" >&2
	exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCS_DIR="$REPO_ROOT/docs"
SOURCE_DIR="$DOCS_DIR/assets/screenshots"

mkdir -p "$OUTPUT_DIR"

# Scan markdown files for referenced screenshot filenames
referenced=$(grep -roh 'screenshots/[^")*]*\.png' "$DOCS_DIR" --include='*.md' \
	| sed 's|screenshots/||' \
	| sort -u)

copied=0
for filename in $referenced; do
	src="$SOURCE_DIR/$filename"
	if [[ -f "$src" ]]; then
		cp "$src" "$OUTPUT_DIR/$filename"
		copied=$((copied + 1))
	fi
done

echo "Copied $copied doc-referenced screenshots to $OUTPUT_DIR"
