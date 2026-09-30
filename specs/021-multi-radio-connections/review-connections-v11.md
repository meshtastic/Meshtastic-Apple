# Review V11: connections, focus and windows (feature/multi-radio)

Branch `feature/multi-radio` at `6aa5ea48`. V10 was at `8f4569be`. A full review of the area after
D-19 (one window per radio, no app-wide focus), not only the diff.

Read first: `windows.md` (W-01 to W-14), plan.md › One window per radio, tasks.md › Phase 11
(T300–T325), HANDOFF › In progress and Gotchas. Then the code:
- `RadioWindow.swift`, `AccessoryManager.swift` (diff), `+Connect`, `+AdditionalRadios`,
  `+RadioAttention`, `+RadioChoice` (`linkStatus`), `+ServiceRadios`, `+Lockdown`,
  `+Discovery`, `+LaunchFallback`, `+ToRadio` (every send that still reads the first radio),
  `RadioSession`, `PreferredRadio`, `LockdownCoordinator`, `BLETransport` (restore);
- `RadioWindowViews.swift`, the scenes in `MeshtasticApp.swift`, `AppState`,
  `MeshtasticAppDelegate`, `WindowRouters.swift`, `ContentView.swift`, `AdditionalRadioRow`,
  `RadioSwitcherMenu`, `ConnectedDevice`, `LockdownSheet.swift`, `Connect.swift`
  (`DeviceConnectRow`, `disconnectFocusedRadio`, `switchToDevice`), `Settings.swift`;
- the firmware update screens (ESP32 OTA, nRF DFU, UF2), `SaveChannelQRCode`,
  `DeviceProfileImporter`, `DiscoveryScanEngine` and the Discovery views, `WaypointForm`,
  `TraceRouteButton`, `RequestLocalStatsButton`.

## Tests and build

- The full suite passes in the iOS Simulator (iPhone 17 Pro): 3,483 Swift Testing tests in 601
  suites and 32 XCTests, with no other `xcodebuild` running.
- A Mac Catalyst build succeeds (own derived data, signing off). Built only, never run.

## Findings, most serious first

### X1. Several actions in a window still go through the first radio, whichever radio the window shows

- `AccessoryManager+ToRadio.swift`: `saveChannelSet` (`:754`), `joinBeaconMesh` (`:1057`),
  `addBeaconChannel` (`:1195`) and the beacon slot helpers (`:1160`, `:1176`), `sendWaypoint`
  (`:1238`), `sendTraceRouteRequest` (`:1318`), `sendLocalStatsRequest` (`:3185`). Each takes its
  radio from `activeConnection`.
- `DiscoveryScanEngine.swift:162-164, 219` (`currentRadioNum` is `activeDeviceNum ??
  PreferredRadio.nodeNum`).
- Callers in a window: `SaveChannelQRCode.swift:269`, `DeviceProfileImporter.swift:364`,
  `DiscoverySummaryView.swift:148, 854`, `WaypointForm.swift:265, 692`,
  `TraceRouteButton.swift:15`, `RequestLocalStatsButton.swift:87, 179`.
