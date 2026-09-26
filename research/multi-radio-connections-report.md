# Multi-Radio Simultaneous Connections — Feasibility Report & Plan

**Status:** Research / proposal
**Scope:** iOS, iPadOS, Mac Catalyst app target (`Meshtastic/`). tvOS (`Meshtastic TV/`) is noted separately.
**Question:** What would it take for the app to hold live connections to more than one Meshtastic radio at the same time?

---

> **Revision (follow-up discussion):** for radios **at the same location on the same mesh**,
> a **single shared database** (a refined Option B) is the better fit, and it avoids the
> container-switching risk (R1) entirely. See **§13 — Revised design: unified database**,
> which supersedes the Option C recommendation below for that use case.

## 1. Executive summary

The transport layer is **mostly** ready: every `Connection` is already its own actor (`BLEConnection`, `TCPConnection`, `SerialConnection`) with its own event stream, and CoreBluetooth, Network.framework and the serial stack can all hold several links at once. Everything above the transport assumes one radio, and that assumption is built into three places:

1. **`AccessoryManager` is a single-session state machine.** It is one `@MainActor` singleton that owns exactly one `activeConnection`, one `activeDeviceNum`, one connect stepper, one heartbeat pair, one config-refresh owner, one DB gate, one MQTT proxy, one lockdown coordinator, and one set of `@Published` connection flags. 94 view files take it as an `@EnvironmentObject` and 57 files reach it through `AccessoryManager.shared`.
2. **The SwiftData store is deliberately per-radio, with no owner column.** The code says so directly: *"Nodes carry no owner column — the store is global"* (`AccessoryManager+FromRadio.swift:191`, `Connect.swift:1102`). Switching radios is a **backup → clear → restore → reconnect** cycle (`switchToDevice`, `Connect.swift:1166`), guarded by `defensiveResetIfForeignDatabase` so that one radio's nodes can't leak into another's store. Two radios writing to one store at once would cause exactly the "node bleed" that code was written to stop.
3. **"My node" is a process-wide global.** `UserDefaults.preferredPeripheralNum` (51 refs / 19 files), `activeDeviceNum` (173 refs / 51 files), `activeConnection` (147 refs / 51 files) and `UserDefaults.firmwareVersion` are read directly by views, ingest code, the discovery engine, CarPlay, TAK and App Intents.

**Recommendation:** use **one SwiftData store per radio**, managed by a new **`RadioSessionManager`** that holds N `RadioSession` objects. Each session owns its connection, state machine, `MeshPackets` ingest actor and `ModelContainer`. The UI binds to one **focused radio** at a time. `AccessoryManager` stays as a thin facade that forwards to the focused session, so most of the ~100 view files keep compiling during the migration.

This fits the codebase's existing rule that each radio has its own data (backups are already per-radio SQLite files). It needs no schema migration of `NodeInfoEntity`/`MessageEntity`. It also removes the most fragile code in the app: the clear/restore switch flow and the container-swap SIGTRAP workarounds.

A cheaper **"primary + monitor"** option (§6, Option A) could ship in about 4–6 weeks as a stepping stone.

**Rough effort for the recommended path:** 4–6 months for one senior engineer familiar with the codebase, delivered over 6 phases that can each ship on their own (§8).

---

## 2. Current architecture (as-is)

### 2.1 Connection stack

```
Views (94 files @EnvironmentObject AccessoryManager)
        │
AccessoryManager (@MainActor singleton, AccessoryManager.swift:141)
  ├─ activeConnection: (device: Device, connection: any Connection)?   ← ONE
  ├─ activeDeviceNum: Int64?                                            ← ONE
  ├─ state / isConnected / isConnecting / allowDisconnect (@Published)  ← ONE
  ├─ connectionStepper / connectionEventTask / heartbeat timers         ← ONE
  ├─ activeAutomaticConfigRefresh / wantDatabaseGate / firstDB cont.    ← ONE
  ├─ lockdownCoordinator, firmwareEdition, loRaRegionPresets            ← ONE
  ├─ mqttManager = MqttClientProxyManager.shared                        ← ONE broker client
  ├─ locationTask (phone GPS → radio)                                   ← ONE
  └─ transports: [BLETransport, TCPTransport, (SerialTransport)]
        │
Transport (protocol, Protocols/Transport.swift)
  ├─ BLETransport (actor)    — single activeConnection + single connectContinuation
  ├─ TCPTransport (actor)    — stateless per connect (OK)
  └─ SerialTransport (actor) — stateless per connect (OK)
        │
Connection (protocol: Actor, Protocols/Connection.swift)  ← already per-instance ✅
  ├─ BLEConnection(peripheral:)
  ├─ TCPConnection(host:port:)
  └─ SerialConnection(port:)
```

### 2.2 Hard single-connection gates (must change)

| Location | Gate |
|---|---|
| `AccessoryManager+Connect.swift:29` | `if activeConnection != nil { throw "Already connected to a device" }` |
| `BLETransport.swift:374,387` | `guard activeConnection == nil, connectContinuation == nil` → "BLE transport is busy" |
| `BLETransport.swift:30-32` | one `activeConnection`, one `connectContinuation`, one `connectingPeripheral`, one `restoredConnectContinuation` |
| `BLETransport.swift:520` | state restoration only takes `peripherals.first` |
| `BLETransport.swift:531,586,608` | restoration uses `UserDefaults.preferredPeripheralNum` and calls `AccessoryManager.shared.connect` |
| `BLETransport.swift:330-348` | scanning is paused for the whole handshake |
| `TCPTransport.swift:186` | `manuallyConnect` → `AccessoryManager.shared.connect` |
| `AccessoryManager+Connect.swift:299` (Step 8) | `stopDiscovery()` after connect, so no other radios appear |
| `Connect.swift:416` | "Available Radios" section hidden while connected |
| `AccessoryManager+Connect.swift:208` | Step 5 writes `UserDefaults.preferredPeripheralId` (single preferred radio) |
| `AccessoryManager+Discovery.swift:67-73` | auto-connect only to the one preferred peripheral |
| `AccessoryManager.swift:430` | `otaInProgress` blocks **all** connects |
| `AccessoryManager.swift:238` / `ContentView` | `firmwareUpdateRequired` puts a gate over the **whole app** |

### 2.3 Inbound packet routing assumes one radio

`didReceive(_:)` → `processFromRadio(_:)` (`AccessoryManager.swift:791-1262`) has no parameter for which radio sent the packet. Every handler reads `activeConnection?.device.num` / `activeDeviceNum` to decide:

