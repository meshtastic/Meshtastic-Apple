#!/bin/bash

# Check if the release version number is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <release-version>"
  exit 1
fi

# Set the release version number
RELEASE_VERSION=$1

# Check if the release branch already exists on the remote repository
if git ls-remote --exit-code --heads origin $RELEASE_BRANCH; then
  echo "The branch $RELEASE_BRANCH already exists on the remote repository."
  exit 1
fi

# Prompt the user for confirmation
echo "You are about to create and push the release branch ${RELEASE_VERSION}-release."
read -p "Are you sure you want to proceed? (Y/n): " confirmation

# Check the user's response
if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
  echo "Operation cancelled."
  exit 0
fi

# Check out the main branch and pull the latest changes
git checkout main
git pull origin main

# Create a new branch for the release
RELEASE_BRANCH="${RELEASE_VERSION}-release"
git checkout -b $RELEASE_BRANCH

# Push the new release branch to the remote repository
git push origin $RELEASE_BRANCH

echo "Release branch $RELEASE_BRANCH created and pushed successfully."
