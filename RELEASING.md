# Releasing Meshtastic

This document outlines the process for preparing and making a release for Meshtastic.

## Table of Contents

1. [Branching Strategy](#branching-strategy)
2. [Preparing for a Release](#preparing-for-a-release)
3. [Creating a Release Branch](#creating-a-release-branch)
4. [Docs Release Step](#docs-release-step)
5. [Documentation Publishing & Website Sync](#documentation-publishing--website-sync)
6. [Finalizing the Release](#finalizing-the-release)

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

## Docs Release Step

Before creating the final tag, rebuild the in-app docs without the pre-release
banner and commit the result. This ensures App Store users see clean documentation
without the “Pre-release — subject to change” warning.

1. Ensure `MARKETING_VERSION` in the Xcode project already matches the version
   you are about to release (this is typically set weeks earlier when the build
   entered TestFlight).
2. Run the release docs script:
   ```sh
   bash scripts/cut-release-docs.sh X.YY.ZZ
   ```
   The script will:
   - Verify `MARKETING_VERSION` matches the argument
   - Rebuild all bundled HTML without the pre-release banner
   - Commit the result with message `docs: rebuild for vX.YY.ZZ release`
   - Create annotated tag `vX.YY.ZZ`
3. Push the commit and tag:
   ```sh
   git push origin X.YY.ZZ-release
   git push origin vX.YY.ZZ
   ```

For full details and error recovery, see
[`specs/013-docs-release-versioning/quickstart.md`](specs/013-docs-release-versioning/quickstart.md).

## Documentation Publishing & Website Sync

Documentation publishes **only at a tagged release** — never from day-to-day commits
to `main`. Pushing the `vX.YY.ZZ` tag (step 3 above) runs three GitHub Actions
workflows:

| Workflow | What it does |
|---|---|
| [`docs-release-gate.yml`](.github/workflows/docs-release-gate.yml) | Fails the release if any bundled HTML still carries the pre-release banner. If it fails, re-run `scripts/cut-release-docs.sh X.YY.ZZ`, then **delete and recreate the tag** — re-running the script makes a new commit, so a plain re-push won't move the existing tag. The workflow prints the exact recovery commands (`git tag -d vX.YY.ZZ && git push origin :refs/tags/vX.YY.ZZ`, then re-tag and push `vX.YY.ZZ`). |
| [`docs-release.yml`](.github/workflows/docs-release.yml) | Builds and deploys this repo's GitHub Pages docs site (production, no beta banner). |
| [`docs-release-bundle.yml`](.github/workflows/docs-release-bundle.yml) | Creates the GitHub **Release** for the tag and attaches `meshtastic-apple-docs-<version>.tar.gz` — the canonical English user/developer guides and screenshots, in the repo's `docs/` layout. |

**Website (meshtastic.org) sync.** The main docs site pulls Apple docs from this repo
via its `sync-apple-docs` job. That job downloads the **latest Meshtastic-Apple
release** asset (`meshtastic-apple-docs-*.tar.gz`) and runs `sync-apple-docs.js`
against it — it does **not** clone `main`. So the published Apple docs are pegged to
the released app version and only change when a new `vX.YY.ZZ` tag is cut, not on
every docs commit to `main`.

> The website sync runs on a weekly schedule (and on demand). The first sync after a
> release picks up the new bundle automatically; to publish sooner, manually run the
> `Sync Apple App Documentation` workflow in the `meshtastic/meshtastic` repo.

## Finalizing the Release

1. Perform final testing and quality checks on the `X.YY.ZZ-release` branch.
    a. If any hotfix changes are required, merge those changes into `X.YY.ZZ-release`.
    b. After merging these changes into the release branch, cherry-pick the changes onto `main`.
2. Once everything is ready, push the final release tag. Use the **`v`-prefixed**
   form — this is the same `vX.YY.ZZ` tag created by the Docs Release Step, and the
   docs release workflows only trigger on `v*.*.*` (a bare `X.YY.ZZ` tag would never
   publish the docs bundle or Pages). See
   [Documentation Publishing & Website Sync](#documentation-publishing--website-sync).
   ```sh
   git tag -a vX.YY.ZZ -m "Release vX.YY.ZZ"
   git push origin vX.YY.ZZ
   ```

Thank you for following the release process and helping to ensure the stability and quality of Meshtastic!

---

Feel free to modify this template to better fit your project's specific needs.