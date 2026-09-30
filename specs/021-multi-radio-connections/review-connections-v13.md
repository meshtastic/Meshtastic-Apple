# Review V13: connections, focus and windows (feature/multi-radio)

Branch `feature/multi-radio` at `049c59d4`. V12 (`review-connections-v12.md`) was at `1ede1bbe`.
This round checks the fixes since (T350–T359) and what they touch:
- the scan's radio;
- the first radio released for an update;
- Disconnect on the first radio making another the preferred radio;
- radioless links on the Mac;
- Remove Node, Client History, the metadata request and Exchange User Info on their own radio;
- the DM conversation's radios;
- the one window's presentation order.

Files read (diff since `1ede1bbe`, then the code around it): `+AdditionalRadios`, `+Connect`,
`AccessoryManager.swift`, `+ToRadio`, `+RadioRemoval`, `+LaunchFallback`, `+Discovery`,
`RadioWindow.swift`, `WindowRouters.swift`, `DiscoveryScanEngine`, `Connect.swift`,
`ContentView.swift`, `ServiceRadioPickers.swift`, `DirectMessageQuery.swift`,
`UserMessageList.swift`, `ClientHistoryButton.swift`.

No build or test run this round: the owner said the build and tests were already done.

## Where the V12 findings stand

| V12 | What | Now |
|---|---|---|
| Y1 | Analyze Current Preset ran on the first radio | Fixed: `startScan(radio:)` gets the radio. |
| Y2 | An update of the first radio switched the one window | Fixed (`firstRadioReleasedForUpdate`). |
| Y3 | Disconnect on the first radio didn't stick across a relaunch | Fixed as proposed: another connected radio becomes the preferred one. One consequence: Z1. |
| Y4 | A radioless link lost on the Mac with no radio window open | Fixed: a connected radio's window opens and the link waits for it. |
| Device check | The one window's sheets, covers and alerts at once | Ordered (T359); checked below. |

## Findings

### Z1. The last radio left connected isn't reconnected when it drops, unless it's the first radio

- `AccessoryManager+AdditionalRadios.swift:60` (`hasRadioToJoin`: a radio connected, or the first
  one connecting), `:311` (a dropped radio's reconnect loop only tries while `hasRadioToJoin`);
  `AccessoryManager+Discovery.swift:72-75` (discovery auto-connects only the preferred radio, and not
  after a user disconnect: `!userRequestedConnectionCancellation`); `AccessoryManager.swift:825` (set
  by the first radio's Disconnect, cleared only when a first-radio connect starts);
  `AccessoryManager+LaunchFallback.swift:31-36` and `+Discovery.swift:41` (the remembered-radio
  fallback needs no radio connected and no user disconnect, and is only scheduled when discovery
  starts).
- A radio alongside that drops waits in its loop for another radio to join. When it was the only
  radio still connected, nothing else will connect one:
  - After the user disconnects the first radio A and keeps B: T352 makes B the preferred radio,
    but discovery's auto-connect stays off for the session (the Disconnect's flag), and B's loop
    has no radio to join. If B then drops, B stays disconnected until the user reconnects it or
    relaunches, even though it's in range. A config save that reboots B is enough.
  - With A dropped and away and B connected: if B drops more than 30 s after A, the same happens.
    Discovery only looks for A. The fallback was scheduled when A's teardown restarted discovery,
    found B connected and did nothing, and discovery is still running when B drops, so
    `startDiscovery()` returns early and the fallback isn't scheduled again.
- T333 (V11 W2) fixed the case with another radio still connected, not this one.
- Scenario (Mac): A and B connected; Disconnect A; in B's window, save LoRa settings; B reboots.
  B's window stays open (a drop doesn't close it) and B doesn't come back until the user connects
  it.
- Sure: high on the code. With no radio connected and no first-radio connect in progress, the loop
  could connect its radio as the first one (what the fallback would do) instead of waiting.

### Z2. Removing the first radio with others connected clears the preferred radio

- `AccessoryManager+RadioRemoval.swift:65-71` (with no first radio left, `PreferredRadio` is
  cleared), unlike `Connect.swift:1291-1297` (T352: Disconnect on the first radio makes another
  connected radio the preferred one).
- Remove This Radio on A, the first radio, while B is connected leaves no preferred radio. At the
  next launch discovery has nothing to connect, and B comes back only through the remembered-radio
  fallback after 30 s. Handing the preference to `connectedRadioAfterFirst`, as T352 does, would
  make the two the same.
- Sure: high; low impact.

## Checked and found fine

- Y1: `startCurrentPresetScan(radio:)` passes its radio to `startScan(radio:)`, so the scan's radio,
  its connection check, the home config snapshot and the primary-channel switch are all that
  radio's.
- Y2: `firstRadioReleasedForUpdate` is set only by `disconnect(forUpdate: true)` and cleared by the
  next first-radio connect or a user disconnect. The one window keeps the updated radio.
  `userRequestedConnectionCancellation` still keeps discovery off during the update, and the OTA
  sheets clear it when they close.
- Y3: the new preferred radio is `connectedRadioAfterFirst`, the same radio the one window switches
  to. With one radio nothing changes, as on `main`. The Shortcuts Disconnect goes through the same
  path.
- Y4: with no window registered, a radioless link opens the first connected radio's window and waits
  in `pendingLinks`; with nothing connected there's no window to open, as the fix says.
- Remove Node, Client History and Exchange User Info send on the connection of the radio they're
  from and fail when it's off. The metadata request checks that radio (the first radio's flag only
  when none is named).
- DM radios: `conversationRadios` always includes the window's radio, so with it off its thread
  shows and a reply fails instead of going from another radio. With one radio the list is that
  radio, so the Via picker stays hidden as before.
- T359 presentation order in the one window:
  - The gates come up only when neither the Choose Radios sheet nor another radio's prompt or
    passphrase sheet is up, and a gate that's up stays up.
  - The Choose Radios sheet waits for the gates and the prompts, and comes up 600 ms after they
    close.
  - Another radio's alert and passphrase sheet wait while `isGateUp`, which each presentation's
    `onDismiss` clears.
  - I followed the flows: a gate up then a prompt; the Choose Radios sheet up then the window's
    radio locking; a prompt answered with Unlock, then the gate. Each ends with the next one shown
    and nothing left waiting.
  - With one radio there's no Choose Radios sheet and no other radio's prompt, so the gates follow
    the radio's state exactly as before. On the Mac each radio window has no Choose Radios sheet
    (the Radios window asks) and no other radio's prompts (`RadioWindows.areEnabled`), so its gates
    follow its own radio as before.