- T304–T306 moved these screens to the window's radio for what they show and enable, but not for
  what they send. In a window for a radio other than the first (every radio but one on the Mac, or
  the iPhone window after Show This Radio):
  - A channel QR code or link saved in the window replaces the first radio's channels and LoRa
    settings, and that radio reboots.
  - Importing a device profile applies the user, device and module settings to the window's
    radio, but the channels and LoRa settings (`.channelURL`) to the first radio. Two radios are
    left half-configured.
  - A discovery scan offers the window's radio's presets but steps the first radio through them,
    rebooting it into each one. Joining a beacon's mesh writes the first radio's channels.
  - Waypoints, trace routes and local stats requests go out from the first radio. A trace route's
    result is filed under the first radio.
  - While the first radio is gone (W2's state), all of these fail with "No active device" even
    though the window's radio is connected.
- Scenario (Mac): A's window and B's window; in B's window, Settings › Channels › add a channel
  from a QR code with Replace: A's channels and LoRa settings are replaced and A reboots; B is
  unchanged.
- Sure: high on the code (each function reads `activeConnection` for its node number, and the
  admin packets are addressed to that number).

### W1. An ESP32 firmware update disconnects the first radio, and on the Mac aborts itself

- `ESP32BLEOTASheet.swift:143`, `ESP32WifiOTASheet.swift:145` (`accessoryManager.disconnect()`),
  their `.onDisappear` (`:84`, `:88`, which cancels `otaTask`), `AccessoryManager.swift:812-814`
  (`disconnect()` sends `radioDisconnectedByUser` for the first radio),
  `RadioWindowViews.swift:88` (a radio's window closes on that signal).
- The sheets reboot the window's radio into update mode, but step 3 disconnects the first radio:
  - Updating another radio: the first radio is disconnected for the whole update, and on the Mac
    its window closes. It comes back when the sheet closes (`releaseRadio`).
  - Updating the first radio from its own window on the Mac: `disconnect()` closes that window, so
    the sheet disappears, its task is cancelled after the reboot command went out, and it stops at
    `guard !Task.isCancelled`. The radio waits in update mode with nothing sending it the firmware.
    The ESP32 update is offered on the Mac.
- nRF DFU and UF2 don't call `disconnect()`.
- Sure: high on the code.

### W7. Settings loses its radio whenever a radio window's radio reboots, on the Mac for a single radio too

- `RadioWindow.swift:135` (`radioNodeNum(for:)` returns `session(for: window)?.nodeNum ?? 0` for a
  window with a device id), `Settings.swift:951-955` (on a change it sets `preferredNodeNum` and
  `selectedNode` to the new value).
- Its doc says it gives the radio's number "also while it's disconnected", and for `.focused` it
  does (`PreferredRadio.nodeNum`). For a window with a device id it drops to 0 as soon as the radio
  disconnects, for example rebooting after a config save. Settings then zeroes its selected node,
  which collapses the Configure, Radio, Device, Module and Logging sections. That's the behaviour
  the comment at `Settings.swift:965-972` says `main` fixed by tracking the preferred radio.
- Every Mac window has a device id, so on the Mac this happens for every radio, including a
  single-radio user's only one. On iPhone and iPad it happens while the window shows a radio other
  than the first.
- Scenario: Mac, one radio; Settings › LoRa, change the preset and save; the radio reboots and
  Settings' sections collapse until it reconnects.
- Sure: high on the code.

### W2. While the first radio is gone, the other radios can't reconnect

- `AccessoryManager+AdditionalRadios.swift:272` (the reconnect loop only tries while
  `activeConnection != nil`), `:295` (`reconnectRememberedRadios` does the same),
  `AccessoryManager+Connect.swift:117` (a connect alongside refuses with no first radio).
- T316 makes "first radio gone, others connected" a normal state. In it, a radio alongside that
  drops can't come back until the first radio returns: its loop keeps sleeping, and discovery only
  auto-connects the preferred radio. T317 changed only discovery's side, so a remembered radio's
  loop is scheduled but never connects; `rememberedRadioComesBackWithoutTheFirst` checks only
  that it's scheduled.
- Scenario (Mac): windows for A (first) and B; A is switched off. Saving LoRa settings in B's window
  reboots B, and B's window stays "reconnecting" until A is back.
- Sure: high.

### W3. Adding a radio while the first radio is gone takes its place and strands it

- `AccessoryManager+AdditionalRadios.swift:129-131` (with no first radio, `connectAdditionalRadio`
  is a plain first-radio `connect(to:)`), `Connect.swift:1046-1056` (`DeviceConnectRow` runs
  `performRadioSwitch`, and `switchToDevice` sets `PreferredRadio` to the new radio up front),
  connect Step 5 (a first-radio connect records itself as preferred), discovery (auto-connects only
  `PreferredRadio`).
- In W2's state, adding a radio (the Connect tab, the Mac's Connect window, a manual entry) connects
  it as the first radio and makes it preferred. The dropped first radio is then neither preferred
  nor reconnected by discovery, has no reconnect loop, and usually isn't remembered (a radio that
  was always first keeps `autoConnect` false). It stays disconnected until the user reconnects it;
  HANDOFF's device check says it "comes back on its own".
- Sure: high.

### W4. Links and notification taps can go to the wrong window, or nowhere, on the Mac

