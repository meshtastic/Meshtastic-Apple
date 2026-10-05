# Review V28: the V27 fixes (T387)

Branch `feature/multi-radio`, uncommitted work on top of `a00e58ca`. Checks T387, the fixes for
review V27, against the files. One run: `MultiRadioConnectFlowTests` and `RadioRemovalTests` in the
iOS Simulator (60 tests, all passed, the six new ones included). SwiftLint run on the changed files.

## The V27 findings

| Finding | Status | Notes |
|---|---|---|
| V27-1 store cleared while a connect starts | Fixed | Decided and done under `handshakeGate`, from what's connected, connecting and stored then. `connect(to:)` refuses the radio's ids and number during the removal. No deadlock: nothing in `resetDatabaseAfterClear` or `removeRadioData` waits on the gate. |
| V27-2 removal runs twice | Fixed | `radiosBeingRemoved` guards `removeRadio`, `canRemoveRadio`, `offlineRadio` and the addable lists. Two removals of different radios queue on the gate, and the second decides on the store the first left. |
| V27-3 data `storedRadios` doesn't count | Fixed | `holdsUncountedData`. The new `wasConnected` check from V27-4 causes a regression: see V28-3. |
| V27-4 ghosts after Clear App Data or a restore | Fixed for Clear App Data and iPhone | On the Mac, a restore's signal goes out while the radio windows are unmounted: V28-2. |
| V27-5 Remove while connecting | Fixed | Every entry point checks `canRemoveRadio`. A connect that starts between the dialog and the confirm is cancelled by `takeRadioOffline` before the data goes. |
| V27-6 update release shown as off | Fixed | `radiosReleasedForUpdate`. The ESP32 sheets set and clear it. NRF DFU doesn't use `releaseRadioForUpdate`, but discovery is stopped and the device has left `devices`, so Connect stays disabled. |
| V27-7 pin on every Disconnect | Partly | Works for a radio alongside and for a lone first radio. Doesn't work for the first radio while another is connected: V28-1. |
| V27-8 connected on another device id | Fixed | `offlineRadio` checks `isRadioConnected(nodeNum:)`. |
| V27-9 single-radio clear's side effects | Fixed | Clears notifications, refills the catalog, and falls back to `removeRadioData` after a partial clear. |
| Minors 1, 2, 4–6 | Fixed | Minors 3 and 7 are left on purpose (T387). |

SwiftLint: no new violations. `Connect` body is 696 → 706 lines and `MultiRadioConnectFlowTests`
950 → 1048 (both were already over 400). The new files are clean.

## Findings

### V28-1. The first radio's Disconnect doesn't pin the window while another radio is connected (medium-low)

- `RadioWindow.swift:95-108`: `lastShown` is updated whenever the window shows a connected radio.
  The pin matches the Disconnect signal against `lastShown` or `window.deviceId`.
- `AccessoryManager.swift:833-835, 864`: `disconnect()` sends the signal from its `defer`, after
  `closeConnection()`. `closeConnection()` sets `activeConnection = nil` (line 776), then awaits
  `tearDown` (line 783). SwiftUI renders during that await.
- In that render, `oneWindowRadio` (`RadioWindow.swift:120-136`) skips the stored radio. The stored
  radio is still `firstDeviceId`, because `PreferredRadio` only moves after `disconnect()` returns
  (`Connect.swift:1364-1367`). The function then falls through to the `userRequestedConnectionCancellation`
  branch and returns the other radio, B. The scope sets `lastShown = B`.
- When A's signal arrives, it matches neither `lastShown` (B) nor `window.deviceId` (B). The
  window stays on B. This happens for every Disconnect of the first radio with B connected that
  doesn't come from the Connect tab: the update screen, Shortcuts, Settings. T387 and the device
  checklist both say these pin.
- On the Connect tab, `disconnectWindowRadio` (`Connect.swift:95`) selects A first, so A wins in
  the end. Until `PreferredRadio` moves to B *and* something publishes, though, the window still
  shows B. That publish is often a discovery event about a second later. The comment says the early
  select prevents this flicker, but it doesn't.
