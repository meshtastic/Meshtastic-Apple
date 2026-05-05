#!/usr/bin/env bash
# scripts/copy-snapshots.sh
# Copies snapshot PNGs from the test suite into the docs assets directory.
# Usage: bash scripts/copy-snapshots.sh --output <dir>
# See specs/003-app-docs-markdown/contracts/ci-workflow-contract.md for full interface.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SNAPSHOTS_DIR="$REPO_ROOT/MeshtasticTests/__Snapshots__/SwiftUIViewSnapshotTests"
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Usage: $0 --output <dir>" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$OUTPUT_DIR" ]]; then
    echo "error: --output <dir> is required" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

if [[ ! -d "$SNAPSHOTS_DIR" ]]; then
    echo "::warning::Snapshots directory not found: $SNAPSHOTS_DIR — skipping PNG copy"
    exit 0
fi

PNG_COUNT=0
while IFS= read -r -d '' png; do
    cp "$png" "$OUTPUT_DIR/"
    PNG_COUNT=$((PNG_COUNT + 1))
done < <(find "$SNAPSHOTS_DIR" -name "*.png" -print0)

if [[ $PNG_COUNT -eq 0 ]]; then
    echo "::warning::No PNG files found in $SNAPSHOTS_DIR — docs will deploy without screenshots"
else
    echo "✅ Copied $PNG_COUNT PNG(s) → $OUTPUT_DIR"
fi
