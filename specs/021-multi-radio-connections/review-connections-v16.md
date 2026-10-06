# Review V16: connections, focus and windows (feature/multi-radio)

Branch `feature/multi-radio` at `d35836a6`. V15 (`review-connections-v15.md`) was at `7796736b`.
This round checks the one fix since (T370: Remove cancels a connect of the radio as the first
radio) and what it touches.

Files read (diff since `7796736b`, then the code around it): `+RadioRemoval`, `+AdditionalRadios`,
`+Connect`, `+Discovery`, `+LaunchFallback`, `AccessoryManager.swift` (`disconnect()`),
`RadioWindow.swift`, `Connect.swift` (`disconnectFirstRadio`), `StoredRadiosSection.swift`,
`DeviceConfig.swift`, and the new test.

No build or test run this round: the owner said the build and tests were already done.

## Where the V15 findings stand

| V15 | What | Now |
|---|---|---|
| Q1 | Remove from the stored radios list didn't stop a connect as the first radio | Fixed: `stopBringingBack` cancels it through `disconnect()`. That call has one side effect: S1. |
| Device check | The prompt must show as a presented alert | On the device checklist. |

## Findings

### S1. Cancelling a radio that's connecting as the first radio in the preferred radio's place keeps the preferred radio from reconnecting

- `AccessoryManager.swift:831` (`disconnect()` sets the user-disconnect flag), `+Connect.swift:134`
  (only a connect as the first radio clears it), `+Discovery.swift:72` and `+LaunchFallback.swift:36`
  (discovery's auto-connect of the preferred radio and the remembered-radio fallback both stop while
  it's set), `+RadioRemoval.swift:52-56` (T370: Remove calls `disconnect()` for such a connect),
  `+AdditionalRadios.swift:90-92` (Disconnect on it goes through `disconnectFirstRadio`, also
  `disconnect()`).
- Since T360, B (a radio alongside that dropped) connects as the first radio on its own when
  nothing else is connected, standing in for A, the preferred radio. If A dropped rather than being
  disconnected, the flag is clear, and A is meant to come back when it's in range. `connectAsFirst`
  even remembers A to join.
- Cancelling B's connect, by Remove (T370) or by Disconnect while B is connecting, goes through
  `disconnect()` and sets the flag. From then on, for the rest of the session:
  - discovery doesn't auto-connect A when it comes back in range;
  - the fallback doesn't connect a remembered radio either.

  A stays off until the user connects a radio or relaunches. On `main`, and before T360, the flag
  was only ever set by turning off the radio it holds back.
- Scenario (iPhone): A (preferred) and B connected. A is carried out of range, then B reboots.
  As B comes back it starts connecting as the first radio. The user taps Disconnect on it while it
  connects, or confirms removing it from a stored radios list shown just before. A comes back in range and isn't reconnected.
- Sure: high on the code; low to medium impact (needs a dropped preferred radio and the user
  cancelling the stand-in). Leaving the flag as it was when the cancelled connect isn't the
  preferred radio's would keep Disconnect and Remove meaning "this radio" only.

## Checked and found fine

- T370 itself:
  - `stopBringingBack` finds the radio's first attempt by node number or by its peripheral id. A
    radio connected from discovery has no number until MyInfo, so the peripheral id is what finds
    it (`Device.num` is nil for a radio discovery reports).
  - `disconnect()` then cancels the attempt: the generation check at the gate, `isCancelled`, and
    the stepper once past it. It also stops the radio's loop and its discovery wait.
  - `disconnectAdditionalRadio(byUser:)` follows as before, so nothing is left to bring it back.
- After Step 1 a radio connecting as the first is the active connection. If its session has its
  number, `takeRadioOffline` finds it; if not yet, `stopBringingBack` still finds it by peripheral id
  and `disconnect()` disconnects it. Either way the removal disconnects it before its data goes.
- With other radios connected alongside, a first attempt can only be the preferred radio's own
  reconnect. Removing that radio cancels it the way Disconnect on the first radio does, and the
  removal then hands the preference to a connected radio (T361/T366). The one window moves to that
  radio, as for Disconnect.
- `radioDisconnectedByUser` fires for the removed radio, from `disconnect()` and again from
  `disconnectAdditionalRadio`. Closing a window twice is harmless. On the Mac, a dropped radio's
  window, left open by the drop, closes on removal.
- Single radio: the stored radios list only shows with two or more known radios
  (`StoredRadiosSection.swift:39`), and Device Config's Remove needs the radio connected and goes
  through `takeRadioOffline`'s session path, unchanged. So with one radio nothing here runs.
