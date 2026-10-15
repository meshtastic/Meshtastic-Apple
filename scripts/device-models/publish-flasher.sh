#!/bin/bash
# Copyright(c) Garth Vander Houwen 10/14/26.
#
# Opens a web-flasher pull request with the models from out/ in
# public/models/devices/, next to the README carrying the copyright notice.
# Each USDZ also gets a GLB for Android, desktop and the web, made by the
# flasher's own scripts/usdz2glb.py so it matches the GLBs already there.
# Run build.sh first and review out/contact-sheet.html. Needs uv.
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

# A first publish adds the models; later ones update them.
if compgen -G "$DEST/*.usdz" >/dev/null; then
	title="Update the device models"
	summary="Rebuilds the device models in \`public/models/devices/\` from the current specs in Meshtastic-Apple's \`scripts/device-models/\`, and regenerates their GLBs."
else
	title="Add real-size 3D device models"
	summary="Adds real-size USDZ models in \`public/models/devices/\`, one for each device SVG that has a spec in Meshtastic-Apple's \`scripts/device-models/\`, and a GLB of each for glTF viewers. They will be served at \`/models/devices/<name>.usdz\` and \`<name>.glb\`."
fi
mkdir -p "$DEST"
cp "$HERE/flasher-README.md" "$DEST/README.md"
cp "${models[@]}" "$DEST/"
published=()
for m in "${models[@]}"; do published+=("$DEST/$(basename "$m")"); done
[ -f scripts/usdz2glb.py ] || { echo "scripts/usdz2glb.py is missing from the flasher; can't make the GLBs"; exit 1; }
uv run -q scripts/usdz2glb.py "${published[@]}" --out "$DEST"
git add "$DEST"
if git diff --cached --quiet; then
	echo "no changes to publish"
	exit 0
fi

names=""
for m in "${models[@]}"; do names+="${names:+ }$(basename "$m" .usdz)"; done
git commit -q -m "$title" -m "USDZ models built from the device SVGs, each with a GLB converted from it: $names"
git push -q -u origin "$BRANCH"
# The body comes in on stdin: a here-document inside "$(...)" breaks on the
# apostrophes in it under macOS's bash 3.2.
gh pr create --base main --head "$BRANCH" --title "$title" --body-file - <<EOF
## Summary
$summary

## What changed
- \`public/models/devices/*.usdz\`: $names
- \`public/models/devices/*.glb\`: the same models, converted with \`scripts/usdz2glb.py\`
- \`public/models/devices/README.md\`: the Meshtastic LLC asset notice, worded for the models. The notice is also embedded in each file.

## Testing
Each model passes \`usdchecker --arkit\` and was checked against the manufacturer's published dimensions. The GLBs come from the flasher's converter, unchanged.
EOF
