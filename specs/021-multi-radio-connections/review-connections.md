# Review: connections and focus (feature/multi-radio)

Branch `feature/multi-radio` at `bdca4708`, compared with `origin/main...HEAD`. I read HANDOFF.md,
plan.md, spec.md, tasks.md and CLAUDE.md first, then the connection code: `AccessoryManager.swift`
and its `+Connect`, `+AdditionalRadios`, `+Focus`, `+FocusHandover`, `+RadioAttention`,
`+RadioChoice`, `+RadioMQTT`, `+MQTT`, `+Lockdown`, `+Position`, `+Discovery`, `+FromRadio`,
`+ToRadio` (the diff), `+ServiceRadios` and `+TAK` (the diff); `RadioSession.swift`,
`PreferredRadio.swift`, `BLETransport.swift`; `Connect.swift`, `AdditionalRadioRow.swift`,
`FirmwareUpdateGate.swift`, `ContentView.swift`, `LockdownSheet.swift`. I also read
`LockdownCoordinator`, `AsyncGate`, `MeshPackets.recreateShared` and `TCPTransport` where the
code above depends on them.

The full suite passes in the iOS Simulator (iPhone 17 Pro): 3,402 Swift Testing tests in 595
suites and 29 XCTests. None of the findings below is covered by a test.

Ranked most serious first. "Sure" is how confident I am that it happens as described.

## 1. Unlock on a radio that is still connecting disconnects the focused radio

- `AccessoryManager+RadioAttention.swift:172` (prompt raised), `AccessoryManager+Focus.swift:19-27`,
  `Connect.swift:1288-1330` (`switchToDevice` fallback), `AdditionalRadioRow.swift:116`,
  `ContentView.swift:66-75`.
- A locked radio reports its lock-down status right after the config handshake (connect Step 3),
  and `handleAdditionalLockdown` raises the prompt then. Its connect is still running (Steps 4-7:
  node DB, version check), so `connectAttempts[id]` is set and `connectionState` is `.connecting`.
  `canFocusWithoutReconnecting` returns false, and `switchToDevice` takes the old reconnect path:
  it disconnects the locked radio (`byUser: true`), calls `disconnect()` on the focused radio, and
  reconnects the locked radio as the focused one. The row's menu explicitly allows this: the
  button is only disabled while connecting when there is no attention.
- Scenario: A connected. Connect B, a lock-down radio with no saved passphrase. The "B is locked"
  alert appears while B is still downloading its node DB. Tap Unlock. A disconnects, B reconnects
  from scratch as the focused radio. A comes back only if B's focused connect succeeds
  (`reconnectRememberedRadios`). If locked firmware doesn't answer the node-DB request (the open
  question in HANDOFF), B's connect fails, nothing is focused, A stays disconnected, and discovery
  keeps retrying B because it is now the preferred radio.
- Contradicts T073 and the HANDOFF checklist ("Unlock focuses B without reconnecting").
- Sure: high that the path is taken when Unlock is tapped before B's connect reaches Step 7; the
  prompt appearing mid-connect makes that the likely case. The old-firmware prompt (Step 6) has
  the same problem but only for the short Steps 7-8 window.

## 2. A focused radio that dropped and was handed over never reconnects in this session

- `AccessoryManager+FocusHandover.swift:40-66`, `AccessoryManager+Focus.swift:35-63`,
  `AccessoryManager+Discovery.swift:72-78`, `AccessoryManager.swift:474-484`.
- After 30 s the handover focuses another connected radio through `switchToDevice` →
  `focusConnectedRadio`, and sets the dropped radio's `autoConnect`. Nothing schedules a reconnect
  for it: `scheduleAdditionalRadioReconnect` is only called from `didReceiveAdditional` and
  `reconnectRememberedRadios` (which runs only at the end of a focused connect), and discovery
  auto-connects only `PreferredRadio`, which the handover just moved to the new focused radio.
- Scenario: A focused, B connected. A goes out of range (or is power-cycled) for more than 30 s.
  B takes the focus. A comes back in range: it shows under "Add a Radio" but never reconnects
  until the next launch or the next focused connect.
- Contradicts FR-004 ("Each radio reconnects on its own after it drops"), the doc comment at
  `FocusHandover.swift:38-39` ("comes back as an additional radio") and HANDOFF › Focus when
  things go wrong.
