# Review V10: data, messages and services (feature/multi-radio)

Branch `feature/multi-radio` at `6aa5ea48`. A full review of the area after D-19 (one window per
radio), not only the diff. I read windows.md (W-01 to W-14), plan.md › One window per radio,
tasks.md › Phase 11 (T300–T325) and the HANDOFF.md changes first, and re-read every claim below in
the files. The ingest and storage code (`MeshPackets*`, `Persistence/`, the SwiftData models)
hasn't changed since `e5fd2ec1`, so V1–V9 still cover it; this round is about which radio each
send, save and service uses now that there's no focused radio.

Tests: the full suite passes in the iOS Simulator (iPhone 17 Pro) at `6aa5ea48`: 3,483 Swift
Testing tests in 601 suites and 32 XCTests, started once no other `xcodebuild` was running. The
Mac Catalyst build succeeds (own derived data, signing off; built, not run). No tracked file
changed. None of the findings below is covered by a test.

Background for all of them: `connectedSession(forRadio: nil)` is the radio connected first
(`activeConnection`, `AccessoryManager+RadioChoice.swift:96-102`), and a radio that drops leaves
`additionalRadios` until its reconnect (`AccessoryManager+AdditionalRadios.swift:232, 357-360`),
so `nodeNum(for:)` / `session(for:)` of its window are nil meanwhile (`RadioWindow.swift`).

Ranked most serious first. "Sure" is how confident I am that it happens as described.

## Findings

### R10-1. Saving channels from a link or QR writes the first radio, whatever the window shows

- `Views/Settings/SaveChannelQRCode.swift:57-61, 269, 283-300`, `AccessoryManager+ToRadio.swift:753-756`
  (`saveChannelSet` uses `activeConnection`). Callers: `Tools.swift:142`, `MessageText.swift:31`
  (a channel link in a message), `MeshtasticApp.swift:438`.
- The sheet checks that the window's radio is connected and shows that radio's channels and LoRa
  settings, but Save writes the channel set, and on Replace the LoRa settings, to the radio
  connected first. T320 records this only for the Save Channel Settings intent; the in-app sheet
  does the same.
- Scenario: iPhone with A (connected first) and B; show B; open a channel link and Replace. A's
  channels and region or preset are replaced and A reboots; B is unchanged. The same from B's
  window on the Mac.
- Sure: high.

### R10-2. The discovery scan and beacon join act on the first radio from any window

- `Services/DiscoveryScanEngine.swift:162-163, 219, 1161` (`scanRadioNum = activeDeviceNum ??
  PreferredRadio.nodeNum`), `AccessoryManager+ToRadio.swift:1056-1057` (`joinBeaconMesh`) and
  `:1194-1195` (`addBeaconChannel`), both on `activeConnection`. `DiscoveryScanView` and
  `DiscoverySummaryView` read the window's radio for its presets, enabling and joined channels.
- A scan started in B's window cycles the first radio's preset (each change reboots it). Joining a
  beacon's mesh or adding its channel from B's window writes the first radio's channels and LoRa.
- Sure: high.

### R10-3. While a window's radio has dropped, its messages go out through another radio

- `Views/Messages/ChannelMessageList.swift:388-399`, `UserMessageList.swift:433-449`.
- Channel: `sendingRadio` is nil while the window's radio reconnects, so the send passes no radio
  and goes through the radio connected first, in the window radio's slot number, which can be
  another channel there. That's a Mac window of a radio other than the first; in the one window
  on iPhone (the first radio's) the send fails instead.
- Direct messages: `selectedRadio` falls to `conversationRadios.first`, another connected radio,
  so the thread shown flips to that radio's and replies go from it, with the composer still
  enabled. This happens in a Mac window, and in the iPhone window when the radio connected first
  drops and another is connected: the window still names the first radio.
- D-13 says a DM reply goes through the conversation's radio; W-10's rule that a radio that's off
  isn't swapped for another is the same idea.
- Fix direction: keep the window's radio as the sender while it reconnects (its node number from
  `radioNodeNum(for:)` or the stored window), and let the send fail, or disable the composer.
- Sure: high for the code path.

### R10-4. Node actions and the map's waypoints go through the first radio

