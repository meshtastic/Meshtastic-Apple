## What changed?

Implements and hardens per-node database backup and restore when switching radios, then follows through on the real-world issues found while validating that flow.

### Radio switching and node backup/restore

- Back up the active SwiftData store before switching radios
- Restore a previously connected radio by importing its backup into the live container instead of swapping database files
- Reuse the same backup/clear/restore flow from both the Connect view and Backup Management
- Show blocking switch/restore progress UI while the database handoff is happening
- Keep the currently active database backed up even when the target node number is not yet known

### Backup management and storage polish

- Add restore and delete actions to Backup Management, including Mac Catalyst-friendly inline actions
- Cap retained backups and keep the backup index in sync with current snapshots
- Compact copied backups after creation so the copied `.store-wal` and `.store-shm` contents are merged into the copied store and the sidecar files are removed
- Expand App Data file visibility with active database size breakdown, relative file paths, and export/delete actions

### Connection and data integrity fixes

- Fix serial disconnect/import crashes by tightening teardown ordering and continuation cleanup
- Fix database clearing so route-preservation logic no longer keeps `TraceRouteEntity` rows and duplicates them on restore
- Restore pending trace routes in the Trace Route Log instead of only showing completed responses
- Refresh bundled device hardware data immediately after switch-time `wantConfig`, then refresh the Meshtastic hardware API catalog in the background

### Docs and supporting assets

- Update the user and developer docs for radio switching and transport sequencing
- Rebuild bundled docs output for the in-app documentation viewer
- Refresh bundled device hardware resources and generated image/docs manifests as part of the branch changes

## Why did it change?

The original feature goal was to preserve a full local database per radio and restore it safely when returning to that radio. Earlier file-swap and container-recreation approaches were brittle under SwiftData and caused crashes or stale model references. The import-based restore path keeps the live container stable while still restoring the full node-specific dataset.

Once that core flow worked, additional validation exposed practical issues around disconnect races, trace route duplication, backup ergonomics, and stale hardware catalog data after switching radios. This branch addresses those follow-on issues so the switching experience is reliable enough for regular use.

## How is this tested?

- Manual testing of switching between previously connected radios and verifying full database restoration
- Manual testing of Backup Management restore/delete flows
- Manual testing of trace route visibility after the restore and clear-database fixes
- Manual testing of disconnecting a serial node while database retrieval/import is still in progress
- Repeated Mac Catalyst build verification:
	- `xcodebuild -workspace Meshtastic.xcworkspace -scheme Meshtastic -destination 'platform=macOS,variant=Mac Catalyst' build`
- Documentation rebuild verification:
	- `bash scripts/build-docs.sh --output Meshtastic/Resources/docs`

Note: targeted tests were not run locally because of the current macOS host / test target version mismatch.

## Screenshots/Videos (when applicable)

Not applicable.

## Checklist

- [x] My code adheres to the project's coding and style guidelines.
- [x] I have conducted a self-review of my code.
- [x] I have verified whether these changes require an update to existing documentation or if new documentation is needed, and created an issue in the [docs repo](http://github.com/meshtastic/meshtastic/issues) if applicable.
- [x] I have tested the change to ensure that it works as intended.