- which node is "self" (`nodeinfoApp` drops self-packets, line 1007)
- which `MyInfoEntity` owns channels (`handleChannel`, FromRadio.swift:417)
- which node owns config (`handleConfig`, `handleModuleConfig`)
- which node's `lastHeard`/`snr`/`hopsAway` to update relative to (`updateAnyPacketFrom(packet:activeDeviceNum:)`)
- who a text message was addressed to (`textMessageAppPacket(connectedNode:)`)
- routing ACK correlation (`routingPacket(connectedNodeNum:)`)
- admin session passkeys (`adminAppPacket(connectedNodeNum:)`)

Once the handlers take a session explicitly, this refactor is mechanical, but it touches every handler.

### 2.4 Outbound (ToRadio) assumes one radio

`AccessoryManager+ToRadio.swift` (3,089 lines, 96 functions) calls `send(_:)` (`AccessoryManager.swift:778`), which always writes to `activeConnection`. Most functions read `activeConnection?.device.num` as `from`. Examples: `sendMessage` (line 378), `sendWaypoint`, `sendTraceRouteRequest` (1181), every `save*Config` / `request*Config`, `sendPosition` (Position.swift:35). Each of these needs a target session, either explicit or the focused one.

### 2.5 Persistence is per-radio by design

- `PersistenceController.shared` owns **one** `ModelContainer` (`Persistence.swift:32`), injected with `.modelContainer(persistenceController.container)` at the scene root (`MeshtasticApp.swift:356`).
- `MeshPackets` is a `@ModelActor` with a static `_shared` instance that gets recycled every 5,000 packets (`AccessoryManager.swift:809-813`) and on connect (Step 7).
- **No owner scoping in the schema** (46 models in `MeshtasticSchemaV1`; V1 is frozen):
  - `NodeInfoEntity.num` is `@Attribute(.unique)`. A remote node seen by two radios would be **one row**, but these fields describe it *from one radio's point of view*: `hopsAway`, `snr`, `rssi`, `lastHeard`, `viaMqtt`, `channel`, `favorite`, `ignored`, `isKeyManuallyVerified`, `sessionPasskey`, `sessionExpiration`, `hasBeenAdministered`. The node-DB dump overwrites them (`MeshPackets.swift:1050-1072`).
  - `MessageEntity` channel messages are keyed only by `channel` **index** (`ChannelMessageList.swift:50`: `$0.channel == channelIndex && $0.toUser == nil`). Channel 0 on radio A and channel 0 on radio B are usually different channels.
  - `ChannelEntity` hangs off `MyInfoEntity`, which is correctly per-radio. The messages that reference channels are not.
- The store switch path (`backupCurrentAndRestoreDatabase`, `Connect.swift:1053-1150`) has comments documenting several SIGTRAP classes caused by replacing containers under live SwiftUI `@Query` observers ("immortal stale observer bridge", Datadog 324bff02). Any design that **swaps** the container the UI is bound to has to deal with this.

#### 2.5.1 What happens today on A → B → A

1. **Switching A → B** happens when you tap any radio other than the preferred one (`DeviceConnectRow`, `Connect.swift:959`). The app then:
   - flushes pending writes and **copies the whole store file** to a backup keyed by A's `device_id` (`NodeBackupManager.createBackup`),
   - disconnects A,
   - **clears** the live store (everything except routes/locations and the event-firmware cache: `UpdateSwiftData.swift:167`),
   - imports B's backup if one exists,
   - connects to B, which then dumps its config and node DB on top.
2. **Switching back B → A** does the same thing in reverse: back up B, clear, **import A's backup**, then connect to A. A's node-DB dump then refreshes the live values (hops, SNR, last heard).

What is **restored** from A's backup (`NodeBackupManager.restoreFromBackup`): nodes, users, MyInfo, channels, device metadata, positions, telemetry, **messages**, waypoints, trace routes (with hops and position snapshots) and pax counters.

What is **not** restored:
- **Radio config entities.** The radio sends these again on connect, so nothing is lost.
- **Discovery scan history** (`DiscoverySession*`, `DiscoveredBeacon/Node*`). It is cleared and not imported, so it is lost on every switch.
- **Some `NodeInfoEntity` fields that `importNodes` doesn't copy:** ~~`powerChannelLabels` (user-edited, lost on switch), `nodeStatus`, `isKeyManuallyVerified`, `hasXeddsaSigned`~~. **Fixed** in `NodeBackupManager+Import.swift`, together with other stored fields the importer was dropping: waypoint geofence settings and `isLocal`, PM1.0/2.5/10 air-quality telemetry, and `MessageEntity.xeddsaSigned`. Covered by `MeshtasticTests/NodeBackupRestoreFieldTests.swift`. Only relationships are not copied field by field now; they are rebuilt by the per-entity importers, or the radio sends its config again on connect. Config fetched from *remote* nodes through remote admin is still not restored; it has to be requested again.
- **Mesh traffic while the phone was on B.** The app never saw it. Radio A's node DB catches up on node state, but messages A received while you were away are not in the app, apart from whatever the firmware's small to-phone queue still holds when you reconnect.

Skip conditions:
- The backup is skipped if free space is under 50 MB, or if the copy fails twice. In that case A's data since the previous backup is lost at the clear.
- The restore is skipped (and the radio fills an empty store) if the backup's checksum doesn't match, in which case the backup is deleted.
- The app keeps at most 100 backups, pruning the oldest first.

### 2.6 Cross-cutting singletons tied to "the" radio

| Service | Coupling |
|---|---|
| `MqttClientProxyManager.shared` | one CocoaMQTT client; `initializeMqtt()` reads the active node's MQTT config; `mqttForwardGate` is static |
| `TAKServerManager` / `TAKMeshtasticBridge` / `GenericCoTHandler` | `AccessoryManager.shared.activeDeviceNum`, `activeConnection` (TAKMeshtasticBridge.swift:570, TAKServerManager.swift:739) |
| `LocationsHandler` + `initializeLocationProvider()` | sends phone GPS to the one radio |
| `DiscoveryScanEngine` | 13× `UserDefaults.preferredPeripheralNum` |
| `CarPlaySceneDelegate` | `AccessoryManager.shared.isConnected` / `activeDeviceNum` |
| `WatchSessionManager.shared` | sends "the" node list |
| `MeshShareSnapshotBuilder.refresh(nodeNum:)` | a single Messages-extension snapshot |
| `LockdownCoordinator` | one instance on `AccessoryManager`, state is per-connection |
| `MeshTrafficMonitor.shared` | one inbound-rate gauge (map flyover) |
| `Logger.datadog.setRadioContext` | global radio attributes on telemetry |
| `AppState.unreadChannelMessages/DirectMessages` | one set of badges |
| `UserDefaults.firmwareVersion` | fallback for `checkIsVersionSupported` (27 call sites) |
| App Intents / SiriKit (`MeshtasticAppDelegate`) | send via the shared manager |

### 2.7 What is already in good shape

