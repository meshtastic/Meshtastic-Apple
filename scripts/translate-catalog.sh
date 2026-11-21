#!/usr/bin/env bash
# translate-catalog.sh — Translate Localizable.xcstrings into one language with Xcode 27's
# translation agent, run from Claude Code.
#
# Usage:
#   scripts/translate-catalog.sh <locale>            # fill strings with no translation
#   scripts/translate-catalog.sh <locale> --review   # redo strings marked Needs Review
#
# Requirements:
#   - Xcode 27 or later, selected with xcode-select or DEVELOPER_DIR, and running.
#   - Claude Code (`claude`) signed in.
#   - The first run in each checkout asks, in Xcode, to approve the agent opening the project
#     (the Xcode MCP icon in the menu bar). Approve it and run the script again.
#
# Strings already translated are never changed. New translations are marked machine
# translated. Xcode rewrites the whole catalog when it saves, so at the end only this
# language's entries are copied back into the catalog as it was, keeping its key order.
# Nothing is committed: check `git diff` and open a pull request yourself.

set -euo pipefail

LOCALE="${1:-}"
MODE="${2:-}"
if [[ -z "$LOCALE" || ( -n "$MODE" && "$MODE" != "--review" ) ]]; then
  echo "Usage: scripts/translate-catalog.sh <locale> [--review]"
  exit 1
fi
STATE="new"
[[ "$MODE" == "--review" ]] && STATE="needs_review"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CATALOG="$REPO_ROOT/Localizable.xcstrings"
PROJECT="$REPO_ROOT/Meshtastic.xcodeproj"
GUIDE="$REPO_ROOT/scripts/translation-guide.md"
RESOLVED="$PROJECT/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
# Keys per run: each run hands out batches of 15 to sub-agents and checks its work.
KEYS_PER_RUN=300
MAX_RUNS=20

command -v claude >/dev/null || { echo "Claude Code (claude) not found on PATH."; exit 1; }
MCPBRIDGE="$(xcrun --find mcpbridge 2>/dev/null)" || { echo "mcpbridge not found: select Xcode 27 or later."; exit 1; }
PLUGIN_DIR="$(xcrun agent plugin path --plugin-format claude)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# Each run's notes on choices worth checking are kept after the script ends.
LOGS="$(mktemp -d -t "translate-$LOCALE")"
cp "$CATALOG" "$WORK/before.xcstrings"
RESOLVED_WAS_CLEAN=true
git -C "$REPO_ROOT" diff --quiet -- "$RESOLVED" || RESOLVED_WAS_CLEAN=false

cat > "$WORK/mcp.json" <<JSON
{"mcpServers":{"xcode":{"command":"$MCPBRIDGE","args":[]}}}
JSON

cat > "$WORK/prompt.txt" <<PROMPT
Translate Meshtastic's String Catalog into $LOCALE using Xcode's translation tools.

1. Call XcodeOpenWorkspace for $PROJECT to get the workspace identifier.
2. Activate the xcode-integration:translation-coordinator skill and follow it, with these limits:
   - File: $CATALOG only. Locale: $LOCALE. Do not call LocalizationPlanner and do not build.
   - Only strings in the "$STATE" state. Never change strings in any other state.
   - Take up to $KEYS_PER_RUN keys in that state from offset 0, in batches of 15, as the skill says.
3. Forward this guidance to every sub-agent. It overrides the style guide:

$(cat "$GUIDE")

4. At the end, call StringCatalogRead for $LOCALE with no requestedState, and print as the very
   last line exactly: REMAINING=<count of keys still in the "$STATE" state>
PROMPT

previous=""
for run in $(seq 1 "$MAX_RUNS"); do
  echo "Run $run: translating up to $KEYS_PER_RUN $STATE strings into $LOCALE..."
  claude -p "$(cat "$WORK/prompt.txt")" ${TRANSLATE_MODEL:+--model "$TRANSLATE_MODEL"} \
    --mcp-config "$WORK/mcp.json" --strict-mcp-config --plugin-dir "$PLUGIN_DIR" \
    --allowedTools "mcp__xcode__*" "Skill" "Agent" "Task" "Read" \
    < /dev/null > "$LOGS/run-$run.log" 2>&1 || true
  remaining="$(grep -o 'REMAINING=[0-9]*' "$LOGS/run-$run.log" | tail -1 | cut -d= -f2 || true)"
  if [[ -z "$remaining" ]]; then
    echo "Run $run didn't report what's left. Its output:"
    tail -20 "$LOGS/run-$run.log"
    break
  fi
  echo "  $remaining left"
  if [[ "$remaining" == "0" || "$remaining" == "$previous" ]]; then
    break
  fi
  previous="$remaining"
done

cp "$CATALOG" "$WORK/rewritten.xcstrings"
python3 "$REPO_ROOT/scripts/merge-catalog-locale.py" --locale "$LOCALE" \
  --from "$WORK/rewritten.xcstrings" --into "$WORK/before.xcstrings" --output "$CATALOG"
# Opening the project makes Xcode resolve packages again; that isn't part of a translation.
if $RESOLVED_WAS_CLEAN; then
  git -C "$REPO_ROOT" checkout -- "$RESOLVED" 2>/dev/null || true
fi
echo "Done. Each run's notes, with choices worth checking, are in $LOGS"
