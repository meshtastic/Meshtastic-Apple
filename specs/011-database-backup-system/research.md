# Research: Automatic Node Database Backup & Restore

**Feature**: 011-database-backup-system
**Date**: 2025-07-14
**Status**: Complete

## Research Questions & Findings

### R0: Multi-Radio Physical Store Spike (2026-08-03)

**Question**: Can the app replace backup/clear/import switching with one SwiftData store per local radio without key collisions or relationship leakage?

**Finding**: An initial disposable harness opened the complete 51-model production schema in two explicit URL-backed containers. The permanent tests then split that schema into 49 radio-owned models and two global route models. `MultiRadioStoreIsolationTests` verifies colliding `NodeInfoEntity.num`, `UserEntity.num`, and `MessageEntity.messageId` values, representative relationships, repeated A→B→A access, close/reopen behavior, old-context store affinity, and deletion of one radio store without damaging the other. `MultiRadioStoreSchemaTests` verifies the radio/global schemas are disjoint, complete, and independently openable. These tests passed on the iOS 26.5 simulator runtime.

This proves full-schema store isolation is viable on the tested runtime. It does not prove production store switching is safe. An old context remains bound to its original store and can still save after another store becomes active, so production switching needs a generation-bound lease or equivalent single-writer gate.

**Ownership decision: mirror Android**

Android uses one Room database per local radio and keeps every Room entity in that radio database, including nodes, messages, logs, discovery history, firmware-release caches, hardware/link metadata, quick-chat data, and merge markers (`../android/core/database/src/commonMain/kotlin/org/meshtastic/core/database/MeshtasticDatabase.kt:46-158`). Apple will mirror that coarse ownership boundary rather than inventing entity-by-entity exceptions:

- Every existing SwiftData model is radio-owned except `RouteEntity` and `LocationEntity`.
- `RouteEntity` and `LocationEntity` are app-global because they are phone-recorded map data with no Android radio-database counterpart. Apple already preserves them across radio switches and resets through `clearDatabase(includeRoutes: false)` (`Meshtastic/Persistence/UpdateSwiftData.swift:167-230`, `Meshtastic/Views/Connect/Connect.swift:1133`, `MeshtasticTests/SwiftDataMigrationTests.swift:769-796`).
- `WaypointEntity` is radio-owned. Waypoints arrive through mesh packet ingest and are copied by per-radio backup restore (`Meshtastic/Helpers/MeshPackets.swift:1641-1724`, `Meshtastic/Persistence/NodeBackupManager+Import.swift:258-277`).
- Discovery sessions, discovered nodes, and beacons are radio-owned, matching Android's `DiscoverySession`, `PresetScanResult`, `DiscoveredNode`, and `DiscoveredBeacon` Room entities.
- Hardware, firmware, event-firmware, and device-link cache rows remain in each radio store, matching Android. This duplicates rebuildable cache data but keeps ownership and store switching predictable.
- Apple radio configuration models remain radio-owned because they are attached to the radio's `NodeInfoEntity` graph. Android stores current configuration in process-global protobuf DataStores and clears/repopulates it on reconnect; preserving an offline snapshot per Apple radio is an intentional parity improvement, not a different owner.
- The global store contains phone-recorded routes/locations plus radio profiles, transport aliases, selected-radio state, migration markers, and quarantine records. App preferences remain outside SwiftData as they are today.

**Identity evidence**: A valid `MyInfo.deviceId` is the preferred physical-radio identity. Node number is a claim that can change, while BLE UUID, TCP address, and serial path are transport locators.

A two-radio hardware check on 2026-08-03 covered two Heltec V4 devices running firmware 2.8.0 and 2.7.27. Each reported a distinct 16-byte `MyInfo.device_id` and node number over serial. Both values survived firmware reboot on both radios. Each radio was also read over BLE: its BLE `MyInfo.device_id` and node number exactly matched its serial values, the radios remained distinct, and both CoreBluetooth peripheral UUIDs remained stable across reboot.

