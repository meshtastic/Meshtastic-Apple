# Review V27: W-02 revised (T386)

Branch `feature/multi-radio`, uncommitted work on top of `a00e58ca`. Checks T386: Disconnect keeps
the radio's window, Remove Radio closes it, and a single radio can be removed. Read in the files,
plus one run: `MultiRadioConnectFlowTests` and `RadioRemovalTests` in the iOS Simulator (55 tests,
all passed, the new ones included; no compiler warnings in the changed files; no tracked file
changed by the build). SwiftLint run on the changed files.

## The six questions

| # | Question | Answer |
|---|---|---|
| 1 | Can `removeRadio` clear the store while another radio connects or still has data? | Yes, in two narrow ways: V27-1 (it decides before it awaits, and nothing holds connects off until the clear) and V27-3 (`storedRadios` can miss another radio's data after an upgrade). The backfill drain itself is safe against the clear. |
| 2 | Can the one window get stuck on a removed radio? Is the update release unchanged? | Not on a removed radio. It can on a radio the store no longer has after Clear App Data or a restore (V27-4). The release for an update is unchanged for `.firstRadio`; on the Mac, and for a radio alongside on iPhone, the released radio now shows as off with Connect and Remove (V27-6). |
| 3 | After Remove, can the radio come back or leave a ghost row? | Not through the normal path. Exceptions: the preferred radio auto-connected while it's being removed (V27-1), Remove during a connect (V27-5), a clear that fails part-way (V27-9), and stale `knownNodeNums` (V27-4). |
| 4 | Main-thread and actor safety; stale main-context reads (V24, V25)? | Fine. No new SwiftData reads in view bodies; the dialog carries values only; `storedRadios` reads the actor's own writes. One minor pre-existing read at confirm time (Minor 1). |
| 5 | Mac: focused value, Radios menu, close vs hide | Fine. Notes on Clear App Data (V27-4) and two windows for one radio (V27-8). |
| 6 | SwiftLint | No new violations. `Connect` body 675 → 696 lines and `MultiRadioConnectFlowTests` 907 → 950 (both were already over 400). `RadioWindowViews.swift` and the two new files are clean. |

## Findings

### V27-1. Remove decides to clear the store, then awaits, and nothing stops a connect before the clear (medium)

- `AccessoryManager+RadioRemoval.swift:74-101`: `clearsStore` is decided before
  `takeRadioOffline` (a BLE disconnect, `flushDebouncedSaves`, the teardown), then the store is
  cleared and the container recreated. Nothing in between stops a connect, and the decision isn't
  made again.
- Removing the only radio from the Connect tab shows Available Radios as soon as it disconnects.
  If the user taps another radio, or enters a manual address, its connect runs alongside the
  clear. Its MyInfo, channels and config land in a store being cleared, or are queued on the
  actor that `resetDatabaseAfterClear` replaces. The radio then shows connected with no config or
  channels until it reconnects.
- The removed radio itself: removing the preferred radio while it isn't connected doesn't stop
  discovery's preferred-radio auto-connect (`userRequestedConnectionCancellation` is false, and
  `PreferredRadio` is only cleared after `takeRadioOffline`'s awaits). If discovery sees it in
  that window, it reconnects. Its own attempt is left out of `othersConnecting`, so the clear goes
  ahead, and the "removed" radio comes back connected with a fresh MyInfo.
- `removeRadio` doesn't take `handshakeGate`, so it isn't ordered with the launch backup merge
  either. A clear between the merge's chunks disrupts it; the backup stays, so nothing is lost, but
  it uses one of its three attempts.
- Fix:
  - Take the radio offline first.
  - Then acquire `handshakeGate` (its own connect has been cancelled, so this can't deadlock;
    see the HANDOFF note).
  - Under the gate, decide again: any connect attempt (the removed radio's own new ones too),
    connected radios, `storedRadios`. Clear and repoint while still holding the gate.
  - When the removed radio is the preferred one, hand on or clear `PreferredRadio` before the
    first await.

### V27-2. Nothing guards a removal in progress (low to medium)

- `RemoveRadioConfirmation.swift:37-43` starts a `Task` and returns. While it runs, the radio's
  rows stay actionable: `OfflineRadioRow` (Connect, Remove), the Mac's Connect window and the
  Radios menu. Only Your Radios shows progress (`removing`).
- Connect tapped on the off row while `takeRadioOffline` is still running reconnects the radio
  that's being removed. Its data is then removed under the new connection, which is R3-4's case.
- A second Remove of the only radio runs a second `clearDatabase` and a second
  `repointToFreshContainer`. The code warns against more than one container recreation
  (`rebindToCurrentContainer`, `backupCurrentAndRestoreDatabase`: each one can leave a stale
  observer bridge).
- Fix: keep a `radiosBeingRemoved` set on the manager. `removeRadio` returns early for a radio
  already in it, and `offlineRadio` / `offlineKnownRadios` / the Remove entries skip it.

### V27-3. `storedRadios` can miss another radio's data, and the clear deletes it (low, upgrade-time)

- `removalClearsStore` treats "no other radio in `storedRadios`" as "the store is only this
  radio's". `storedRadios` counts a MyInfo only when it has `lastConnected` or observations.
  Two cases slip through:
  - A pending backfill owned by another radio (`hasPendingBackfill()` with `BackfillOwner` ≠ the
    removed radio). Those rows have no radio recorded on them yet.
  - T230's case: the owner's rows were attributed (`localNodeNum`), but the owner got no
    observations and hasn't connected since the update.
- In both, the user's earlier radio's history goes with the radio they remove. Before T386 only
  that radio's own data went (`removeRadioData`), or Remove wasn't offered at all.
- Fix: don't clear when a backfill is pending for another owner, or when another MyInfo's number
  owns messages (`localNodeNum`). Stray MyInfo rows without data still don't count.

### V27-4. Stale `knownNodeNums` after Clear App Data or a restore now shows ghost radios (low to medium)

- `RadioWindow.swift:193-196`: `offlineRadio` only asks `knownNodeNums`. Clear App Data
  (`AppSettings.swift:202-235`) and a backup restore (`backupCurrentAndRestoreDatabase`) never
  clear it.
- Mac: before T386 these paths closed every radio window, because their disconnects sent
  `radioDisconnectedByUser`. Now every radio window stays open after Clear App Data, showing a
  radio the app no longer has as "Not connected" (often by its hex number), with Connect and
  Remove. The Radios menu's Remove is enabled for it too.
- iPhone: a window set to a radio alongside stays on it (`oneWindowRadio` pins any known id),
  even with no radios left.
- Removing such a ghost runs the clear path on an empty store: another container recreation
  (V27-2).
- Fix: in `offlineRadio`, also require the radio in `knownRadios`, which comes from the store. Also
  have Clear App Data and restore empty `knownNodeNums`, sending `radioRemoved` for each id.

### V27-5. Remove is offered while a radio is connecting, which reopens R3-4 (T197) (low)

- Remove is offered in four places while the radio is still connecting:
  - `AdditionalRadioRow.swift:131-137`: shown while `isConnecting`, because it uses
    `knownNodeNums` for the number.
  - `RadioWindowViews.swift:296-301`: the Mac Connect window's `ConnectedRadioRow`, the same way.
  - `Connect.swift:370-376`: the Connect tab's menu during the node-DB download.
  - The Radios menu.
- `takeRadioOffline` cancels the connect, so this is narrower than R3-4. But a packet already
  in flight from the cancelled handshake (MyInfo, a channel) can still land after
  `removeRadioData` or `clearDatabase`. The radio then comes back as known after a relaunch.
- Fix: offer Remove only when the radio is connected (`link.isConnected`) or off, as Your Radios
  does.

### V27-6. A radio released for a firmware update shows as off with Connect and Remove (low)

- Only the `.firstRadio` branch of `Connect.offlineWindowRadio` checks
  `firstRadioReleasedForUpdate`. On the Mac every radio window has a device id, so the window of a
  radio being updated shows the off row, and the Connect window lists it under Your Radios. The
  same happens on iPhone for a radio alongside.
- On iPhone, a radio alongside now keeps the one window during its update (`oneWindowRadio`).
  Before, the window fell back to `.firstRadio` for that time. That's an improvement, but it
  changes the update path the request says is unchanged.
- During the update, Connect becomes enabled once the radio restarts in normal mode, and it races
  `reclaimRadioAfterUpdate`. The status "Looking for it…" is misleading.
- Fix: record the device ids released for an update. `offlineRadio` can then return nil for them,
  or show "Updating…".

### V27-7. Only the Connect tab's Disconnect keeps the window on the radio (low)

- `Connect.disconnectWindowRadio` selects the radio before it disconnects. Other Disconnects don't,
  so the window doesn't keep the radio:
  - `FirmwareUpdateGate`'s Disconnect on `.firstRadio` with another radio connected: the window
    moves to the other radio.
  - Shortcuts' Disconnect.
- The reverse case: `ManualConnectionMenu`'s connect with nothing connected (`Connect.swift:1054-1062`)
  doesn't select the new radio, as `connectPickedRadio` does. A window kept on a radio that's off
  keeps showing it after the user connects another one by address.
- Fix: keep the radio in `OneWindowRadioScope` instead
  (`onReceive(radioDisconnectedByUser)` when it's the shown radio and several radios are known).
  Route Manual through `connectPickedRadio`.

### V27-8. An off radio is matched by device id only (low)

- `offlineRadio(deviceId)` doesn't check whether the same radio, by node number, is connected on
  another device id (BLE and TCP). A window, or the iPhone's stored id, on the old id shows the
  radio as off with Connect while it's connected in another window (W-03).
- Fix: `guard !isRadioConnected(nodeNum: num)`.

### V27-9. The single-radio clear does less than Clear App Data (low)

- `AccessoryManager+RadioRemoval.swift:99-101`: no `clearNotifications()`. Delivered notifications
  for the removed radio's messages stay, and open threads that no longer exist.
- No device-catalog refill (`refreshBundledDevicesData`), which Clear App Data does because no
  reconnect follows. The hardware catalog stays empty until the next connect.
- The `clearDatabase` result is ignored. A clear that stops part-way can keep the MyInfo, and with
  `knownNodeNums` already cleared, the radio comes back as a ghost after relaunch. Fall back to
  `removeRadioData`, or escalate as the switch path does.

## Minor

1. `DeviceConfig.swift:226`: the confirmation's closure ignores the `RadioToRemove` it's given and
   reads `node?.num` again in `remove()`. That's the #2006 pattern if the node faults while the
   dialog is up (pre-existing). Pass `$0.nodeNum`.
2. Errors and dialogs on rows that disappear:
   - `OfflineRadioRow`'s "Couldn't Connect" alert can't appear. The row unmounts when the connect
     starts (`offlineRadio` is nil while connecting) and returns with fresh state. The Connect
     tab shows the error through `link.lastError`; the Mac Connect window shows nothing.
   - The Remove dialogs on `AdditionalRadioRow`, `ConnectedRadioRow` and `OfflineRadioRow` vanish
     if the radio's state changes while they're up. `Connect.swift` attaches its dialog to the
     List for this reason.
3. The dialog's text is chosen by `hasSeveralRadios`, but the removal is decided by
   `removalClearsStore`. They only disagree in the safe direction: the "whole store" text with
   only the radio's data going (a merged backup's radio, or one in its first download).
4. `docs/user/bluetooth.md`:
   - "next to **Disconnect** wherever that appears" doesn't hold for the swipe actions, the
     Mac's bottom Disconnect button or the update gate.
   - The off row on iPhone needs several radios. A single radio still shows "No device connected".
   - The heading "Resetting or Removing One of Several Radios" now covers one radio too.
5. Specs not updated:
   - `HANDOFF.md:188` still says Remove is "only offered with several radios".
   - `HANDOFF.md:502` still says Radios › Disconnect "closes its window".
   - `plan.md:298` still says "disconnecting closes it (W-02)".
   - The device checklist has nothing for T386.
6. VoiceOver: the Open, Connect and Remove buttons in `OfflineRadioRow` and `ConnectedRadioRow`
   don't include the radio's name.
7. Optional: for a remembered BLE radio, `OfflineRadioRow` could connect with the peripheral-id
   device (`device(for:)`) instead of waiting for discovery.

## Checked and found fine

- `oneWindowRadio`:
  - A removed radio falls through: `knownNodeNums` is cleared for every device id the radio had,
    before `refreshKnownRadios`.
  - The first radio released for an update stays `.firstRadio`, because the stored id equals
    `firstDeviceId` (the preferred radio). `offlineWindowRadio` leaves it out.
  - The updated `oneWindowRadioChoice` covers both the off and the removed cases.
- After Remove, nothing brings the radio back:
  - `autoConnect` is turned off, then the MyInfo is deleted.
  - Its reconnect loop and its wait for discovery stop.
  - `PreferredRadio` is handed on or cleared.
  - `seedKnownNodeNums` has no row left to seed from.
  - `offlineKnownRadios` drops the radio at once.
- Threads and contexts:
  - The new view code reads only manager state on the main actor.
  - `RadioToRemove` carries values. Your Radios used to hold a `MyInfoEntity` across its dialog.
  - `storedRadios` reads MyInfo `lastConnected` and observations on the packet actor, which is
    where they're written, so the V24/V25 problem doesn't apply.
- Backfill drain against the clear: the drain holds no model objects across its yields, and it
  stops when the repoint invalidates the actor. A radio's join and the launch merge hold the gate.
- Mac windows:
  - `removeWindowRadio` is set per scene by `RadioWindowRoot` only, so it's nil, and Remove is
    disabled, when the Connect or Mesh Map window is key.
  - The removal `Task` outlives the window it dismisses.
  - Disconnect keeps the window, and the tracker forgets the radio. On the next connect a closed
    window reopens, and an open one comes to the front (same `RadioWindow` value, no duplicate).
  - Closing an off radio's window just closes it; the Radios menu and the Connect window reopen it.
- `connectPickedRadio`: same behaviour as the old `DeviceConnectRow.handleTap`, with the limit
  check moved earlier. It adds the select when the window shows another radio that's off.
- Tests:
  - `disconnectKeepsWindowRemoveClosesIt`, `removalClearsStoreOnlyForTheOnlyRadio` and the updated
    `oneWindowRadioChoice` pass.
  - `removeOfflineRadio` now adds another radio, so it doesn't clear the shared test store.
  - Untested: the clear path end to end (hard with a shared store) and V27-1's race.

## Device checks for the owner

- macOS window restoration: windows open at quit come back. A restored window for a radio that
  connects isn't duplicated. A window restored before `seedKnownNodeNums` runs shows the radio
  once the numbers are seeded.
- iPhone relaunch with the window on a radio the user disconnected: it opens on that radio, off,
  every launch until another radio is picked. Check that this is what you want with the first
  radio connected and listed under Also Connected.
- Disconnecting a stand-in on iPhone (the radio connecting in the preferred radio's place): the
  window stays on the stand-in while the preferred radio comes back.
- Clear App Data with two radios on the Mac, after V27-4: every radio window closes.
