---
title: SwiftData
parent: Developer Guide
nav_order: 5
---

# SwiftData

The app uses SwiftData exclusively for persistence. Do not introduce SQLite, Realm, Core Data, or any other persistence library.

## ModelContainer Setup

`PersistenceController.shared` (in `Meshtastic/Persistence/Persistence.swift`) creates and owns the active `ModelContainer`. Production opens one combined container with two explicit configurations: 49 radio-owned models use the selected file under `RadioStores/`, while phone-recorded routes and the radio registry use `RadioRegistry.store`. `MeshtasticApp` injects the current container through `.modelContainer(...)` and rebuilds its query tree after a store change.

Autosave is **disabled** in production (`container.mainContext.autosaveEnabled = false`). Runtime writers call `ModelContext.coordinatedSave()` or a writer-specific helper. Raw `ModelContext.save()` calls are limited to bootstrap code and code that already holds a `ContainerWritePermit`.

## Save Strategy

The app uses two save patterns depending on packet frequency:

### Immediate Saves

Config changes, messages, waypoints, and other low-frequency mutations call `savePendingChanges()` directly after updating the model graph. The helper acquires a container write permit, saves, and releases the permit. A stale or transitioning container rolls back pending changes instead of writing into a retired radio store.

### Debounced Saves

High-frequency packets — positions and telemetry — use `scheduleDebouncedSave()` to coalesce writes. The debouncer waits **2 seconds** of inactivity before flushing, with a hard ceiling of **5 seconds** from the first dirty change. This prevents dozens of SQLite writes per second when the mesh is busy.

```
Position packet 1 → dirty flag set, 2s timer starts
Position packet 2 (200ms later) → timer resets to 2s
Position packet 3 (200ms later) → timer resets to 2s
...
No packets for 2s → save() fires
— OR —
5s since first dirty change → save() fires regardless
```

Debounced saves are flushed explicitly on disconnect so no data is lost.

## Container Coordination

`ContainerAccessCoordinator` serializes saves against container replacement. A writer captures `ContainerWriteAccess` with its context, acquires a permit through the save, and releases it synchronously. A container transition rejects new permits and waits up to five seconds for active writers to finish before replacing the container.

`ModelContext.coordinatedSave()` looks up the authority registered for the context's exact `ModelContainer`. Current containers acquire permits. Retired containers roll back and throw `ContainerLeaseError.stale`. Independent test and preview containers that are not managed by `PersistenceController` save normally.

Do not add a raw runtime `context.save()` call. `CoordinatedSaveGuardTests` scans app Swift sources and fails unless an exceptional raw save has a `coordinated-save-allow` annotation explaining which permit or bootstrap phase makes it safe.

## Global Radio Registry

`RadioRegistrySchemaV1` defines a separately versioned global schema for phone-recorded routes, immutable radio profiles, transport aliases, registry metadata, and quarantine state. `RadioRegistryController` opens this schema independently of the active radio container, so replacing or deleting a radio store cannot erase identity records.

`RadioIdentityRegistry` contains the conservative claim-resolution rules. Valid firmware device IDs take precedence over node-number fallback claims. A fallback profile is promoted only when the same BLE alias corroborates it. TCP endpoints and serial paths can be reassigned, so they cannot prove continuity. Conflicting claims are quarantined rather than merged. Store keys are random UUIDs and never derive from a device ID, node number, BLE UUID, TCP endpoint, or serial path.

`RadioStoreCoordinator` is the production selection boundary. Every connection first resolves its transport alias. A known alias opens its persistent radio store; an unknown alias opens an empty in-memory bootstrap store. Incoming radio-owned packets remain in a bounded memory buffer until `MyInfo` supplies a usable canonical claim. Identity confirmation then opens the matching persistent store, rebinds long-lived contexts, stores the selected profile, writes `MyInfo`, and replays the buffered packets. Conflicting or unusable claims remain in the bootstrap store and do not reach SwiftData.

Hardware checks confirmed that firmware device ID remains stable across serial, BLE, TCP, reboot, both factory-reset modes, and full erase/reflash. Full erase changed the node number until the previous security keys were restored, confirming that node number is only a fallback claim. A physical-iPhone uninstall/reinstall preserved the observed BLE peripheral UUID for one radio, and the app successfully attached a new BLE alias to the other radio's stable firmware identity after bond loss.

### Legacy store migration

`MultiRadioStoreBootstrap` runs before the production container opens. If `Meshtastic.store` exists, `LegacyRadioStoreMigrator` copies radio-owned rows into a new immutable radio store and routes/locations into `RadioRegistry.store`, preserving relationships. It records migration start and completion in registry metadata, refuses ambiguous identity, existing destination data, and orphaned sidecars, and archives the source as `Meshtastic.store-legacy-backup` only after both destinations commit. A launch after interruption resumes from the recorded profile and store key.

