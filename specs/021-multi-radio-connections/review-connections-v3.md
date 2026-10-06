# Review V3: connections and focus (feature/multi-radio)

Branch `feature/multi-radio` at `2957d36f`. V2 (`review-connections-v2.md`) reviewed `dc63a31d`;
this pass checks the fixes since (T170–T188) and the code they added: the passphrase sheet for a
radio that isn't focused (`RadioUnlockSheet`, `submitPassphrase(_:…toRadio:)`), the BLE restore
hand-over, the handover's memory of the dropped radio, the recycle's extra saves, the
backfill before a second radio joins, the position loop through a handover, and Remove for a
radio that isn't connected (App Settings › Your Radios).

Files read (diff since `dc63a31d`, then the code around it): `AccessoryManager.swift`, `+Connect`,
`+AdditionalRadios`, `+Focus`, `+FocusHandover`, `+Position`, `+RadioAttention`,
`+RadioRemoval`; `RadioSession.swift`; `BLETransport.swift`; `Connect.swift`, `ContentView.swift`,
`LockdownSheet.swift`, `StoredRadiosSection.swift`; `MeshtasticApp.swift`; in `MeshPackets` the
recycle, `noteRadioConnected`, `rememberedRadios` and `drainMultiRadioBackfill`.

## Tests

The full suite didn't complete cleanly on this Mac today, for reasons outside the code:

