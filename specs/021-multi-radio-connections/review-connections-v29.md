# Review V29: the V28 fixes (T388)

Branch `feature/multi-radio`, uncommitted work on top of `58671b92`. This review checks T388, the
fixes for review V28, against the files. Tests: one run of `MultiRadioConnectFlowTests`,
`RadioRemovalTests` and `RadioWindowTrackerTests` in the iOS Simulator. All 65 passed, including
the four new tests, and the build changed no tracked files. SwiftLint was run on the changed files.

## The V28 findings

| Finding | Status | Notes |
|---|---|---|
| V28-1: the first radio's Disconnect doesn't pin the window | Fixed | Both Disconnects now send the signal before the teardown (`AccessoryManager.swift:843-849`, `+AdditionalRadios.swift:281-286`), while the window still shows the radio. `oneWindowRadio` shows the stored first radio as off from the moment its link goes (`RadioWindow.swift:129-131`), so the other radio no longer flashes in its place. `firstRadioDisconnectPinsTheWindow` covers both orders. |
| V28-2: a restore on the Mac leaves ghost windows | Fixed | `BackupManagement.swift:255-260` runs `forgetRadiosNotInStore()` after the gate has dropped and after the restore's drain, with a 300 ms settle first. The radio windows have remounted by then and hear `radioRemoved`. |
| V28-3: removing the store's own radio before its first connect doesn't clear | Fixed | `ownsPendingBackfill` (`MeshPackets+RadioRemoval.swift:91-93`) is computed under the gate, using the owner captured before `PreferredRadio` moves. Other radios' data still wins (`removalClearsStore` guard). Unit and store-level tests were added. |
| V28-4: stray `keys(of:)` rename | Fixed | `git diff -U0` was checked over `Meshtastic/` and `MeshtasticTests/`. Every removed line belongs to T386–T388, and no file has lost its final newline. |
| Minor 1: strings | Open, T134 | T388 lists all of them, and which ones need manual entries. |
| Minor 2: a radio known on several device ids | Fixed | `deviceId(ofRadio:)` uses the store's `peripheralId` (`radioLastDeviceIds`), but only while `knownNodeNums` still maps that id to the radio. Otherwise it takes the lowest id. Notification taps (`WindowRouters.swift:138`) benefit too. |
| Minor 3: backfill with no owner | Done | Recorded as a decision in T387. |

SwiftLint found no new violations. `Connect`'s body is unchanged at 706 lines. `MultiRadioConnectFlowTests` grew from 1048 to 1104 lines and `AccessoryManager` from 911 to 916, both already over 400. The three vertical-whitespace warnings in the test file were already at HEAD.

## Findings

### V29-1. On the Mac, a full factory reset of the only radio leaves its window showing a radio the store no longer has (low)

- `DeviceConfig.swift:323-341`: with no other radios, `factoryReset(resetDevice: true)` calls
  `disconnect()`, which is now a Disconnect that keeps the window (T386). It then clears the store
  (`clearDatabase` + `resetDatabaseAfterClear`).
- Nothing refreshes `knownRadios` or `knownNodeNums` afterwards. Only launch, a connect, a removal
  and `forgetRadiosNotInStore` do that.
- **For the rest of this run**, `offlineRadio` still counts the radio as one of the user's. Its
  window shows it as Not connected, with Connect and Remove, although the store has nothing for
  it.
- **At the next launch**, both lists come from the store and no longer have the radio. macOS
  restores the window anyway. It then has no Connect or Remove, is titled "Meshtastic" (or
  whatever discovery calls the radio), and stays until the user closes it. This is the kind of
  ghost window V27-4 closed for Clear App Data and V28-2 closed for a restore. Before T386,
  this Disconnect closed the window.
- iPhone and iPad aren't affected: with one radio the window is `.firstRadio`. The NodeDB reset
  and the config-only factory reset aren't affected either, because the radio reconnects and is
  stored again.
