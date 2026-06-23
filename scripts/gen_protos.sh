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

echo
echo "Done — generated Swift into MeshtasticProtobufs/Sources with $("$PLUGIN" --version)."
echo "Build, test, and commit the changes (including the bumped 'protobufs' submodule)."
