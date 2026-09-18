#!/bin/bash
set -euo pipefail

# Regenerate the Swift protobufs in MeshtasticProtobufs/Sources from the `protobufs`
# submodule, optionally bumping the submodule to the latest upstream first.
#
# Usage:
#   scripts/gen_protos.sh            # pull protobufs origin/master, then regenerate
#   scripts/gen_protos.sh develop    # pull a different branch/tag/commit
#   scripts/gen_protos.sh --no-pull  # regenerate against the current pinned protos
#
# IMPORTANT — toolchain pinning:
# We build `protoc-gen-swift` from the swift-protobuf version pinned in
# MeshtasticProtobufs/Package.resolved, NOT from a globally-installed (Homebrew)
# protoc-gen-swift. Brew's plugin drifts and is usually OLDER than what the project
# links; generating with it silently DOWNGRADES every file — dropping `Sendable`,
# `Swift.CaseIterable`/`allCases`, the `// swiftlint:disable all` header, and the
# `FoundationEssentials` conditional imports — which removes concurrency conformance
# and makes SwiftLint lint the generated files, breaking CI. Pinning the plugin to
# Package.resolved keeps regeneration reproducible and CI-clean.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PROTO_REF="master"
PULL=1
if [ "${1:-}" = "--no-pull" ]; then
	PULL=0
elif [ -n "${1:-}" ]; then
	PROTO_REF="$1"
fi

if ! command -v protoc >/dev/null 2>&1; then
	echo "error: protoc not found. Install it with:  brew install protobuf" >&2
	exit 1
fi
if ! command -v swift >/dev/null 2>&1; then
	echo "error: swift not found. Install Xcode / the Swift toolchain." >&2
	exit 1
fi

# 1. Make sure the proto submodule is checked out, and (by default) pull latest upstream.
git submodule update --init --recursive protobufs
if [ "$PULL" -eq 1 ]; then
	echo "Pulling protobufs @ origin/${PROTO_REF} …"
	git -C protobufs fetch --quiet origin "$PROTO_REF"
	git -C protobufs checkout --quiet FETCH_HEAD
fi
echo "protobufs @ $(git -C protobufs log -1 --format='%h %ci %s')"

# 2. Build protoc-gen-swift at the version pinned in MeshtasticProtobufs/Package.resolved.
#    SwiftPM caches the build, so this is only slow the first time (or after a bump).
#    `swift build` re-resolves and would prune MeshtasticProtobufs/Package.resolved down to
#    just swift-protobuf; back it up and restore it (even on failure) so the script never
#    dirties the committed file.
echo "Building protoc-gen-swift from the pinned swift-protobuf …"
RESOLVED="$REPO_ROOT/MeshtasticProtobufs/Package.resolved"
RESOLVED_BAK="$(mktemp)"
cp "$RESOLVED" "$RESOLVED_BAK"
restore_resolved() { cp "$RESOLVED_BAK" "$RESOLVED"; rm -f "$RESOLVED_BAK"; }
trap restore_resolved EXIT
swift build --package-path MeshtasticProtobufs --product protoc-gen-swift -c release
PLUGIN="$REPO_ROOT/MeshtasticProtobufs/.build/release/protoc-gen-swift"
echo "Using $("$PLUGIN" --version)"