- Sure: high.

## 3. Phone position stops going to every radio after a focus handover

- `AccessoryManager.swift:730-731` (`closeConnection` cancels `locationTask`),
  `AccessoryManager+Connect.swift:477-481` (only a focused connect starts it),
  `AccessoryManager+Focus.swift:67-97` (`applyFocusedRadioState` doesn't restart it).
- When the focused radio drops, `closeConnection` cancels the one loop that shares the phone's
  position with every radio. The handover focuses the next radio without a connect, so the loop
  is never restarted. Until the handover, the other radios get nothing either.
- Scenario: A focused, B connected, "Provide location" on. A drops, B takes the focus. Neither B
  nor anything else gets the phone's position for the rest of the session.
- Contradicts D-12 / T101 (phone position to every radio). The Disconnect-on-focused path is fine
  (it never cancels the loop).
- Sure: high.

## 4. BLE restoration: the restore continuation isn't tied to a peripheral

- `BLETransport.swift:512-517`, `528-533`, `613-616`.
- `handleDidConnect` and `handleDidFailToConnect` resume `restoredConnectContinuation` for any
  peripheral, before looking at `connectContinuations`. Before this branch only one peripheral
  could be connecting, so that was safe. Now restored standby radios can still have CoreBluetooth
  connects pending, and `isBusy` is per peripheral, so other connects are allowed during a
  restore.
- Scenario: the app is killed with A (preferred) and B connected; both links drop while it's
  suspended, so iOS restores both as `.connecting`. B reconnects first: its `didConnect` resumes
  A's restore. A's restore then runs the connect steps on A's `BLEConnection` while A isn't
  connected, fails Step 1 and its retries (the same stale `withConnection` each time), and gives
  up. B's `didConnect` was swallowed, so B sits connected with no owner and is released after
  180 s. The same happens to a user connect started during a pending restore.
- Sure: medium-high on the code; needs the device test to see how often iOS produces it.

## 5. BLE restoration: a restored radio that is connected is dropped while the preferred one is pending

- `BLETransport.swift:553` (`focusedPeripheral` picks the preferred radio whatever its state),
  `613-616` (the pending restore waits with no timeout), `305` (`restoreInProgress` blocks
  discovery), `663-705` (standby released after 180 s), `AccessoryManager+Connect.swift:172-174`
  (standby radios are only claimed after the focused connect finishes).
- Scenario: A (preferred) was left at home; B is with the user and connected when iOS relaunches
  the app for B. A is restored `.connecting` and becomes the focused restore; B goes to standby.
  A never connects, so `reconnectRememberedRadios` never runs, discovery is blocked by
  `restoreInProgress`, and after 3 minutes B's link is cancelled. The radio that woke the app is
  the one dropped.
- HANDOFF says unclaimed radios are released "if the focused restore fails"; a pending restore
  never fails.
- Sure: medium. It depends on iOS listing pending connects in the restore dictionary, which its
  documentation says it does.

## 6. Every radio's connect recycles the ingest actor while the other radios are receiving

- `AccessoryManager+Connect.swift:433-435` (Step 7, now run for every radio),
  `AccessoryManager.swift:910-914` (the periodic recycle), `MeshPackets.swift:204-229`.
- `recreateShared()` invalidates the old actor, and an invalidated actor never saves again.
  A connected radio's packet handler that was queued on the old actor during Step 7's
  `flushDebouncedSaves()` writes into the old context after the flush; its debounced save is then
  cancelled, so positions, telemetry and node updates from that packet are lost. The handshake
  gate only keeps another radio's node dump out, not a connected radio's live traffic. The same
  now applies to the periodic recycle: it runs "between packets" of the focused radio only, while
  other radios' handlers may be mid-write.
- plan.md › T070 lists Step 7's recycle as "safe: the handshake gate is held"; that's only true for
  dumps. HANDOFF records the mechanism for additional radios as rare, but with D-17 every connect
  and reconnect of any radio triggers it, including a radio that keeps dropping and reconnecting.
- Sure: medium. The loss per event is a few packets.

## 7. The heartbeat timeout is decided by the focused radio's firmware

- `AccessoryManager.swift:1553` (`setupPeriodicHeartbeat(on:)` calls `checkIsVersionSupported`,
  which reads `activeConnection`'s version).
- For a radio connected alongside, Step 8 creates the response timer (or not) from the focused
  radio's firmware. A TCP or serial radio on 2.5.14-2.7.3 next to a newer focused radio gets a
  5 s response timer it can't satisfy (those versions don't answer the heartbeat), so it is
  disconnected after 15 s of quiet and reconnected, over and over. The other way round, a newer
  radio next to an old focused one gets no timeout, which is the gap T071 meant to close.
- Scenario: focused BLE radio on 2.7.15, second radio over TCP on 2.6.x on a quiet mesh: it drops
  every 20 s or so and `🔗🔁` reconnect lines repeat.
- Sure: high on the code; medium on old firmware staying silent for 5 s (the code comment says it
  doesn't answer).

## 8. A manual TCP radio can't be added alongside another radio

- `Connect.swift:457` (Available Radios, the manual-connection menu and the saved Manual
  Connections are hidden while connected), `Connect.swift:423-437` ("Add a Radio" lists only
  discovered devices), `Connect.swift:962-973` (manual entry only ever switches),
  `TCPTransport.swift:185-187` (`manuallyConnect` is a focused connect).
- A TCP radio that isn't found by Bonjour can only be connected as the focused radio. The
  workaround is to connect it first and add the BLE radios after it.
- Against FR-001 and the checklist item "TCP radio plus BLE radios together".
- Sure: high.

## 9. A remembered TCP radio found by Bonjour isn't brought back after the focused radio connects

- `AccessoryManager+Connect.swift:467` (Step 8 still calls `stopDiscovery()`, which empties
  `devices`), `174` (`reconnectRememberedRadios` right after), `AccessoryManager+AdditionalRadios.swift:250-260`.
- `device(for:)` looks in `devices` (just emptied), then `ManualConnectionList` (Step 7 only saves
  manual connections), then gives up for anything but BLE. A remembered radio that isn't found is
  skipped for good; nothing retries when discovery sees it later.
- Scenario: A (BLE) and B (TCP, Bonjour) connected. Quit and relaunch: A reconnects, B is logged
  as "Can't bring back … not found on tcp" and stays disconnected. HANDOFF step 9 expects it back.
- plan.md step 3 says stopping discovery after a connect goes; Step 8 still does it.
- Sure: high.

## 10. The periodic ingest recycle only counts the focused radio's packets

- `AccessoryManager.swift:876-890` (a radio connected alongside returns before
  `packetsReceived += 1`), `910` (recycle only on the focused path, only while `state` is
  `.subscribed`).
- With a quiet focused radio and a busy one alongside (or no focused radio for a while), the
  ingest context grows without the recycle meant to bound it (the comment cites multi-GB RSS
  under a busy TCP stream).
- Sure: high on the code; the effect needs a busy second radio.

## 11. A focused connect waiting at the handshake gate doesn't count as connecting

- `AccessoryManager+Connect.swift:78-105` (the gate wait comes before any status change, and a
  focused connect overwrites `connectAttempts[id]` without checking it), `AccessoryManager.swift:478`,
  `AccessoryManager+FocusHandover.swift:26-34, 76-83`.
- While it waits, `state` stays `.discovering`, so `isConnecting` is false. Discovery can start
  another focused connect for the same radio (each overwrites `connectAttempts[id]`, so the one
  that runs isn't the one found by lookups such as the heartbeat timeout), and the focus handover
  or the remembered-radio fallback can fire. If the handover fires, the queued connect later
  throws "Already connected" and that radio isn't brought back (finding 2).
- Single-radio exposure: on the first launch with old backups, the backup merge holds the gate
  (T030), so the preferred radio's connect waits there.
- Sure: medium; mostly wasted attempts rather than wrong state.

## 12. Losing the focus doesn't carry a radio's lock-down or old-firmware state

- `AccessoryManager+Focus.swift:37-53`.
- The previous focused radio moves to `additionalRadios` with `attention` nil, even if its
  `lastLockdownStatus` is locked or its firmware is below the minimum. Its Connect row says
  "Connected" and nothing prompts. Mostly unreachable while the sheet or the update gate covers
  the app, but reachable while the coordinator is waiting on a submitted or auto-replayed
  passphrase (`state == .none`) and the toolbar menu changes the focus.
- Sure: high on the code, low reachability.

## 13. Unlocking through the focused coordinator doesn't ask for the config again

- `AccessoryManager+RadioAttention.swift:138-146` vs `AccessoryManager.swift:1388-1389` and
  `LockdownCoordinator.handleUnlocked`.
- A radio unlocked while not focused (saved passphrase) gets `sendWantConfig` again; one unlocked
  through the sheet, which is where T073 sends every Unlock, doesn't. spec 007 says the app
  re-requests the config after unlock. `main` doesn't do it for the focused radio either, so this
  isn't a regression, but the two paths now disagree about whether it's needed.
- Sure: low-medium; depends on whether lock-down firmware resends the config by itself.

## 14. Minor

- `AccessoryManager.swift:1584-1609`: only the focused connection is told about background and
  foreground, so BLE radios connected alongside keep polling RSSI in the background (each reading
  redraws through `updateDevice`).
- `AccessoryManager+FromRadio.swift:172-175`: a radio reporting the focused radio's node number
  (the same radio over TCP and BLE) is dropped with `byUser: false`, so a reconnect loop for it
  keeps reconnecting it; the check also ignores the other radios alongside.
- `AccessoryManager.swift:298`: one `radioAttentionPrompt`; a second radio needing the user
  replaces the first radio's prompt.
- `BLETransport.swift:721-735`: any BLE disconnect clears the transport-wide scan pause, even while
  another radio is in its pairing window.
- HANDOFF's Step 5 note (the node-DB completion can arrive before the wait starts) is still open:
  `sendWantDatabase` still sends before it waits.

## Checked and found fine

- Handshake gate: FIFO, always released by `defer` after `acquire`; nothing awaits `connect` while
  holding it (`reconnectRememberedRadios` only schedules; `switchToDevice` is only called from UI
  and the handover task). A focused connect waiting at the gate is cancelled by `disconnect()`
  (generation), another radio's by `disconnectAdditionalRadio` (`isCancelled`). No deadlock found.
- Session registration: no suspension between creating the event task and putting the session in
  `activeConnection` / `additionalRadios`, so the first event is never taken for a stale one.
- Event routing in `didReceive`: sessions alongside go to `didReceiveAdditional` before the focused
  handling; retired sessions are dropped; `focusConnectedRadio` swaps the roles without a
  suspension, so no event is handled under neither radio.
- Errors and disconnects of a radio alongside: its own connect's stepper while connecting,
  otherwise its own teardown and reconnect loop; never the focused connection.
- Teardown: continuations cleared before they're resumed; the node-DB gate's waiters cancelled;
  config-refresh waiters resumed with `CancellationError`; the double teardown when a radio is
  disconnected mid-connect (`disconnectAdditionalRadio`, then `cleanUpAfterFailedConnect`) is
  harmless. No continuation left unresumed or resumed twice.
- BLE per peripheral: every callback except the restore continuation routes by identifier;
  Bluetooth off resumes every pending connect; `abandonPendingConnect` runs after the cancelled
  connect has unwound, so its guard sees the right state; `connectTransport` closes a connection
  that arrives after its timeout.
- `send(_:via:)` refuses a session that is neither focused nor connected alongside.
- App-wide work in the handlers is limited to the focused radio (`lastConfigRefresh`, Messages
  snapshot, Datadog context, preferred radio, TAK bridge, event firmware defaults); canned
  messages, ringtone, timezone and set-time go through the radio they're for.
- Per-radio MQTT: started in Step 8 and on reboot, stopped in `tearDown`; `startMqtt` re-checks
  the session after its delay.
- Focus swap: preferred radio, update gate, Datadog, lock-down replay, unread badges, Messages
  snapshot, TAK bridge and Settings reset all follow the new focused radio.
- Single radio: the connect steps run in the same order (characterization tests pass); the
  handover and remembered-radio fallback do nothing with no other radios; `send(_:via:)` is the
  old `send`. Visible by design (FR-002): the Connect tab now shows "Add a Radio" and scans while
  it's open. Apart from finding 11 on a first launch with old backups, I found no single-radio
  regression.
