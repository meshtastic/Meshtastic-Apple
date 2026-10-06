# Review V31: the V30 fixes (T392)

Branch `feature/multi-radio`, uncommitted work on top of `58671b92`. This review checks T392, the
fixes for review V30, against the files.

## What changed since V30

- Code: the new `AccessoryManager.disconnectAfterFactoryReset(_:)` in `+RadioRemoval`, and its
  caller in `DeviceResetSection.factoryReset`.
- Tests: two new ones.
- Specs: `HANDOFF.md`, and `tasks.md` (adds T393).

## How it was checked

- **Tests:** one run of `MultiRadioConnectFlowTests`, `RadioRemovalTests` and
  `RadioWindowTrackerTests` in the iOS Simulator. 67 tests, all passed, including the 2 new ones.
  The build changed no tracked files.
- **SwiftLint:** `+RadioRemoval` and `DeviceConfig` are clean. The test struct grew from 1104 to
  1146 lines; it was already over 400. The three vertical-whitespace warnings in the test file
  were already at HEAD.
- **Removed lines:** `git diff -U0` was checked again. Every removed line belongs to T386–T392,
  and every changed file still ends in a newline.

## The V30 findings

| Finding | Status | Notes |
|---|---|---|
| V30-1: the only radio, connected alongside, isn't disconnected by a full factory reset | Fixed, for one radio. One case is left: V31-1 | See below. |
| Minor 1: the last window on the Mac | Deferred | Moved to T393, the owner's call. It's on the device check (`HANDOFF.md:548-551`) and in the open items (`HANDOFF.md:228`). |
| Minor 2: HANDOFF | Done | The status note counts four review files (V27–V30). The two long checklist lines are rewrapped (now at most 102 characters). |

How V30-1 is fixed:

- `factoryReset` now captures the radio's number before its task starts.
- `disconnectAfterFactoryReset` calls `takeRadioOffline(_:reconnect: false)`. It takes the radio
  offline whether it's the first radio or one alongside.
- If the radio's link has already dropped, `stopBringingBack` cancels its reconnect loop.
- Going beyond the review: if the preferred radio has already dropped, it also runs `disconnect()`
  (`+RadioRemoval.swift:55-57`). That sets `userRequestedConnectionCancellation` as `main`
  did, so discovery (`+Discovery.swift:72`) doesn't connect the radio again.
- The test `factoryResetOfTheOnlyRadioAlongside` covers A removed with B alone alongside.
  `factoryResetAfterTheLinkDropped` covers both drop cases.

## Findings

### V31-1. With several radios, a full factory reset of the first radio doesn't stop discovery reconnecting it (low)

- **The cause.** `resetOneOfSeveral` still takes the radio offline with
  `takeRadioOffline(radioNum, reconnect: !resetDevice)` (`DeviceConfig.swift:278-281`). It
  doesn't call `disconnectAfterFactoryReset`.
- **Why the radio is usually gone already.** T392 points out that the firmware turns Bluetooth off
  as it resets. A BLE radio's link has therefore usually dropped within the one-second wait. That
  makes this the common path, not an edge case.
- **What happens for the first radio.** `takeRadioOffline` finds no session and calls
  `stopBringingBack`. There's no connect attempt yet, so nothing calls `disconnect()`, and
  `userRequestedConnectionCancellation` stays false. `PreferredRadio` is still this radio.
- **The effect.** When the reset radio advertises again, discovery connects it as the first radio
  (`+Discovery.swift:72`). It's the case T392 fixed for a single radio. It can show as:
  - repeated failed connects or a pairing prompt, because the phone still holds the old bond;
  - the radio's reset row clean-up (`removeRadioData(.reset)`) running while its handshake writes
    (the V27-1 kind of overlap), if the connect gets through.

  A radio alongside isn't affected: `stopBringingBack` cancels its loop. TCP isn't affected
  either: its link is usually still up after the wait, so `disconnect()` runs.
- **Suggested fix.** For `.factory(resetDevice: true)`, call
  `await accessoryManager.disconnectAfterFactoryReset(radioNum)` in `resetOneOfSeveral` too.
  - Its extra `disconnect()` with no first radio and B connected touches nothing of B's. It only
    sets the flag, and the window falls back to B (T314), as a Disconnect does.
  - A test can reuse the second half of `factoryResetAfterTheLinkDropped`, with B left connected.
  - Optional: a dropped radio's reset doesn't pin the window, because no signal goes out without a
    session or an attempt. A connected radio's reset does. If that matters, send
    `radioDisconnectedByUser` for the preferred radio's device id before the extra `disconnect()`.

## Checked and found fine

- **Each case of `disconnectAfterFactoryReset`.**
  - First radio connected: `takeRadioOffline` disconnects it and sets the flag, so the extra
    branch is skipped.
  - A radio alongside, connected: `disconnectAdditionalRadio(byUser: true)` turns auto-connect
    off, sends the signal and stops the loop.
  - A radio alongside, dropped: `stopBringingBack` cancels its loop through the store's
    `peripheralId`.
  - Preferred radio, dropped: the flag is set as on `main`.
  - A stand-in can't reach the single-radio path, because a stand-in means another radio is
    stored.
- **Error handling.** The Disconnect's error is no longer reported, so the clear always runs.
  That's right: the reset has been sent.
- **After the clear.** `forgetRadiosNotInStore()` now finds B offline and forgets it. Its window
  closes, and it isn't restored at the next launch.
- **Edge case, part of T390.** On the single-radio path, a new radio connecting as first at that
  moment could have its connect cancelled by the extra `disconnect()` (while it has no
  `activeConnection` yet, because a first connect resets the flag). Its handshake data would be
  cleared anyway. The single-radio reset doesn't use the handshake gate, which is T390.
