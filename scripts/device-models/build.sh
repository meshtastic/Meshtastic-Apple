#!/bin/bash
# Copyright(c) Garth Vander Houwen 10/14/26.
#
# Builds a real-size .usdz for every spec in specs/, from the matching device
# SVG on the flasher, then checks and renders each one for review.
#
#   scripts/device-models/build.sh [--install] [name ...]
#
# Output goes to scripts/device-models/out/ (git-ignored) along with
# contact-sheet.html. --install also copies the models into
# Meshtastic/Resources/DeviceModels, which the app bundles.
# Needs uv (brew install uv); Python packages are fetched on first run.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
OUT="$HERE/out"
CACHE="$OUT/svg"
INSTALL_DIR="$REPO/Meshtastic/Resources/DeviceModels"
IMAGE_BASE_URL="https://flasher.meshtastic.org/img/devices"
API_URL="https://api.meshtastic.org/resource/deviceHardware"
VENDORS='seeed|rak|elecrow|thinknode|crowpanel|sensecap|xiao|wio|muzi|heltec|lilygo'

install=false
names=()
for arg in "$@"; do
	case "$arg" in
		--install) install=true ;;
		*) names+=("$arg") ;;
	esac
done

mkdir -p "$OUT" "$CACHE"
if [ ${#names[@]} -eq 0 ]; then
	for spec in "$HERE"/specs/*.toml; do names+=("$(basename "$spec" .toml)"); done
fi

# The renderer is compiled once and reused.
if [ ! -x "$OUT/render" ] || [ "$HERE/render.swift" -nt "$OUT/render" ]; then
	swiftc -O -o "$OUT/render" "$HERE/render.swift"
fi

failed=()
built=()
for name in "${names[@]}"; do
	spec="$HERE/specs/$name.toml"
	svg="$CACHE/$name.svg"
	url="$IMAGE_BASE_URL/$name.svg"
	[ -f "$spec" ] || { echo "no spec for $name"; failed+=("$name (no spec)"); continue; }
	# A spec can name our own drawing instead, for a device whose flasher
	# illustration isn't a front view.
	drawing=$(sed -n 's/^drawing *= *"\(.*\)".*/\1/p' "$spec")
	if [ -n "$drawing" ]; then
		svg="$HERE/$drawing"
		url="https://github.com/meshtastic/Meshtastic-Apple/blob/main/scripts/device-models/$drawing"
		[ -f "$svg" ] || { echo "$name: $drawing is missing"; failed+=("$name (missing drawing)"); continue; }
	elif ! curl -sfL -o "$svg" "$url" || ! head -c 512 "$svg" | grep -q "<svg"; then
		echo "$name: $url is not an SVG"
		failed+=("$name (missing on flasher)")
		continue
	fi
	log="$OUT/$name.check.txt"
	if uv run -q "$HERE/svg2usdz.py" "$spec" "$svg" "$OUT/$name.usdz" --source-url "$url" 2>&1 | tee "$log" \
		&& uv run -q --python 3.12 --with usd-core usdchecker --arkit "$OUT/$name.usdz" >>"$log" 2>&1 \
		&& "$OUT/render" "$OUT/$name.usdz" "$OUT/$name.png" 600 >>"$log" 2>&1; then
		built+=("$name")
	else
		echo "$name: build or check failed (see $log)"
		failed+=("$name (build/check)")
	fi
done

# Vendor SVGs the API lists that have no spec yet.
missing=$(curl -sf "$API_URL" | python3 -c "
import json, re, sys, os
seen = set()
for d in json.load(sys.stdin):
    text = ' '.join([d.get('displayName', ''), d.get('hwModelSlug', '')] + d.get('tags', []))
    if not re.search(r'$VENDORS', text, re.I):
        continue
    for img in d.get('images') or []:
        name = img.rsplit('.', 1)[0]
        if name != 'meshtasticd_tux' and not os.path.exists('$HERE/specs/' + name + '.toml'):
            seen.add(name)
print(' '.join(sorted(seen)))
" || true)

# Contact sheet for review.
python3 - "$OUT" "$HERE/specs" "${built[@]+"${built[@]}"}" <<'PY'
import html, os, re, sys
out, specs, names = sys.argv[1], sys.argv[2], sys.argv[3:]
cards = []
for n in names:
    with open(os.path.join(specs, n + ".toml")) as f:
        spec = f.read()
    def field(k):
        m = re.search(rf'^{k}\s*=\s*"?([^"\n]*)"?', spec, re.M)
        return m.group(1) if m else ""
    size = f'{field("width_mm")} × {field("height_mm")} × {field("depth_mm")} mm'
    kb = os.path.getsize(os.path.join(out, n + ".usdz")) // 1024
    src = field("source")
    flag = "" if field("confidence") in ("", "vendor") else f' <b>{html.escape(field("confidence"))}</b>'
    cards.append(
        f'<figure><img src="{n}.png" alt="{n}"><figcaption><a href="{n}.usdz">{n}</a><br>{size} · {kb} KB{flag}'
        f'<br><small>{html.escape(field("covers"))}</small>'
        + (f'<br><small><a href="{html.escape(src)}">source</a></small>' if src else "")
        + "</figcaption></figure>"
    )
page = """<!doctype html><meta charset="utf-8"><title>Device models</title>
<style>body{font:14px system-ui;margin:16px;background:#f4f4f4}main{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:12px}
figure{margin:0;background:#fff;padding:8px;border-radius:8px}img{width:100%}</style><main>""" + "".join(cards) + "</main>"
with open(os.path.join(out, "contact-sheet.html"), "w") as f:
    f.write(page)
PY

if $install && [ ${#built[@]} -gt 0 ]; then
	mkdir -p "$INSTALL_DIR"
	for name in "${built[@]}"; do cp "$OUT/$name.usdz" "$INSTALL_DIR/"; done
	echo "installed ${#built[@]} models into ${INSTALL_DIR#"$REPO"/}"
fi

echo "built ${#built[@]}: ${built[*]-}"
[ ${#failed[@]} -eq 0 ] || printf 'failed: %s\n' "${failed[@]}"
[ -z "$missing" ] || echo "no spec yet: $missing"
echo "review: $OUT/contact-sheet.html"
