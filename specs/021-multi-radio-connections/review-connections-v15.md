# Review V15: connections, focus and windows (feature/multi-radio)

Branch `feature/multi-radio` at `7796736b`. V14 (`review-connections-v14.md`) was at `af926ebe`.
This round checks the fixes since (T363–T368) and what they touch:
- a radio's reconnect loop ends once it's connected as the first radio, or disconnected (T363);
- Clear App Data and Restore Backup stop every radio coming back (T364);
- the first radio's update mark is cleared when its update sheet closes (T365);
- Remove This Radio hands the preferred radio on before the data cleanup (T366);
- the one window's Choose Radios sheet, other radios' prompts and passphrase sheet, and gates wait
  for the window to be free, and are asked for again if they didn't come up (T367, T368).

Files read (diff since `af926ebe`, then the code around it): `+AdditionalRadios`, `+Connect`,
`+RadioRemoval`, `AccessoryManager.swift`, `MeshPackets+RadioRemoval`, `ContentView.swift`,
`OtherRadioPresentation.swift`, `WindowPresentationProbe.swift`, `ServiceRadioPickers.swift`,
`StoredRadiosSection.swift`, `DeviceConfig.swift`, `AppSettings.swift`, `Connect.swift`, the ESP32
OTA and nRF DFU sheets, and the new tests.

No build or test run this round: the owner said the build and tests were already done.

## Where the V14 findings stand

| V14 | What | Now |
|---|---|---|
| P1 | Disconnect or Remove on a radio back as the first radio was undone by its loop | Fixed. One narrow path left for Remove from the stored radios list: Q1. |
| P2 | Clear App Data and Restore Backup left dropped radios' loops running | Fixed. |
| P3 | A lost prompt or passphrase sheet held the gates and the Choose Radios sheet back | Fixed in the code: asked for only with the window free, and again if it didn't come up. Device check below. |
| P4 | A failed first-radio update held a dropped radio back | Fixed. |

## Findings

### Q1. Remove from the stored radios list doesn't stop a connect as the first radio that started after the list was shown

- `StoredRadiosSection.swift:24-30` (the list leaves out radios that are connected or connecting,
  T197), `:84-89` (Remove doesn't check again when it's confirmed),
  `AccessoryManager+RadioRemoval.swift:19-22` (a radio that isn't connected goes to
  `stopBringingBack`), `:46-54` (`stopBringingBack` hands every attempt for the radio to
  `disconnectAdditionalRadio`), `AccessoryManager+AdditionalRadios.swift:272` (which only cancels
  a connect alongside, not one as the first radio), `:396` (`droppedRadioSeen` starts one).
- A dropped radio with its reconnect loop running is neither connected nor connecting, so the list
  offers it for removal. Since T360, discovery connects it as the first radio the moment it's seen,
  when nothing else is connected. If that starts between the list being shown and the removal being
  confirmed, and hasn't reached Step 1 (BLE connect, up to 20 s):
  - `stopBringingBack` cancels the loop but not the connect;
  - the radio's data is removed, and with no radio connected the preferred radio is cleared;
  - the connect then finishes, the radio becomes the first and preferred radio again, and its
    handshake writes its data back.
- After Step 1 the radio is the active connection, `takeRadioOffline` finds it and `disconnect()`
  stops both, so that case is fine. Device Config's Remove needs the radio connected, so it isn't
  affected.
- T197's note gives the reason for the list's filter: a removal while the radio connects deletes
  data the connect goes on writing. Before T360 a radio that wasn't the preferred one only connected
  as the first radio through the 30 s launch fallback; now any dropped radio can.
- Sure: high on the code; narrow timing, low impact. `stopBringingBack` cancelling a connect as the
  first radio too (through `disconnect()` when the attempt is the first), or Remove checking the
  radio's state again when confirmed, would close it.

## Worth checking on the device

