# SwiftData schema history fixtures

These fixtures answer one question: can the current production schema and migration plan open stores written by every SwiftData release from `v2.7.13` through `v2.7.21` without replacing local data?

## Generate

Install an iOS 18.2 simulator named `iPhone 16`, or provide another destination:

```sh
SCHEMA_FIXTURE_DESTINATION='platform=iOS Simulator,id=<device-id>' \
  scripts/generate-swiftdata-schema-fixtures.sh
```

The script:

1. Exports each release tag into a temporary directory without changing this checkout.
2. Adds a test-only generator to that tag's existing migration test file.
3. Creates a populated disk store containing users, a favorite node, a position, a message, optional values, and relationships.
4. Reads `NSStoreModelVersionHashes` from the finished store.
5. Deduplicates stores by a SHA-256 checksum of the sorted entity version hashes.
6. Records each tag's resolved commit and the Xcode version used.
7. Writes the retained stores and tag mapping to `research/fixtures/swiftdata-schema-history`.

The script refuses to overwrite existing fixtures. Move the fixture directory aside before regenerating it.

## Validate

Run the focused current-version tests:

```sh
xcodebuild test \
  -project Meshtastic.xcodeproj \
  -scheme Meshtastic \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2' \
  -only-testing:MeshtasticTests/SchemaHistoryUpgradeTests
```

The tests copy each unique fixture, open it with `MeshtasticSchema.current` and `MeshtasticMigrationPlan`, then verify the sentinel rows and relationships. They also check that no `-broken-*` replacement store appears.
