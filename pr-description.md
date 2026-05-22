## What changed?

Implements and hardens automatic per-node database backup and restore when switching radios, using the final import-based approach rather than swapping the live SwiftData container.

### Automatic backup and restore

- Before switching away from a connected node, the app snapshots the full SwiftData store files for that node
- When reconnecting to a previously seen node, the app restores that node by importing the backup into the existing live container after clearing the current database
- Backup resolution supports reconnecting by node number and by stored peripheral identifier
- Backup integrity validation now runs on the real restore path

### Approach changes and cleanup

- Removed obsolete restore paths from the earlier file-swap/container-recreation attempts
- Split the large import helper block out of `NodeBackupManager` into `NodeBackupManager+Import.swift`
- Kept the live `ModelContainer` stable to avoid stale-model crashes during node switching

### Additional bug fixes

- Fixed traceroute history fetching so completed traceroutes are shown again instead of flooding the UI with sent-only records
- Fixed a serial disconnect crash when disconnecting while node import was still in progress
- Made disconnect teardown idempotent and dropped late in-flight events during shutdown to avoid teardown races
- Fixed continuation cleanup ordering for database retrieval so disconnect/cancel paths do not double-resume continuations

## Why did it change?

The original backup/restore goal required restoring the whole database for each node, not just selected entities. Earlier restore attempts based on swapping database files or recreating the SwiftData container were unstable and caused more aggressive crashes. Importing a backed-up store into the existing live container preserves the full node-specific database while avoiding those SwiftData lifecycle issues.

The follow-up bug fixes in this PR close the regressions and race conditions found while validating the feature in real radio-switching and serial-disconnect flows.

## How is this tested?

- Manual testing of switching between previously connected radios and verifying full database restoration
- Manual testing of traceroute history after backup/restore changes
- Manual testing of disconnecting a serial node while database retrieval/import is still in progress
- Mac Catalyst build verification:
	- `xcodebuild -workspace Meshtastic.xcworkspace -scheme Meshtastic -destination 'platform=macOS,variant=Mac Catalyst' build`

Note: targeted tests were not run locally because of the current macOS host / test target version mismatch.

## Screenshots/Videos (when applicable)

Not applicable.

## Checklist

- [x] My code adheres to the project's coding and style guidelines.
- [x] I have conducted a self-review of my code.
- [x] I have verified whether these changes require an update to existing documentation or if new documentation is needed, and created an issue in the [docs repo](http://github.com/meshtastic/meshtastic/issues) if applicable.
- [x] I have tested the change to ensure that it works as intended.