- Trace Route (`AccessoryManager+ToRadio.swift:1317-1318`), Request Local Stats (`:3179-3185`),
  Exchange Positions (`ExchangePositionsButton.swift:22-23`, no `viaRadio`; its channel from
  `channelSlot(toReach:)`, which reads `activeDeviceNum`, `RadioChoice.swift:113-120`), Exchange
  User Info (the window's radio as `fromUser`, sent on the first radio's connection), the map's
  waypoint form (`WaypointForm.swift:265, 692` → `sendWaypoint`, `+ToRadio.swift:1237-1238`, while
  it records `createdBy` as the window's radio).
- In B's window these go out from A, or fail with "No active device" when A isn't connected. T306
  moved the views' reads to the window's radio but not these sends.
- Sure: high.

### R10-5. Siri's voice send checks the first radio, and swaps a default that's off

- `Intents/SendMessageIntentHandler.swift:104-118` (`confirm` and `handle` require
  `AccessoryManager.shared.isConnected`, the first radio's flag), `:125` (`radioNum(for:
  .carPlay)`), `AccessoryManager+ServiceRadios.swift` (`session(for:)`).
- With the first radio gone and the Siri radio connected, voice sends fail ("open the app"). With
  the chosen Siri radio off and another connected, a send without a conversation radio goes through
  the first radio (or another). W-10: the SiriKit send "always uses the default".
- Sure: high.

### R10-6. Services with no connected choice: the first radio, else an arbitrary one; the spec differs

- `AccessoryManager+ServiceRadios.swift` `session(for:)`: the chosen radio if connected, else
  `activeConnection`, else `additionalRadios.values.first { connected }`, else
  `additionalRadios.values.first` (possibly not connected yet). With the first radio gone and
  several connected, TAK, the CarPlay lists and the Messages sharing snapshot follow whichever the
  dictionary lists first, which can change as radios come and go.
- windows.md says TAK and the Watch use the chosen radio or the only one connected, and App
  Settings asks when several are connected and none is chosen. The code and App Settings' footer
  use "the radio connected first" instead, and nothing asks. The owner should pick one; whichever
  it is, the pick with the first radio gone should be stable (the lowest node number, say).
- Sure: high for the code; the behaviour to want is the owner's call.

### R10-7. Intents: a named radio that's off asks "Which radio?"; destructive ones confirm unnamed

- `AppIntents/*Intent.swift` with `IntentRadioChoice.radioNum` (`.notConnected` → `needsValue`):
  the command re-asks for a radio instead of saying the named one is off (W-10 calls it an error).
  Nothing goes through another radio unless the user picks one.
- `FactoryResetNodeIntent` and `ShutDownNodeIntent` confirm before the radio is decided, and the
  confirmation doesn't name it. With a Siri default set, "factory reset" confirms and resets that
  radio, which may not be the one the user means.
- Sure: high.

### R10-8. Minor

- `Views/Settings/Config/Module/MeshBeaconConfig.swift:191-199`: the only `performConfigSave` call
  without `window:`, so it sends as the first radio. Saving B's own module still reaches B (admin
  routing goes by the target), but when the first radio isn't connected the save does nothing (a
  logged warning; this call passes no `onError`), and remote admin of another node from B's window
  relays through A.
- The Siri & CarPlay question (`AccessoryManager+ServiceRadios.swift` `askAboutServiceRadioIfNeeded`,
  `AccessoryManager+Connect.swift:192-195`): the radio is marked as asked when the question is set,
  and on the Mac it's shown only by the Connect window (`RadioWindowViews.swift:162`). A radio
  reconnecting at launch with the Connect window closed is marked but never asked, and the pending
  question holds back the next radio's. Also, a user with merged backups is asked about their only
  live radio at its first connect with this version, since the backup radios count as known.

## Checked and found fine

- Lock-down per radio (T301): each `RadioSession` has its own `LockdownCoordinator`, started with
  its own peripheral id; saved passphrases are keyed by peripheral id in the keychain; each window
  gets its radio's coordinator (`WindowLockdownScope`), and a passphrase that can't be sent brings
  the sheet back with the reason.
- Settings (T304): `performConfigSave` and `requestRemoteConfig` take the window's radio as the
  sender everywhere except R10-8's one call; admin messages route by the target radio;
  `configuredChannelOfferKeys` and the discovery views pass the window's radio; the profile import
  reads `lastConfigRefresh(for:)` for its radio.
- `FirmwareUpdateNotifier`: the notice and the notification are per radio, from that radio's own
  firmware version.
- Named radios in the App Intents (`RadioEntity`, `intentRadio`): a named radio that isn't connected
  is never swapped for another; with no radio named, the default if connected, else the only
  connected radio, else the command asks. `SetMeshtasticRadioIntent` sets the default and refreshes
  the sharing snapshot.
- Notification taps and links (W-05, `WindowRouters`): a DM opens the window of its radio; a
  channel link goes to a window whose radio has that channel, and `Messages` maps the slot by key.
- The Messages sharing snapshot follows the CarPlay & Siri radio on its connect, config and
  channel saves.
- Catalog: the two new manual keys are in it; the four removed keys aren't used anywhere; no
  translations were lost. The Phase 11 SwiftUI and intent strings ("Use %@ for Siri and CarPlay?",
  "Automatic", "Which radio?", …) aren't in the catalog yet, which HANDOFF expects from the next
  export (T122). The `.localized` strings missing from the catalog in the changed files are all
  missing on `main` too.
- Single radio against `main`: services, intents, SiriKit, CarPlay, the snapshot, Settings, the
  composer and notifications use the one radio exactly as before (every lookup through `.focused`
  or `activeConnection`); the Siri question isn't asked with one radio known; the Disconnect
  intent calls `disconnect()` as on `main`.
