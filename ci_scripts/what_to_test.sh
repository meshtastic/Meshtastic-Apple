#!/bin/bash
# Copyright(c) Garth Vander Houwen 10/17/26.
#
# Writes TestFlight's "What to Test" notes for the build at HEAD of a clone: one entry per pull
# request merged since the previous release tag, newest first, each the opening paragraph of the
# pull request's Summary so testers read what changed rather than a title. A pull request whose
# description can't be read (GitHub is unreachable, rate limited, or there is no Summary) falls
# back to its title.
#
#   ci_scripts/what_to_test.sh <repo path> <output file>
#
# Best effort: it never fails, and writes nothing when there is no history to describe.

REPO="${1:?repo path}"
OUT="${2:?output file}"
API="https://api.github.com/repos/meshtastic/Meshtastic-Apple/pulls"
# Xcode Cloud's machines share addresses, so unauthenticated requests run into GitHub's rate
# limit. Any token can read a public repository; the build already has one as a secret.
TOKEN="${GITHUB_TOKEN:-$TRANSLATIONS_GITHUB_TOKEN}"
AUTH=()
[ -n "$TOKEN" ] && AUTH=(-H "Authorization: Bearer $TOKEN")
# TestFlight takes up to 4000 characters.
MAX_ENTRIES=12
MAX_SUMMARY=300
MAX_TOTAL=3900

# Xcode Cloud clones are shallow. Fetch the full history and the tags so the previous release
# tag is reachable from HEAD; a fixed depth can stop short of it after a long release cycle.
git -C "$REPO" fetch --tags --quiet 2>/dev/null || true
if [ "$(git -C "$REPO" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
	git -C "$REPO" fetch --unshallow --quiet 2>/dev/null \
		|| echo "WhatToTest: could not fetch the full history; the notes may stop short of the last release."
fi

# Bound the notes at the previous release tag, so a build lists what is new in it. If this
# commit is itself tagged, the release has already been cut: measure from the tag before it.
LAST_TAG=$(git -C "$REPO" describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null)
if [ -n "$LAST_TAG" ] && \
	[ "$(git -C "$REPO" rev-list -n1 "$LAST_TAG" 2>/dev/null)" = "$(git -C "$REPO" rev-parse HEAD 2>/dev/null)" ]; then
	LAST_TAG=$(git -C "$REPO" describe --tags --abbrev=0 --match 'v[0-9]*' "$LAST_TAG^" 2>/dev/null)
fi
if [ -n "$LAST_TAG" ]; then
	RANGE="$LAST_TAG..HEAD"
	echo "WhatToTest range: $RANGE"
else
	RANGE=""
	echo "WhatToTest: no release tag found, falling back to the last 40 commits."
fi

# Pull requests in the range, newest first, as "commit<TAB>number<TAB>title". A merge commit
# carries the number in its subject and the title in its body; a squash carries both in its
# subject, as "Title (#1234)". Version bumps are left out.
PULLS=$(git -C "$REPO" log ${RANGE:---max-count=40} --pretty=format:'%x1e%H %p%x1f%s%x1f%b' 2>/dev/null \
	| awk -v RS='\036' -F'\037' '
		NF < 3 { next }
		{
			split($1, ids, " "); commit = ids[1]; parents = substr($1, length(commit) + 2)
			subject = $2; body = $3; number = ""; title = ""
			if (parents ~ / / && match(subject, /#[0-9]+/)) {
				number = substr(subject, RSTART + 1, RLENGTH - 1)
				n = split(body, b, "\n")
				for (i = 1; i <= n; i++) if (b[i] != "") { title = b[i]; break }
			} else if (match(subject, /\(#[0-9]+\)[ \t]*$/)) {
				title = substr(subject, 1, RSTART - 1)
				number = substr(subject, RSTART + 2)
				sub(/\).*/, "", number)
				sub(/[ \t]+$/, "", title)
			}
			if (number != "" && title !~ /^[Bb]ump version/) print commit "\t" number "\t" title
		}' \
	| awk -F'\t' '!seen[$2]++')

# A pull request that changes nothing in the app (CI, tests, the project file, docs) has nothing
# for a tester to try.
touches_app() {
	git -C "$REPO" diff --name-only "$1^1" "$1" 2>/dev/null \
		| grep -v -E '^(ci_scripts|\.github|MeshtasticTests|MeshtasticUITests|docs|scripts|specs)/|^(project\.yml|Meshtastic\.xcodeproj/|\.swiftlint|README|CLAUDE)' \
		| grep -q .
}

# The opening paragraph of a pull request description's "## Summary" section, as plain text:
# Markdown links keep their text, code spans and emphasis lose their marks, and a long
# paragraph is cut at the last sentence that fits.
summary_of() {
	awk -v max="$MAX_SUMMARY" '
		/^##[ \t]+Summary/ { inside = 1; next }
		inside && comment { if (/-->/) comment = 0; next }
		inside && /^[ \t]*<!--/ { if ($0 !~ /-->/) comment = 1; next }
		inside && /^#/ { exit }
		inside && /^[ \t]*$/ { if (text != "") exit; next }
		inside { sub(/^[ \t]*[-*][ \t]+/, ""); text = text (text == "" ? "" : " ") $0 }
		END {
			while (match(text, /\[[^]]*\]\([^)]*\)/)) {
				link = substr(text, RSTART, RLENGTH); sub(/\]\(.*/, "", link); sub(/^\[/, "", link)
				text = substr(text, 1, RSTART - 1) link substr(text, RSTART + RLENGTH)
			}
			gsub(/`|\*\*|__/, "", text)
			gsub(/[ \t]+/, " ", text)
			if (length(text) > max) {
				cut = substr(text, 1, max)
				if (match(cut, /.*[.!?] /)) text = substr(cut, 1, RLENGTH - 1)
				else { sub(/ [^ ]*$/, "", cut); text = cut "…" }
			}
			print text
		}'
}

NOTES=""
count=0
while IFS=$'\t' read -r commit number title; do
	[ -n "$number" ] || continue
	[ "$count" -lt "$MAX_ENTRIES" ] || break
	touches_app "$commit" || continue
	body=$(curl -sf --max-time 10 -H 'Accept: application/vnd.github+json' "${AUTH[@]}" "$API/$number" 2>/dev/null \
		| plutil -extract body raw -o - - 2>/dev/null)
	entry=$(printf '%s\n' "$body" | tr -d '\r' | summary_of)
	[ -n "$entry" ] || entry="$title"
	line="• $entry"
	if [ $(( ${#NOTES} + ${#line} + 1 )) -gt "$MAX_TOTAL" ]; then
		break
	fi
	NOTES="${NOTES:+$NOTES
}$line"
	count=$((count + 1))
done <<< "$PULLS"

if [ -n "$NOTES" ]; then
	mkdir -p "$(dirname "$OUT")"
	printf "What changed in this build:\n\n%s\n" "$NOTES" > "$OUT"
	echo "WhatToTest generated with $(printf '%s\n' "$NOTES" | wc -l | tr -d ' ') entries."
else
	echo "No pull requests found to describe; skipping WhatToTest."
fi
exit 0
