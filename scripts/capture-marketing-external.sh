#!/usr/bin/env bash
#
# capture-marketing-external.sh — App Store screenshots captured from outside the app.
#
# The in-app snapshot path (drawHierarchy) cannot capture a Metal-backed layer, so the Map screen
# came out as an empty grid. This driver instead lets the app seed its data and walk the screens
# while taking the shots itself: simctl for simulators, screencapture for Mac Catalyst. Both read
# the real framebuffer, so map tiles and node overlays are in the image.
#
# The app announces each settled screen by writing marketing/<appearance>/ready-<name> in its
# container and waits; this script screenshots, deletes the marker, and the app moves on.
#
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="gvh.MeshtasticClient"
APP_NAME="Meshtastic.app"
DERIVED="${TMPDIR:-/tmp}/meshtastic-marketing-build"
DERIVED_MAC="${TMPDIR:-/tmp}/meshtastic-marketing-build-mac"
OUT_DIR="marketing-external"
SEATTLE_LOC="47.6205,-122.3400"
# Target content 1280x800 AppKit points — @2x that is 2560x1600, an accepted Mac screenshot size.
# The window size is requested in UIKit points, and Catalyst renders the iPad interface at 77.03%,
# so ask for content/0.7703 and let the measured window tell us the real region.
MAC_CONTENT_W=1280
MAC_CONTENT_H=800
MAC_FRAME="1666x1078"
STEPS=(01-nodes 02-map 03-node-detail 04-messages-channel 05-messages-dm 06-settings 07-discovery)
APPEARANCES=("light" "dark")
# Override with SIM_DEVICES_OVERRIDE="Device A|Device B" to capture a subset.
if [ -n "${SIM_DEVICES_OVERRIDE:-}" ]; then
	IFS='|' read -ra SIM_DEVICES <<<"$SIM_DEVICES_OVERRIDE"
else
	SIM_DEVICES=("iPhone 17 Pro Max" "iPhone 17 Pro" "iPad Pro 13-inch (M4)")
fi
LAUNCH_ARGS=(--meshtastic-marketing-seed --marketing-capture --marketing-external-capture)

SIM_APP="$DERIVED/Build/Products/Debug-iphonesimulator/$APP_NAME"
MAC_APP="$DERIVED_MAC/Build/Products/Debug-maccatalyst/$APP_NAME"