The 2.7.27 radio then underwent a standard firmware factory reset with `full=false` after its configuration, channels, owner, and security keys were captured. Its firmware device ID, node number, serial path, private identity key, and CoreBluetooth UUID all survived the reset. Serial and BLE continued to report the same identity. The reset state was restored and the saved configuration diff returned an exact match.

A subsequent `full=true` reset also preserved the firmware device ID, node number, serial path, and advertised CoreBluetooth UUID. It cleared security keys, BLE bonding, and reboot history. The macOS central could still discover the same peripheral UUID but could not reconnect without pairing again, returning `CBErrorDomain Code=14` because the radio had removed its pairing record. Restoring the saved configuration, channels, owner, and security keys returned the radio to its original state.

The same radio was then fully erased and upgraded from 2.7.27 to 2.8.0 using a factory image, unified OTA image, and LittleFS image. The firmware device ID, USB identity, and advertised CoreBluetooth UUID survived. The first boot generated a different node number and empty security-key state. Restoring the saved configuration and security keys restored the previous node number. This is consistent with node number depending on identity-key state and confirms that it cannot identify the physical radio across erase/reflash. Every shared configuration field was restored; the only remaining diff was a new 2.8.0 traffic-management default, which was retained in a new post-upgrade baseline.

A physical-iPhone reinstall check used a separately signed developer app after securely backing up its SwiftData store, WAL, preferences, and documents. The pre-reinstall store contained FA98's firmware device ID, node number, and iOS CoreBluetooth peripheral UUID. After uninstalling and reinstalling the app, reconnecting to FA98 produced the same three values. Both database copies passed SQLite integrity checks. This confirms BLE alias continuity for that iPhone/radio pair across app reinstall, while the firmware device ID remains the stronger identity claim.

After the full reset and erase/reflash cleared FA99's BLE bond, the freshly installed developer app paired to it again. The app's SwiftData row contained FA99's expected firmware device ID and restored node number under a newly observed iOS CoreBluetooth peripheral UUID, and the copied database passed its integrity check. This confirms that a new BLE alias can be attached to the stable firmware identity after bond loss.

A controlled TCP check temporarily joined FA99 to the same LAN as the test Mac. A direct TCP connection to the radio reported the same firmware device ID, node number, owner, hardware model, and firmware version seen over serial and BLE. The temporary Wi-Fi credentials were then cleared, Wi-Fi was disabled, and FA99 was rebooted. Its live configuration matched the protected post-erase baseline exactly and the TCP endpoint disappeared.

These results support firmware device ID as the canonical claim and transport identifiers as advisory aliases. BLE reinstall, post-bond pairing, and physical TCP identity gates pass.

**Platform finding**: The app builds with native macOS settings, while `SUPPORTED_PLATFORMS` currently contains only `iphoneos iphonesimulator` despite `SUPPORTS_MACCATALYST = YES`. Catalyst must not be claimed as supported until the target configuration exposes a Catalyst destination.

**Decision**: Use one persistent store per physical radio plus a small global identity/alias registry. Connection switching no longer clears and imports a shared database. Existing node backups remain available for explicit recovery, and restore is constrained to the store assigned to the target profile.

**Implementation checkpoint**: `MultiRadioStoreSchema` pins 49 existing radio-owned models and a five-model global schema: the two phone-route models plus three registry models. `ContainerAccessCoordinator` now serializes saves against container transitions: a transition rejects new writers, waits up to five seconds for active write permits, installs the replacement container, rotates its lease, registers the new container, and retires the old one. A failed destructive reopen falls back to an in-memory container, so deleted store files never retain a valid lease.