Migration and selection tests cover relationship preservation, idempotency, interrupted recovery, rollback behavior, stale-writer rejection, two-radio isolation, backup restore targeting, and conflict quarantine. A normal simulator launch migrated an existing 144-node store, retained its `MyInfo`, created one selected profile, preserved the legacy backup, and passed SQLite integrity checks on all three files. A clean TCP replay launch also exercised the production unknown-alias path: canonical `MyInfo` created a profile and persistent store before six radio-owned node rows were committed; the global store contained only registry rows.

Node backups copy the active UUID-named radio store and its matching WAL/SHM sidecars. New backup-index entries include the canonical firmware device ID. Restore requires that identity to match the target profile before the store is cleared. Version-1 indexes still decode, but their identity-less backups must be recreated after connecting to the radio before they can be restored.

An in-place update on a physical iPhone exercised production migration and switching with two Heltec V4 radios. The app archived the intact 35-node legacy store, created the global registry and FA99 radio store, reconnected FA99 under its existing BLE alias, then switched FA99 → FA98 → FA99. FA98 remained isolated at 149 node rows while FA99 advanced independently from 40 to 41 rows after reconnect. Each store retained only its own canonical firmware device ID and node number. The registry selected the correct profile after each switch, and the registry, both radio stores, and archived legacy store passed SQLite integrity checks.

## Indexes

Frequently queried fields use `@Attribute(.unique)` to create a UNIQUE INDEX in the underlying SQLite store. This eliminates full table scans on the hottest lookup paths:

| Field | Entity | Why |
|-------|--------|-----|
| `num` | `NodeInfoEntity` | Looked up on every incoming packet |
| `num` | `UserEntity` | Looked up on every message |
| `messageId` | `MessageEntity` | ACK lookups, deduplication |
| `hwModel` | `DeviceHardwareEntity` | Hardware image lookups |

> **Note** — `@Attribute(.indexed)` requires iOS 18+. The app targets iOS 17.5, so `@Attribute(.unique)` is used instead (it creates a UNIQUE INDEX which also serves as a regular index).

## Using the ModelContext in Views

```swift
struct MyView: View {
    @Environment(\.modelContext) private var context
    @Query private var nodes: [NodeInfoEntity]

    var body: some View { ... }
}
```

Use `@Query` for data that drives the view. Use `context.insert(_:)` / `context.delete(_:)` for mutations, then call `try context.coordinatedSave()`. Main-actor isolation alone does not protect a context that outlives a radio-store transition.

### Snapshot liveness

Views that intentionally keep a throttled `@State` snapshot instead of a live `@Query` must treat the snapshot as invalid after a node-database reset or a context teardown. Before reading persisted properties from a `NodeInfoEntity` held in such a snapshot, require both `modelContext != nil` and `!isDeleted`. `NodeInfoEntity.adminPickerOrder(_:)` applies this rule for the Settings node picker, so deleted or detached nodes cannot be selected or rendered from a stale snapshot.

## Background Writes

Writes triggered by incoming radio packets run through the `MeshPackets` `@ModelActor`.

The shared `MeshPackets` actor is created with the active container and its matching `ContainerWriteAccess`. Its save helpers drop and roll back work after that container retires.

Never write to the main `ModelContext` from a background thread. A new background writer must capture write access with its context and hold a permit through save.

## Model Types

All model types live in `Meshtastic/Model/`. Each type is decorated with `@Model`:

```swift
@Model
final class NodeInfoEntity {
    var num: Int64
    var longName: String?
    // ...
}
```

Key model types:

| Type | Description |
|------|-------------|
| `NodeInfoEntity` | A node heard on the mesh |
| `MessageEntity` | A channel or direct message |
| `PositionEntity` | A GPS position update |
| `TelemetryEntity` | Device, environment, power, air-quality (PM), and local-stats sensor data, discriminated by `metricsType` |
| `TraceRouteEntity` | A recorded trace route |
| `WaypointEntity` | A shared map waypoint |
| `EventFirmwareEntity` | Cached off-device event-firmware branding/lifecycle metadata |

### `EventFirmwareEntity` — off-device event branding cache

