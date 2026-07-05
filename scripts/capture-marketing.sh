#!/usr/bin/env bash
#
# capture-marketing.sh — App Store marketing screenshots for Meshtastic.
#
# Builds the app (iOS simulator + Mac Catalyst), then for each device/appearance:
#   • iPhone / iPad (simulator): boot, set appearance + a Seattle GPS location, reinstall (clean
#     SwiftData store), grant location up front, launch with the marketing seed + capture flags.
#   • Mac Catalyst: launch the built .app directly at a MacBook-Air window size.
# The in-app MarketingCapture coordinator (DEBUG only) seeds a curated ~140-node Seattle mesh, forces
# the requested light/dark appearance, walks each screen, snapshots the window, writes PNGs into the
# app sandbox, and exits. This script then pulls the PNGs into ./marketing/<device>/<appearance>/.
#
# Env: SKIP_BUILD=1 reuses already-built apps (skip the slow SwiftLint-heavy build).
# Requires Xcode 16+ and the target simulators. Safe to re-run.
#
set -euo pipefail
cd "$(dirname "$0")/.."

# ---- Config ----------------------------------------------------------------
WORKSPACE="Meshtastic.xcworkspace"
SCHEME="Meshtastic"
BUNDLE_ID="gvh.MeshtasticClient"
APP_NAME="Meshtastic.app"
# DerivedData OUTSIDE the repo: the project's SwiftLint build phase lints everything under the source
# tree, so an in-repo derivedDataPath would make it lint the vendored SPM checkouts and fail.
DERIVED="${TMPDIR:-/tmp}/meshtastic-marketing-build"
DERIVED_MAC="${TMPDIR:-/tmp}/meshtastic-marketing-build-mac"
OUT_DIR="marketing"
SEATTLE_LOC="47.6205,-122.3400"       # central Seattle — the map frames on the mesh centroid here
MAC_WINDOW="1280x832"                 # 13" MacBook Air logical size (points); @2x = 2560x1664
LAUNCH_ARGS=(--meshtastic-marketing-seed --marketing-capture)
EXPECTED_SHOTS=7
APPEARANCES=("light" "dark")

# Simulator devices (App Store sizes). Edit to taste.
SIM_DEVICES=("iPhone 17 Pro Max" "iPhone 17 Pro" "iPad Pro 13-inch (M4)")

SIM_APP="$DERIVED/Build/Products/Debug-iphonesimulator/$APP_NAME"
MAC_APP="$DERIVED_MAC/Build/Products/Debug-maccatalyst/$APP_NAME"

slugify() { echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/-*$//'; }

# ---- Build -----------------------------------------------------------------
if [ "${SKIP_BUILD:-0}" != "1" ]; then
	echo "▶︎ Building $SCHEME for iOS Simulator…"
	xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration Debug \
		-sdk iphonesimulator -destination "generic/platform=iOS Simulator" \
		-derivedDataPath "$DERIVED" -quiet build
	echo "▶︎ Building $SCHEME for Mac Catalyst…"
	xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration Debug \
		-destination "platform=macOS,variant=Mac Catalyst" \
		-derivedDataPath "$DERIVED_MAC" -quiet build
fi
[ -d "$SIM_APP" ] || { echo "✗ Simulator app not found at $SIM_APP" >&2; exit 1; }
[ -d "$MAC_APP" ] || echo "⚠︎ Mac Catalyst app not found at $MAC_APP — skipping Catalyst" >&2

# ---- Simulator capture -----------------------------------------------------
udid_for_device() {
	# Fixed-string match on "<name> (" so parens in names like "iPad Pro 13-inch (M4)" aren't treated
	# as regex, and so "iPhone 17 Pro" doesn't match "iPhone 17 Pro Max".
	xcrun simctl list devices available | grep -F "$1 (" | head -1 | grep -oE '[0-9A-Fa-f-]{36}'
}

capture_sim() {
	local device="$1" appear="$2" udid slug cont shots dest count
	udid="$(udid_for_device "$device" || true)"
	if [ -z "${udid:-}" ]; then echo "  ⚠︎ '$device' not available — skipping" >&2; return; fi
	slug="$(slugify "$device")"
	echo "  • $device / $appear"
	xcrun simctl boot "$udid" >/dev/null 2>&1 || true
	xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
	xcrun simctl ui "$udid" appearance "$appear" >/dev/null 2>&1 || true
	xcrun simctl uninstall "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
	xcrun simctl install "$udid" "$SIM_APP"
	xcrun simctl privacy "$udid" grant location "$BUNDLE_ID" >/dev/null 2>&1 || true
	xcrun simctl location "$udid" set "$SEATTLE_LOC" >/dev/null 2>&1 || true
	xcrun simctl launch "$udid" "$BUNDLE_ID" "${LAUNCH_ARGS[@]}" --marketing-appearance "$appear" >/dev/null

	cont="$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data)"
	shots="$cont/Documents/marketing/$appear"
	for _ in $(seq 1 60); do
		count="$(find "$shots" -maxdepth 1 -name '*.png' 2>/dev/null | wc -l | tr -d ' ')"
		[ "${count:-0}" -ge "$EXPECTED_SHOTS" ] && break
		sleep 2
	done
	dest="$OUT_DIR/$slug/$appear"; mkdir -p "$dest"
	if ls "$shots"/*.png >/dev/null 2>&1; then
		cp "$shots"/*.png "$dest"/; echo "    ✓ $(ls "$dest"/*.png | wc -l | tr -d ' ') shots → $dest"
	else echo "    ✗ no screenshots for $device / $appear" >&2; fi
	xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
}

echo "▶︎ Simulator captures"
for device in "${SIM_DEVICES[@]}"; do
	for appear in "${APPEARANCES[@]}"; do capture_sim "$device" "$appear" || echo "    ✗ pass failed: $device / $appear" >&2; done
done

# ---- Mac Catalyst capture --------------------------------------------------
capture_catalyst() {
	local appear="$1" shots dest count
	shots="$HOME/Library/Containers/$BUNDLE_ID/Data/Documents/marketing/$appear"
	echo "  • Mac Catalyst / $appear ($MAC_WINDOW)"
	pkill -f "$APP_NAME/Contents/MacOS/Meshtastic" >/dev/null 2>&1 || true
	sleep 1
	rm -rf "$shots" 2>/dev/null || true
	open -n "$MAC_APP" --args "${LAUNCH_ARGS[@]}" --marketing-appearance "$appear" --marketing-size "$MAC_WINDOW"
	for _ in $(seq 1 60); do
		count="$(find "$shots" -maxdepth 1 -name '*.png' 2>/dev/null | wc -l | tr -d ' ')"
		[ "${count:-0}" -ge "$EXPECTED_SHOTS" ] && break
		sleep 2
	done
	dest="$OUT_DIR/mac-catalyst/$appear"; mkdir -p "$dest"
	if ls "$shots"/*.png >/dev/null 2>&1; then
		cp "$shots"/*.png "$dest"/; echo "    ✓ $(ls "$dest"/*.png | wc -l | tr -d ' ') shots → $dest"
	else echo "    ✗ no screenshots for Mac Catalyst / $appear" >&2; fi
	pkill -f "$APP_NAME/Contents/MacOS/Meshtastic" >/dev/null 2>&1 || true
}

if [ -d "$MAC_APP" ]; then
	echo "▶︎ Mac Catalyst captures"
	for appear in "${APPEARANCES[@]}"; do capture_catalyst "$appear" || echo "    ✗ pass failed: Mac Catalyst / $appear" >&2; done
fi

echo "✓ Done. Output in ./$OUT_DIR/"
