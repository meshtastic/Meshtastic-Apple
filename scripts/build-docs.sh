#!/usr/bin/env bash
# scripts/build-docs.sh
# Converts GFM markdown docs to HTML, injects CSS, builds keyword index, enforces bundle size.
# Usage: bash scripts/build-docs.sh --output <dir> [--beta]
# See specs/003-app-docs-markdown/contracts/ci-workflow-contract.md for full interface.

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
DOCS_SIZE_WARN_BYTES="${DOCS_SIZE_WARN_BYTES:-8388608}"   # 8 MB
DOCS_SIZE_LIMIT_BYTES="${DOCS_SIZE_LIMIT_BYTES:-10485760}" # 10 MB
OUTPUT_DIR=""
BETA_FLAG=false
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$REPO_ROOT/docs"
CSS_SOURCE="$REPO_ROOT/Meshtastic/Resources/docs/assets/docs.css"

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --beta)
            BETA_FLAG=true
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Usage: $0 --output <dir> [--beta]" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$OUTPUT_DIR" ]]; then
    echo "error: --output <dir> is required" >&2
    exit 1
fi

# ── Dependency check ──────────────────────────────────────────────────────────
if ! command -v cmark-gfm &>/dev/null; then
    echo "error: cmark-gfm not found. Install with: brew install cmark-gfm" >&2
    exit 1
fi

# ── Setup output directories ──────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR/user" "$OUTPUT_DIR/developer" "$OUTPUT_DIR/assets"

# Write .nojekyll to output dir to suppress native GitHub Pages Jekyll build (FR-003)
touch "$OUTPUT_DIR/.nojekyll"

# Copy CSS into output assets (skip if source and destination are the same file)
if [[ "$(realpath "$CSS_SOURCE")" != "$(realpath "$OUTPUT_DIR/assets/docs.css" 2>/dev/null || echo "")" ]]; then
    cp "$CSS_SOURCE" "$OUTPUT_DIR/assets/docs.css"
fi

# ── Beta banner ───────────────────────────────────────────────────────────────
BETA_BANNER=""
if [[ "$BETA_FLAG" == true ]]; then
    BETA_BANNER='<div class="pre-release-banner">⚠️ <strong>Pre-release</strong> — subject to change</div>'
fi

# ── HTML template ─────────────────────────────────────────────────────────────
html_template() {
    local title="$1"
    local content="$2"
    local page_id="$3"
    cat <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title}</title>
  <link rel="stylesheet" href="../assets/docs.css">
</head>
<body data-page="${page_id}">
${BETA_BANNER}${content}
</body>
</html>
EOF
}

# ── Convert a single markdown file to HTML ────────────────────────────────────
convert_md() {
    local src="$1"      # source .md path
    local section="$2"  # "user" or "developer"
    local stem
    stem="$(basename "$src" .md)"

    # Strip YAML front matter (--- ... ---) and Jekyll inline attributes ({: .xxx })
    local md_content
    md_content="$(awk '
        /^---$/ && NR==1 { in_fm=1; next }
        in_fm && /^---$/ { in_fm=0; next }
        in_fm { next }
        /^\{:.*\}[[:space:]]*$/ { next }
        { print }
    ' "$src")"

    local html_content
    html_content="$(echo "$md_content" | cmark-gfm \
        -e table \
        -e strikethrough \
        -e autolink \
        -e tasklist \
        -e tagfilter \
        --unsafe)"

    # Convert blockquote tips/notes/warnings to styled callout divs
    # Matches: <blockquote>\n<p><strong>Tip …</strong> text</p>\n</blockquote>
    html_content="$(echo "$html_content" | python3 -c '
import sys, re

def repl(m):
    inner = m.group(1).strip()
    # Determine callout type from leading bold label
    if re.match(r"<strong>[Tt]ip", inner):
        cls = "tips-callout"
    elif re.match(r"<strong>[Nn]ote", inner):
        cls = "tips-callout"
    elif re.match(r"<strong>[Ww]arning", inner):
        cls = "warning-callout"
    else:
        return m.group(0)  # leave plain blockquotes as-is
    return f"<div class=\"{cls}\">{inner}</div>"

html = sys.stdin.read()
html = re.sub(r"<blockquote>\s*<p>(.*?)</p>\s*</blockquote>", repl, html, flags=re.DOTALL)
print(html, end="")
')"

    local title
    # Extract first H1 as title; fall back to stem
    title="$(echo "$html_content" | grep -o '<h1[^>]*>[^<]*</h1>' | head -1 | sed 's/<[^>]*>//g')"
    if [[ -z "$title" ]]; then
        title="$stem"
    fi

    html_template "$title" "$html_content" "$stem" > "$OUTPUT_DIR/$section/$stem.html"
    echo "$stem"
}

