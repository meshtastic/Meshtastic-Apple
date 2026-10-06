# Review V14: connections, focus and windows (feature/multi-radio)

Branch `feature/multi-radio` at `af926ebe`. V13 (`review-connections-v13.md`) was at `fb719385`.
This round checks the fixes since (T360–T362) and what they touch:
- a radio alongside that drops with no other radio left comes back as the first radio (T360);
- Remove This Radio on the first radio hands the preferred radio on (T361);
- a Choose Radios sheet that never came up doesn't hold the others back (T362).

Files read (diff since `fb719385`, then the code around it): `+AdditionalRadios`, `+Connect`,
`+Discovery`, `+RadioRemoval`, `+LaunchFallback`, `+RadioAttention`, `+FromRadio`,
`+RadioChoice`, `AccessoryManager.swift`, `RadioWindow.swift`, `BLETransport`, `TCPTransport`,
`SerialTransport`, `Connect.swift`, `AppSettings.swift` (Clear App Data), `BackupManagement.swift`,
`ContentView.swift`, `ServiceRadioPickers.swift`, `RadioWindowViews.swift`, the ESP32 OTA and
nRF DFU sheets, and the new tests.

No build or test run this round: the owner said the build and tests were already done.

## Where the V13 findings stand

| V13 | What | Now |
|---|---|---|
| Z1 | The last radio left connected wasn't reconnected when it dropped | Fixed: it comes back as the first radio once discovery sees it. Two gaps around its reconnect loop: P1, P2. |
| Z2 | Removing the first radio cleared the preferred radio | Fixed: another connected radio becomes the preferred one. |
| R12-1 (data) | A Choose Radios sheet that never came up held the others back | Fixed for that sheet. The other radio's prompt has the same exposure: P3. |

## Findings, most serious first

### P1. Disconnect or Remove This Radio on a radio that came back as the first radio doesn't stick while its reconnect loop is still running

- `AccessoryManager+AdditionalRadios.swift:368-369` (`droppedRadioSeen` connects the radio as the
  first radio from its own task and leaves the reconnect loop sleeping), `:308` and `:335` (the loop
  only ends when it next wakes and finds the radio connected; the wait backs off up to 60 s),
  `:347-348` (`mayConnectAsFirst` doesn't look at a user disconnect), `:90-92` (Disconnect on the
  first radio goes to `disconnectFirstRadio`), `AccessoryManager.swift:817-853` (`disconnect()`
  doesn't stop the radio's reconnect loop), `AccessoryManager+RadioRemoval.swift:27-33` (Remove This
  Radio on the first radio goes through `disconnect()` too).