- Suggested fix: after the clear in `factoryReset` when `resetDevice` is true, call
  `await accessoryManager.forgetRadiosNotInStore()`, as Clear App Data does. Don't add it to the
  paths that reconnect: their reconnect may not have an attempt yet, so the window would close
  and then reopen. If the owner would rather keep the window to reconnect the reset radio, then
  at least refresh `knownRadios` and leave the window to show what the store has.

## Minors

1. HANDOFF needs updating:
   - The status note at lines 109-112 still stops at "V27 … fixed (T387)". Add V28 and T388.
   - The device check "Disconnect and Remove" (line 516) lists the Disconnects that pin as "the
     Connect tab, update screen, or Shortcuts". Add Settings › Device (the V28-1 case).
   - Add a Mac check: restoring a backup with two radios closes the window of the radio the
     backup doesn't have (V28-2).
2. Single-radio resets don't get removal's protections. `reset` and `factoryReset`
   (`DeviceConfig.swift:300-341`) still clear the store outside the handshake gate. They decide
   from `storedRadios` and the connected radios only (`hasOtherRadios`), so the checks removal
   gained in T387 aren't there:
   - a connect starting meanwhile (V27-1);
   - data `storedRadios` doesn't count (V27-3).

   This predates the change (T147) and isn't part of T386–T388. But the docs now say removal
   clears "as a reset does", so a reader could assume the two paths match. If the owner wants them
   aligned, that's a task of its own.
3. Still open before the commit:
   - The T134 strings.
   - The docs HTML: `Meshtastic/Resources/docs` hasn't been regenerated since the `bluetooth.md`
     and `settings.md` edits.
   - `review-connections-v27.md`, `review-connections-v28.md` and this file are untracked.
     Commit them with the work, as V24–V26 were.

## Checked and found fine

- **Sending the Disconnect signal early.**
  - It has two subscribers, `OneWindowRadioScope` and `RadioWindowOpener`. Neither touches the
    link.
  - `userRequestedConnectionCancellation` and `firstRadioReleasedForUpdate` are set before the
    send.
  - A release for an update still sends nothing.
  - Remove Radio also goes through `disconnect()` (via `takeRadioOffline`). In that case
    `radiosBeingRemoved` stops the pinned window from showing the radio as off during the removal.
    Once `knownNodeNums` drops the radio, the window falls back to the other radio, not the
    removed one.
- **`userDisconnectedFirst`.**
  - It only applies with several radios.
  - The flag it reads is manager-wide and outlives the radio it was about. After `PreferredRadio`
    moves to B, an off B is shown as `RadioWindow(B)`. `.firstRadio` already showed B as off the
    same way (`offlineWindowRadio`), so nothing visible changes.
  - Stand-ins and NRF DFU behave as before.
- **`RadioWindowTracker.leaving`.**
  - The next `toOpen` from any mounted opener clears it.
  - That includes the remount after the reset gate. A restore disconnects every radio while the
    openers are unmounted.
  - A radio told while still connecting is forgotten at once.
  - Calls from several windows are idempotent.
- **V28-2, the restore.**
  - `restoreBackup`'s `Task` outlives the popped view, which the T162 drain before it already
    relied on.
  - A radio that starts connecting during the settle is skipped, because `isRadioConnected`
    counts attempts.
  - `.skipped` and `.noBackupFound` forget every radio. That's right: the store was cleared.
- **V28-3, the owner's pending backfill.**
  - With another radio stored, the owner's pending backfill can't be left over. The launch merge
    or drain runs under the gate first (`MeshtasticApp.swift:160-180`,
    `MeshPackets+BackupMerge.swift:109`), and removal waits for the gate.
  - After Clear App Data nothing is pending, so a ghost radio still isn't treated as the owner.
- **`refreshKnownRadios`.** It now also reads `radioPeripheralIds()`. It publishes only on
  change, and a removal or `forgetRadiosNotInStore` drops the removed radio's entry.