# 3. Generate the Swift sources with the pinned plugin.
protoc \
	--plugin=protoc-gen-swift="$PLUGIN" \
	--proto_path=./protobufs \
	--swift_opt=Visibility=Public \
	--swift_out=./MeshtasticProtobufs/Sources \
	./protobufs/meshtastic/*.proto

# 4. Generate the field-metadata registry from the (meshtastic.field_metadata) and
#    (meshtastic.enum_value_metadata) options.
#
#    Two things differ from step 3 and both matter.
#
#    The output goes to the APP TARGET, not to MeshtasticProtobufs. The registry emits
#    its labels and descriptions as String(localized:), and Xcode only extracts those
#    from a target that owns a string catalog and sets SWIFT_EMIT_LOC_STRINGS. A SwiftPM
#    package has neither, so a registry generated there would compile fine and resolve to
#    English forever - a silent failure. Hence a separate protoc invocation rather than a
#    second --*_out on the call above. The plugin emits a bare filename with no package
#    path, so the out directory is the destination directory itself.
#
#    This plugin is pinned by the 'protobufs' submodule SHA, not by
#    MeshtasticProtobufs/Package.resolved as protoc-gen-swift is above. The guard in step
#    2 does not cover it.
FIELDMETA_PKG="$REPO_ROOT/protobufs/tools/protoc-gen-fieldmeta-swift"
if [ -d "$FIELDMETA_PKG" ]; then
	echo "Building protoc-gen-fieldmeta-swift from the protobufs submodule …"
	swift build --package-path "$FIELDMETA_PKG" -c release --cache-path "$FIELDMETA_PKG/.build/spm-cache"
	FIELDMETA_PLUGIN="$FIELDMETA_PKG/.build/release/protoc-gen-fieldmeta-swift"
	protoc \
		--plugin=protoc-gen-fieldmeta-swift="$FIELDMETA_PLUGIN" \
		--proto_path=./protobufs \
		--fieldmeta-swift_out=./Meshtastic/Model \
		./protobufs/meshtastic/*.proto
	# The plugin emits no imports: it cannot know what module holds the generated
	# protobuf types, since that is the consumer's choice. Ours is MeshtasticProtobufs,
	# and the file is full of `extension Config { … }`, so add it here.
	REGISTRY="$REPO_ROOT/Meshtastic/Model/FieldMetadataRegistry.swift"
	if ! grep -q "^import MeshtasticProtobufs$" "$REGISTRY"; then
		awk 'NR==1 { print; print ""; print "import MeshtasticProtobufs"; next } { print }' \
			"$REGISTRY" > "$REGISTRY.tmp" && mv "$REGISTRY.tmp" "$REGISTRY"
	fi
	# Stop a regeneration that would quietly empty settings search.
	#
	# Generating against protos with no field_metadata annotations succeeds. It
	# still emits a row per deprecated field, so the file looks populated while
	# carrying almost no labels - and labels are what search matches on. With no
	# arguments this script pulls origin/master first, so this happens by accident
	# whenever the annotations have not landed upstream yet.
	#
	# Compare labelled entries against the committed file rather than a fixed
	# threshold, so the check calibrates itself as annotations land. Set
	# ALLOW_FEWER_LABELS=1 for a deliberate upstream removal.
	LABELS=$(grep -c 'label: String(localized:' "$REGISTRY" || true)
	WAS=$(git show HEAD:Meshtastic/Model/FieldMetadataRegistry.swift 2>/dev/null \
		| grep -c 'label: String(localized:' || true)
	if [ "$LABELS" -lt "$WAS" ] && [ "${ALLOW_FEWER_LABELS:-0}" != "1" ]; then
		echo "error: regenerating dropped labelled entries: $WAS -> $LABELS." >&2
		echo "protobufs is at $(git -C protobufs rev-parse --short HEAD), which carries fewer" >&2
		echo "field_metadata annotations than the commit the registry was built from." >&2
		echo "Settings search matches on those labels, so this would empty it silently." >&2
		echo "Point the submodule at protos carrying the annotations, or re-run with" >&2
		echo "ALLOW_FEWER_LABELS=1 if the removal is intended." >&2
		exit 1
	fi
	echo "Generated Meshtastic/Model/FieldMetadataRegistry.swift ($LABELS labelled entries)"
else
	echo "error: $FIELDMETA_PKG not present." >&2
	echo "The app needs Meshtastic/Model/FieldMetadataRegistry.swift, which is generated from" >&2
	echo "the submodule. Exiting non-zero rather than leaving the committed registry stale" >&2
	echo "while this script reports success. Bump 'protobufs' to a commit carrying" >&2
	echo "tools/protoc-gen-fieldmeta-swift." >&2
	exit 1
fi

# 5. Field schema for the configuration forms (typed descriptors: tag, key path, kind).
#    Generated into the app target next to the registry. Nothing here is display text -
#    labels come from the registry at runtime - so this is purely structural, and a field
#    the schema renames or removes fails to compile instead of failing to render.
#
#    The plugin lives in this repo (scripts/protoc-gen-configform-swift) and is pinned to
#    the exact swift-protobuf version MeshtasticProtobufs resolves, so the key paths it
#    writes spell properties the way protoc-gen-swift did.
CONFIGFORM_PKG="$REPO_ROOT/scripts/protoc-gen-configform-swift"
echo "Building protoc-gen-configform-swift …"
swift build --package-path "$CONFIGFORM_PKG" -c release --cache-path "$CONFIGFORM_PKG/.build/spm-cache"
CONFIGFORM_PLUGIN="$CONFIGFORM_PKG/.build/release/protoc-gen-configform-swift"
mkdir -p "$REPO_ROOT/Meshtastic/Model/ConfigForms"
protoc \
	--plugin=protoc-gen-configform-swift="$CONFIGFORM_PLUGIN" \
	--proto_path=./protobufs \
	--configform-swift_out=./Meshtastic/Model/ConfigForms \
	./protobufs/meshtastic/config.proto ./protobufs/meshtastic/module_config.proto
SCHEMA="$REPO_ROOT/Meshtastic/Model/ConfigForms/ConfigFormSchema.swift"
# A schema that shrank means a message or field vanished upstream, or the plugin
# broke. Either deserves a look before it is committed.
# Typed descriptors and the .unsupported(...) rows for repeated, map and oneof
# fields both count, so dropping only the latter cannot slip past.
FIELDS=$(grep -cE 'ConfigField<|\.unsupported\(' "$SCHEMA" || true)
WAS=$(git show HEAD:Meshtastic/Model/ConfigForms/ConfigFormSchema.swift 2>/dev/null | grep -cE 'ConfigField<|\.unsupported\(' || true)
if [ "$FIELDS" -lt "$WAS" ] && [ "${ALLOW_FEWER_FIELDS:-0}" != "1" ]; then
	echo "error: regenerating dropped field descriptors: $WAS -> $FIELDS." >&2
	echo "Re-run with ALLOW_FEWER_FIELDS=1 if fields were removed upstream on purpose." >&2
	exit 1
fi
echo "Generated Meshtastic/Model/ConfigForms/ConfigFormSchema.swift ($FIELDS field descriptors)"

echo
echo "Done — generated Swift into MeshtasticProtobufs/Sources with $("$PLUGIN" --version)."
echo "Build, test, and commit the changes (including the bumped 'protobufs' submodule)."