- `Connection` is a per-instance actor with its own `AsyncStream<ConnectionEvent>`, so several can run side by side.
- `Device` has a stable `id: UUID` for every transport (BLE peripheral UUID, SHA-256 of `host:port` for TCP, and so on). It works as a session key.
- `TCPTransport` and `SerialTransport` build a new connection on each `connect(to:)` and keep no per-connection state.
- Backups are already **per-radio SQLite store copies**, keyed by `MyNodeInfo.device_id` (`NodeBackupManager`), which can be promoted into live per-radio stores.
- The tvOS target's `MeshClient` (`Meshtastic TV/Client/MeshClient.swift`) is a small, self-contained, in-memory TCP client with its own handshake. It shows that a lightweight client that can have several instances is workable.

---

## 3. Physical / protocol constraints

| Constraint | Impact |
|---|---|
| **iOS CoreBluetooth** supports several connected peripherals from one `CBCentralManager`. The practical ceiling depends on the device (roughly 5–10), and throughput is shared. | Fine for 2–4 radios. Expect higher latency during simultaneous node-DB dumps, so stagger handshakes. |
| **Radio firmware** normally serves one phone API client per radio per transport. | Not a phone-side blocker. Each radio still has exactly one phone. |
| **BLE background mode / state restoration** returns *all* restored peripherals in `CBCentralManagerRestoredStatePeripheralsKey`. | Restoration has to iterate that array (today it takes `.first`). |
| **Two radios on the same mesh** hear each other and the same packets. | The same packet id arrives twice. Per-radio stores keep both copies, which is correct for "as seen by radio X". A unified inbox would need to deduplicate. |
| **MQTT client proxy** keeps one broker session per radio. | You need N CocoaMQTT clients. Two radios uplinking the same packet to the same broker already happens with two phones, so that part is acceptable. |
| **Phone GPS sharing** | Each radio gets the phone's position. That's fine because each is its own node. |
| **Memory**: each `ModelContainer` plus ingest actor adds working set; `ingestRecycleInterval` bounds it today. | Budget for N containers and cap concurrent sessions (for example, 4). |

---

## 4. Design options

### Option A — "Primary + monitors" (lightweight)

Keep today's full-featured connection as the **primary** radio (owns the store, all settings and messaging). Add up to N **monitor** connections built on a portable `MeshClient`-style actor (like tvOS). Monitors keep in-memory node lists, live packets, telemetry and text messages, and can send text or DMs. They have no persistence, config editing or MQTT/TAK.

- **Pros:** small blast radius, no persistence changes, reuses the tvOS client design, about 4–6 weeks.
- **Cons:** second-class radios, history lost on relaunch, and two code paths for packet decoding.

### Option B — Single shared store with owner scoping (schema V2)

Add a `RadioEntity` and an `observerNum`/`radio` relationship on everything observer-relative. Split `NodeInfoEntity` into an identity row plus a `NodeObservationEntity` per radio (hops, SNR, favorite, ignored, session passkey…). Add `radio` to `MessageEntity`, `TraceRouteEntity`, `PositionEntity`, `TelemetryEntity`, the config entities, and so on. Update all 55 `@Query` and 260 `FetchDescriptor` sites to filter by radio.

- **Pros:** a unified cross-radio view ("everything I can hear") comes naturally, with one container and no container juggling.
- **Cons:**
  - The largest change: schema V2 plus a custom migration of every existing store and backup.
  - Every query needs a radio predicate, and any site that forgets one brings back cross-radio bleed.
  - Relationship predicates on SwiftData are slow and fragile.
  - The backup system has to be rewritten.
  - Highest risk. Estimated at 7–10 months.
- **Revised:** §13 shrinks this considerably. Keeping denormalized aggregates on `NodeInfoEntity` means most queries need **no** radio predicate, and only DMs, observations and admin sessions need scoping. That brings the estimate down to about 22–27 weeks.

### Option C — One store per radio + session manager (**recommended**)