`EventFirmwareEntity` is a **runtime cache**, not user data. A device only reports *which*
event edition it runs via the `MyNodeInfo.firmwareEdition` proto enum (mapped to the
`FirmwareEditions` Swift enum); the display data for each edition — name, welcome message,
dates, IANA time zone, accent color, links, theme, and the event's own firmware build — lives
off-device at `https://api.meshtastic.org/resource/eventFirmware` (version 2). `MeshtasticAPI`
seeds the cache from the bundled `event_firmware.json` at launch (offline-first) and then
refreshes it from the live endpoint in the background. The `edition` proto-enum name (e.g.
`"DEFCON"`) is the unique join key against the connected device's reported edition. Because it
is a rebuildable cache, a failed/empty refresh is a **no-op** that leaves existing rows intact
(it never wipes the cache), and the row lives in the unreleased **V1** schema — adding it
required no new `VersionedSchema`/`MigrationStage` (see below).

## Schema Migrations

When you add, rename, or remove properties on a `@Model` type, you must provide a migration. Schema files live in `Meshtastic/Model/Schema/`.

> **Note — V1 is unreleased.** While `MeshtasticSchemaV1` remains the initial, unshipped version, additive `@Model` changes go **directly into V1** rather than a new versioned schema + stage (see the comment in `MeshtasticMigrationPlan.swift`). For example, the air-quality particulate-matter fields on `TelemetryEntity` (`pm10/25/100Standard`, `pm10/25/100Environmental`) were added in place. Start adding `VersionedSchema` versions and migration stages only once V1 has shipped.

### Adding a New Schema Version

1. Create `Meshtastic/Model/Schema/MeshtasticSchemaV2.swift` with the updated models:

```swift
enum MeshtasticSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { ... }
}
```

2. Append `MeshtasticSchemaV2.self` to `MeshtasticMigrationPlan.schemas` (newest last).
3. Add a migration stage to `MeshtasticMigrationPlan.stages`:

```swift
// Lightweight — SwiftData infers additive changes automatically (new optional properties)
static let migrateV1toV2 = MigrationStage.lightweight(
    fromVersion: MeshtasticSchemaV1.self,
    toVersion: MeshtasticSchemaV2.self
)

// Custom — when you need to transform or backfill data
static let migrateV1toV2 = MigrationStage.custom(
    fromVersion: MeshtasticSchemaV1.self,
    toVersion: MeshtasticSchemaV2.self,
    willMigrate: { context in },
    didMigrate: { context in
        // Transform data, populate new fields, etc.
        try context.save()
    }
)
```

4. Update `MeshtasticSchema.current` to point to the new version.

> **Warning — Never delete a `VersionedSchema`.** Migration history must be preserved or the migration plan will fail on devices that skipped intermediate versions.

### Deprecated Properties

When a proto field is deprecated upstream and the app stops using it, **do not remove the corresponding `@Model` property** — deleting a stored property is a schema change that would require a migration, and while V1 is unreleased there is nowhere to migrate from. Instead, retain the property as-is so:

- the SwiftData schema is unchanged, and
- any values already persisted on-device remain readable.

The field simply stops being surfaced in the UI, read, or actively written by app code. Mark it with a doc comment noting the deprecation and the tracking issue. Current examples:

| Model | Property | Notes |
|-------|----------|-------|
| `CannedMessageConfigEntity` | `enabled` | #2021 — no successor; retained for schema/value compatibility, no longer read or written |

## Query Helpers

`QuerySwiftData.swift` contains helper functions for common fetches:

```swift
let node = getNodeInfo(id: nodeNum, context: context)
```

`UpdateSwiftData.swift` contains helpers for upsert patterns:

```swift
upsertNode(packet: packet, context: context)
```

Prefer these helpers over direct queries to keep logic consistent.

## Data Caps

To prevent unbounded database growth, the app enforces per-node caps when inserting new records. Older rows beyond the cap are deleted in the same transaction:

| Relationship | Cap | Behavior |
|-------------|-----|-----------|
| `NodeInfoEntity.positions` | 5 000 | Oldest positions deleted when exceeded |
| `NodeInfoEntity.telemetries` | 5 000 per metrics type | Oldest telemetry of that type deleted |
| `MessageEntity` (per channel) | 50 000 | Oldest messages in the channel deleted |

These caps are enforced in `UpdateSwiftData.swift` during the upsert path, so they run on every incoming packet without requiring a separate maintenance task.

## Performance Testing — Large Database Seed Harness

`Meshtastic/Persistence/PerformanceSeedData.swift` provides a DEBUG-only harness for seeding thousands of synthetic nodes, telemetry rows, positions, and messages into the simulator store. It is entirely gated by launch-time flags; production builds and unlaunched DEBUG builds are unaffected.

### Triggering the harness

The harness activates when **either** of the following is present at launch:

