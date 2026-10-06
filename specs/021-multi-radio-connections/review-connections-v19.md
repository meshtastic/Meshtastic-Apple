# Review V19: connections, focus and windows (feature/multi-radio)

Branch `feature/multi-radio` at `dee5b4d0`. V18 (`review-connections-v18.md`) was at `5d6c975b`.
This round checks the one fix since: T374, where Remove This Radio, or a factory reset that deletes
bonds, on the stand-in from Device Config during its node download puts the preferred radio back.

Files read (diff since `5d6c975b`, then the code around it): `+RadioRemoval`
(`takeRadioOffline`, `stopBringingBack`, `removeRadio`), `+AdditionalRadios` (`disconnectRadio`,
`standIn(for:)`, `restorePreferred(after:)`, `reclaimRadioAfterUpdate`), `AccessoryManager.swift`
(`disconnect()`), `DeviceConfig.swift`, `Connect.swift`, `AppSettings.swift`, the ESP32 OTA sheets,
and the new test. Every caller of `disconnect()`, `disconnectFirstRadio` and `takeRadioOffline` was
checked again.

No build or test run this round: the owner said the build and tests were already done.

## Where the V18 finding stands

| V18 | What | Now |
|---|---|---|
| D1 | Remove or a bond-deleting reset of the stand-in from Device Config didn't restore the preferred radio | Fixed. |

## Findings

None this round.

## Checked and found fine

- T374:
  - `takeRadioOffline`'s first-radio branch (when `!reconnect`) takes the stand-in record before
    `disconnect()` and restores after it, as `disconnectRadio` and `stopBringingBack` do. For any
    other radio there's no record, and `restorePreferred(after: nil)` does nothing.
  - Remove: with A put back, `removeRadio`'s handover no longer sees the stand-in's number and leaves
    A, and `removeRadioData` keeps the shared messages on A's slots (R13-2). If A can't be put back
    (removed meanwhile, or the preference changed), the handover clears it as before.
  - A factory reset that deletes bonds: A is put back and the flag cleared, so A reconnects when
    it's seen. B, reset, has its reconnect at launch turned off.
- The user's ways to cancel a stand-in now all restore A: Disconnect (`disconnectRadio`, from the
  window, the Connect screen, the firmware gate or Shortcuts), Remove from the stored radios list
  (`stopBringingBack`), and Remove or a bond-deleting reset from Device Config
  (`takeRadioOffline`).
- The flows that deliberately don't restore are unchanged: Clear App Data, Restore Backup and
  `switchToDevice` call `disconnect()` directly. Device Config's single-radio reset
  (`DeviceConfig.swift:330`) only runs without other radios, where no stand-in can exist.
  `didDismissSheet` has no callers.
- Two other ways a stand-in can end during its download:
  - A reset that reboots it (`reconnect: true`) drops it with reconnect, and its connect ends.
    Since Step 5 it's the preferred radio, so discovery reconnects it after the reboot (its loop
    may also try, and the one-connect-per-radio guard keeps that to one). A, remembered by
    `connectAsFirst`, joins it.
  - A firmware update: `disconnect(forUpdate: true)`, then `reclaimRadioAfterUpdate` clears the
    update mark for it as the preferred radio, and discovery brings it back. The user acted on B,
    so B staying the first radio, with A joining, fits.
- Single radio: no stand-in starts, so none of the new branches run.