slugify() { echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/-*$//'; }

if [ "${SKIP_BUILD:-0}" != "1" ]; then
	echo "▶︎ Building for iOS Simulator…"
	xcodebuild -workspace Meshtastic.xcworkspace -scheme Meshtastic -configuration Debug \
		-sdk iphonesimulator -destination "generic/platform=iOS Simulator" \
		-derivedDataPath "$DERIVED" -quiet build
	echo "▶︎ Building for Mac Catalyst…"
	xcodebuild -workspace Meshtastic.xcworkspace -scheme Meshtastic -configuration Debug \
		-destination "platform=macOS,variant=Mac Catalyst" \
		-derivedDataPath "$DERIVED_MAC" -quiet build
fi

# Wait for the app to announce a settled screen, capture it, then release the app.
# $1 marker dir, $2 step name, $3 destination png, $4 capture command
drive_step() {
	local dir="$1" name="$2" dest="$3"; shift 3
	local marker="$dir/ready-$name" waited=0
	while [ ! -f "$marker" ]; do
		sleep 0.5; waited=$((waited + 1))
		if [ "$waited" -gt 240 ]; then echo "    ✗ timed out waiting for $name" >&2; return 1; fi
	done
	sleep 1.5   # let the last frame present after the app says it is ready
	# Clear any shot from an earlier run first: otherwise a failed capture leaves the old
	# file in place and this reads as success.
	rm -f "$dest"
	if ! "$@" "$dest" || [ ! -f "$dest" ]; then
		echo "    ✗ capture failed: $name" >&2
		# Leave the marker: releasing it would move the app to the next screen and this one
		# would be missing from the set with nothing to show it.
		return 1
	fi
	rm -f "$marker"
	echo "    ✓ $name"
}

capture_sim() {
	local device="$1" appear="$2" udid slug container dir dest
	udid="$(xcrun simctl list devices available | grep -F "$device (" | head -1 | grep -oE '[0-9A-Fa-f-]{36}')"
	if [ -z "${udid:-}" ]; then echo "  ⚠︎ '$device' unavailable — skipping" >&2; return 0; fi
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
	container="$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data)"
	dir="$container/Documents/marketing/$appear"
	mkdir -p "$OUT_DIR/$slug/$appear"
	for name in "${STEPS[@]}"; do
		drive_step "$dir" "$name" "$OUT_DIR/$slug/$appear/$name.png" \
			xcrun simctl io "$udid" screenshot || true
	done
	xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
}

# Region capture: the window frame includes the title bar, so drop it by the difference between
# the frame height we asked for and the content height we want.
mac_window_rect() {
	local pid="$1"
	osascript <<OSA 2>/dev/null
tell application "System Events"
  set procs to (every process whose unix id is $pid)
  if (count of procs) = 0 then return ""
  set ws to windows of (item 1 of procs)
  if (count of ws) = 0 then return ""
  set w to item 1 of ws
  set p to position of w
  set z to size of w
  return ((item 1 of p) as text) & " " & ((item 2 of p) as text) & " " & ((item 1 of z) as text) & " " & ((item 2 of z) as text)
end tell
OSA
}

capture_catalyst() {
	local appear="$1" dir dest rect x y w h offset
	echo "  • Mac Catalyst / $appear"
	pkill -f "$APP_NAME/Contents/MacOS/Meshtastic" >/dev/null 2>&1 || true
	sleep 1
	dir="$HOME/Library/Containers/$BUNDLE_ID/Data/Documents/marketing/$appear"
	rm -rf "$dir"
	open -n "$MAC_APP" --args "${LAUNCH_ARGS[@]}" --marketing-appearance "$appear" --marketing-size "$MAC_FRAME"
	sleep 8
	local pid
	pid="$(pgrep -f "$APP_NAME/Contents/MacOS/Meshtastic" | head -1)"
	rect="$(mac_window_rect "$pid" || true)"
	if [ -z "${rect:-}" ]; then echo "    ✗ could not read the window frame" >&2; return 1; fi
	read -r x y w h <<<"$rect"
	offset=$((h - MAC_CONTENT_H))
	echo "    window ${w}x${h} at ${x},${y} — trimming ${offset}pt of title bar"
	if [ "$w" -lt "$MAC_CONTENT_W" ] || [ "$offset" -lt 0 ]; then
		echo "    ✗ window is smaller than the capture region — nothing to capture" >&2; return 1
	fi
	mkdir -p "$OUT_DIR/mac-catalyst/$appear"
	for name in "${STEPS[@]}"; do
		drive_step "$dir" "$name" "$OUT_DIR/mac-catalyst/$appear/$name.png" \
			screencapture -x -o -R"$x,$((y + offset)),$MAC_CONTENT_W,$MAC_CONTENT_H" || true
	done
	pkill -f "$APP_NAME/Contents/MacOS/Meshtastic" >/dev/null 2>&1 || true
}

if [ "${MAC_ONLY:-0}" != "1" ]; then
	echo "▶︎ Simulator captures"
	for device in "${SIM_DEVICES[@]}"; do
		for appear in "${APPEARANCES[@]}"; do capture_sim "$device" "$appear" || true; done
	done
fi

if [ -d "$MAC_APP" ]; then
	echo "▶︎ Mac Catalyst captures"
	for appear in "${APPEARANCES[@]}"; do capture_catalyst "$appear" || true; done
fi

echo "✓ Done. Output in ./$OUT_DIR/"
