# Contributing to Meshtastic

Thank you for considering contributing to Meshtastic! We appreciate your time and effort in helping to improve the project. This document outlines the guidelines for contributing to the project.

## Table of Contents

- [Contributing to Meshtastic](#contributing-to-meshtastic)
  - [Table of Contents](#table-of-contents)
  - [Getting Started](#getting-started)
    - [Code Signing](#code-signing)
    - [Changing the Project Structure](#changing-the-project-structure)
  - [Development Workflow](#development-workflow)
    - [Targeting `main`](#targeting-main)
    - [Small, Incremental Changes](#small-incremental-changes)
    - [Rebase Commits](#rebase-commits)
  - [Creating a Branch](#creating-a-branch)
  - [Making Changes](#making-changes)
  - [Commit Messages](#commit-messages)
  - [Merging Changes](#merging-changes)
  - [Testing](#testing)
  - [Code Review](#code-review)
  - [Documentation](#documentation)
  - [Style Guides](#style-guides)
    - [Git Commit Messages](#git-commit-messages)
    - [Code Style](#code-style)
  - [Community](#community)

## Getting Started

1. Fork the repository on GitHub.
2. Clone your fork to your local machine:
   ```sh
   git clone https://github.com/<your-username>/Meshtastic-Apple.git
   ```
3. Navigate to the project directory:
   ```sh
   cd Meshtastic-Apple
   ```
4. Open the Meshtastic.xcworkspace
   ```sh
   open Meshtastic.xcworkspace
   ```

### Code signing

The project reads signing values from `Configuration/Signing.xcconfig`. That
committed file contains the Meshtastic Apple Developer team and bundle
identifier defaults. Meshtastic team members can use those values as-is.

If you are not a member of the Meshtastic Apple Developer team, create
`Configuration/Signing.local.xcconfig` to override the defaults with your own
Apple Developer team and bundle identifier. The committed configuration
optionally includes this file when it exists, so no project-file changes are
needed:

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
BASE_BUNDLE_IDENTIFIER = com.example.MeshtasticClient
```

- Set `DEVELOPMENT_TEAM` to your 10-character Apple Developer Team ID.
- Choose a reverse-DNS `BASE_BUNDLE_IDENTIFIER` that is unique to your team.
  Use only the base identifier; the project automatically adds suffixes for
  the widgets, Watch app, and test bundles.
- Do not edit `Configuration/Signing.xcconfig` just to use a personal account.
  `Signing.local.xcconfig` is ignored by Git and must not be committed.
- Simulator builds do not require a local signing override.
- Changing the local file does not require XcodeGen or a regenerated project.
  Close and reopen the workspace, or clean the build folder, if Xcode has
  cached the previous signing values.

Xcode uses automatic signing for the app and its extensions. After creating
the local file, select your device and build the `Meshtastic` scheme normally.

### Changing the project structure

`Meshtastic.xcodeproj` is generated from `project.yml` and committed to the
repository, so cloning and opening the workspace requires no extra tooling.
Source files are picked up from disk by their folder, so adding, moving or
deleting one never touches the project file.

If you change **targets, build settings, dependencies or schemes**, edit
`project.yml` instead of the project, then regenerate and commit.

XcodeGen's output is version-dependent, so the version is pinned exactly in
`.xcodegen-version` — regenerate with that version or CI will report drift:

```sh
version=$(cat .xcodegen-version)
curl -fsSL -o /tmp/xcodegen.zip \
  "https://github.com/yonaskolb/XcodeGen/releases/download/${version}/xcodegen.zip"
unzip -q /tmp/xcodegen.zip -d /tmp/xcodegen-dist
/tmp/xcodegen-dist/xcodegen/bin/xcodegen generate
```

CI regenerates the project on every pull request with the pinned version and
fails if the committed project does not match `project.yml`.

## Development Workflow

### Targeting `main`

In accordance with trunk-based development, all changes should target the `main` branch.

### Small, Incremental Changes

To facilitate easy code reviews and minimize merge conflicts, we encourage making small, incremental changes. Each change should be a self-contained, logically coherent unit of work that addresses a specific task or fixes a particular issue.

### Rebase Commits

To keep the project history clean, please use rebasing over merging when incorporating changes from the `main` branch into your feature branches. To rebase your branch on `main`, you can perform the following steps.

```sh
git fetch
git rebase main
```

To enable pulls to rebase by default, you can use this git configuration option.

```sh
git config pull.rebase true
```

## Creating a Branch

1. Always create a new branch for your work. Use a descriptive name for your branch:
   ```sh
   git checkout -b your-branch-name
   ```

## Making Changes

1. Make your changes in the new branch.
2. Ensure your changes adhere to the project’s coding standards and conventions.
3. Keep your changes focused and avoid combining multiple unrelated tasks in a single branch.

## Commit Messages

1. Write clear and concise commit messages following the guidelines in [Git Commit Messages](#git-commit-messages).

## Merging Changes

1. Push your changes to your fork:
   ```sh
   git push origin your-branch-name
   ```
2. Create a pull request (PR) targeting the `main` branch.
3. Ensure your PR adheres to the project's guidelines and includes a clear description of the changes.
4. Request a code review from the project maintainers.

## Testing

1. Ensure all existing tests pass before submitting your PR.
2. Write new tests for any new features or bug fixes.
3. Run the tests locally

## Code Review

1. Address any feedback or changes requested by the reviewers.
2. Once approved, the PR will be merged into the `main` branch by a project maintainer.

## Documentation

1. Update the documentation to reflect any changes you have made.
2. Ensure the documentation is clear and concise.

## Style Guides

### Git Commit Messages

- Use the imperative mood in the subject line (e.g., "Fix bug" instead of "Fixed bug").
- Use the body to explain what and why, not how.

### Code Style

- This project requires swiftLint - see https://github.com/realm/SwiftLint
- Use SwiftUI
- Use SFSymbols for icons
- Use Core Data for persistence
- Ensure your code is clean and well-documented.

## Community

- Join our community on [Discord](https://discord.com/invite/ktMAKGBnBs).
- Participate in discussions and share your ideas.

Thank you for contributing to Meshtastic!