- The `--meshtastic-perf-seed` launch argument, **or**
- The `MESHTASTIC_PERF_SEED_NODES` environment variable (any non-zero integer value)

When neither is set, `PerformanceSeedData.configuration` returns `nil` and no seed code runs.

### Environment variables

Pass variables to the simulator using the `SIMCTL_CHILD_` prefix (the prefix is stripped before the app sees them):

| Variable | Default | Description |
|----------|---------|-------------|
| `MESHTASTIC_PERF_SEED_NODES` | — | **Required to activate.** Number of nodes to seed (e.g. `5000`). |
| `MESHTASTIC_PERF_TELEMETRY_HISTORY` | `3` | Device + environment metric samples per node. |
| `MESHTASTIC_PERF_LOCAL_STATS_HISTORY` | `MESHTASTIC_PERF_TELEMETRY_HISTORY` | Local stats samples per node, including synthetic noise floor, packet counters, utilization, and node counts. |
| `MESHTASTIC_PERF_POSITION_HISTORY` | `3` | Position history entries per node. |
| `MESHTASTIC_PERF_DIRECT_MESSAGES` | `0` | Direct messages to seed between node 0 and node 1. |
| `MESHTASTIC_PERF_CHANNEL_MESSAGES` | `0` | Channel messages to seed on channel 0. |
| `MESHTASTIC_PERF_RESET_STORE` | `0` | Set to `1`/`true` to clear the store before seeding. |
| `MESHTASTIC_PERF_COMPACT_LIST` | `0` | Set to `1`/`true` to switch the node list to compact density. |
| `MESHTASTIC_PERF_ENABLE_DISCOVERY` | `0` | Set to `1`/`true` to leave BLE discovery enabled (disabled by default for perf runs). |

### Example: seed 5 000 nodes with a clean store

First, find your simulator UDID:

```bash
xcrun simctl list devices booted
```

Then launch with the seed variables:

```bash
SIMCTL_CHILD_MESHTASTIC_PERF_SEED_NODES=5000 \
SIMCTL_CHILD_MESHTASTIC_PERF_RESET_STORE=true \
SIMCTL_CHILD_MESHTASTIC_PERF_COMPACT_LIST=true \
xcrun simctl launch <UDID> gvh.MeshtasticClient
```

### Example: seed local stats for noise-floor chart work

Use a smaller node count and a larger local stats history when tuning the Local Stats Log UI. This keeps the simulator responsive while giving the chart enough variation to show quiet periods, busy periods, and occasional interference spikes.

```bash
SIMCTL_CHILD_MESHTASTIC_PERF_SEED_NODES=20 \
SIMCTL_CHILD_MESHTASTIC_PERF_LOCAL_STATS_HISTORY=168 \
SIMCTL_CHILD_MESHTASTIC_PERF_TELEMETRY_HISTORY=3 \
SIMCTL_CHILD_MESHTASTIC_PERF_POSITION_HISTORY=3 \
SIMCTL_CHILD_MESHTASTIC_PERF_RESET_STORE=true \
SIMCTL_CHILD_MESHTASTIC_PERF_ENABLE_DISCOVERY=0 \
xcrun simctl launch <UDID> gvh.MeshtasticClient \
  --meshtastic-perf-seed \
  --meshtastic-perf-start-local-stats
```

`--meshtastic-perf-start-local-stats` selects seeded node `0x0A000000` and opens its Local Stats Log directly in DEBUG simulator builds.

Add `--meshtastic-perf-local-stats-same-hour` when checking short-range noise-floor chart layout. It keeps local stats samples in the same hour at 5-minute intervals, which makes `1h` axis label clipping easy to reproduce.

On subsequent launches **without** `MESHTASTIC_PERF_RESET_STORE`, the harness detects the existing node count and skips re-seeding, so the app starts at full speed against the already-seeded store.

### What to expect

5 000 nodes (3 device/environment telemetry samples, 3 local stats samples, 3 positions/node) seed in approximately **12 seconds** on an Apple Silicon Mac. The app navigates automatically to the Nodes tab. Typical idle CPU after seeding is under 2%.

> **Tip — Checking seed progress**
> Seed log lines are emitted at `Info` level under the `🗄️ Data` OSLog category. To stream them:
> ```bash
> log stream --predicate 'process == "Meshtastic" AND eventMessage CONTAINS "[PerfSeed]"' --level info
> ```

### Skip-reseed logic

If the store already contains at least as many nodes as `MESHTASTIC_PERF_SEED_NODES` requests, seeding is skipped unless `MESHTASTIC_PERF_RESET_STORE=true` is set. This means you can kill and relaunch the app against the existing large dataset without waiting for a reseed.
