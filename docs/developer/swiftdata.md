---
title: SwiftData
parent: Developer Guide
nav_order: 5
---

# SwiftData

The app uses SwiftData exclusively for persistence. Do not introduce SQLite, Realm, Core Data, or any other persistence library.

## ModelContainer Setup

`PersistenceController.shared` (in `Meshtastic/Persistence/PersistenceController.swift`) creates and owns the `ModelContainer`. It is initialised once at app launch in `MeshtasticApp.swift` and injected via `.modelContainer(PersistenceController.shared.container)`.

## Using the ModelContext in Views

```swift
struct MyView: View {
    @Environment(\.modelContext) private var context
    @Query private var nodes: [NodeInfoEntity]

    var body: some View { ... }
}
```

Use `@Query` for data that drives the view. Use `context.insert(_:)` / `context.delete(_:)` for mutations. Mutations on the main context are safe on the main actor.

## Background Writes

For writes triggered by incoming radio packets (off the main thread), use the `MeshPackets` `@ModelActor`:

```swift
let actor = MeshPackets(modelContainer: PersistenceController.shared.container)
await actor.savePacket(packet)
```

Never write to the main `ModelContext` from a background thread.

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
| `TelemetryEntity` | Device/environment sensor data |
| `TraceRouteEntity` | A recorded trace route |
| `WaypointEntity` | A shared map waypoint |

## Schema Migrations

When you add, rename, or remove properties on a `@Model` type, you must provide a migration:

1. Add a new `VersionedSchema` in `MeshtasticSchema.swift`.
2. Add a `MigrationStage` to the `SchemaMigrationPlan`.
3. Use `.lightweight` for additive changes (new optional properties); use `.custom` for destructive changes.

```swift
enum MeshtasticSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] = [NodeInfoEntity.self, ...]
}

// In the migration plan:
.lightweight(fromVersion: MeshtasticSchemaV1.self, toVersion: MeshtasticSchemaV2.self)
```

**Never delete a `VersionedSchema`.** Migration history must be preserved.

## Query Helpers

`QueryCoreData.swift` contains helper functions for common fetches:

```swift
let node = getNodeInfo(id: nodeNum, context: context)
```

`UpdateCoreData.swift` contains helpers for upsert patterns:

```swift
upsertNode(packet: packet, context: context)
```

Prefer these helpers over direct queries to keep logic consistent.
