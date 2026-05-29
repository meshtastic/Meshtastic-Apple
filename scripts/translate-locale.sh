#!/usr/bin/env bash
# translate-locale.sh — Machine-translate missing strings for a locale using local-localizer.
#
# Usage:
#   scripts/translate-locale.sh <locale> [tone]
#
# Examples:
#   scripts/translate-locale.sh fr
#   scripts/translate-locale.sh de formal
#   scripts/translate-locale.sh ja polite
#
# Requirements:
#   - macOS 26 or later with Apple Silicon
#   - Apple Intelligence enabled (System Settings → Apple Intelligence & Siri)
#   - local-localizer installed: https://github.com/JoshuaSullivan/local-localizer
#     Build and install:
#       git clone https://github.com/JoshuaSullivan/local-localizer.git ~/local-localizer
#       cd ~/local-localizer && swift build -c release
#       cp .build/release/local-localizer ~/bin/local-localizer
#       (ensure ~/bin is on your PATH)

set -euo pipefail

# ── Arguments ──────────────────────────────────────────────────────────────────

LOCALE="${1:-}"
TONE="${2:-professional}"

if [[ -z "$LOCALE" ]]; then
  echo "Usage: scripts/translate-locale.sh <locale> [tone]"
  echo "  tone options: professional (default), formal, informal, neutral, polite"
  echo ""
  echo "Examples:"
  echo "  scripts/translate-locale.sh fr"
  echo "  scripts/translate-locale.sh de formal"
  echo "  scripts/translate-locale.sh ja polite"
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
XCSTRINGS="$REPO_ROOT/Localizable.xcstrings"
GLOSSARY="$REPO_ROOT/scripts/glossary.json"

# ── Check prerequisites ────────────────────────────────────────────────────────

if ! command -v local-localizer &>/dev/null; then
  echo "❌  local-localizer not found on PATH."
  echo ""
  echo "Install it:"
  echo "  git clone https://github.com/JoshuaSullivan/local-localizer.git ~/local-localizer"
  echo "  cd ~/local-localizer && swift build -c release"
  echo "  cp .build/release/local-localizer ~/bin/local-localizer"
  echo "  # Make sure ~/bin is on your PATH"
  exit 1
fi

if ! command -v gh &>/dev/null; then
  echo "❌  GitHub CLI (gh) not found. Install from https://cli.github.com/"
  exit 1
fi

cd "$REPO_ROOT"

# ── Audit: count missing strings ───────────────────────────────────────────────

echo "🔍  Auditing missing strings for locale: $LOCALE"

MISSING=$(python3 - <<PYEOF
import json, sys

with open("$XCSTRINGS", encoding="utf-8") as f:
    data = json.load(f)

lang = "$LOCALE"
missing = []
for key, val in data.get("strings", {}).items():
    if not key:
        continue
    locs = val.get("localizations", {})
    if lang not in locs:
        missing.append(key)
    else:
        loc = locs[lang]
        if "stringUnit" in loc and loc["stringUnit"].get("state") not in ("translated",):
            missing.append(key)

print(len(missing))
PYEOF
)

if [[ "$MISSING" -eq 0 ]]; then
  echo "✅  No missing strings for $LOCALE — nothing to do."
  exit 0
fi

echo "   Found $MISSING strings to translate."
echo ""

# ── Build glossary ─────────────────────────────────────────────────────────────

python3 - <<PYEOF
import json

glossary = {
  "doNotTranslate": [
    "Meshtastic", "LoRa", "MQTT", "BLE", "GPS", "TAK", "CoT", "PKC",
    "SNR", "GPIO", "DFU", "API", "Wi-Fi", "Bluetooth", "IAQ",
    "ATAK", "WinTAK", "mPWRD-OS", "iOS", "macOS", "CarPlay", "SiriKit"
  ],
  "tone": {
    "default": "$TONE",
    "$LOCALE": "$TONE"
  }
}

with open("$GLOSSARY", "w", encoding="utf-8") as f:
    json.dump(glossary, f, ensure_ascii=False, indent=2)
    f.write("\n")
PYEOF

echo "📖  Glossary written to scripts/glossary.json (tone: $TONE)"
echo ""

# ── Branch ─────────────────────────────────────────────────────────────────────

BRANCH="translations/$(echo "$LOCALE" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"

if git show-ref --quiet "refs/heads/$BRANCH"; then
  echo "🌿  Switching to existing branch: $BRANCH"
  git checkout "$BRANCH"
else
  echo "🌿  Creating branch: $BRANCH"
  git checkout -b "$BRANCH"
fi

echo ""

# ── Translate ──────────────────────────────────────────────────────────────────

echo "🤖  Running local-localizer (on-device Apple Intelligence)..."
echo "   This may take several minutes. Translations are written incrementally."
echo ""

local-localizer "$XCSTRINGS" \
  --locales "$LOCALE" \
  --glossary "$GLOSSARY"

echo ""

# ── Verify ─────────────────────────────────────────────────────────────────────

echo "✅  Verifying results..."

python3 - <<PYEOF
import json

with open("$XCSTRINGS", encoding="utf-8") as f:
    data = json.load(f)

lang = "$LOCALE"
missing, needs_review, translated = [], 0, 0

for key, val in data["strings"].items():
    if not key:
        continue
    locs = val.get("localizations", {})
    if lang not in locs:
        missing.append(key)
    else:
        loc = locs[lang]
        if "stringUnit" in loc:
            state = loc["stringUnit"].get("state")
            if state == "translated":
                translated += 1
            elif state == "needs_review":
                needs_review += 1
            else:
                missing.append(key)
        elif "variations" in loc:
            translated += 1

print(f"   Confirmed translated : {translated}")
print(f"   Needs review         : {needs_review}")
print(f"   Still missing        : {len(missing)}")
if missing:
    print(f"\n⚠️  Missing keys (add manually):")
    for k in missing:
        print(f"   • {k}")
PYEOF

echo ""

# ── Commit ─────────────────────────────────────────────────────────────────────

git add "$XCSTRINGS" "$GLOSSARY"

COMMIT_MSG="Add $LOCALE machine translations (needs_review)

Machine-translated using local-localizer with Apple on-device Intelligence.
All strings marked needs_review for native speaker review."

git commit -m "$COMMIT_MSG"

echo "💾  Committed."
echo ""

# ── Push & PR ──────────────────────────────────────────────────────────────────

git push -u origin "$BRANCH"

gh pr create \
  --base main \
  --title "Add $LOCALE machine translations" \
  --body "## What changed
Machine-translated all missing \`$LOCALE\` strings in \`Localizable.xcstrings\` using [local-localizer](https://github.com/JoshuaSullivan/local-localizer) (Apple on-device Intelligence — no API keys, no network).

## Status
- All new strings are marked \`needs_review\`
- A native $LOCALE speaker should review before merging

## How to review in Xcode
Open \`Localizable.xcstrings\`, filter by locale **$LOCALE** and state **Needs Review**, and confirm or edit each string."

echo ""
echo "🎉  Done! PR opened. A native speaker should review the needs_review strings before merging."
