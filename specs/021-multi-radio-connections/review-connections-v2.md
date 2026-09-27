# Review V2: connections and focus (feature/multi-radio)

Branch `feature/multi-radio` at `2e029fab`. V1 (`review-connections.md`) reviewed `d9ccf477`; this
pass checks the fixes made since (T148–T156, recorded in tasks.md and HANDOFF.md) and looks again
at the connection code as it is now, including what's new: radio reset and removal (D-18,
`AccessoryManager+RadioRemoval.swift` and its callers in `DeviceConfig.swift`), the per-radio
attention queue, the launch backfill, and the discovery scan following its own radio.

Files read (diff since `d9ccf477`, then the surrounding code): `AccessoryManager.swift`,
`+Connect`, `+AdditionalRadios`, `+Focus`, `+FocusHandover`, `+RadioAttention`, `+RadioChoice`,
`+RadioRemoval`, `+Discovery`, `+Position`, `+FromRadio`, `+ToRadio`; `RadioSession.swift`;
`BLETransport.swift`; `Connect.swift`, `AdditionalRadioRow.swift`, `ContentView.swift`;
`DeviceConfig.swift` (resets), `DiscoveryScanEngine.swift` (connection handling),
`MeshtasticApp.swift` (launch merge/backfill), and in `MeshPackets` the recycle, the save
helpers, `recordReception` and `removeRadioData`.

The full suite passes in the iOS Simulator (iPhone 17 Pro): 3,442 Swift Testing tests in 598
suites and 29 XCTests.

## Where the V1 findings stand

| V1 | What | Now |
|---|---|---|
| C1 | Unlock while connecting disconnected the focused radio | Fixed: no reconnect path any more. See N1 for a case the new approach can't handle, and N5. |
| C2 | Dropped focused radio not reconnected after a handover | Partly fixed. Works when the dropped radio makes no connect attempt of its own before the handover; see N2. |
| C3 | Phone position stopped after a handover | Fixed (`applyFocusedRadioState` restarts the loop, and the loop replaces any running one). |
| C4 | Restore continuation not tied to its peripheral | Fixed. |
| C5 | Connected restored radio dropped while the preferred one was pending | Partly fixed: handled when iOS reports the other radio `.connected`; see N4. |
| C6 | Recycle dropped other radios' writes | Partly fixed: writes that schedule their own save now land; see N3. |
| C7 | Heartbeat timeout by the focused radio's firmware | Fixed (`isVersionSupported(forVersion:on:)`). |
| C8 | Manual TCP radio couldn't be added alongside | Fixed. Small follow-up in N10. |
| C9 | Remembered Bonjour TCP radio not brought back | Fixed (`recentlyDiscoveredDevices`, `awaitedRememberedRadios`). |
| C10 | Recycle counted only the focused radio's packets | Fixed (`noteIngestedPacket` on both event paths). |
| C11 | Focused connect at the gate didn't count as connecting | Fixed (`connect` refuses a second live attempt; `hasFocusedConnectInProgress`). |
| C12 | Losing the focus dropped a radio's lock/firmware state | Fixed (`attentionAfterLosingFocus`). Side effect in N8. |
| C13 | No config request after unlocking through the sheet | Left as is by decision (it's `main`'s behaviour); a device-test check is in HANDOFF. |
| C14 | Minors | All addressed: background/foreground to every radio, same radio twice, prompt queue, BLE scan pause per radio, Step 5 race. |

## New findings, most serious first

### N1. A locked radio that isn't focused may be impossible to unlock (depends on firmware)

- `AccessoryManager+RadioAttention.swift:91-96`, `AccessoryManager+Focus.swift:19-27`.
- Unlock now waits for the radio's connect to finish before focusing it (`pendingAttentionFocus`),
  and only the focused radio gets the passphrase sheet. If lock-down firmware doesn't answer the
  node-DB request while locked (the open question in HANDOFF), that connect never finishes:
  Step 5 times out, the attempt retries and fails, the reconnect loop starts another, and the
  prompt comes back each time. The radio can't be focused until it's connected, and can't
  connect until it's unlocked. The only way out is to disconnect the other radios and connect it
  first. V1's reconnect path was wrong, but it did reach the sheet.
- Scenario: A connected; lock-down radio B with no saved passphrase connects alongside, prompts
  "B is locked"; tap Unlock; nothing happens, B's row keeps cycling Connecting…, and the prompt
  returns on B's next attempt.
