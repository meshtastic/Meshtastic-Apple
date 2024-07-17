#!/bin/bash
set -e

# Define the source and destination paths
SOURCE_PATH="./scripts/hooks/pre-commit"
HOOKS_DIR=".git/hooks"
DEST_PATH="$HOOKS_DIR/pre-commit"

# Check if the hooks directory exists
if [ ! -d "$HOOKS_DIR" ]; then
  echo "Error: .git/hooks directory not found. Make sure you're in the root of a Git repository."
  exit 1
fi

# Copy the script to the hooks directory
cp "$SOURCE_PATH" "$DEST_PATH"

# Make the hook script executable
chmod +x "$DEST_PATH"

echo "Pre-commit hooks have been set up successfully."