- T368 counts a prompt as up when the window's root controller tree has a presented controller
  (`WindowPresentationProbe.swift:23-24`). That needs the SwiftUI alert to show as a presented
  `UIAlertController`, which it should; if it doesn't, the prompt would be asked for again every
  2.5 s while it's on screen. T362's checklist line covers seeing it.

## Checked and found fine

- T363:
  - A connect as the first radio removes the radio's loop entry when it succeeds. A loop that was
    running that connect returns after it; one that was asleep finds its entry gone when it wakes
    and returns. Neither removes a newer loop's entry (`ReconnectLoopHandle`, compared in the wake
    guard and the `defer`). `droppedRadioSeen` needs the entry, so it doesn't fire again either.
  - `disconnect()` cancels the loop of the radio it disconnects or cancels: the connected first
    radio, or the one connecting as the first. That covers Disconnect, Remove This Radio and the
    Shortcuts Disconnect on the first radio, and a cancel while it connects. Disconnect on a radio
    alongside already stopped its loop.
  - A first connect that fails leaves the entry, so the loop tries again, as T360 intends. The
    handle is set before the loop can run: the manager is `@MainActor` and the task starts after
    `scheduleAdditionalRadioReconnect` returns.
- T364: `disconnectAllAdditionalRadios` (only Clear App Data and Restore Backup call it) now takes
  the connected radios, those in a reconnect loop and those connecting alongside. It also clears
  `awaitedRememberedRadios`. A connect as the first radio already under way stops at the
  `disconnect()` both flows make next. After that, discovery's preferred auto-connect and the
  fallback are held off by the user-disconnect flag, and `mayConnectAsFirst` also refuses during a
  restore (`isDatabaseResetting`). On the Mac the dropped radios' windows close, as the connected
  ones' do.
- T365: both ESP32 sheets' `releaseRadio()` runs on close (while `otaInProgress`) and on failure.
  It clears the user-disconnect flag before `reclaimRadioAfterUpdate` clears the update mark, so the
  one window still doesn't switch. The Wi-Fi sheet's own reconnect after the transfer is a first
  connect, which clears the mark at its start; if that connect throws first, the catch releases.
  nRF DFU never sets the mark.
- T366: the preferred radio is handed on right after `takeRadioOffline`, so `activeConnection` is
  already nil for a removed first radio and `connectedRadioAfterFirst` takes it, before
  `removeRadioData` reads it through its default argument. The user-disconnect flag keeps discovery
  from reconnecting the removed radio in between.
- T367 / T368 in the code:
  - With one radio, `takesTurns` is false: no polling, the gates' waits are as before, and there are
    no prompts. On the Mac (`RadioWindows.areEnabled`) every radio window behaves as before.
  - The Choose Radios sheet keeps its turn from being asked for until it has come up and closed, or
    the choice is made elsewhere; one that didn't come up is asked for again once the window is free.
  - While it holds its turn, only `isWindowFree` decides its re-ask, and the prompts and gates wait
    for its turn. So none of them waits on another forever.
  - A prompt or passphrase sheet is asked for only with the window free and no gate up, one at a
    time, and again if it isn't up two seconds later. Unlock in the alert leads to the passphrase
    sheet at the next check, once the alert has gone.
  - A gate the window radio needs waits for the Choose Radios sheet, another radio's prompt, or any
    other presentation, and the half-second check brings it up afterwards. A gate that's up stays
    up.
  - The probe may not see the window's own lock-down and firmware covers: under UIKit's full-screen
    style the presenting view leaves the window, and `isPresenting` is then false. Harmless either
    way: `isGateUp`/`isShowingGate` already hold the Choose Radios sheet and the prompts back while
    a gate is up. The app's other full-screen cover (Waypoint bounds) is presented from the waypoint
    sheet (`MeshMapMK.swift`), which the probe still sees.
  - Nothing in the app stays presented on its own (no popover tips), so the window doesn't stay
    "busy".