- Suggested fix: send the user-disconnect signal before the teardown starts (the Mac tracker
  doesn't care about the order). In `oneWindowRadio`, also show the stored first radio as off when
  the user disconnected it: `stored != firstDeviceId || (userRequestedConnectionCancellation &&
  !firstRadioReleasedForUpdate)`. `offlineRadio` already excludes a radio released for an update.
  A test can drive `oneWindowRadio` with `activeConnection == nil`,
  `userRequestedConnectionCancellation` set, `PreferredRadio` still on A, and B connected.

### V28-2. After a backup restore on the Mac, the windows of radios the restored store doesn't have stay open (low)

- `Connect.swift:1344` calls `forgetRadiosNotInStore()` inside `backupCurrentAndRestoreDatabase`,
  while `appState.isDatabaseResetting` is still true. The flag is only cleared by the `defer` at
  line 1288.
- `MeshtasticApp.swift:318` unmounts every `RadioWindowRoot` while that flag is set, so
  `radioRemoved` has no subscriber and `dismissWindow()` never runs. When the gate drops, the window
  remounts for a radio that `knownNodeNums` no longer has. It shows "No device connected" under the
  title "Meshtastic".
- Clear App Data isn't affected: it doesn't set the gate, and the send happens after awaits, so the
  re-identified views have subscribed again by then. The device check for it still applies.
- Suggested fix: call `forgetRadiosNotInStore()` from `BackupManagement.restoreBackup` after
  `backupCurrentAndRestoreDatabase` returns. Alternatively, run it after the gate drops.

### V28-3. Removing the store's own radio before its first connect since the update no longer clears the store (low-medium)

- V27-4 added `wasConnected || storedRadios.contains(radioNum)` to `removalClearsStore`
  (`AccessoryManager+RadioRemoval.swift:178-181`). Before the update's first connect, the store's
  own radio has `lastConnected == nil` and no observations, so `storedRadios` doesn't count it. It
  isn't connected either.
- App Settings › Your Radios lists exactly this radio as "Not connected since the update"
  (`StoredRadiosSection.swift:50-52`). Since T386 it is offered with a single radio too.
- If the user removes it, `removeRadioData(.remove)` runs instead of a clear. Its MyInfo goes, but
  its pre-021 rows have no `localNodeNum` and no observations, so they all stay: messages, nodes and
  channels. `BackfillOwner` still names the removed radio, so the next radio to join credits those
  rows to it. The docs ("When the app holds no other radio's data, removing a radio clears the
  app's data") and T386's first version both cleared the store here.
- Suggested fix: also treat the removed radio as stored when it owns the pending backfill
  (`backfillOwner == radioNum && hasPendingBackfill()`). A ghost or a stray row still won't clear
  the store: after Clear App Data nothing is pending, and a stray isn't the owner. Add a
  `removalClearsStore` case and a `RadioRemovalTests` case for it.

### V28-4. An unrelated rename in `MeshPackets+RadioRemoval.swift` reverts V25's naming (low, hygiene)

- The diff renames `radioKeys(of:)` back to `keys(of:)` (`MeshPackets+RadioRemoval.swift:201-213`),
  which brings back `let keys = keys(of: other)`. Commit `04825b20` (the V25-1 fix) had introduced
  `radioKeys`. T387 doesn't mention the rename, and behaviour doesn't change.
- This looks like the stale-editor-copy gotcha in HANDOFF (lines 430-431). Revert the hunk. Before
  committing, check `git diff` for other undone lines. A pass over the removed lines in this diff
  turned up nothing else.

## Minors

1. String catalog: besides the strings T387 lists for T134, these aren't in `Localizable.xcstrings`
   yet: "Not connected", "Not connected · Looking for it…", "Reconnecting…", "Remove Radio…",
   "Remove Radio", "Open %@", "Connect %@", "Remove %@", "Remove %@…", "%@ (Not Connected)", and both
   `RemoveRadioConfirmation` dialog bodies.
2. `offlineKnownRadios` (`RadioWindow.swift:222`) gets each radio's device id from
   `deviceId(ofRadio:)`, which takes the first matching `knownNodeNums` entry in dictionary order. A
   radio known over both BLE and TCP can list, and Open, a different id from the window the user
   had open. That breaks W-03 (one window per radio). Prefer the store's `peripheralId`, which is
   the device it last connected on.
3. `holdsUncountedData` treats pending backfill rows as nobody's when no owner is known
   (`backfillOwner == 0`), and the test asserts this. That's defensible, since the rows most likely
   belong to the only radio. Note it as a decision in T387 so a later reader doesn't take it for an
   oversight.