`MeshPackets`, `AccessoryManager`, `DiscoveryScanEngine`, backup restore, app/API/TAK/intent writers, and SwiftUI `ModelContext` saves now use this coordinator. A source guard rejects new raw runtime `ModelContext.save()` calls unless the line has an explicit bootstrap or permit-held annotation. Mutation tests prove the guard, writer drain, timeout, container-identity check, and stale `MeshPackets`/`AccessoryManager` rejection fail when their protection is removed.

`RadioRegistrySchemaV1` versions the global schema from its first revision. `RadioIdentityRegistry` records immutable random store identities, validated firmware device-ID claims, node-number fallback claims, raw transport evidence, and quarantine state. Device-ID claims converge aliases. A node-only profile is promoted only when the same BLE alias corroborates it; TCP endpoints and serial paths are too easily reassigned to prove continuity. Disagreement between device, node, or alias claims quarantines the affected profiles instead of applying Android's silent device-ID precedence. Registry tests prove the global file survives destructive active-radio container replacement. Mutation tests cover device-ID validation, ambiguous promotion, conflict quarantine, and store-key independence.

`LegacyRadioStoreMigrator` now splits the previous `Meshtastic.store` into the selected radio file and `RadioRegistry.store`. It copies before deleting, preserves model relationships, records migration start before copying, resumes interrupted work with the same immutable store key, rejects ambiguous identity and nonempty destinations, and fails closed when an orphaned WAL or SHM sidecar exists. The original files are archived as `Meshtastic.store-legacy-backup` only after both destinations commit. Fixture tests cover radio/global routing, relationship preservation, idempotency, existing-destination protection, interrupted recovery, ambiguous identity, and sidecar handling. Five migration safety mutations were each caught by the focused tests.

Production now opens a combined SwiftData container with explicit radio and global configurations. `RadioStoreCoordinator` preselects stores from known aliases, places unknown aliases in an empty in-memory bootstrap store, and confirms canonical identity from `MyInfo` before any radio-owned packet is persisted. Pre-identity packets are bounded and replayed in arrival order only after successful selection; disconnect drops them if `MyInfo` never arrives. Long-lived contexts retain their containers and rebind after transitions, while a source guard rejects direct singleton capture by new stored contexts. Selected-profile metadata persists in the global store.

Node backup creation now copies the selected UUID-named radio store and that store's WAL/SHM sidecars rather than the obsolete `Meshtastic.store` path. Version-2 backup metadata records canonical firmware device ID. Manual restore resolves the target profile and requires an identity match before clearing or importing. Version-1 indexes remain decodable, but identity-less backups fail closed and must be recreated after connecting to the radio.

A normal simulator launch exercised the real startup path outside XCTest. It migrated an existing legacy store with one `MyInfo` row and 144 node rows, created one selected profile and immutable radio-store file, preserved the legacy backup, and returned `PRAGMA integrity_check = ok` for the registry, radio, and backup files. A clean TCP replay launch exercised the production connection path: the unknown endpoint received no persistent store before canonical `MyInfo`; identity confirmation created one profile, one TCP alias, and one radio store; six node rows landed only in that radio store; and the registry store held no `MyInfo` or node rows. Reconnecting through a second TCP endpoint that reported the same firmware device ID attached the new alias to the existing profile rather than creating a duplicate.

A backed-up developer app was then updated in place on a physical iPhone. First launch archived the intact 35-node legacy store and created a registry profile and UUID-named store for FA99. FA99's firmware device ID `735afb8a53b6869ee51d5b8c7348ce3b`, node number `2245138074`, and BLE alias `16D7BAA0-DE2E-EBCA-94A1-4C3046A89F42` agreed across registry and radio-store rows. The app then switched FA99 → FA98 → FA99. FA98 received a distinct immutable store under firmware device ID `c5e54790b7806d847abf989193a8a7df`, node number `1526261255`, and BLE alias `A5203B4E-5A1F-9D75-E690-50DA2C70AFCC`. FA98 remained at 149 node rows during the return switch while FA99 advanced independently from 40 to 41 rows. Selected-profile metadata returned to FA99, each store contained only its own `MyInfo`, and `PRAGMA integrity_check` passed for the registry, both radio stores, and archived legacy store. This closes the physical migration and repeated two-radio selection gate.

