# Review V12: connections, focus and windows (feature/multi-radio)

Branch `feature/multi-radio` at `cf26aa79`. V11 (`review-connections-v11.md`) was at `d038d296`.
This round checks the fixes since (T330–T342) and what they touch:
- window sends through their radio (`sendingRadio(for:)`, `viaRadio:` on the senders);
- the ESP32 update's release and reclaim;
- `knownNodeNums`;
- `hasRadioToJoin`;
- link routing that opens a hidden window;
- attention for the first radio;
- W-15 (a required radio for each service in use, `knownRadios`, the choice sheet);
- the renames of T341.

Files read (diff since `d038d296`, then the code around it): `+AdditionalRadios`, `+Connect`,
`AccessoryManager.swift`, `+RadioAttention`, `+ServiceRadios`, `RadioWindow.swift`,
`WindowRouters.swift`, `RadioWindowViews.swift`, `ContentView.swift`, `Connect.swift`,
`LockdownSheet.swift`, `ServiceRadioPickers.swift`, the ESP32 OTA sheets, `DiscoveryScanEngine`
and the Discovery views, `SaveChannelQRCode`, `DeviceProfileImporter`, `WaypointForm`,
`TraceRouteButton`, `RequestLocalStatsButton`, `SaveChannelSettingsIntent`, `SendWaypointIntent`.

## Tests and build

- The full suite passes in the iOS Simulator (iPhone 17 Pro): 3,490 Swift Testing tests in 601
  suites and 32 XCTests. The run waited for another session's `xcodebuild` to finish and ran alone.
- The Mac Catalyst build succeeds (own derived data, signing off). Built only, never run.

## Where the V11 findings stand

| V11 | What | Now |
|---|---|---|
| X1 | Window actions went through the first radio | Fixed for every sender and caller listed, except one path: Y1. |
| W1 | ESP32 update disconnected the first radio / aborted on the Mac | Fixed: only the window's radio is released, its window stays, and it's reclaimed after. One iPhone/iPad effect: Y2. |
| W7 | Settings lost its radio on a reboot | Fixed (`knownNodeNums`). |
| W2 | Radios alongside couldn't reconnect without the first | Fixed (`hasRadioToJoin`). |
| W3 | Adding a radio took the first radio's place | Fixed: it joins alongside. |
| W4 | Links to the wrong window or nowhere on the Mac | Fixed for links about a radio; one gap remains: Y4. |
| W5 | First radio's lock/old firmware unannounced | Fixed: attention on every radio, the prompt skips only the radio shown. |
| Minors | Version fallback, the Siri question, a doc, the map window | Fixed or recorded (the map window is noted in HANDOFF). |

## Findings, most serious first

### Y1. "Analyze Current Preset" in another radio's window still runs on the first radio

