#!/bin/bash
# Copyright(c) Garth Vander Houwen 10/14/26.
#
# Opens a web-flasher pull request with the models from out/ in
# public/models/devices/, next to the README carrying the copyright notice.
# Run build.sh first and review out/contact-sheet.html.
#
#   scripts/device-models/publish-flasher.sh [path-to-web-flasher-clone]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/out"
FLASHER="${1:-$HOME/Source/web-flasher}"
DEST="public/models/devices"
BRANCH="device-models-$(date +%Y%m%d)"

shopt -s nullglob
models=("$OUT"/*.usdz)
[ ${#models[@]} -gt 0 ] || { echo "no models in $OUT; run build.sh first"; exit 1; }

if [ ! -d "$FLASHER/.git" ]; then
	gh repo clone meshtastic/web-flasher "$FLASHER"
fi
cd "$FLASHER"
# The models add up to tens of MB; the default HTTP buffer rejects the push.
git config http.postBuffer 524288000
if [ -n "$(git status --porcelain)" ]; then
	echo "$FLASHER has uncommitted changes; aborting"
	exit 1
fi
git fetch -q origin main
git switch -q -C "$BRANCH" origin/main

mkdir -p "$DEST"
cp "$HERE/flasher-README.md" "$DEST/README.md"
cp "${models[@]}" "$DEST/"
git add "$DEST"
if git diff --cached --quiet; then
	echo "no changes to publish"
	exit 0
fi

names=""
for m in "${models[@]}"; do names+="${names:+ }$(basename "$m" .usdz)"; done
git commit -q -m "Add real-size 3D device models" -m "USDZ models built from the device SVGs: $names"
git push -q -u origin "$BRANCH"
gh pr create --base main --head "$BRANCH" --title "Add real-size 3D device models" --body "$(cat <<EOF
## Summary
Adds real-size USDZ models in \`public/models/devices/\`, one for each device SVG that has a spec in Meshtastic-Apple's \`scripts/device-models/\`. They will be served at \`/models/devices/<name>.usdz\`.

## What changed
- \`public/models/devices/*.usdz\`: $names
- \`public/models/devices/README.md\`: the same Meshtastic LLC asset notice as \`img/devices\`, worded for the models. The notice is also embedded in each file.

## Testing
Each model passes \`usdchecker --arkit\` and was checked against the manufacturer's published dimensions.
EOF
)"
