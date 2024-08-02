# Releasing Meshtastic

This document outlines the process for preparing and making a release for Meshtastic.

## Table of Contents

1. [Branching Strategy](#branching-strategy)
2. [Preparing for a Release](#preparing-for-a-release)
3. [Creating a Release Branch](#creating-a-release-branch)
4. [Finalizing the Release](#finalizing-the-release)

## Branching Strategy

- **Main Branch (`main`)**: This is the main development branch where daily development occurs. 
- **Release Branch (`X.YY.ZZ-release`)**: This branch is created from `main` for preparing a specific release version.

## Preparing for a Release

1. Ensure all desired features and fixes are merged into the `main` branch.
2. Update the version number in the relevant files.
3. Update the project documentation to reflect the upcoming release.

## Creating a Release Branch

1. Create a release branch from `main`.
   ```sh
   ./scripts/create-release-branch.sh
   ```

## Finalizing the Release

1. Perform final testing and quality checks on the `X.YY.ZZ-release` branch.
    a. If any hotfix changes are required, merge those changes into `X.YY.ZZ-release`.
    b. After merging these changes into the release branch, cherry-pick the changes onto `main`.
2. Once everything is ready, create a final tag for the release:
   ```sh
   git tag -a X.YY.ZZ -m "Release version X.Y.Z"
   git push origin X.YY.ZZ
   ```

Thank you for following the release process and helping to ensure the stability and quality of Meshtastic!

---

Feel free to modify this template to better fit your project's specific needs.