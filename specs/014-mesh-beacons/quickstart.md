# Quickstart — Mesh Beacons (implement & validate)

## Prerequisites
- Xcode (latest), a checkout on branch `014-mesh-beacons`.
- **Before any config-editor UI work**: fetch and review the [Meshtastic Client Design Standards](https://raw.githubusercontent.com/meshtastic/design/refs/heads/master/standards/meshtastic_design_standards_latest.md) (Constitution VIII).
- Protobufs already provide `MeshBeacon` + `ModuleConfig.MeshBeaconConfig` — no `gen_protos.sh` run needed unless upstream changes.

## Build & test
```bash
# Simulator build (fast compile check)
xcodebuild -scheme Meshtastic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipMacroValidation build

# Run the feature's suites
xcodebuild -scheme Meshtastic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipMacroValidation test \
  -only-testing:MeshtasticTests/ModemPresetFrequencySlotTests \
  -only-testing:MeshtasticTests/BeaconAddVsSwitchTests \
  -only-testing:MeshtasticTests/MeshBeaconConfigEditorTests
```
New `.swift` files MUST be registered in `project.pbxproj` (the `Meshtastic/` group is not synchronized) and use Swift Testing (`@Suite`/`@Test`/`#expect`), not XCTest.

## Implementation order (suggested)
1. **`frequencySlot` helper** (C5) + `ModemPresetFrequencySlotTests` — pure, no UI; unblocks Add gating.
2. **`beaconJoinOption`** decision (C6) + tests.
3. **Add channel action** in `DiscoverySummaryView` (C3) + secondary-slot write in `AccessoryManager+ToRadio`; Switch rollback (C4/D3).
4. **Passive listen** (C7, FR-015) + session-less Beacons list.
5. **MeshBeaconConfig editor** (C1/C2, FR-009–014) in `Views/Settings/Config/Module/` + Module Configuration list entry + validation tests.

## Manual validation (2 radios)
- **Add vs Switch**: Radio A beacons a channel on **your current preset+region+frequency** → its card shows **Add channel**; confirm → channel appears in a free secondary slot, **no reboot**, you message both meshes. Radio A beacons on a **different** frequency/preset/region → only **Switch** is shown; confirm → radio reboots onto that mesh.
- **No free slot**: fill secondary slots 1–7, then Add → replace-a-secondary picker appears (primary never offered).
- **Config editor**: enable broadcast on Radio A (message, offered channel/region/preset, interval); Radio B running discovery captures the beacon with all fields intact. Try a 101-byte message and a 3599 s interval → both blocked with inline errors.
- **Passive listen**: with listening enabled and no scan running, a heard beacon appears in the Beacons list and its channel/preset show up pre-selectable in the next scan setup.

## Simulated / offline validation
Use the meshtastic-mcp replay + the DEBUG `--meshtastic-seed-beacons` seed (session with custom-channel beacons) to exercise the Beacons UI and Add/Switch gating without hardware. Frequency-slot and decision logic are covered by the pure unit suites above — no radio required.

## Definition of done
- Constitution Check re-passes (esp. VIII design standards, V protobuf fidelity, IV logging).
- All new suites green; existing discovery suites unregressed (SC-005).
- SC-003 (Switch), SC-007 (Add, no reboot), SC-006 (broadcast round-trip) demonstrated.
- Docs: add a `docs/user/whats-new.md` entry and rebuild bundled docs (`scripts/build-docs.sh --output Meshtastic/Resources/docs`).
