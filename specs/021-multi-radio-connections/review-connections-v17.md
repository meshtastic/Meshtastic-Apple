# Review V17: connections, focus and windows (feature/multi-radio)

Branch `feature/multi-radio` at `4f07da18`. V16 (`review-connections-v16.md`) was at `d35836a6`.
This round checks the one fix since (T371: cancelling a radio that's connecting in the dropped
preferred radio's place leaves the preferred radio to come back) and what it touches.

Files read (diff since `d35836a6`, then the code around it): `+AdditionalRadios`
(`connectAsFirst`, `StandInConnect`, `disconnectAdditionalRadio`), `AccessoryManager.swift`
(`disconnect()`, `standInConnect`), `+RadioRemoval`, `+Discovery`, `+LaunchFallback`,
`+RadioChoice` (`linkStatus`), `RadioSession.swift`, `Connect.swift` (`disconnectFirstRadio`,
`switchToDevice`, the restore), `AppSettings.swift` (Clear App Data), `DeviceConfig.swift`,
`AdditionalRadioRow.swift`, and the new test. Every caller of `disconnect()` was checked.

No build or test run this round: the owner said the build and tests were already done.

## Where the V16 finding stands

| V16 | What | Now |
|---|---|---|
| S1 | Cancelling the stand-in kept the preferred radio from coming back | Fixed for Disconnect and Remove. The fix sits in `disconnect()`, which other flows call too: U1. |

## Findings

### U1. The stand-in restore runs on every `disconnect()`, not only the user's Disconnect or Remove of that radio

- `AccessoryManager.swift:827-835` (if a stand-in connect is running when `disconnect()` is
  called, its defer puts back the preferred radio and the user-disconnect flag, whoever the caller
  is), `+AdditionalRadios.swift:395-410` (the record is kept for the whole connect, handshake
  included).
- The other callers of `disconnect()` that can meet a stand-in connect:
  - Clear App Data (`AppSettings.swift:206-207`) and Restore Backup (`Connect.swift:1194`).
    Before T371 both left the flag set, so nothing reconnected for the session, as on `main`.
    Now the flag goes back to clear when A dropped rather than being disconnected. Discovery
    then reconnects A whenever it's seen: possibly while the store is cleared or replaced, and
    otherwise later, though Clear App Data expects nothing to reconnect after a full reset
    (`AppSettings.swift:226`). The restore's `isDatabaseResetting` check only covers
    `mayConnectAsFirst`, not this path.
  - Switching the first radio to C (`switchToDevice`, `Connect.swift:1321`, `:1343`, `:1350`). The
    switch makes C the preferred radio up front, so that if C's connect fails, auto-connect retries
    C. Its `disconnect()` of the stand-in puts A back. If C then connects, C is recorded again; if
    it fails, discovery retries A instead of the radio the user picked.
- The record is also a snapshot. If the preferred radio changes during the stand-in's connect, a
  later Disconnect still puts the old one back. For example: Remove This Radio on A from the stored
  radios list hands the preference on or clears it; then Disconnect on B before it has connected
  makes A, now removed, the preferred radio again, with auto-connect allowed, so A reconnects when
  it's seen.
- Sure: high on the code; each case needs the stand-in's few seconds of connecting, so low to
  medium impact. Doing the restore only in the user's Disconnect and Remove of that radio
  (`disconnectRadio`, `stopBringingBack`), and only while `PreferredRadio` still names A or the
  stand-in, would keep it to what S1 needed.

### U2. Disconnect on a radio before its connect knows its number leaves it remembered, so it comes back at the next launch

- `Connect.swift:1292` (`disconnectFirstRadio` turns off the radio's reconnect at launch only
  through `activeConnection?.nodeNum`), `RadioSession.swift:47` (`nodeNum` is `device.num`),
  `+AdditionalRadios.swift:415-417` and `+Discovery.swift:95` (the stand-in connect from discovery
  uses the device discovery reported, whose `num` is nil until MyInfo),
  `+AdditionalRadios.swift:276-282` (Disconnect on a radio alongside that hasn't reached Step 1 has
  no session, so its reconnect at launch isn't turned off either).
- T371 says the cancelled radio stays off. It does for this session: its loop is cancelled. But its
  remembered flag (`autoConnect`) stays on when Disconnect comes before the radio's number is known:
  - a stand-in started by discovery, from its start until MyInfo arrives early in the config
    download;
  - any connect alongside before Step 1 (Disconnect is offered while a connect runs,
    `linkStatus(of:)`), on this branch since T063.
- At the next launch A connects and `reconnectRememberedRadios` brings B back alongside. If A
  isn't around, the 30 s fallback connects B. That goes against `disconnectRadio`'s "it isn't
  brought back". On the Mac, B's window, closed by the Disconnect, reopens.
- Scenario: A away, B reboots and comes back as the stand-in; the user taps Disconnect on B as it
  connects. Relaunch: B connects again.
- Sure: high on the code; low impact. Turning off its reconnect at launch by the radio's known
  number (`knownNodeNums[deviceId]`, seeded at launch) rather than the session's would close both.

## Checked and found fine

- T371 for what it was for:
  - The record is claimed before `connectAsFirst`'s first wait, and a second stand-in can't start
    while it's held.
  - It's cleared when the connect ends, succeeded or not, and by `disconnect()`.
  - It only matches the radio `disconnect()` is cancelling: the active connection or the first
    attempt.
  - Disconnect or Remove of B while it connects puts A and the flag back. B's loop and discovery
    wait are cancelled. The one window then shows `.firstRadio` (A), as before B started.
- Once B's connect has returned, the record is gone and Disconnect on B is the ordinary
  first-radio Disconnect (T352).
- A user's own connect, the preferred radio's auto-connect and the fallback don't make a record, so
  they're unchanged. With one radio no stand-in ever starts, so `disconnect()` behaves as on `main`.
- `DeviceConfig.swift:330` (factory reset with BLE bonds deleted) disconnects a connected radio,
  which has no record by then. `didDismissSheet` (`Connect.swift:822`) has no callers.