- `DiscoveryScanEngine.swift:1150-1175` (`startCurrentPresetScan(radio:)` sets `scanRadioNum` to the
  window's radio and reads its preset, then calls `startScan()` with no radio), `:221`
  (`startScan` sets `scanRadioNum = radio ?? currentRadioNum`, the first radio), `:208`
  (connected is the first radio's), `:243` (with the first radio connected it switches that radio's
  primary channel to the default public one for the scan, and restores it after).
- The fix passes the window's radio in (`DiscoveryScanView.swift:704`), but `startScan()` drops it.
  From B's window, "Analyze Current Preset" reads B's preset, then:
  - measures the first radio's packets under B's preset;
  - with the first radio connected, temporarily switches that radio's primary channel (the
    seeded pass skips the preset change, so the preset isn't touched);
  - with the first radio gone, runs offline although B is connected.
- Sure: high on the code. Passing `radio` through to `startScan(radio:)` closes it.

### Y2. Updating the first radio's firmware switches the iPhone/iPad window to another radio

- `AccessoryManager.swift:813-821` (`disconnect(forUpdate: true)` still sets
  `userRequestedConnectionCancellation`), `RadioWindow.swift:98-100` (`oneWindowRadio`: with the
  first radio's slot empty and that flag set, the one window shows another connected radio),
  `ESP32BLEOTASheet.swift:153`, `ESP32WifiOTASheet.swift:155`.
- The switch is the rule for a user who disconnects the first radio (T314), and it doesn't check
  `forUpdate`. With another radio connected, releasing the first radio for its update switches the
  window to that other radio for the length of the update:
  - Settings, the radio-name banner and the rest of the window describe the other radio while the
    update screen is still up;
  - the window returns to the first radio once it reconnects after the update.
- Whether the switch also takes down the update sheet (as W1 did on the Mac) needs the device:
  Settings re-selects its node when the window's radio changes.
- Sure: high that the window switches; unconfirmed whether the sheet survives.

### Y3. Disconnect on the first radio doesn't stick across a relaunch, unlike on any other radio

- `Connect.swift:1289-1294` (`disconnectFirstRadio` clears the radio's `autoConnect` but leaves
  `PreferredRadio` on it), `AccessoryManager+Discovery.swift:75` (discovery auto-connects
  `PreferredRadio`), `AccessoryManager+AdditionalRadios.swift` (`disconnectRadio`'s doc: "it isn't
  brought back").
- Disconnecting any other radio clears its `autoConnect`, so it stays off at the next launch.
  Disconnecting the first radio does the same, but it's still the preferred radio. At the next
  launch discovery connects it as the first radio again, and the radios the user kept connected
  come back behind it. With several radios, the radio the user turned off returns; on the Mac its
  window reopens.
- With one radio this is `main`'s behaviour and has to stay. With others still connected when it's
  disconnected, moving `PreferredRadio` to one of them (or clearing it) would make Disconnect mean
  the same for every radio.
- Sure: high on the code.

### Y4. On the Mac, a link that names no radio is lost when no radio window is open

- `WindowRouters.swift:115-116` (with no radio in the link and no window registered, the link goes
  to `fallback`), and the Mac's main window (`RadioListWindow`) doesn't show that router.
- Links about a radio now open its window (T334). A link without one, such as the firmware notice's
  `meshtastic:///settings/debugLogs` or a node link from a notification, still goes to the
  fallback router when every radio window is closed, and nothing opens.
- Sure: high on the code; low impact.

### Worth checking on the device

- `ContentView.swift:53, 70, 74, 80`: the one window now has the required service choice sheet
  (`ServiceRadioChoiceGate`) besides the passphrase sheet and the lock-down and firmware full-screen
  covers. Adding a second radio for the first time makes the choice sheet appear. If that radio is
  also locked or on old firmware and the window shows it, two presentations are wanted at once, and
  SwiftUI may drop one until the view appears again.

## Checked and found fine

- Sends from a window: `saveChannelSet` (QR code, profile import's channels, the Save Channel
  Settings intent), the beacon join and slot helpers, waypoints (form and intent), trace route and
  local stats all take the radio. `sendingRadio(for:)` gives the window's own radio even while it's
  off, so a send fails instead of going through another radio; `.firstRadio` keeps the first
  radio's path for one radio.
- ESP32 update: `releaseRadioForUpdate` releases only the window's radio: the first radio through
  `disconnect(forUpdate:)`, any other through `disconnectAdditionalRadio(forUpdate:)`. That stops
  its reconnect loop, keeps `autoConnect`, and doesn't close its window. After the update,
  `reclaimRadioAfterUpdate` brings another radio back through its loop and the preferred radio
  through discovery. The other radios aren't touched.
- `knownNodeNums`: set when a session gets a number and seeded at launch (`MeshtasticApp.swift:162`).
  `radioNodeNum(for:)` and the version check use a window's own radio while it's off.
- `hasRadioToJoin`: a connect alongside, the reconnect loop and `reconnectRememberedRadios` work
  with any radio connected. With nothing connected, a connect is the first radio's, as on `main`.
  A connect alongside still re-checks after the gate and after the transport connect.
- Links: a link about a radio finds its window, also while the radio is off; on the Mac a hidden
  window is opened and the link waits for it (`pendingLinks`). One window gets the same choice.
- Attention: set on every radio. The prompt skips the radio the one window shows (before it's
  known, the first radio), so with one radio nothing is prompted, as before. `RadioUnlockSheet` and
  the prompt queue find the first radio's session.
- W-15: with one known radio every service uses the connected radio and nothing is asked; with
  several, a chosen radio that's off is waited for and never replaced. `intentRadio` gives
  `notConnected` for a named or chosen radio that's off, and `needsChoice` only when none is chosen.
  Removal clears the choices that pointed at the removed radio.
- T341's renames are names and comments only; the suite and the Mac build pass.