# ── Extract keywords from HTML ────────────────────────────────────────────────
extract_keywords() {
    local html_file="$1"
    # Strip tags, lowercase, split on non-alpha, count, exclude stop words, take top 30
    local stop_words="the a an and or but in on at to for of with is are was were be been being have has had do does did will would could should may might shall can this that these those it its we you they he she what when where how which who i me my our your"
    cat "$html_file" \
        | sed 's/<[^>]*>//g' \
        | tr '[:upper:]' '[:lower:]' \
        | tr -cs 'a-z0-9' '\n' \
        | grep -v '^[0-9]*$' \
        | grep -E '.{3,}' \
        | sort | uniq -c | sort -rn \
        | awk '{print $2}' \
        | grep -vxFf <(echo "$stop_words" | tr ' ' '\n') \
        | head -30
}

# ── Build index entry ─────────────────────────────────────────────────────────
build_index_entry() {
    local html_file="$1"
    local section="$2"
    local md_file="$3"   # original source .md for frontmatter
    local stem
    stem="$(basename "$html_file" .html)"

    local title
    title="$(grep -o '<h1[^>]*>[^<]*</h1>' "$html_file" | head -1 | sed 's/<[^>]*>//g')"
    if [[ -z "$title" ]]; then
        title="$stem"
    fi

    # Extract nav_order from YAML frontmatter; default 999
    local nav_order
    nav_order="$(awk '/^---$/ && NR==1{in_fm=1;next} in_fm && /^---$/{exit} in_fm && /^nav_order:/{print $2}' "$md_file")"
    nav_order="${nav_order:-999}"

    # Character count of plain text (strip tags)
    local char_count
    char_count="$(sed 's/<[^>]*>//g' "$html_file" | wc -c | tr -d ' ')"

    # Build keyword JSON array
    local keywords_json
    keywords_json="$(extract_keywords "$html_file" | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')"

    printf '{"id":"%s","title":"%s","section":"%s","navOrder":%s,"keywords":%s,"charCount":%s}' \
        "$stem" \
        "$(echo "$title" | sed 's/"/\\"/g')" \
        "$section" \
        "$nav_order" \
        "$keywords_json" \
        "$char_count"
}

# ── Process all sections ──────────────────────────────────────────────────────
INDEX_ENTRIES=()
PAGE_COUNT=0

for section in user developer; do
    src_section="$SOURCE_DIR/$section"
    if [[ ! -d "$src_section" ]]; then
        continue
    fi
    for md_file in "$src_section"/*.md; do
        [[ -e "$md_file" ]] || continue
        stem="$(convert_md "$md_file" "$section")"
        html_file="$OUTPUT_DIR/$section/$stem.html"
        entry="$(build_index_entry "$html_file" "$section" "$md_file")"
        INDEX_ENTRIES+=("$entry")
        PAGE_COUNT=$((PAGE_COUNT + 1))
    done
done

# ── Write index.json ──────────────────────────────────────────────────────────
INDEX_JSON="["
first=true
for entry in "${INDEX_ENTRIES[@]}"; do
    if [[ "$first" == true ]]; then
        INDEX_JSON+="$entry"
        first=false
    else
        INDEX_JSON+=",$entry"
    fi
done
INDEX_JSON+="]"

echo "$INDEX_JSON" | python3 -m json.tool --no-ensure-ascii > "$OUTPUT_DIR/index.json"

# ── Bundle size check ─────────────────────────────────────────────────────────
TOTAL_BYTES=0
while IFS= read -r -d '' f; do
    size="$(wc -c < "$f" | tr -d ' ')"
    TOTAL_BYTES=$((TOTAL_BYTES + size))
done < <(find "$OUTPUT_DIR" -type f -print0)

TOTAL_MB=$(echo "scale=1; $TOTAL_BYTES / 1048576" | bc)

if [[ $TOTAL_BYTES -gt $DOCS_SIZE_LIMIT_BYTES ]]; then
    echo "error: Bundle size ${TOTAL_MB} MB exceeds hard limit of $((DOCS_SIZE_LIMIT_BYTES / 1048576)) MB" >&2
    exit 1
elif [[ $TOTAL_BYTES -gt $DOCS_SIZE_WARN_BYTES ]]; then
    echo "::warning::Bundle size ${TOTAL_MB} MB exceeds soft warning threshold of $((DOCS_SIZE_WARN_BYTES / 1048576)) MB"
fi

echo "✅ Built $PAGE_COUNT pages → $OUTPUT_DIR"
echo "📦 Bundle size: ${TOTAL_MB} MB / $((DOCS_SIZE_LIMIT_BYTES / 1048576)) MB limit"