- The first run never started (the simulator's service hub failed, `simctl` not found).
- The second ran 3,321 tests, all passing; `ResettableTimerTests.repeatingTimer_firesMultipleTimes`
  started and never reported. Neither the timer nor its test is touched by the branch, and it
  passes on its own.
- The third had the test host killed partway ("Restarting after unexpected exit"). Different tests
  were in flight each time, there is no Meshtastic crash report, and macOS services (gamed,
  siriactionsd, maild) crashed in the same minutes.

The suites for this area all pass when run on their own: connect flow (characterization and
several radios), lock-down, connect lifecycle, remembered radios, sessions, BLE transport and
restoration, admin routing, service radios, reset and removal, share snapshots, the timer, and the
telemetry snapshot that was in flight during one of the kills. The full suite needs a re-run on a
quiet machine before this is called green.

## Where the V2 findings stand

| V2 | What | Now |
|---|---|---|
| N1 | A locked radio that isn't focused might never unlock | Fixed: its own passphrase sheet, sent on its own connection. Small gaps in R4. |
| N2 | Handover forgot the dropped radio after its failed reconnect | Fixed (`handoverPrevious`). |
| N3 | Recycle lost unsaved observation/reception writes | Fixed (two saves queued on the old instance). |
| N4 | Standby radio connecting first was dropped | Fixed for the radio that connects; the radio it displaces is the new problem in R1. |
| N5 | Update did nothing while the focused radio was connecting | Fixed (the wait covers the focused connect and an update). |
| N6 | Scan didn't see its radio's connect finish | Fixed (`objectWillChange` when an attempt ends). |
| N7 | Every first launch waited for the backfill | Fixed for single-radio stores; the backfill moved to a second radio's first connect, see R3. |
| N8 | Prompt flash for a radio about to be disconnected | Fixed (`previousStays: false`). |
| N9 | Handover could pick a locked radio | Fixed. |
| N10 | Manual entry didn't ask Keep Both / Switch | Fixed. |
| Also noted | Position stopped during a handover | Fixed (the loop keeps running while other radios are connected). |

## New findings, most serious first

### R1. A BLE restore that picks another radio never brings the preferred radio back

- `BLETransport.swift:752` (`focusedPeripheral` takes a connected radio first), `697-703`
  (`handOverRestore` moves the waiting radio to standby), `777` (standby released after 180 s);
  `AccessoryManager+Connect.swift:191` (`reconnectRememberedRadios`), `405` (Step 5 sets the
  preferred radio); `MeshPackets+MultiRadio.swift:127-141, 160-168`; `MyInfoEntity.autoConnect`
  defaults to false.
- Standby radios are only claimed by the remembered-radio reconnect, which brings back radios with
  `autoConnect` on. The focused radio's own connects leave `autoConnect` unchanged, so a radio that
  has only ever been focused (the user's main radio) isn't remembered. When the restore picks
  another radio (T155: the other is connected at relaunch; T178: the other connects first), the
  preferred radio sits in standby, isn't claimed, and is released after 180 s. Discovery won't
  reconnect it either, because it only auto-connects the preferred radio while nothing is
  connected. With T178 the radio that took over also ran a full handshake, so Step 5 made it the
  preferred radio from then on.
- Scenario: A (main, always focused) and B (added alongside) are connected; iOS kills the app in
  the background; A is out of range when iOS relaunches it for B. B is restored as the focused
  radio. A comes back in range and stays disconnected for the rest of the session; after T178, B
  is also the radio the app connects first at every later launch.
- The focus handover solves the same problem by calling `setRadioAutoConnect(previous, true)` and
  scheduling the dropped radio's reconnect; the restore hand-over does neither.
- Sure: high on the code.

### R2. Removing a radio that isn't connected doesn't stop it reconnecting

- `AccessoryManager+RadioRemoval.swift:19-24` (`takeRadioOffline` with no session only clears
  `autoConnect`), `54`; `AccessoryManager+AdditionalRadios.swift:223`
  (`scheduleAdditionalRadioReconnect`); `StoredRadiosSection.swift` (lists every radio that isn't
  connected).
- A radio that dropped has a reconnect loop running (`additionalRadioReconnects`), and one the
  handover dropped gets one too; a remembered radio not found at launch waits in
  `awaitedRememberedRadios`. Remove clears `autoConnect` and the radio's data but cancels none of
  these, so the radio reconnects when it's next in range, recreating its `MyInfoEntity` and data
  and marking itself remembered again. The confirmation says it "isn't reconnected". A connect for
  it still waiting at the handshake gate isn't cancelled either.
- Scenario: B was connected alongside A and went out of range. App Settings › Your Radios lists B;
  Remove. B comes back in range and rejoins within a minute.
- Sure: high. Cancelling the loop, the awaited entry and any attempt for the radio's device id (as
  `disconnectAdditionalRadio(byUser: true)` does) would close it.

### R3. The first backfill when a second radio joins stops every radio's ingest, and can drop a TCP radio

- `AccessoryManager+Connect.swift:122`, `AccessoryManager+AdditionalRadios.swift:167`,
  `MeshPackets+BackupMerge.swift:35` (one synchronous actor call over the whole message table),
  `AccessoryManager+ToRadio.swift:315` (5 s heartbeat response).
- While the drain runs, every packet handler from every radio waits for the ingest actor, so each
  radio's event loop stalls on its current packet. On TCP or serial, the focused radio's heartbeat
  timer isn't reset while no packet is handled: after 15 s it sends a heartbeat, the answer can't
  be handled within 5 s, and the link is closed with a timeout, so the focused radio drops and
  reconnects. BLE radios only pause.
- Once per store: the first time a second radio connects to a store that was never backfilled. On
  a Mac kept in front the background passes never ran, so that's the whole table. It hits the
  user's always-connected radio right when they try the feature for the first time.
- Sure: high on the mechanism; whether it drops the radio depends on the drain taking more than
  about 20 s, which a large store should (T133 would tell).

### R4. The passphrase sheet for a radio that isn't focused: rate limit and failed sends

- `AccessoryManager+RadioAttention.swift:318-326`, `LockdownSheet.swift:65-90`.
- `.unlockFailed` with a backoff is shown as a wrong passphrase, and the sheet lets the user submit
  again during the lockout. The focused radio's coordinator shows a countdown instead
  (`enterBackoff`). Whether an attempt during backoff extends it is up to the firmware.
- The sheet closes before the passphrase is sent, and a failed send (radio gone, no node number
  yet, send error) returns false with nothing shown.
- Sure: high; low impact.

## Checked and found fine

- Passphrase sheet: the packet is the same as the focused radio's (`lockdownAuthPacket`), sent on
  the radio's own connection; a typed passphrase is saved only when the radio reports unlocked,
  never when refused; a refused saved one is deleted only without backoff, as the coordinator
  does; `.locked` clears a pending one; the sheet closes when the radio unlocks, stops needing a
  passphrase or disconnects; an unlocked radio that was already connected is asked for its config
  again, one still connecting carries on.
- Handover memory: `handoverPrevious` is only used when a handover is pending, and every real drop
  overwrites it first, so a stale value (left when focusing cancels the running handover) is never
  read.
- Unlock/Update wait: `retryPendingAttentionFocusSoon` runs after the attempt is removed (defer
  order), on every connect exit and when an update ends; it waits while anything holds off the
  focus and ends when the radio is focusable or gone.
- BLE restore hand-over: only a standby radio's didConnect can take over, the waiting restore gets
  `RestoreHandedOver` and leaves `restoreInProgress` to the new one, the displaced radio's
  connection object is dropped so a later claim takes over its link cleanly.
- Recycle: the old instance is kept alive by the save task for its 2 s, then released.
- Position loop: keeps sending to every connected radio while none is focused, stops when none is
  left, restarted by the next focus.
- `previousStays: false` on Disconnect, reset and removal: no prompt, not remembered; a reset radio
  is remembered explicitly and reconnected.
- Manual entry: the same Keep Both / Switch choice and error alert as the listed radios.
- Single radio: no launch wait (the launch drain needs several stored radios); resets and Clear
  App Data as on `main`; the connect steps unchanged (characterization suite passes).