### R1: Backup File Copy Safety with SwiftData

**Question**: How to safely create a backup copy of the SwiftData backing store while SwiftData/ModelContainer is active?

**Decision**: For backup creation, flush pending writes via `flushDebouncedSaves()` and `modelContext.save()`, then copy the `.store`, `.store-wal`, and `.store-shm` files with `FileManager`. Do not apply the same file-swap approach to restore.

**Rationale**: SwiftData uses SQLite with WAL mode. Copying without flushing WAL risks incomplete data. The working backup approach is:
1. Call `modelContext.save()` to flush pending changes
2. Copy the active `.store`, `.store-wal`, and `.store-shm` files into `NodeBackups/{nodeNum}/`
3. Treat the copied store as a snapshot artifact that will later be opened read-only for import

The abandoned restore approaches were:
- swapping SQLite files while the active container still held file descriptors
- recreating the app `ModelContainer` and forcing the UI to rebind

Both produced more aggressive SwiftData crashes than the original problem.

**Alternatives considered**:
- `NSPersistentStoreCoordinator` migration API — not available for SwiftData
- SwiftData `ModelContainer` export API — does not exist in current SDK
- `VACUUM INTO 'path'` — requires raw SQLite access; adds complexity but is atomic
- File coordination (`NSFileCoordinator`) — overkill for single-process app

### R2: Backup Storage Location

**Question**: Where should backup files be stored on-device?

**Decision**: Store in `Application Support/NodeBackups/{nodeNum}/` directory.

**Rationale**:
- `Application Support` is the standard iOS location for app-generated data files that are not user-visible documents
- It is included in device backups (iTunes/Finder) and excluded from iCloud by default
- Organizing by node number creates a clean 1:1 mapping structure
- Files: `Meshtastic.store`, `Meshtastic.store-wal`, `Meshtastic.store-shm` per node subfolder

**Alternatives considered**:
- Documents directory — visible in Files app, inappropriate for internal data
- Caches directory — may be purged by system, unacceptable for backups
- Temporary directory — not persistent
- iCloud container — spec explicitly says local-only unless decided otherwise

### R3: Backup Integrity Verification

**Question**: How to detect backup corruption and ensure integrity (FR-007)?

**Decision**: Use SHA-256 checksum of the `.store` file stored in the metadata index. On restore, recompute and compare before proceeding.

**Rationale**:
- SHA-256 is fast enough for files up to 50MB (< 100ms on modern Apple silicon)
- Detects bit rot, incomplete copies, or filesystem corruption
- Stored in the metadata index alongside other backup info
- If checksum fails on restore, treat as "no backup exists" and proceed normally with a warning toast

**Alternatives considered**:
- SQLite `PRAGMA integrity_check` — slower, more thorough but may take seconds on large DBs
- CRC32 — faster but weaker collision resistance
- No verification — unacceptable per FR-007
- Both checksum + integrity_check — overkill for the use case; checksum is sufficient

### R4: Metadata Storage Format

**Question**: How to track which backups exist and their metadata (node name, date, size)?

**Decision**: Use a JSON file (`backup-index.json`) in the `NodeBackups/` directory.

**Rationale**:
- A JSON file is simple, human-readable, and doesn't require the SwiftData container to be active to read
- The backup index must be accessible before opening any backup snapshot for restore
- Using SwiftData for metadata would create an unnecessary second persistence system for simple file metadata
- `Codable` struct maps cleanly to JSON with minimal code

**Alternatives considered**:
- Separate SwiftData store for metadata — adds complexity, second ModelContainer
- UserDefaults — not appropriate for structured data with variable size
- Property list (plist) — functionally equivalent to JSON but less tooling-friendly
- Core Data (separate store) — unnecessary given simple data structure

