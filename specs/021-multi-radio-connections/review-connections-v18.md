# Review V18: connections, focus and windows (feature/multi-radio)

Branch `feature/multi-radio` at `af19fa29`. V17 (`review-connections-v17.md`) was at `6526fd4b`.
This round checks the two fixes since: T372 (the stand-in restore only for the user's own cancel)
and T373 (Disconnect forgets a radio by its known number).

Files read (diff since `6526fd4b`, then the code around it): `+AdditionalRadios`
(`disconnectRadio`, `disconnectAdditionalRadio`, `standIn(for:)`, `restorePreferred(after:)`),
`+RadioRemoval`, `AccessoryManager.swift` (`disconnect()`), `+RadioChoice`, `RadioWindow.swift`,
`Connect.swift` (`disconnectFirstRadio`, `switchToDevice`), `DeviceConfig.swift`, `AppSettings.swift`,
and the new tests. Every caller of `disconnect()` and `disconnectAdditionalRadio(byUser: true)` was
checked again.

No build or test run this round: the owner said the build and tests were already done.

## Where the V17 findings stand

| V17 | What | Now |
|---|---|---|
| U1 | The stand-in restore ran on every `disconnect()` | Fixed for Clear App Data, Restore Backup and the switch. One user path lost the restore: D1. |
| U2 | Disconnect before the number was known left the radio remembered | Fixed. |

## Findings

### D1. Remove This Radio from Device Config on the stand-in, during its node download, no longer puts the preferred radio back

- `AccessoryManager+RadioRemoval.swift:27-33` (a removal of the connected first radio goes
  straight to `disconnect()`, without `restorePreferred`), `:70-74` (then, with
  `PreferredRadio.nodeNum` already the stand-in's from its MyInfo, the preferred radio is
  cleared), `+AdditionalRadios.swift:94` and `+RadioRemoval.swift:56` (the restore is only in
  `disconnectRadio` and `stopBringingBack`).
- The stand-in's record lasts until its connect returns, after the node download. During that
  download the radio counts as connected (`+RadioChoice.swift:36`, `.retrievingDatabase`, and
  `:74` for the first radio). So its window's Device Config shows Remove This Radio
  (`DeviceConfig.swift:187-192`, `:224`), and `takeRadioOffline` finds it as the active
  connection.
- T371 put the restore in `disconnect()`, which covered this path: A and the flag came back first,
  so the handover saw A and left it. T372 moved the restore to the two callers above, so this path
  now gets neither:
  - the user-disconnect flag stays set, so A isn't reconnected this session;
  - the preferred radio is cleared, so at the next launch A comes back only through the 30 s
    fallback.

  That's S1 again, for this one path.
- The same branch serves a factory reset that deletes bonds on one of several radios
  (`DeviceConfig.swift:276-279`, `reconnect = false`). On the stand-in during its download it leaves
  the flag set and B, now reset, the preferred radio.
- Scenario (Mac): A away, B reboots and comes back as the stand-in. While its node list downloads,
  B's Settings › Device › Remove This Radio. A, back in range, isn't reconnected; after a relaunch
  it connects only after 30 s.
- Sure: high on the code; low impact (the stand-in's download, and the user removing it then).
  Taking `standIn(for: device.id)` before the `disconnect()` in `takeRadioOffline`'s first-radio
  branch (when `!reconnect`) and calling `restorePreferred(after:)` after it would match the other
  two paths.

## Checked and found fine

- T372:
  - `disconnect()` no longer touches the preferred radio or the flag. Clear App Data, Restore
    Backup and `switchToDevice` keep the flag set, and the switch's up-front choice of C stands.
  - The record now lives until `connectAsFirst` returns, or until a restore clears it. After
    those flows cancel the connect, it returns soon after, so another radio's stand-in waits a
    moment at most.
  - `restorePreferred` acts only while `PreferredRadio` still names A or the stand-in, and A is
    still a known radio. So A, removed during the stand-in's connect, isn't put back (V17's
    stale-snapshot case), and the flag then stays set, as after any Disconnect.
  - It reads `PreferredRadio.peripheralId`. Between MyInfo (number set to B) and Step 5 (peripheral
    set to B) that's still A, so it restores both halves and leaves no mix.
  - Disconnect of B while it connects, when the user had earlier disconnected A (T352 made B the
    preferred radio): B stays preferred and the flag stays set. B is the only radio in play, so it
    connects again at the next launch, as one radio does on `main`.
- T373:
  - `disconnectFirstRadio` finds the radio's number by its device id, from the active connection
    or the first attempt, through `knownNodeNums` (seeded at launch from the store, updated on each
    MyInfo).
  - `disconnectAdditionalRadio(byUser: true)` does the same with or without a session.
  - Callers that newly reach the no-session branch:
    - the user's Disconnect while a connect alongside hasn't reached Step 1 (intended);
    - Remove (the data goes anyway);
    - Clear App Data (the same);
    - Restore Backup (the store is replaced right after);
    - `switchToDevice` for a target in its reconnect loop. It becomes the first and preferred
      radio, and discovery's auto-connect of the preferred radio doesn't read `autoConnect`. A later
      fallback remembers it again, as it does any preferred radio.
  - With one radio, `autoConnect` doesn't decide anything, so Disconnect and relaunch connect it
    again, as on `main`.
- `forUpdate` and the duplicate-radio disconnect (`byUser: false`) don't reach the new code.
