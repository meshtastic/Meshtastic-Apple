#!/bin/bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
fixture_root="$repo_root/research/fixtures/swiftdata-schema-history"
template="$repo_root/research/schema-history/FixtureGenerator.swift.template"
metadata_tool="$repo_root/research/schema-history/StoreMetadata.swift"
destination=${SCHEMA_FIXTURE_DESTINATION:-"platform=iOS Simulator,name=iPhone 16,OS=18.2"}
xcode_version=$(xcodebuild -version | awk 'NR == 1 { print $2 }')
xcode_build=$(xcodebuild -version | awk 'NR == 2 { print $3 }')
default_tags=(v2.7.13 v2.7.14 v2.7.15 v2.7.16 v2.7.17 v2.7.18 v2.7.19 v2.7.20 v2.7.21)
if (($#)); then
	tags=("$@")
else
	tags=("${default_tags[@]}")
fi

if [[ -e "$fixture_root" ]]; then
	echo "Refusing to replace existing fixtures: $fixture_root" >&2
	echo "Move that directory aside, then rerun this script." >&2
	exit 1
fi

work_root=$(mktemp -d /tmp/meshtastic-schema-history.XXXXXX)
staging_root="$fixture_root.staging.$$"
checkout="$work_root/checkout"
derived_data="$work_root/DerivedData"
records="$work_root/records.tsv"
mkdir -p "$staging_root"
: > "$records"

cleanup() {
	rm -rf "$work_root"
	if [[ -n "${staging_root:-}" && -d "$staging_root" ]]; then
		rm -rf "$staging_root"
	fi
}
trap cleanup EXIT

for tag in "${tags[@]}"; do
	if ! git -C "$repo_root" rev-parse --verify --quiet "refs/tags/$tag" >/dev/null; then
		echo "Missing tag: $tag" >&2
		exit 1
	fi
	commit=$(git -C "$repo_root" rev-list -n 1 "$tag")

	echo "Generating $tag ($commit)"
	mkdir -p "$checkout"
	git -C "$repo_root" archive "$tag" | tar -x -C "$checkout"

	tag_output="$work_root/output/$tag"
	mkdir -p "$tag_output"
	sed \
		-e "s|__TAG__|$tag|g" \
		-e "s|__OUTPUT_DIRECTORY__|$tag_output|g" \
		"$template" >> "$checkout/MeshtasticTests/SwiftDataMigrationTests.swift"

	build_log="$work_root/$tag.xcodebuild.log"
	if ! xcodebuild \
		-project "$checkout/Meshtastic.xcodeproj" \
		-scheme Meshtastic \
		-destination "$destination" \
		-derivedDataPath "$derived_data" \
		-only-testing:MeshtasticTests/SchemaHistoryFixtureGeneratorTests \
		CODE_SIGNING_ALLOWED=NO \
		test >"$build_log" 2>&1; then
		echo "Fixture build failed for $tag. Relevant output:" >&2
		grep -E 'error:|failed|TEST FAILED|Testing failed' "$build_log" | tail -80 >&2 || true
		exit 1
	fi

	store="$tag_output/Meshtastic.store"
	if [[ ! -f "$store" ]]; then
		echo "Fixture generator did not create $store" >&2
		exit 1
	fi

	sqlite3 "$store" 'PRAGMA wal_checkpoint(TRUNCATE);' >/dev/null
	if [[ $(sqlite3 "$store" 'PRAGMA integrity_check;') != "ok" ]]; then
		echo "SQLite integrity check failed for $tag" >&2
		exit 1
	fi

	metadata="$tag_output/metadata.json"
	checksum=$(xcrun swift "$metadata_tool" "$store" "$tag" "$metadata")
	fixture_directory="$staging_root/$checksum"
	if [[ ! -d "$fixture_directory" ]]; then
		mkdir -p "$fixture_directory"
		cp "$store" "$fixture_directory/Meshtastic.store"
		cp "$metadata" "$fixture_directory/metadata.json"
		source_tag="$tag"
	else
		source_tag=$(awk -F '\t' -v checksum="$checksum" '$2 == checksum { print $3; exit }' "$records")
	fi
	printf '%s\t%s\t%s\t%s\n' "$tag" "$checksum" "$source_tag" "$commit" >> "$records"

	find "$checkout" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
done

{
	printf '{\n'
	printf '  "formatVersion" : 1,\n'
	printf '  "tags" : [\n'
	first=1
	while IFS=$'\t' read -r tag checksum source_tag commit; do
		if ((first)); then
			first=0
		else
			printf ',\n'
		fi
		printf '    {\n'
		printf '      "checksum" : "%s",\n' "$checksum"
		printf '      "commit" : "%s",\n' "$commit"
		printf '      "fixture" : "%s/Meshtastic.store",\n' "$checksum"
		printf '      "sourceTag" : "%s",\n' "$source_tag"
		printf '      "tag" : "%s"\n' "$tag"
		printf '    }'
	done < "$records"
	printf '\n  ],\n'
	printf '  "xcode" : {\n'
	printf '    "build" : "%s",\n' "$xcode_build"
	printf '    "version" : "%s"\n' "$xcode_version"
	printf '  }\n'
	printf '}\n'
} > "$staging_root/manifest.json"

mv "$staging_root" "$fixture_root"
staging_root=""
echo "Generated fixtures at $fixture_root"