### R5: Connection Lifecycle Hook Point

**Question**: Where exactly in the connection flow should backup be triggered?

**Decision**: Insert backup logic in `Connect.swift` (and any other call sites) immediately after `flushDebouncedSaves()` and before `clearDatabase(includeRoutes: false)`. This is the existing "switch node" code path at lines 610–616 and 696–702.

**Rationale**:
- The spec states backup must happen "immediately before the DB is cleared for the new node connection"
- The existing code path is: disconnect → flush → clear → recreate → connect new
- The backup must be synchronous (blocking) per spec: "The clear is blocked until the snapshot completes"
- `AccessoryManager.activeDeviceNum` provides the current node number for backup identification

**Alternatives considered**:
- Hook in `AccessoryManager+Connect.swift` — would work but the clear/recreate calls live in `Connect.swift` view code
- Background async backup — violates spec requirement that clear is blocked until snapshot completes
- Notification-based trigger — too loosely coupled, timing not guaranteed

### R6: Restore Trigger & Flow

**Question**: How and when does restore happen during connection?

**Decision**: Check for an existing backup in the node-switch sequence after the app has navigated away from model-bound views and after `clearDatabase` + `MeshPackets.recreateShared()`. If a backup exists, open it as a read-only `ModelContainer` and import all entities into the already-live container before the new connection begins processing packets.

**Rationale**:
- The restore must happen *after* clearing (to have a fresh slate) but *before* new data arrives
- Keeping the same app `ModelContainer` avoids SwiftData "destroyed backing data" failures during repeated switches
- Importing from a read-only backup container preserves full historical entities the radio will not resend, such as messages, trace routes, telemetry history, and waypoints
- Flow: backup current node → disconnect → route UI away from bound models → clear live DB → recreate `MeshPackets` → import target backup into live container → connect new radio

**Alternatives considered**:
- Restore by swapping SQLite files under the live store — unsafe with an active SwiftData container
- Restore by recreating the app `ModelContainer` and forcing `.id()`-based UI teardown — caused stale model crashes
- Restore during `AccessoryManager.connect()` — too late, packets may have arrived

### R7: Concurrency & Thread Safety

**Question**: How to ensure backup/restore doesn't block the UI and handles concurrent access safely?

**Decision**: Run file operations on a detached `Task` with `.userInitiated` priority, wrapped in a `@MainActor`-isolated async method that awaits completion. Use `await` at the call site to block the logical flow without blocking the UI thread.

**Rationale**:
- Swift Concurrency's structured concurrency ensures the backup completes before `clearDatabase` proceeds
- `FileManager` operations are synchronous but fast (file copy, not network I/O)
- For databases up to 50MB, copy takes < 1 second on modern devices
- The `@MainActor` isolation of `AccessoryManager` and `PersistenceController` means we need to hop off main for the file I/O
- Restore helper methods that read from backup snapshots must be `nonisolated` when called from detached tasks

**Alternatives considered**:
- `DispatchQueue.global().async` — old-style, doesn't integrate with Swift Concurrency
- `Task.detached` without awaiting — violates the "synchronous gate" requirement
- Running on main thread — would block UI for large databases

### R8: Error Handling & Retry Strategy

**Question**: How to implement the retry-once-then-skip error handling (FR-004)?

**Decision**: Wrap backup/restore in a `do/catch` with a single retry. On second failure, log the error and return a `.skipped` result that triggers a toast notification.

**Rationale**:
- Spec: "Retry once automatically. If the retry also fails, skip with a non-blocking toast warning"
- The connection must never be blocked by backup failures — user experience takes priority
- Failed backups are not catastrophic — they'll be retried on the next node switch
- Toast notifications use the existing app notification system

**Alternatives considered**:
- Exponential backoff — overkill for a file copy operation
- User-prompted retry — violates the "transparent" requirement
- No retry — spec explicitly requires one retry attempt