- Sure: the code path, high. Whether it happens depends on the firmware; the device-test item
  "Unlock tapped while B is still connecting focuses B once its connect finishes" is the check.
  If it fails there, a non-focused radio needs its own way to send the passphrase (the
  saved-passphrase path in `handleAdditionalLockdown` already sends on the radio's own session).

### N2. The handover forgets the dropped radio if that radio tried to reconnect first

- `AccessoryManager.swift:740-750`, `AccessoryManager+FocusHandover.swift:48-68`.
- Every `closeConnection()` cancels the pending handover and schedules a new one with the
  radio being closed now. When the dropped radio A's own reconnect attempt fails in Step 1 (the
  transport connect times out), `activeConnection` was never set, so the Step 0 retry cleanup and
  the final cleanup both call `closeConnection()` with nothing to close: the handover is
  rescheduled with `previousRadio` and `previousDevice` both nil. 30 s later B takes the focus,
  A isn't remembered (`setRadioAutoConnect` is skipped) and no reconnect is scheduled for it,
  which is V1's C2 again.
- Scenario: A at the edge of BLE range drops. Discovery sees an advertisement and tries A as the
  focused radio; the connect times out twice. B takes the focus. A comes back in range and stays
  disconnected until the next launch, and isn't remembered for that launch either.
- Sure: high. A fix is to keep the earlier previous radio when the new close has none.

### N3. The recycle still loses the observation and reception writes of queued packets

- `AccessoryManager.swift:413-418` and `AccessoryManager+Connect.swift:440-442` (recycles),
  `AccessoryManager.swift:1307` (the trailing save), `UpdateSwiftData.swift:263-330`
  (`updateAnyPacketFrom`), `MeshPackets+MultiRadio.swift:192` (`recordReception`).
- Calls queued on the old instance behind `flushDebouncedSaves()` run on it after the swap.
  `updateAnyPacketFrom` and `recordReception` never save; they rely on the
  `scheduleDebouncedSave()` at the end of `processFromRadio`, which now goes to the new
  instance. Unless another queued call on the old instance scheduled its own save (positions and
  node info do), the old instance is released with those changes unsaved: the node's last heard,
  SNR, hops and that radio's observation and reception for those packets are lost. Smaller than
  V1's C6 but not zero, and a lost reception can let the next radio's copy of the same broadcast
  through as new (the de-duplication looks for it).
- Also worth knowing: for up to the debounce window, the old and new instances write through two
  contexts that can't see each other's unsaved rows, which the "one writer" rule in plan.md
  assumes can't happen.
- Sure: medium-high on the code; each event loses a handful of packets' metadata at most.

### N4. BLE restoration: a radio restored while connecting is still dropped if it connects first

- `BLETransport.swift:703-709` (`focusedPeripheral`), `525-535` (a standby radio's didConnect is
  ignored), `673-677`, `728-735`, `311`.
- The fix prefers a radio reported `.connected` in the restore dictionary. If iOS reports every
  restored radio as `.connecting` and delivers didConnect afterwards (the order the existing
  `.connecting` restore path is written for), the preferred radio is still the focused restore.
  When a standby radio connects first, its didConnect matches neither the restore nor a connect
  continuation and is ignored; the focused restore keeps waiting with no timeout and discovery
  stays off; the standby radio is released after 180 s.
- Scenario: as in V1's C5, with B reported connecting rather than connected at relaunch.
- Sure: medium on the code path; low on how often iOS reports it this way. A standby radio's
  didConnect while the focused restore still waits could take over as the focused restore.

### N5. Unlock or Update does nothing while the focused radio is itself connecting

- `AccessoryManager+RadioAttention.swift:91-105`, `AccessoryManager+Focus.swift:24-26`.
- When B is connected but can't take the focus because the focused radio's own connect is running
  (A reconnecting) or an OTA is in progress, `focusRadioNeedingAttention` sets
  `pendingAttentionFocus`, which is only used when B's own connect finishes. B's connect already
  finished, so the tap is dropped silently and the prompt is gone (the row still offers Unlock).
- Sure: high; low impact.

### N6. A discovery scan on a radio that isn't focused can wait out its whole reconnect window

- `DiscoveryScanEngine.swift:473-477` (driven by `objectWillChange`),
  `AccessoryManager.swift:1485` (`linkState(ofRadio:)`: subscribed means no connect attempt),
  `AccessoryManager+Connect.swift:88` (the attempt is removed without a change notification).
- The last change notification of the scan radio's reconnect is Step 7's `connectionState`
  update, while its attempt still exists, so the scan sees "not subscribed". Removing the attempt
  sends nothing. The scan moves on only at the next unrelated notification (a BLE RSSI change
  usually comes within seconds) or when the 120 s reconnect window expires.
