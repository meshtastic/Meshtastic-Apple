# Research: Local Mesh Discovery

## R-001: NeighborInfo Packet Processing

**Decision**: Implement NeighborInfo handling in `AccessoryManager+FromRadio.swift` to extract neighbor node numbers, SNR values, and build a topology graph per scan preset.

**Rationale**: NeighborInfo (portnum 71 / `neighborinfoApp`) is currently deserialized and logged with the message `"🕸️ MESH PACKET received for Neighbor Info App UNHANDLED"` but not persisted or processed. The `NeighborInfo` proto contains `nodeId` (the reporting node), `lastSentById`, and a repeated `neighbors` field — each neighbor has `nodeId` and `snr`. This maps directly to the spec's "Mesh Neighbor" concept (FR-007).

**Alternatives considered**:
- Process in `MeshPackets.swift` @ModelActor: Rejected — NeighborInfo needs real-time routing to the scan engine during dwell, not just persistence.
- Create a dedicated `NeighborInfoManager`: Rejected — over-engineering for a single packet type. The scan engine can consume it directly.

**Implementation path**: Add a case in the `neighborinfoApp` switch to forward the deserialized `NeighborInfo` to `DiscoveryScanEngine` if a scan is active, otherwise log as today. The engine extracts neighbor node numbers and stores them as `DiscoveredNodeEntity` records with `neighborType = .mesh`.

---

## R-002: Detecting Radio Reboot After Preset Change

**Decision**: Treat every LoRa preset change as a potential reboot. After calling `saveLoRaConfig`, enter the `Reconnecting` state and wait for BLE reconnection + the `.rebooted` FromRadio variant.

**Rationale**: The firmware reboots automatically on LoRa config changes. The existing code at `AccessoryManager.swift` handles `case .rebooted:` by re-sending `sendWantConfig()`. There is no pre-flight check to determine if a config change will reboot — it's firmware behavior.

**Alternatives considered**:
- Check if current preset == target preset to skip reboot: **Adopted** as optimization — spec edge case "User starts a scan while already on the target preset" says to skip the admin change.
- Add a firmware query for "will this reboot?": Rejected — requires firmware changes outside scope.

**Implementation path**: The scan engine transitions `Shifting → Reconnecting` after sending `saveLoRaConfig`. A 60-second timer starts. If BLE reconnects and `wantConfigComplete` fires, transition to `Dwell`. If the timer expires, transition to `Paused`.

---

## R-003: Apple Foundation Models API

**Decision**: Use `FoundationModels` framework (`SystemLanguageModel`, `@Generable`) gated behind `#available(iOS 26, *)`. Fall back to a structured metrics table on unsupported devices.

**Rationale**: No existing Foundation Models usage exists in the codebase — this is greenfield. The API is available on iOS 26+ (Apple Intelligence capable devices). The prompt will include per-preset metrics plus historical session summaries for trend analysis (per FR-013 clarification).

**Alternatives considered**:
- Third-party LLM (OpenAI, etc.): Rejected — constitution requires offline-capable, adds external dependency.
- No AI at all (just tables): Rejected — AI summary is a P3 user story and differentiated value.
- Core ML custom model: Rejected — over-engineering; Foundation Models provides general text generation sufficient for this use case.

**Implementation path**: Define a `DiscoveryRecommendation` struct conforming to `@Generable`. Build a prompt with current scan metrics + last N session summaries. Call `SystemLanguageModel.default.generate(DiscoveryRecommendation.self, prompt:)`. Wrap in `if #available(iOS 26, *)` with fallback.

---

## R-004: Navigation Integration (Settings > Developers)

**Decision**: Add `case localMeshDiscovery` to `SettingsNavigationState` and a `NavigationLink` in the `developersSection` of `Settings.swift`. Register `meshtastic:///settings/localMeshDiscovery` deep link.

**Rationale**: The Developers section currently contains "App Files" and "Tools" (iOS 18+). It uses the standard `NavigationLink(value: SettingsNavigationState.xxx) { Label {} }` pattern. The section is only shown in `#if DEBUG` builds, which aligns with this being a developer/power-user tool.

**Alternatives considered**:
- Top-level tab: Rejected by user — too prominent for a diagnostic tool.
- Map tab toolbar: Rejected by user — discovery has its own map.

**Implementation path**: Add `case localMeshDiscovery` to enum. Add `NavigationLink` with SF Symbol `antenna.radiowaves.left.and.right` in `developersSection`. Add `.navigationDestination(for:)` case in Settings to push `DiscoveryScanView`. Add deep link handling in `Router.route(url:)`.

---

## R-005: 2.4 GHz Hardware Tag Gating

**Decision**: Query `DeviceHardwareEntity.tags` for a tag with `.tag == "2.4GHz"` to conditionally show the LORA_24 preset.

**Rationale**: The `DeviceHardwareTagEntity` model exists with a `tag: String` property and many-to-many relationship to `DeviceHardwareEntity`. Tags are imported from `DeviceHardware.json` via `MeshtasticAPI.findOrCreateTag()`. However, no existing code queries for "2.4GHz" specifically — this is new logic.

**Alternatives considered**:
- Hardcode hardware model list: Rejected — fragile, requires manual updates when new 2.4 GHz hardware ships.
- Check LoRa region from config: Rejected — region doesn't imply 2.4 GHz capability.

**Implementation path**: In the preset picker view, access the connected node's `DeviceHardwareEntity` via `NodeInfoEntity.deviceHardware` and check `tags.contains { $0.tag == "2.4GHz" }`. If true, include `ModemPresets.LORA_24` in the picker list.

---

## R-006: MapKit Discovery Map Pattern

**Decision**: Use SwiftUI `Map(position:bounds:scope:)` with `Annotation` for node markers, `MapPolyline` for topology lines, and a custom `RadarSweepOverlay` view for the animation.

**Rationale**: The existing `MeshMap.swift` uses this exact pattern — `Map {}` with `Annotation()`, `MapPolyline`, `MapCircle`, and `UserAnnotation()`. The radar sweep is a cosmetic overlay — a semi-transparent `Canvas` view with a rotating gradient, not a MapKit annotation.

**Alternatives considered**:
- MKMapView via UIViewRepresentable: Rejected — constitution mandates SwiftUI.
- MapBox/Google Maps: Rejected — unnecessary external dependency.

**Implementation path**: Create `DiscoveryMapView` using `Map(position:scope:)`. Iterate `DiscoveredNodeEntity` records with `ForEach` inside the map content builder. Green `Annotation` for direct neighbors, blue for mesh. `MapPolyline` from user position to each direct neighbor. `RadarSweepView` overlay using `Canvas` + `TimelineView` for 60fps rotation.

---

## R-007: SwiftData Schema (No Versioned Migration Exists)

**Decision**: Add 3 new `@Model` classes to `MeshtasticSchema.allModels`. Since no `VersionedSchema` / `SchemaMigrationPlan` exists in the codebase, follow the current pattern of flat model registration.

**Rationale**: Despite the copilot-instructions mentioning `VersionedSchema`, the actual `MeshtasticSchema.swift` is a flat `allModels` array with 38 models and no migration plan. Adding 3 new models follows the existing pattern. SwiftData handles lightweight schema changes (adding new model types) automatically without explicit migration stages.

**Alternatives considered**:
- Introduce VersionedSchema now: Rejected — orthogonal refactor, not required for adding new models.
- Store discovery data in existing entities: Rejected — discovery sessions are a distinct bounded context.

**Implementation path**: Create 3 files in `Meshtastic/Model/`, add all 3 types to `MeshtasticSchema.allModels`.
