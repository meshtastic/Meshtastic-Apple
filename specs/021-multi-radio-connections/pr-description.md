## What changed?

The app can stay connected to up to four radios at once, over any mix of BLE, TCP and serial. All radios share one database. Traffic that several radios hear is stored once. What belongs to one radio is kept per radio: its direct messages, its view of each node, its admin sessions and its reception details.

**Single-radio users see no change.** With one radio, every path behaves as on `main`: the same connect flow, the same node writes, and the same reset, removal and Clear App Data behaviour.

### Connections
- One `RadioSession` per radio. Every radio goes through the same connect flow (Steps 1–8). Handshakes run one at a time, behind a handshake gate.
- BLE works per peripheral. Each radio reconnects on its own after a drop, and radios connected alongside are remembered and brought back at launch. BLE state restoration brings back every radio.
- Connect › **Add a Radio** keeps the radios already connected. A fifth radio is refused, with the reason shown.
- Lock-down and old-firmware prompts name the radio they're about, and don't disconnect it.

### One window per radio
- **Mac:** each connected radio has its own window, which is the whole app for that radio. The Connect window lists every radio, connected or off. **Radios › Add Radio…** (⇧⌘N) opens it.
- **iPhone and iPad:** one window that switches between radios without reconnecting. The other radios stay connected.
- **Disconnect** keeps the radio's window, showing the radio off with Connect and **Remove Radio**. Remove Radio closes the window.

### Data (SwiftData, additive changes to the V1 schema)
- `NodeObservationEntity`: each radio's view of a node (hops, SNR/RSSI, last heard, favorite, heard on current LoRa). The node shows the best path across radios.
- Reception records: a packet heard by several radios is stored once, and which radios heard it is kept. Messages get `localNodeNum`, plus `messageKey` (`sender:packetId`) for de-duplication.
- Channels the radios share (same name, key and network) show as one timeline.
- At first launch, old per-radio backups from radio switching are merged into the shared store.

### Features across radios
- Node detail **Heard By** lists the radios that heard a node, and the node list has a **Heard By** filter.
- Favorite and ignore apply on every connected radio. Admin messages go through the radio they concern.
- Direct messages are per radio, and each window sends through its own radio. Notifications say which radio a message came in on.
- **Heard on current LoRa** is per radio: each window shows its radio's answers, and **Remove Them** keeps a node another of your radios still has.
- Services:
  - each radio runs its own MQTT client proxy;
  - the phone's position goes to every radio;
  - TAK, CarPlay & Siri and the Watch each use a radio you pick, from a **Choose Radios** sheet shown when a second radio is first connected.
- Resetting, removing and clearing (decision D-18):
  - **Reset NodeDB** or a factory reset of one radio disconnects only that radio.
  - A node another of your radios still uses (on the same network, or heard by it) stays.
  - Removing the only radio is Clear App Data, as on `main`.

### Also in this branch
- `183de839` Keep every stored field when restoring a radio's backup (a fix to `main`'s restore importer, with tests).
- The string catalog is synced with the source: the feature's new strings, plus the drift since the last sync. No translation is lost.
- User and developer docs are updated (Bluetooth, Messages, Nodes, Map, Settings, MQTT, CarPlay, TAK, Watch, Lock-down, What's New; architecture, transport, SwiftData, CarPlay, deep links, LoRa region presets). The bundled HTML is rebuilt.

Design and decisions: `specs/021-multi-radio-connections/` (`spec.md`, `windows.md`, `plan.md`). The work log and device checklist are in `HANDOFF.md` and `tasks.md`.

## Why did it change?

People with several radios in one place had to switch between them. Each switch backed up one radio's database and restored another's, so the app only ever showed one radio's view of the mesh. With this change, one app shows one node list and one channel timeline across all radios, shows which radio heard what, and lets each radio be used in full in its own window.

## How is this tested?

- **Unit and integration tests (iOS Simulator):** the full suite passes, 3,712 Swift Testing tests in 625 suites plus 32 XCTests.
  - The multi-radio tests run whole connect flows against scripted radios (`ScriptedRadio`, `ScriptedTransport`): two to four radios, drops and reconnects, lock-down, old firmware, removal, resets and backup merges.
  - `SchemaHistoryUpgradeTests` opens every released store version with the new schema.
- **SwiftLint:** no errors, and no warnings beyond those already on `main`.
- **XcodeGen:** regenerating with the pinned 2.46.0 leaves `project.pbxproj` unchanged.
- **Mac Catalyst:** built and installed as a side-by-side build with its own bundle ID and data container.
- **Reviews:** 38 rounds of connection review and 15 of data review, each checked against the files. Every finding is fixed or recorded as a decision.
- **Not yet done:** testing with real radios. The device checklist in `specs/021-multi-radio-connections/HANDOFF.md` (four BLE radios for 24 hours, BLE + TCP, background and restoration, lock-down firmware, Mac windows, Siri/CarPlay) is waiting on hardware. Until then, this is best reviewed as a draft.

## Screenshots/Videos (when applicable)

A radio connected alongside, in Connect:

![Connected radio row](https://github.com/ChDel/Meshtastic-Apple/blob/feature/multi-radio/docs/assets/screenshots/additionalRadioRow_connected.png?raw=true)

A radio's channel changed: the note in that radio's thread:

![Channel change note](https://github.com/ChDel/Meshtastic-Apple/blob/feature/multi-radio/docs/assets/screenshots/channel_change_note_light.png?raw=true)

More screenshots (the Via picker, Heard By, the connect dialog, the attention prompt) and a Mac windows video will follow from the device test.

## Checklist

- [x] My code adheres to the project's coding and style guidelines.
- [x] I have conducted a self-review of my code.
- [x] I have commented my code, particularly in complex areas.
- [x] I have verified whether these changes require updates to the in-app documentation under `docs/user/` or `docs/developer/`, and updated accordingly (see [copilot-instructions.md](../.github/copilot-instructions.md#in-app-documentation) for the view → doc page mapping). If no doc update is needed, add the **`skip-docs-check`** label.
- [ ] I have tested the change to ensure that it works as intended.
  - Simulator and unit tests: yes. Real radios: pending (see How is this tested?).