Each `RadioSession` owns its own `ModelContainer` (file named by the radio's `device_id`) and its own `MeshPackets` actor. The UI's `.modelContainer` points at the **focused** session's container. Background sessions keep ingesting into their own stores. Cross-radio surfaces (connection list, badges, notifications) come from lightweight per-session summaries, not from `@Query`.

- **Pros:**
  - Keeps the existing "store = one radio" invariant, so all ingest code stays correct once it gets its own context.
  - No change to `NodeInfoEntity`/`MessageEntity` semantics and no V1 schema change.
  - Removes the backup/clear/restore switch flow, `defensiveResetIfForeignDatabase`, and `isSwitchingDevices`. Switching focus becomes a container rebind, not a data rewrite.
  - Backups become plain copies of a store that isn't in use.
- **Cons / risks:**
  - Changing the focused container is still a container change under SwiftUI. The containers are **never torn down**, which avoids the "destroyed store" class of crash, but it needs a spike (§9, R1).
  - A unified "all radios" node list or inbox needs fetches across containers (manual merge), not `@Query`.
  - Disk use grows with N stores (same as backups today).

**Why C:** it keeps the rule that has made the app stable ("one radio's data never meets another's"), moves the multi-radio complexity into a new session layer, and lets most views stay unchanged behind a facade.

---

## 5. Target architecture (Option C)

```
Views ──@EnvironmentObject──▶ AccessoryManager (FACADE, keeps today's API)
                                   │ forwards to
                                   ▼
                        RadioSessionManager (@MainActor, ObservableObject)
                          ├─ sessions: [Device.ID: RadioSession]
                          ├─ focusedSessionID: Device.ID?          (@Published)
                          ├─ discovery (always on, while connected too)
                          ├─ transports: [BLETransport, TCPTransport, SerialTransport]
                          └─ summaries: [Device.ID: RadioSummary]  (badges, state, name)
                                   │
                RadioSession (@MainActor, ObservableObject) — one per radio
                  ├─ device: Device, connection: any Connection
                  ├─ state, isConnected, isConnecting, allowDisconnect, lastError
                  ├─ nodeNum, firmwareVersion, firmwareEdition, regionPresets
                  ├─ connectionStepper, eventTask, heartbeat timers
                  ├─ configRefresh owner, wantDatabaseGate, firstNodeInfo continuation
                  ├─ lockdown: LockdownCoordinator
                  ├─ mqtt: MqttClientProxy (instance, not shared)
                  ├─ locationTask, trafficMonitor, packet counters
                  ├─ store: RadioStore  (ModelContainer + main ModelContext)
                  └─ ingest: MeshPackets  (@ModelActor on store.container)
```

### 5.1 Key types

- **`RadioSession`**: all per-connection state currently on `AccessoryManager` moves here. `processFromRadio`, all `handle*` functions, the connect steps and all ToRadio builders become `RadioSession` methods (or extensions such as `RadioSession+FromRadio.swift` and `RadioSession+ToRadio.swift`). Inside a session, `self.nodeNum` replaces every `activeConnection?.device.num`, `activeDeviceNum` and `UserDefaults.preferredPeripheralNum` read.
- **`RadioStore`**: wraps a `ModelContainer` for one radio. It is named by a stable radio key (see 5.3), opened through the same `MeshtasticMigrationPlan`, and never recreated while mounted.
- **`RadioStoreRegistry`** (replaces `PersistenceController.shared` as the owner of containers): `store(for key:) -> RadioStore`, lazy open, LRU close for stores that aren't focused and aren't connected. It keeps the data-protection / first-unlock logic from `PersistenceController`.
- **`RadioSessionManager`**: creates and destroys sessions, runs discovery continuously, handles auto-connect for a **set** of preferred radios, and sets `focusedSessionID`.
- **`AccessoryManager` (facade)**: keeps its property and method names (`isConnected`, `activeConnection`, `activeDeviceNum`, `send…`, `save…Config`) and forwards them to `sessionManager.focused`. Views migrate gradually. New multi-radio UI reads `RadioSessionManager` directly.

### 5.2 Transports

- `BLETransport`:
  - Replace the single `activeConnection`/`connectContinuation`/`connectingPeripheral` with dictionaries keyed by peripheral UUID.
  - Route `didConnect`/`didFail`/`didDisconnect` by `peripheral.identifier`.
  - Stop pausing the scan for the whole handshake; at most, pause per peripheral during pairing.
  - Restoration iterates every restored peripheral and hands each one to a **delegate** (`TransportDelegate.transport(_:didRestore:connection:)`) instead of calling `AccessoryManager.shared.connect`.
- `TCPTransport.manuallyConnect`: go through the delegate rather than `AccessoryManager.shared`.
- `Transport` protocol: add `var delegate: TransportDelegate? { get set }` (or pass a restore handler at init).

### 5.3 Store identity and migration

- Key: `MyNodeInfo.device_id` (hex) when present, otherwise the node num. This is the same key rule `NodeBackupManager` already uses (`adoptLegacyBackups`, `resolveNodeNum`). The key isn't known until `MyInfo` arrives, so a session starts with a **provisional in-memory store** or a peripheral-keyed store, then binds or renames once `MyInfo` lands. Step 1–2 writes nothing that needs keeping.
- First launch of the new version:
  1. The current `Meshtastic.store` (owned by whoever is in its `MyInfoEntity`) is renamed to `radio-<key>.store`.
  2. Each existing per-radio backup is promoted to a `radio-<key>.store`.
  3. The backup index gets marked as migrated.
- Shared, non-radio data now in the store (`DeviceHardwareEntity`, `DeviceHardwareImageEntity`, `DeviceLinkEntity`, `FirmwareReleaseEntity`, `EventFirmwareEntity`, discovery sessions, offline maps metadata) should move to a separate **shared catalog store**. Otherwise each radio store keeps its own copy, which is acceptable for v1 because the data is regenerated from the bundle or API.

### 5.4 Focus model (UI)

- Nodes, Messages, Map and Settings show the **focused radio**. This matches today's UX exactly, so no view logic changes.
- A **radio switcher** (toolbar / `ConnectedDevice` indicator menu) changes focus without disconnecting anything.
- Connect tab: a **Connected Radios** section listing every session (state, RSSI, battery, unread badge, disconnect, "make focused") plus Available Radios, which stays visible while connected.
- Notifications: include the radio short name in the title, and add `radio=<id>` to deep links so that tapping one focuses the right radio first (update `Router.route(url:)` and `docs/developer/deep-links.md`).
- The firmware-update gate and OTA lock apply **per session**. A radio that needs an update only blocks that radio's surfaces.
- Focus change: pop to root on all tabs (as the switch flow does today), set `focusedSessionID`, then bump the environment's `.modelContainer`. Every container stays alive, so nothing is destroyed underneath the old bridges.

### 5.5 Cross-cutting services (per-session vs. focused)

| Service | Proposed ownership |
|---|---|
| MQTT client proxy | **Per session**. `MqttClientProxyManager` becomes an instantiable class; the forward gate moves per session. |
| Phone position sharing | **Per session**, each using its own radio's position config interval. |
| TAK bridge | **Focused session** by default, with a setting for which radio TAK uses. CoT fan-out to several radios is out of scope for v1. |
| CarPlay / Siri / App Intents | **Focused session**, or the radio in the intent parameter (new optional `radio` `AppEntity`). |
| Watch | Focused session's node list. |
| Messages extension snapshot | Focused session; later, one snapshot per radio. |
| Discovery scan engine | Focused session (it drives preset changes on a radio). |
| Mesh traffic monitor | Per session; the map reads the focused one. |
| Datadog radio context | Per event: attach the session's attributes to each action instead of global attributes. |
| Unread badges | Sum of per-session summaries for the app icon badge; per-radio in the switcher. |
| `UserDefaults.preferredPeripheralId/Num` | Replaced by `preferredRadios: [RadioPreference]` (id, transport, auto-connect flag, last node num). Keep the legacy keys read-only for migration. |
| `UserDefaults.firmwareVersion` | Removed. Version gates read `session.firmwareVersion`, falling back to that radio's stored `DeviceMetadataEntity`. |

---

## 6. Alternative fast path (Option A) — if you want something in weeks

1. Move the tvOS `MeshClient` into `Shared/` and extend it to BLE (it already uses `TCPConnection`; add a `BLEConnection` init path).
2. Add `MonitorSessionManager` with `[MeshClient]` and in-memory `MonitorNode` / `MonitorMessage` models.
3. Add a "Monitor another radio" button in the Connect tab, a Monitors section, and a simple per-monitor detail screen (nodes, messages, send text).
4. `BLETransport` still needs the multi-peripheral changes from §5.2. That work is shared with Option C, so none of it is wasted.

About 4–6 weeks. It doesn't handle history, settings or MQTT/TAK on monitors.

---

## 7. Detailed change inventory (Option C)

Measured with `grep` at commit `6f3ee55b`:

| Symbol / pattern | Files | Refs | Action |
|---|---|---|---|
| `activeConnection` | 51 | 147 | Inside session code → `self`. In views → facade (unchanged) or `focused`. |
| `activeDeviceNum` | 51 | 173 | Same |
| `UserDefaults.preferredPeripheralNum` | 19 | 51 | Replace with `session.nodeNum` / `focused.nodeNum`. `@AppStorage` in `ChannelMessageList`/`UserMessageList` becomes an injected value. |
| `UserDefaults.preferredPeripheralId` | 5 | 16 | `preferredRadios` |
| `AccessoryManager.shared` | 57 | 148 | Keep the facade, but ingest/transport code must stop using it. |
| `@EnvironmentObject … AccessoryManager` | 94 | 111 | No change in phase 1 (facade). |
| `accessoryManager.isConnected` | 48 | 88 | Facade = focused session. |
| `MeshPackets.shared` | 23 | 107 | `session.ingest`. Views that call it use `focused.ingest`. |
| `PersistenceController.shared.context/container` | many | — | `focused.store` (UI) / `session.store` (ingest) |
| `checkIsVersionSupported` / `connectedVersion` | 17 / 7 | 27 / 17 | Per session |
| `@Query` sites | — | 55 | No change (bound to the focused container) ✅ |
| `FetchDescriptor<…>` sites | — | 260 | No predicate changes. They must use the right context (session vs. focused). |
| `MeshtasticTests` touching AccessoryManager | 15 | — | Update with a test `RadioSession` factory. |

Largest files that need structural edits:

- `AccessoryManager.swift` (1,531 lines): split into `RadioSessionManager.swift`, `RadioSession.swift`, `RadioSession+Process.swift`, and the facade.
- `AccessoryManager+ToRadio.swift` (3,089 lines): move to `RadioSession+ToRadio.swift`, with facade forwarders generated for the focused session.
- `AccessoryManager+FromRadio.swift` (872 lines), `+Connect.swift` (543), `+MQTT.swift`, `+Position.swift`, `+TAK.swift`, `+Lockdown.swift`.
- `BLETransport.swift` (720 lines): multi-peripheral bookkeeping and restoration.
- `Persistence.swift`, `NodeBackupManager*.swift`: `RadioStoreRegistry`, backups become store copies.
- `Views/Connect/Connect.swift` (1,296 lines): Connected Radios section. Remove the `switchToDevice` / backup-restore flow (about 250 lines).
- `MeshtasticApp.swift`: inject the focused container, and handle the focus-change remount.
- `CarPlaySceneDelegate.swift`, `TAK*`, `DiscoveryScanEngine.swift`, `WatchSessionManager.swift`, `MeshShareSnapshotBuilder.swift`, App Intents.

---

## 8. Phased delivery plan

Each phase ships on its own and leaves the app working with a single radio.

### Phase 0 — Groundwork refactors, still single-radio (3–4 weeks)

1. **Introduce `RadioSession`.** Move all per-connection state off `AccessoryManager` into one `RadioSession`, with `AccessoryManager` holding `var session: RadioSession?`. Keep the old API names as computed forwarders. There should be no behavior change.
2. **Pass the session explicitly** through `didReceive` → `processFromRadio` → `handle*`, and remove `activeConnection?.device.num` reads inside handlers.
3. **Remove `AccessoryManager.shared` from transports**: add a `TransportDelegate` for BLE restoration and TCP manual connect.
4. **Replace `UserDefaults.preferredPeripheralNum` reads** in ingest code (`UpdateSwiftData.swift:385,510`, `AccessoryManager.swift:1472`, `DiscoveryScanEngine`) with `session.nodeNum`.
5. **Make `MeshPackets` instantiable per container.** Keep `.shared` as a forwarder to the current session's instance, and move `recreateShared` to be per instance.
6. **Make `MqttClientProxyManager` instantiable**, with a per-instance forward gate.
7. Version gates read `session.firmwareVersion` and stop falling back to `UserDefaults.firmwareVersion`.

*Exit criteria:* all existing tests pass, and there's no user-visible change. This phase is worth landing even if multi-radio never ships, because it removes several of the global-state hazards the codebase comments describe.

### Phase 1 — Per-radio stores (3–4 weeks)

1. Add `RadioStoreRegistry` and `RadioStore`, and move the data-protection / first-unlock handling into them.
2. Write a one-time migration that renames the live store and promotes backups to `radio-<key>.store`.
3. The session binds its store when `MyInfo` arrives, using a provisional in-memory store before that.
4. Replace `switchToDevice`'s backup → clear → restore with: disconnect the old session, focus the new radio's store, connect. Delete `defensiveResetIfForeignDatabase`, `isSwitchingDevices`, and the reset gate choreography once they're proven redundant.
5. `NodeBackupManager` becomes "copy a store that isn't in use" (export/import stays).
6. Optionally split the shared catalog store (hardware, firmware, links).

*Exit criteria:* switching radios (still one at a time) is fast and never clears data. Soak-test with `SwitchStress.swift`.

### Phase 2 — Multiple concurrent sessions (2–3 weeks)

1. Add `RadioSessionManager` with `sessions: [Device.ID: RadioSession]` and `focusedSessionID`.
2. Multi-peripheral `BLETransport`, including multi-peripheral state restoration.
3. Keep discovery running while connected, and support auto-connect to a set of preferred radios.
4. Stagger handshakes: a global semaphore so only one Step 3–5a (config + DB dump) runs at a time across sessions, to protect BLE throughput and main-actor time.
5. Cap concurrent sessions (feature flag plus a setting, default 2, max 4).
6. Give the heartbeat, OTA lock and firmware gate per-session scope.

*Exit criteria:* two radios (BLE + TCP, and BLE + BLE) stay connected and ingest into separate stores for 24 hours without crashes or bleed.

### Phase 3 — UI & UX (3–4 weeks)

1. Radio switcher in the `ConnectedDevice` toolbar indicator and on iPad/Mac sidebars.
2. Connect tab: Connected Radios section plus persistent Available Radios.
3. Per-radio unread badges, and an app-icon badge that sums them.
4. Notifications labeled by radio, with `radio=` on deep links. Update `Router` and `NavigationState`, and document it in `docs/developer/deep-links.md`.
5. Per-radio firmware-update and lockdown banners.
6. Settings: make it clear which radio is being configured and which one relays remote admin.
7. Snapshot tests for the new views (`<ViewName>SnapshotTests`, with `forDocs: true` where docs reference them).
8. Docs: `docs/user/bluetooth.md` currently says *"only one is active at a time"* (line 36) and needs rewriting. Also update `connect`/`getting-started`, `docs/developer/architecture.md`, `transport.md` and `swiftdata.md`. Regenerate the bundled HTML.

### Phase 4 — Cross-cutting services (3–4 weeks)

MQTT per session; position sharing per session; TAK target-radio setting; CarPlay, Siri and App Intents with a `radio` parameter; the Watch following the focused radio; Messages-extension snapshot; Datadog attributes per event; Discovery scan tied to the focused radio.

### Phase 5 — Hardening (3+ weeks)

- Memory: N containers plus N ingest actors under a saturating TCP replay (reuse the `ingestRecycleInterval` stress harness).
- BLE: 2–4 peripherals, background and foreground transitions, state restoration after the app is killed, pairing a second radio while the first is connected.
- Battery impact measurement.
- Crash-class regression suite: reproduce the SIGTRAP scenarios from `Connect.swift` comments against focus changes.

### Phase 6 — Optional follow-ups

- Unified "All radios" inbox and node list, built from cross-store fetches plus deduplication by `messageId` and node num.
- Send-via picker ("send this DM through radio B, which has the better path").
- A bridge mode that relays between two meshes. This needs careful design because it can create loops.

**Total:** about 17–25 engineer-weeks for Phases 0–5.

---

## 9. Risks & mitigations

| # | Risk | Likelihood / Impact | Mitigation |
|---|---|---|---|
| R1 | Pointing `.modelContainer` at a different (live) container crashes through SwiftUI's SwiftData observer bridges, a known crash family in this codebase. | Med / High | **Spike first** (1 week, before Phase 1): two long-lived containers, switch the scene between them under save load, with TipKit enabled. Fallback: give each radio its own `WindowGroup` scene subtree, keyed with `.id(radioKey)`, so bridges belong to a subtree that is never reused. On Mac/iPad this could even be one window per radio. |
| R2 | Main-actor saturation: N ingest pipelines hop to `@MainActor` for every packet (`didReceive` is main-actor). | Med / Med | Move `processFromRadio` off the main actor (it mostly awaits `MeshPackets`). Update only the `@Published` summary on main, throttled. |
| R3 | BLE throughput contention during concurrent DB dumps leads to connect timeouts (Step 5a has a 120 s limit, Step 1 a 5 s fast path). | High / Med | A global handshake semaphore (Phase 2.4), and scale timeouts with the number of active sessions. |
| R4 | Migrating stores and backups loses data. | Low / Critical | Migrate by copying, keep the originals until the new stores open successfully, verify with checksums (`NodeBackupManager` already computes SHA), and test fixtures in `research/schema-history/`. |
| R5 | Hidden global reads left behind (for example a view reading `UserDefaults.preferredPeripheralNum` through `@AppStorage`). | High / Med | Add a SwiftLint custom rule banning `preferredPeripheralNum` and `firmwareVersion` UserDefaults reads outside the migration file, and a `grep` CI check. |
| R6 | Disk growth from N stores. | Med / Low | LRU close plus a "Forget radio" option that deletes its store. Show store sizes in Backup Management. |
| R7 | Users confused about which radio a message will go through. | Med / Med | Show the focused radio in the compose bar, and use per-radio tint/badges. Follow `.standards/meshtastic_design_standards_latest.md`. |
| R8 | TAK/MQTT duplicate uplinks when two radios share a mesh. | Med / Low | TAK: one target radio. MQTT: document it, and optionally offer "proxy only through focused radio". |

---

## 10. Testing strategy

- **Unit (Swift Testing):**
  - `RadioSessionManager` lifecycle (connect/disconnect/focus with mock `Connection`s).
  - Routing: packets from session A never touch store B (assert on two in-memory containers).
  - `BLETransport` multi-peripheral continuation routing, with a fake central delegate.
  - Store-key binding at `MyInfo`, and the renumber path (`NodeRenumber`) per store.
  - Migration: legacy single store plus backups → per-radio stores.
- **Integration:**
  - Two `TCPConnection`s against simulator firmware (meshtasticd) or fixture replay.
  - A BLE + TCP mix on a device.
- **Stress:** extend `SwitchStress.swift` to focus-switch under load across two live sessions.
- **Snapshot:** Connected Radios section, radio switcher, per-radio badges (light/dark).
- Make sure all existing tests pass after each phase; 15 test files touch `AccessoryManager`.

---

## 11. Open questions for the maintainers

1. Is the **focused-radio** model enough, or is a unified cross-radio inbox or node list required for v1? That decides between C and B.
2. What is the target maximum number of simultaneous radios (2? 4?) and transport mix (BLE+BLE, BLE+TCP)?
3. For TAK, MQTT and phone GPS, should "all radios" or only the focused radio be the default?
4. Is a separate shared catalog store acceptable in Phase 1, or should hardware and firmware catalogs stay duplicated per store for v1?
5. On Mac/iPad, is **one window per radio** a desirable UX? It would also reduce R1.
6. Should the tvOS target get multi-radio support? Its `MeshClient` is already easy to run as several instances, so it is a comparatively small follow-up.

---

## 12. Recommended immediate next steps

1. **Container-switch spike (R1)**, 1 week. This decides whether C is viable as designed or needs the per-scene fallback.
2. **Land Phase 0 steps 1–3** (`RadioSession` extraction, explicit session in handlers, transport delegate). These are low-risk refactors that pay off on their own.
3. Write `specs/0xx-multi-radio-connections/spec.md` and `plan.md` from this report using the SpecKit flow, once the open questions in §11 are answered.

---

## 13. Revised design: unified database (co-located radios)

**Premise from the follow-up discussion:** the radios are at the same location on the same mesh, so they hear mostly the same traffic. Instead of isolating each radio in its own store, keep **one database**, **deduplicate** what both radios hear, and **scope** only what really belongs to one radio.

### 13.1 Short answers

| Question | Answer |
|---|---|
| Can we use the same DB? | **Yes.** For co-located radios it's the better product: one node list, one channel timeline, no store switching. It also removes risk R1 (container swaps under SwiftUI), because the process keeps one container for its whole lifetime, as it does today. |
| Is channel 0 the same for all radios, so we just deduplicate? | **Usually, but don't key on the index.** Channel 0 is only "the same" if both radios have the same primary channel (name + PSK + preset). Secondary slots are often in a different order on each radio, and a radio on a different preset or region is on a different mesh. Key channel messages by **channel identity** (§13.3), not index. Radios with the same channel then merge automatically, and radios with different channels stay separate. |
| Do DMs between nodes still need to be separated? | **Yes.** A DM is addressed to one specific radio's node number and, with PKI, encrypted to that radio's key, so only that radio can decrypt it or reply as that node. A conversation is **(local radio, remote node)**, not just the remote node. Today's queries merge them (§13.4). |
| Can we improve the DB for this? | **Yes, with a new `MeshtasticSchemaV2`** (V1 is frozen). The main changes are a per-radio *observation* table, a channel identity key, flat `fromNum`/`toNum` columns, and a compound message unique key. Details are in §13.3. |

### 13.2 What is shared, deduplicated or scoped

| Data | Treatment | Why |
|---|---|---|
| Node identity: `NodeInfoEntity` (num), `UserEntity` (names, hw, public key) | **Shared** (already unique by `num`) | Describes the node itself, the same from every radio. |
| Positions, telemetry, pax, node status, waypoints | **Shared + deduplicated** by the originating packet | The same broadcast heard by two radios is one fact. |
| Channel (broadcast) messages | **Shared + deduplicated** by `(fromNum, packetId)`, grouped by `channelKey` | The same packet heard by both radios. |
| Per-radio reception (SNR, RSSI, hops, relay, via MQTT, rx time) | **Scoped** to `(radio, packet)` | Physically different for each receiver. It's also useful to show ("heard by A −5 dB, B −12 dB"). |
| Observer-relative node fields: `hopsAway`, `snr`, `rssi`, `lastHeard`, `viaMqtt`, `channel` index, `nextHop` | **Scoped** to `(radio, node)` | The node-DB dump from each radio overwrites these today (`MeshPackets.swift:1050-1072`). |
| Firmware-owned node flags: `favorite`, `ignored`, `isKeyManuallyVerified` | **Scoped** to `(radio, node)` | Each radio stores these in its own NodeDB. |
| Admin session: `sessionPasskey`, `sessionExpiration`, `hasBeenAdministered` | **Scoped** to `(radio, node)` | The passkey is issued to the requesting radio and doesn't work from another one. |
| DMs | **Scoped** by `localNodeNum` | Addressed and encrypted to one radio. |
| ACK / delivery state of a sent message | On the message (single sender) | Only the sending radio receives the routing ACK. |
| Trace routes we started | **Scoped** by originator (`fromNum` already exists) | Started by one radio. |
| Radio config (`LoRaConfigEntity` …), `MyInfoEntity`, `ChannelEntity` rows | **Already per radio** because they hang off that radio's own `NodeInfoEntity`/`MyInfoEntity` | No change. |

### 13.3 Schema V2 changes

All of these go into a new `MeshtasticSchemaV2` plus a custom `MigrationStage` in `MeshtasticMigrationPlan`, following the repository's SwiftData schema-change rules.

**1. The local radio registry: extend `MyInfoEntity` (no new type needed)**
Every `MyInfoEntity` row already represents "a radio this app has connected to". Add:
- `lastConnected: Date?`, `autoConnect: Bool`, `transport: String`, `sortOrder: Int32`, `displayColor: Int32?`

These replace `UserDefaults.preferredPeripheralId/Num` as the list of preferred radios. The set of local node numbers is simply `MyInfoEntity.myNodeNum` across all rows. That set replaces every "is this me?" check (`ChannelMessageRow.swift:26`, `UserMessageRow.swift:29`, the self-packet drop at `AccessoryManager.swift:1007`, `isFromSelf` in `MeshPackets.swift:1912`, beacon self-filter, and so on).

**2. New `NodeObservationEntity`, one row per (radio, node)**
```swift
@Model final class NodeObservationEntity {
	#Unique<NodeObservationEntity>([\.radioNum, \.nodeNum])
	#Index<NodeObservationEntity>([\.nodeNum], [\.radioNum, \.lastHeard])
	var radioNum: Int64 = 0          // local radio (MyInfoEntity.myNodeNum)
	var nodeNum: Int64 = 0           // observed node
	var hopsAway: Int32 = 0
	var snr: Float = 0
	var rssi: Int32 = 0
	var lastHeard: Date?
	var viaMqtt: Bool = false
	var channelIndex: Int32 = 0      // index on THIS radio
	var nextHop: Int64 = 0
	var favorite: Bool = false
	var ignored: Bool = false
	var isKeyManuallyVerified: Bool = false
	var sessionPasskey: Data?
	var sessionExpiration: Date?
	var hasBeenAdministered: Bool = false
	var node: NodeInfoEntity?
}
```
**Keep the existing fields on `NodeInfoEntity` as denormalized aggregates**, recomputed whenever an observation changes:
- `lastHeard` = max
- `hopsAway` = min
- `snr`/`rssi` = from the best (lowest-hop, most recent) observation
- `viaMqtt` = all observations via MQTT
- `favorite` = any
- `ignored` = any

This matters because the Node list's predicate and sorts (`NodeList.swift:290`, `NodeFilterParameters`), the map and the 55 `@Query` sites **keep working unchanged**, and now show the combined view across radios. Only node detail needs to show the per-radio breakdown.

**3. Channel identity key**
- Add `ChannelEntity.channelKey: String`, indexed. It is derived from the **display name** (the modem-preset name when the channel name is empty, as firmware does) plus a hash of the PSK. For the default primary channel, include the preset, so LongFast and MediumFast stay separate even though both have an empty name and the default PSK.
- The per-radio `ChannelEntity` rows stay as they are (index, role, uplink/downlink, mute, position precision are per radio).

**4. `MessageEntity` changes**
- `channelKey: String?`: set for broadcasts, translating the packet's per-radio `channel` index through the receiving radio's `ChannelEntity` at ingest.
- `fromNum: Int64`, `toNum: Int64`: flat, indexed copies of the relationships. This removes the `fromUser?.num` / `toUser?.num` relationship predicates used in most message queries, which is a speed-up even with one radio.
- `localNodeNum: Int64`, indexed: for DMs, whichever party is one of our radios (the sender for outgoing, the recipient for incoming). For broadcasts, the radio that sent it or first heard it.
- **Replace the unique key.** It is currently `@Attribute(.unique) messageId` (`MessageEntity.swift:20`). Change it to a compound `#Unique([\.fromNum, \.messageId])`. Packet ids are random 32-bit values *per sender*, so with a large history, a unique constraint on the id alone will eventually drop a real message from a different sender that happens to share an id. Keep `messageId` indexed for `replyID` and tapback lookups.
- `channel` (index) stays for backward compatibility and display but is no longer used to group messages.

**5. New `PacketReceptionEntity` (optional but recommended)**
Fields: `radioNum`, `fromNum`, `packetId`, `rxTime`, `rxSnr`, `rxRssi`, `hopStart`, `hopLimit`, `relayNode`, `viaMqtt`. Unique on `(radioNum, fromNum, packetId)`.

It is filled for text messages at least, and optionally for every packet with a retention cap. It provides:
- deduplication for all packet types from a single table,
- "heard by" details in the message context menu,
- implicit rebroadcast confirmation: radio B hearing radio A's broadcast shows it went out over the air.

**6. Deduplicate positions and telemetry**
- Add `packetId: Int64`, indexed, to `PositionEntity` and `TelemetryEntity`, alongside the existing node relationship.
- On ingest, if `(node, packetId)` already exists, update only the reception data and skip the insert. Today, two radios hearing the same broadcast would insert two rows. The 9 m near-duplicate reuse in `UpdateSwiftData.swift:655` hides this for positions, but not for telemetry.
- Legacy rows get `packetId = 0` and are never treated as duplicates.

**7. Deployment target note**
`#Unique` and `#Index` need iOS 18+. The main target is currently `IPHONEOS_DEPLOYMENT_TARGET = 17.5`. Either raise it, which fits the repository's policy of supporting the last two major OS versions, or enforce the compound keys manually in the ingest actor (fetch-before-insert, which the text ingest already does at `MeshPackets.swift:1895-1903`).

### 13.4 DM separation: concrete query changes

The current DM queries merge conversations across radios:

- `UserMessageList.swift:133-138` (incoming): `fromUser.num == X && toUser != nil`. This matches X→A and X→B.
- `UserMessageList.swift:154-157` (outgoing): `toUser.num == X`. This matches A→X and B→X.

V2 queries for "conversation between local radio L and remote node X":
```swift
#Predicate<MessageEntity> {
	$0.localNodeNum == L &&
	(($0.fromNum == X && $0.toNum == L) || ($0.fromNum == L && $0.toNum == X)) &&
	$0.isEmoji == false && $0.admin == false && $0.portNum != detectionSensorPortNum
}
```
UI: the DM list is grouped **by local radio**, with sections or a filter chip per radio and a default of "All". Replying always goes out through `L`. If `L` is not connected, the composer offers to connect it or switch focus; it never silently sends from a different radio, because that would reach the recipient as a new sender with a different key. A DM between two of our own radios (A→B) is one row and appears in both A's conversation with B and B's conversation with A.

### 13.5 Ingest pipeline with a shared DB

- **Keep a single `MeshPackets` writer actor** (as today) that receives packets from **all** sessions, tagged with `radioNum`. One writer makes deduplication race-free: the second copy of a packet always sees the first. Many `MeshPackets` calls already take a `connectedNodeNum`/`activeDeviceNum` argument, and it becomes `radioNum` everywhere.
- Per packet:
  1. Upsert the reception for `(radioNum, from, id)`.
  2. If the packet is new, run the existing handler (text, position, telemetry and so on).
  3. Update `NodeObservationEntity(radioNum, from)` and recompute the node aggregates.
- **Node-DB dump from radio B:** upsert node identity (user and key; if B reports a different public key than we have, reuse the existing `keyMatch`/`newPublicKey` handling), upsert B's observation row, and never touch A's.
- **Notifications:** notify once per `(fromNum, messageId)` (the existing duplicate skip at `MeshPackets.swift:1901` already prevents a second notification). Suppress notifications for messages *from* any local radio, so radio B hearing radio A's broadcast doesn't alert.
- Throughput: two co-located radios roughly double the inbound packet count, but most of it is duplicates that hit the fast path (steps 1 and 3 only). Keep `ingestRecycleInterval` and the debounced saves.

### 13.6 What this removes from the current codebase

With one store holding every radio's data, safely scoped:

- `switchToDevice` / `backupCurrentAndRestoreDatabase` backup → clear → restore (`Connect.swift:1003-1237`) is no longer needed. Switching focus is a UI-only change.
- `defensiveResetIfForeignDatabase` (`AccessoryManager+FromRadio.swift:255`), `isSwitchingDevices`, and the reset gate and container-recreation choreography on switch all go.
- Option C's multi-container registry and risk R1 go as well.
- `NodeBackupManager` stays, but backups become snapshots of the whole database (all radios) instead of one file per radio.

### 13.7 Migration V1 → V2

1. **Live store:** it belongs to exactly one radio (its `MyInfoEntity`). The custom stage:
   - creates `NodeObservationEntity` rows for that radio from each node's current observer fields,
   - sets `MessageEntity.localNodeNum` to that radio and fills `fromNum`/`toNum` from the relationships,
   - maps each broadcast's `channel` index to a `channelKey` through that radio's `ChannelEntity` rows,
   - sets `packetId = 0` on legacy positions and telemetry,
   - moves `preferredPeripheralId/Num` into `MyInfoEntity.autoConnect` / `lastConnected`.
2. **Existing per-radio backups (V1 files):** these become **merge imports**, not restores:
   - open each one in a staging container (`NodeBackupManager.stagedBackupContainer` exists),
   - migrate it to V2 with the same backfill scoped to *its* radio,
   - merge into the live store, deduplicating nodes by `num`, messages by `(fromNum, messageId)` and waypoints by `id`, and adding that radio's observation rows.

   Offer this on first launch ("Combine data from your other radios?") or automatically the first time that radio connects. Keep the original backup files until the merge succeeds and has been verified with checksums.
3. Add V1 fixtures from `research/schema-history/` plus a two-radio merge fixture to the test suite.

### 13.8 UI impact (unified DB)

| Surface | Change |
|---|---|
| Nodes / Map | Show the combined view by default (aggregates), with a filter chip "Heard by: All / A / B". Node detail gets a per-radio table: hops, SNR, last heard, favorite and ignored per radio. |
| Channels | One list of channels grouped by `channelKey`. Each row shows badges for the radios that have that channel. The composer's "send via" defaults to the focused radio, or the only radio with that channel. |
| DMs | Grouped by local radio (§13.4). |
| Favorite / ignore actions | Apply to **all connected radios** that know the node (send the admin command to each), with a per-radio override in node detail. |
| Message bubbles | "Mine" means sent by *any* local radio, labelled with the radio's short name or colour when more than one radio is configured. |
| Settings / remote admin | Choose the radio (config is per radio). Remote admin shows which radio it goes through, and the session passkey comes from that radio's observation row. |

### 13.9 Revised effort (unified DB path)

| Phase | Weeks |
|---|---|
| 0 — `RadioSession` extraction, explicit session in handlers, transport delegate (unchanged from §8) | 3–4 |
| 1 — Schema V2, migration, backup merge import | 4–5 |
| 2 — Ingest scoping and deduplication (`radioNum` everywhere, receptions, observations, aggregates) | 3–4 |
| 3 — Multiple concurrent sessions and transports (§8 Phase 2; the per-radio store work is no longer needed) | 2–3 |
| 4 — UI: channel union, DM scoping, per-radio node detail, radio switcher | 4–5 |
| 5 — Services (MQTT, position, TAK, CarPlay, Watch, intents) | 3 |
| 6 — Hardening, including a two-radio soak test and a migration test matrix | 3 |
| **Total** | **~22–27 engineer-weeks** |

This is a little more work than Option C (17–25 weeks), but it has less technical risk (no R1) and gives the combined experience that co-located users actually want.

### 13.10 New risks specific to the shared DB

| Risk | Mitigation |
|---|---|
| Some query site forgets radio scoping where it matters (DMs, admin passkeys, per-radio flags) | Scoping is needed only for DMs, observations and admin sessions, which are a small, reviewable set. Add helpers (`MessageEntity.conversation(local:remote:)`, `NodeObservationEntity.for(radio:node:)`) and a lint check that bans raw `sessionPasskey` reads on `NodeInfoEntity`. |
| Aggregate fields drift from observations | Recompute them in one function on the ingest actor. Add a debug consistency check and a unit test. |
| Migration or merge bugs lose data | Merge by copying from backups, keep originals, verify with checksums, and use fixture-based tests. |
| Channel-key mistakes merge distinct channels | Include the PSK hash **and** the preset for empty-name channels. Add unit tests for the default channel, custom channels, the same name with a different PSK, and different presets. |