- Scenario: TCP-only setup, scan running on the non-focused radio: each preset can sit up to
  120 s after the radio is back.
- Sure: medium; low impact.

### N7. On the first launch after the update, the radio waits for the whole backfill

- `MeshtasticApp.swift:160-182`.
- Every existing store has messages without `fromNum`, so `hasPendingBackfill()` is true once for
  every user, including single-radio users, and the launch task holds the handshake gate while it
  drains the whole message table. The preferred radio's connect waits at the gate meanwhile. It's
  deliberate (T162) and one-time, but it's a visible change for single-radio users: on a large,
  long-lived store the radio sits at "Connecting" until the drain finishes.
- Sure: high that it waits; how long needs measuring on a real store (T133).

### N8. A radio losing the focus can flash a prompt just before it's disconnected

- `AccessoryManager+Focus.swift:55-57`, `Connect.swift` (`disconnectFocusedRadio`),
  `AccessoryManager+RadioRemoval.swift:25-40`.
- The update gate's Disconnect, and resetting or removing a focused radio that's locked or on old
  firmware, focus another radio and then disconnect the previous one. `focusConnectedRadio` gives
  the previous radio its attention in between (with suspensions after it), so its prompt can
  appear for a moment and then close when the radio is torn down.
- Sure: medium; cosmetic.

### N9. The handover can pick a locked or outdated radio

- `AccessoryManager+FocusHandover.swift:41`.
- The first connected radio takes the focus whatever its attention, so 30 s after the focused
  radio drops a passphrase sheet or the update screen can take over the app while a usable radio
  is also connected. Predates V1 (I missed it then).
- Sure: high; low impact. Preferring radios without attention would avoid it.

### N10. Manual entry under Add a Radio

- `Connect.swift:973-988`.
- With the default "Ask", a manually entered TCP radio is added without the Keep Both / Switch
  question the other rows ask, and a failed add is only logged, where `DeviceConnectRow` shows
  "Couldn't Connect".
- Sure: high; minor.

### Also noted

- The phone position loop still stops for the 30 s before a handover, and for good when none
  happens (a scan running, or no connected radio can take the focus), so the other connected
  radios get no position meanwhile. Smaller than C3.
- Worth checking on the device: a second radio's prompt arriving while the first radio's
  passphrase sheet or update screen is up. The alert sits on the same view as those full-screen
  covers; if SwiftUI doesn't present it after the cover closes, `radioAttentionPrompt` stays set
  and every later prompt queues behind it.

## Checked and found fine

- `connect(to:)` refusing a second live attempt: every cancel path marks the attempt first
  (`disconnect()` for focused attempts, `disconnectAdditionalRadio` for the others), so the
  switch fallback and Unlock paths can still start a new attempt; the attempt is always removed
  in `defer`, so nothing is refused for good.
- Unlock/Update during a connect: no path left that disconnects the focused radio;
  `pendingAttentionFocus` is cleared on a failed connect and on any disconnect, so a later
  reconnect can't grab the focus unexpectedly.
- Handover reconnect (when `previousDevice` is known): scheduled only when a radio is focused and
  the dropped one isn't already connecting; discovery won't compete for it.
- Heartbeat timeout per radio; background/foreground to every connection; duplicate-radio check
  against every connected radio, with its reconnect loop cancelled and its remembered state kept.
- BLE: restore continuation keyed by peripheral; scan pause per radio with every pause released
  on success, failure, abandon or `stopScanning`, so no pause is left behind.
- Step 5: `databaseResponseArrived` is reset before each request and set by the first NodeInfo
  or the completion; config-phase NodeInfos come before the reset.
- Attention prompts: queued, skipped when the radio is gone or its reason changed, cleared on
  teardown.
- Radio reset/removal: the reset command goes out on the radio's own connection before it's
  taken offline; a focused radio hands the focus over first; a reset radio is reconnected, a
  removed one is forgotten and the preferred radio moves; `removeRadioData` is one synchronous
  actor call, so a reconnecting radio's node dump queues behind it. The fallback for a focused
  radio with nothing to hand over matches `main`.
- Remembered TCP radios: found through `recentlyDiscoveredDevices` after Step 8 stops discovery,
  otherwise brought back when discovery next sees them.
- Single radio: reset/remove and Clear App Data run as on `main` when the store holds one radio;
  the connect steps are unchanged (characterization tests pass). Apart from N7's one-time wait,
  no single-radio change found.