- Of the disconnects, only the one for a radio alongside (`disconnectAdditionalRadio(byUser: true)`)
  stops a loop. Once B is connecting or connected as the first radio, every Disconnect goes through `disconnect()`,
  and B's loop stays:
  - B came back through discovery: for up to a minute after, until the loop next wakes. The
    disconnect restarts discovery, discovery reports B again (it's advertising), `droppedRadioSeen`
    finds the loop still there, and B reconnects within seconds. `connect(to:)` then clears the
    user-disconnect flag. Remove This Radio in that time removes B's data, clears the preferred
    radio, and then B reconnects, becomes the preferred radio again and writes its data back.
  - B is still connecting as the first radio: Disconnect cancels the connect, and the loop tries
    again at its next wake, or sooner if discovery reports B again.
- The new test shows the loop is still there after B is back: `keptRadioComesBackAsFirst` expects
  the loop to exist, then cancels it in `endDiscovery` before its own `disconnect()`.
- Scenario (iPhone): A and B connected, Disconnect A, B reboots after a LoRa save and comes back as
  the first radio. Within the next minute, Disconnect B: B comes straight back.
- Sure: high on the code. Ending the loop when its radio connects as the first one, and having
  `disconnect()` stop the loop of the radio it disconnects or cancels, would close it.

### P2. Clear App Data and Restore Backup leave a dropped radio's reconnect loop running, and it now connects that radio as the first radio

- `AppSettings.swift:206-219` (Clear App Data: `disconnectAllAdditionalRadios()`, `disconnect()`,
  then the store is cleared and the container replaced), `Connect.swift:1190-1221` (Restore Backup:
  the same disconnects, then the store is replaced in place under `isDatabaseResetting`),
  `AccessoryManager+AdditionalRadios.swift:288-289` (`disconnectAllAdditionalRadios` only goes
  through the connected radios, `additionalRadios`), `:347-348` and `:368-369` (with nothing
  connected, the loop or discovery connects the radio as the first radio). Nothing in the connect
  path checks `isDatabaseResetting`.
- A radio alongside that has dropped (its row says reconnecting) isn't in `additionalRadios`, so its
  loop survives both flows. Before T360 that loop waited while nothing was connected. Now:
  - If the radio is advertising nearby, the disconnect restarts discovery, discovery reports it,
    and `droppedRadioSeen` connects it as the first radio within seconds. Its connect and node dump
    then write into the store while Clear App Data is clearing it and replacing the container, or
    while the restore is replacing it. Both flows disconnect every radio first to prevent exactly
    this.
  - Otherwise it connects when it's back in range, although Clear App Data expects no reconnect
    after a full reset (`AppSettings.swift:226`). It becomes the preferred radio and its data is
    written again.
- On `main`, the user-disconnect flag set by `disconnect()` keeps discovery from reconnecting after
  either flow. The new path ignores that flag, as Z1 needed.
- Scenario: A connected, B dropped a moment ago (rebooting). Clear App Data. B finishes booting and
  connects as the first radio while the store is being cleared.
- Sure: high that the loop survives and connects; medium on how often the timing lands in the clear
  itself. Stopping every reconnect loop (and `awaitedRememberedRadios`) in
  `disconnectAllAdditionalRadios`, or in both flows, would close it.

### P3. A prompt or passphrase sheet lost the way R12-1's sheet was still holds back the gates and the Choose Radios sheet

- `ServiceRadioPickers.swift:161-165` (T362: a Choose Radios sheet that didn't appear within 2 s is
  let go and asked for again), `ContentView.swift:65` (`isAskingAboutAnotherRadio`: another radio's
  prompt or passphrase request is set, shown or not), `:73` (the window radio's lock-down and
  firmware gates wait while it's set), `:88` (the Choose Radios sheet waits while it's set),
  `AccessoryManager+RadioAttention.swift:119, 201` and `AccessoryManager.swift:713` (cleared only
  when that radio no longer needs the user, or disconnects).
- T362 works from the premise that a presentation asked for while an app sheet further in is up
  doesn't come up, and doesn't come up later. The other radio's alert and passphrase sheet are
  presented from the same view. If they're lost the same way, `radioAttentionPrompt` or
  `radioUnlockRequest` stays set, nothing is shown, and until that radio is unlocked some other way
  or disconnects:
  - the window radio's own lock-down screen doesn't come up if it locks;
  - the Choose Radios sheet doesn't come up.
- Before T359 a lost prompt held nothing else back. Single radio and the Mac are unaffected: neither
  uses these prompts.
- Sure: depends on how SwiftUI handles an alert asked for under another sheet, which only the device
  shows. Worth adding to the device checklist next to T362's line: with a channel link's save sheet
  open, power-cycle a locked B.

### P4. After an update of the first radio that doesn't bring it back, a radio alongside that drops stays off

- `AccessoryManager+AdditionalRadios.swift:347-348` (`mayConnectAsFirst` is false while
  `firstRadioReleasedForUpdate`), `AccessoryManager.swift:826` and `+Connect.swift:135` (the flag is
  cleared only by the next connect as the first radio, or a Disconnect). The OTA sheets clear
  `otaInProgress` and the user-disconnect flag when they close, not this flag.
- If the update fails and A stays in its bootloader, the flag stays set for the session. B, still
  connected, then drops and waits for A instead of coming back as the first radio, until the user
  connects a radio.
- Sure: high on the code; low impact (needs a failed update).

## Checked and found fine

- T360, the rest:
  - The loop connects as the first radio only with nothing connected or connecting, not during a
    switch, an OTA or the first radio's update, and only when discovery has the radio.
    `droppedRadioSeen` uses the same check.
  - BLE reports a radio as found once per appearance (later sightings are RSSI events), so
    `droppedRadioSeen` doesn't retry on every advertisement; the loop's backoff paces the retries.
  - Two dropped radios racing to be first: the second's connect stops at "Already connected" after
    the gate, and its loop then joins it alongside.
  - The preferred radio is remembered to join unless the user disconnected it. With A dropped, B
    becomes preferred on connecting (Step 5 and MyInfo), and A comes back through
    `reconnectRememberedRadios` or `awaitedRememberedRadios`.
  - A first connect that fails returns without throwing, its attempt is removed, and the loop tries
    again.
  - The bound on a first connect is passed only by `connectAsFirst`; every other caller passes none,
    so `connectTransport` calls `transport.connect` as before. With one radio there's no loop, and
    `droppedRadioSeen` returns at once.
  - A radio alongside that's updated with nothing else connected comes back as the first radio
    through `reclaimRadioAfterUpdate`, where before it waited.
  - The one window: with B gone it shows `.firstRadio` (or B, if the user picked it, while its loop
    runs), and `.firstRadio` is B once it's back.
- T361: with the first radio removed, `activeConnection` is nil after `takeRadioOffline`, so the
  preference goes to `connectedRadioAfterFirst`, the same radio the window shows and Disconnect
  picks. Removing a radio that isn't connected now also hands the preference to a connected radio.
  With none left it's cleared, as before.
- T362, the rest:
  - `hasAppeared` is reset each time the sheet is asked for, and set by the sheet's `onAppear`.
  - A choice made in App Settings while the sheet hadn't come up lets the others go.
  - Overlapping tasks stop at `!isShowing` / `!isWaiting`, and the re-ask waits while a gate or
    prompt is up.
  - `release()` can run twice (the timeout and a later dismiss); `onClose` only recomputes the gates,
    so twice is harmless.
  - On the Mac the Radios window's gate (default `isUp`, no-op `onClose`) now asks again instead of
    staying lost behind the onboarding sheet.
