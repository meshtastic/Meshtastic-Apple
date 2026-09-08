# SwiftData schema history results

Generated on September 5, 2026 with Xcode 27.0 (`27A5252f`) and an iOS 18.2 simulator. `manifest.json` records the resolved commit for every tag.

## Inventory

The nine SwiftData releases contain eight distinct physical schemas. The checksum is SHA-256 over the sorted `NSStoreModelVersionHashes` entries.

| Release | Entities | Checksum | Change from prior release |
| --- | ---: | --- | --- |
| v2.7.13 | 46 | `02880e176ae9ea6b61970a90a8f03ab621887f66df7ecdd815469df703a01bb1` | Initial fixture |
| v2.7.14 | 46 | `a15a6d3e5c2e0774adda80a5e68131dee89f63d688c3731a11e89ce4028e27a6` | `DeviceLinkEntity` changed |
| v2.7.15 | 46 | `558b2ef749cc5ac4bf6fdb33dfb30fb1bc007897e3477346be851f6a0a822ac8` | `DiscoveryPresetResultEntity` changed |
| v2.7.16 | 47 | `cd7b63c2b2a52199ee3d5a623d43443671b30a73347e7e3858f695aac1ca4837` | Added `TraceRouteNodePositionEntity`; five entities changed |
| v2.7.17 | 51 | `0e4b5cd7583f3bfc4a5f42c2cb8c6f4235b4f22fad7a294ccde8dc63c2ef8da4` | Added four entities; five entities changed |
| v2.7.18 | 51 | `546f11b725b6f9caf81e743d7af542ee981abeadca7e955bee8c3c1191bae293` | Three entities changed |
| v2.7.19 | 51 | `a2cd1ebf5f283d6d58a8f257a7ffdbc37a6946efae39087f2be85bf8a705ccd9` | `EventFirmwareEntity` changed |
| v2.7.20 | 51 | `e6b2a95d7a2ffdcd3c17579191161532a2025a8cf5af8f315bf6331f385117f0` | `NodeInfoEntity` changed |
| v2.7.21 | 51 | `e6b2a95d7a2ffdcd3c17579191161532a2025a8cf5af8f315bf6331f385117f0` | Same as v2.7.20 |

The current V1 schema has checksum `e6b2a95d7a2ffdcd3c17579191161532a2025a8cf5af8f315bf6331f385117f0`, matching v2.7.20 and v2.7.21.

## Upgrade result

Every retained fixture opened through `PersistenceController`, which uses `MeshtasticSchema.current` and `MeshtasticMigrationPlan` for disk stores. The test verified that:

- users, the favorite node, position, message, optional values, and relationships survived;
- the opened store's metadata changed to the current V1 checksum when needed;
- no `-broken-*` store appeared;
- no empty replacement store appeared.

The focused suite passed on iOS 18.2 and iOS 27.0. These results do not justify reconstructing historical schemas now. V1 still needs to remain frozen, and the next persistent-model change must introduce a new versioned schema and migration stage.

The sentinel graph covers `UserEntity`, `NodeInfoEntity`, `PositionEntity`, and `MessageEntity`. It proves that these core rows and relationships survive, but it does not prove value preservation for every changed entity listed above. Add targeted sentinels before relying on this suite for those entities.

The fixtures were rebuilt from source tags with the current Xcode toolchain. If release archives or stores from affected devices become available, run the same upgrade assertions against them because they are closer to the shipped binaries.
