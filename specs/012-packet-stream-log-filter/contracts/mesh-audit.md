# Mesh Category Audit (US2 / T012)

Goal: `Logger.mesh` = over-the-air packet events only (in + out). Relocate non-packet lines; serial stays `.radio`; config/admin/setup → `.admin`; persistence → `.data`. Preserve every `privacy:` marker (FR-024).

## Scope decision

The **runtime ingest / dispatch / persistence / outbound** path determines what the live Packet Stream shows during passive monitoring — that is the audit's focus here. Two classes are documented but intentionally **out of scope** for this pass because they do not appear in the stream during passive monitoring:

- **`.data` config-received summaries** in `UpdateSwiftData.swift` (e.g. `🖥️/📻/🗺️ … config received`) — already off `.mesh` (on `.data`), so they never pollute the Packet Stream. Moving them `.data → .admin` is a semantic cleanup unrelated to the stream.
- **Settings config-view save logs** (`DeviceConfig.swift`, `SecurityConfig.swift`, etc., ~40 `Logger.mesh` sites) fire only on user-initiated config saves, not passive monitoring. Tracked as a follow-up sweep; not required for SC-007.

## Keep on `.mesh` (verified OTA packet events)

- `AccessoryManager.swift`: all `"🕸️ MESH PACKET received for <X> App …"` dispatch lines (601, 645, 652, 654, 674, 683–735) and the packet-handling error lines (579, 628, 634, 638, 647, 657, 663, 678) — these represent received packets / packet-handling.
- `MeshPackets.swift`: 343 (NodeInfo), 692 (PAX), 728 (Routing/ACK), 979 (Text), 1205 (Waypoint), 1295 (Waypoint decode error).
- `UpdateSwiftData.swift`: 285 (NodeInfo received), 529 (Position received).
- `AccessoryManager+FromRadio.swift`: 304–390 (Store & Forward messages), 569 (Trace Route returned).
- `AccessoryManager+ToRadio.swift`: 201, 281 (message-send guards), 630 (Waypoint sent), 712 (TraceRoute sent).

## Move `.mesh → .admin` (config / admin / setup, not OTA packets)

| File | Line | What |
|------|------|------|
| MeshPackets.swift | 212 | MyInfo received |
| MeshPackets.swift | 256 | Channel received |
| MeshPackets.swift | 298 | Device Metadata received |
| MeshPackets.swift | 587 | Canned Messages received (admin) |
| MeshPackets.swift | 663 | Admin App UNHANDLED |
| UpdateSwiftData.swift | 648 | Bluetooth config received |
| UpdateSwiftData.swift | 687 | Device config received |
| AccessoryManager.swift | 759 | deviceUIConfig frame |
| AccessoryManager.swift | 763 | fileInfo frame |
| AccessoryManager+ToRadio.swift | 120 | admin message description (outbound admin) |

## Move `.mesh → .transport` (device-local frames, not OTA packets)

| File | Line | What |
|------|------|------|
| AccessoryManager.swift | 767 | queueStatus (local send-queue status) |
| AccessoryManager.swift | 769 | heartbeat response (periodic, device-local) |
| AccessoryManager.swift | 831 | Unknown FromRadio variant (frame parse) |

## Add to `.mesh` (outbound packet representation — FR-019)

- `AccessoryManager+ToRadio.swift` `sendMessage`: add a `Logger.mesh.info("💬 Sent message …")` so outbound text/emoji packets appear in the stream (today they surface only via the generic transport-frame send at `AccessoryManager.send()`).

## Serial (unchanged, verified)

- `AccessoryManager.swift` `didReceiveLog` (~514) stays on `Logger.radio` — device serial/firmware output, never `.mesh`.

## PII (FR-024)

All relocations move the call verbatim including `privacy:` markers. No coordinate/PII field is downgraded `.private → .public`. Verified in T017.