- `WindowRouters.swift:85` (`guard entries.count > 1 else { return entries.first?.router ?? fallback }`),
  `ContentView.swift:55-56` (a window registers on appear, unregisters on disappear), the Mac's main
  window (`RadioListWindow`, which doesn't show the fallback router).
- With one radio window registered, every link goes to it, whatever radio it's about. A closed
  (hidden, W-01) window is unregistered, so a direct message to B with B's window hidden and A's
  open opens in A's window. With no radio window open the link goes to the fallback router, which
  no Mac window shows, and the tap does nothing. W-05 and plan step 3 say the radio's window opens,
  reopening it if it's hidden.
- Sure: high on the code.

### W5. The first radio's lock-down or old firmware goes unannounced when the window shows another radio, and its Unlock does nothing

- `AccessoryManager+RadioAttention.swift:102` (`setAttention` prompts only for radios other than
  `activeConnection`), `:184-186` (`lockdownStateChanged` sets attention only for them), connect
  Step 6 (the first radio gets `firmwareUpdateRequired`, not attention), `LockdownSheet.swift:101`
  (`RadioUnlockSheet` looks the radio up in `additionalRadios` only).
- These branches still assume the first radio is on screen. Since T314/T324 the iPhone window can
  show B. If A (first) then reconnects locked or with firmware that's too old, its gate belongs to
  a window that isn't showing it, and nothing prompts. Only A's row under Also Connected shows it
  (via `linkStatus(of:)`). That row's Unlock sets `radioUnlockRequest` for A, and
  `RadioUnlockSheet` finds no session for A and dismisses at once.
- Sure: high on the code.

### Minor

- `RadioWindow.swift:184`: `isVersionSupported(forVersion:for:)` falls back to the first radio's
  version when the window's radio has no session, so capability gates in a disconnected radio
  window follow another radio.
- `AccessoryManager+ServiceRadios.swift` (`askAboutServiceRadioIfNeeded`): "another radio known"
  comes from `storedRadios()`, which counts a merged backup's radio. So a user who connects one
  radio but switched radios on `main` (whose backups were merged, D-09) is asked once whether to
  make it the Siri and CarPlay radio. Small, but a visible change for that user.
- `AccessoryManager+AdditionalRadios.swift:82`: `disconnectRadio`'s doc still says "The focused
  radio hands the focus to another first", which T316 removed.
- The Mesh Map window (`MeshtasticApp.swift`) has no window radio, so it uses `.focused`, the first
  radio, even when opened from another radio's window.

## Checked and found fine

- One radio on iPhone and iPad: the one window is `.focused` (no stored pick), every connect is
  `isOnlyConnectedRadio`, so Steps 3a, 3b and 8 run as on `main`. The update notice goes to
  `RadioWindow(deviceId:)`, which for the first radio is the same session. The Siri and CarPlay
  question isn't asked with one radio known. The indicator has no menu, and prompts and gates are
  the first radio's as before.
- Connect: `connect(to:)` refuses to connect as first a radio already alongside;
  `radioConnectErrors` is kept per radio and cleared on the next attempt; discovery's auto-connect
  skips a radio already connected alongside.
- `closeConnection` with others connected: nothing takes the first radio's place, the position loop
  keeps going (T185), discovery restarts without the fallback (it needs no radio connected), and
  lock-down is cleared per session in `tearDown`.
- Per-radio lock-down (T301): each session has its own coordinator and sender on its own
  connection, set up with its peripheral for the saved passphrase. Auto replay, a send failure
  bringing the sheet back with the reason (`passphraseSendFailed`, auto replay included), backoff
  and its expiry, and Lock Now on any radio (first: `closeConnection()`, as `main`'s app-level
  handler did; others: disconnect with reconnect) all work. A window's views get its radio's
  coordinator (`WindowLockdownScope`), and a disconnected window gets `noRadio`, which never
  blocks or sends.
- Services (T319–T321): `session(for:)` falls back to the first radio, then any connected one;
  `intentRadio` never swaps a named radio for another (it asks); the share snapshot follows the
  CarPlay & Siri radio.
- BLE restore (T318): one restored radio connects first, the others are remembered and claimed after
  it or take over the restore when they connect first; nothing is given back or overridden.
- Mac windows: a radio's window opens once when it's connected (one shared tracker for every
  window), stays hidden after a close, closes on the user's Disconnect (and opens again at its next
  connect), and the Radios menu and Connect window reopen it. Radio windows don't take external
  events. Menu commands follow the key window's radio and are disabled for the Connect window.
- Mac Catalyst build compiles.
