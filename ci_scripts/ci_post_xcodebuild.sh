#!/bin/sh

echo "Stage: POST-Xcode Build is activated .... "

# Upload dSYM files to Datadog for crash symbolication.
# Xcode Cloud sets CI_ARCHIVE_PATH after a successful archive action.
# The DATADOG_API_KEY must be configured as a secret environment variable
# in Xcode Cloud (App Store Connect → Xcode Cloud → Workflow → Environment).

if [ -z "$CI_ARCHIVE_PATH" ]; then
	echo "CI_ARCHIVE_PATH is not set — skipping dSYM upload (not an archive action)."
	exit 0
fi

DSYM_DIR="$CI_ARCHIVE_PATH/dSYMs"

if [ ! -d "$DSYM_DIR" ]; then
	echo "❌ ERROR: this is an archive ($CI_ARCHIVE_PATH) but there is no dSYMs directory at $DSYM_DIR."
	echo "   Crashes from this build would be unsymbolicated. Failing the build so it is caught now."
	echo "   Check the Release config uses DEBUG_INFORMATION_FORMAT = dwarf-with-dsym."
	exit 1
fi

DSYM_COUNT=$(find "$DSYM_DIR" -name "*.dSYM" -type d | wc -l | tr -d ' ')
echo "Found $DSYM_COUNT dSYM bundles in $DSYM_DIR"
find "$DSYM_DIR" -name "*.dSYM" -type d | while read -r dsym; do
	echo "  $dsym"
done

if [ "$DSYM_COUNT" -eq 0 ]; then
	echo "❌ ERROR: this is an archive but found 0 dSYM bundles in $DSYM_DIR."
	echo "   Crashes from this build would be unsymbolicated. Failing the build so it is caught now."
	exit 1
fi

if [ -z "$DATADOG_API_KEY" ]; then
	echo "❌ ERROR: DATADOG_API_KEY is not set, but this is an archive build with $DSYM_COUNT dSYM bundle(s)."
	echo "   dSYMs will NOT upload and crashes will be unsymbolicated. Failing the build so it is caught now."
	echo "   Fix: add a secret named exactly DATADOG_API_KEY to the Xcode Cloud workflow"
	echo "   (App Store Connect → Xcode Cloud → Workflow → Environment), and ensure it is available to the Archive action."
	exit 1
fi

# Install datadog-ci if not already present.
if ! command -v datadog-ci >/dev/null 2>&1; then
	ARCH=$(uname -m)
	case "$ARCH" in
		arm64|aarch64)
			DATADOG_CI_ARCH="darwin-arm64"
			;;
		x86_64)
			DATADOG_CI_ARCH="darwin-x64"
			;;
		*)
			echo "ERROR: Unsupported macOS architecture: $ARCH"
			exit 1
			;;
	esac

	DATADOG_CI_BIN_DIR="${TMPDIR:-/tmp}/datadog-ci-bin"
	DATADOG_CI_BIN="$DATADOG_CI_BIN_DIR/datadog-ci"
	DATADOG_CI_VERSION="v5.17.0"
	DATADOG_CI_URL="https://github.com/DataDog/datadog-ci/releases/download/$DATADOG_CI_VERSION/datadog-ci_$DATADOG_CI_ARCH"

	echo "datadog-ci not found, downloading standalone binary for $DATADOG_CI_ARCH..."
	mkdir -p "$DATADOG_CI_BIN_DIR"
	if ! curl -L --fail "$DATADOG_CI_URL" --output "$DATADOG_CI_BIN"; then
		echo "ERROR: Failed to download datadog-ci from $DATADOG_CI_URL"
		exit 1
	fi
	chmod +x "$DATADOG_CI_BIN"
	PATH="$DATADOG_CI_BIN_DIR:$PATH"
	export PATH
fi

# Verify installation succeeded
if ! command -v datadog-ci >/dev/null 2>&1; then
	echo "ERROR: datadog-ci still not found after install attempt."
	echo "PATH: $PATH"
	exit 1
fi

# Upload dSYMs
export DATADOG_SITE="us5.datadoghq.com"
echo "Uploading dSYMs to Datadog ($DATADOG_SITE)..."
datadog-ci dsyms upload "$DSYM_DIR"
UPLOAD_EXIT=$?

if [ $UPLOAD_EXIT -ne 0 ]; then
	echo "ERROR: dSYM upload failed with exit code $UPLOAD_EXIT"
	exit $UPLOAD_EXIT
fi

echo "dSYM upload succeeded."
echo "Stage: POST-Xcode Build is DONE .... "

exit 0
