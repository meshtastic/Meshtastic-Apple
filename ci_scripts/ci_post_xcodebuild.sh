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
	echo "No dSYMs directory found at $DSYM_DIR — skipping upload."
	exit 0
fi

DSYM_COUNT=$(find "$DSYM_DIR" -name "*.dSYM" -type d | wc -l | tr -d ' ')
echo "Found $DSYM_COUNT dSYM bundles in $DSYM_DIR"

if [ "$DSYM_COUNT" -eq 0 ]; then
	echo "No dSYM files to upload."
	exit 0
fi

if [ -z "$DATADOG_API_KEY" ]; then
	echo "WARNING: DATADOG_API_KEY is not set — skipping dSYM upload."
	echo "Configure it as a secret in Xcode Cloud workflow environment variables."
	exit 0
fi

# Install datadog-ci
npm install -g @datadog/datadog-ci

# Upload dSYMs
export DATADOG_SITE="us5.datadoghq.com"
echo "Uploading dSYMs to Datadog ($DATADOG_SITE)..."
datadog-ci dsyms upload "$DSYM_DIR"

echo "Stage: POST-Xcode Build is DONE .... "

exit 0
