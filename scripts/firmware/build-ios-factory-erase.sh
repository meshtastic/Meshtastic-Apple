#!/usr/bin/env bash
set -euo pipefail

SOURCE_REPOSITORY="https://github.com/meshtastic/nrf52_factory_erase.git"
SOURCE_COMMIT="c48244bd65e54a04fac80de36e59eeb3a12289ad"
NORDIC_PLATFORM_VERSION="10.12.0"
ARDUINO_FRAMEWORK_COMMIT="4f591d0f71f75e5128fab9dc42ac72f1696cf89f"
EXPECTED_S140_611_SHA256="30abd2d05a5c0aeb737f3018539813a31371f919abc6a5dba5e62cddac1fdbc8"
EXPECTED_S140_730_SHA256="919721f1129c9b79edaa631a2eb0e00d0274ba2478af2563233e744613ec4c00"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="$repo_root/Meshtastic/Resources/FirmwareMaintenance"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/meshtastic-ios-factory-erase.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

command -v pio >/dev/null || {
  echo "PlatformIO (pio) is required." >&2
  exit 1
}

git clone --quiet "$SOURCE_REPOSITORY" "$work_dir/source"
git -C "$work_dir/source" checkout --quiet "$SOURCE_COMMIT"
git -C "$work_dir/source" apply "$repo_root/scripts/firmware/nrf52-factory-erase-ios.patch"

python3 - "$work_dir/source/arch/nrf52/nrf52.ini" <<PY
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
text = text.replace("platformio/nordicnrf52@^10.5.0", "platformio/nordicnrf52@$NORDIC_PLATFORM_VERSION")
text = text.replace(
    "https://github.com/geeksville/Adafruit_nRF52_Arduino.git",
    "https://github.com/geeksville/Adafruit_nRF52_Arduino.git#$ARDUINO_FRAMEWORK_COMMIT",
)
path.write_text(text)
PY

(
  cd "$work_dir/source"
  pio run -e s140_nrf52_611_softdevice -e s140_nrf52_730_softdevice
)

mkdir -p "$output_dir"
cp "$work_dir/source/.pio/build/s140_nrf52_611_softdevice/firmware.uf2" \
  "$output_dir/nrf52-factory-erase-s140-6.1.1-ios.uf2"
cp "$work_dir/source/.pio/build/s140_nrf52_730_softdevice/firmware.uf2" \
  "$output_dir/nrf52-factory-erase-s140-7.3.0-ios.uf2"

verify_hash() {
  local expected="$1"
  local file="$2"
  local actual
  actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    echo "Unexpected SHA-256 for $file" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
  fi
}

verify_hash "$EXPECTED_S140_611_SHA256" \
  "$output_dir/nrf52-factory-erase-s140-6.1.1-ios.uf2"
verify_hash "$EXPECTED_S140_730_SHA256" \
  "$output_dir/nrf52-factory-erase-s140-7.3.0-ios.uf2"

echo "Rebuilt and verified iOS-compatible nRF52 factory-erase UF2 images."
