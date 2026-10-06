# Review V33: T390 and T393

Branch `feature/multi-radio` at `bd35aa80`, working tree clean. This review checks the two commits
since V32 against the files.

## What changed since V32

- `a5e5a360` commits T386–T395 and T391 with the review files V27–V32. Nothing new in it beyond
  what V27–V32 reviewed.
- `5305ba12` is new code, the owner's calls of 2026-10-05:
  - **T390:** removing the only radio erases the app's data as Clear App Data does. Both call the
    new `AccessoryManager.eraseAppData()` (`AccessoryManager+AppData.swift`). The removal still
    runs it under the handshake gate. The only-radio confirmation says what it erases.
  - **T393:** on the Mac, when a radio's window closes because its radio was removed or forgotten
    and it was the last window open, the Connect window opens in its place
    (`RadioWindowTracker.closesLastWindow`, `RadioWindowRoot`).
  - Docs (`bluetooth.md`, `settings.md`), spec D-18, W-02, HANDOFF and tasks.
- `577b17f2` (Xcode Cloud manifest) and `bd35aa80` (hang-risk notes) aren't part of this work.

## How it was checked

- **Tests:** one run of `MultiRadioConnectFlowTests`, `RadioRemovalTests` and
  `RadioWindowTrackerTests` in the iOS Simulator. 69 tests, all passed. The build changed no
  tracked files.
- **Probe:** a temporary test hosted a view under `.id(token)` in a window and changed the token
  three times, recording `onAppear` and `onDisappear`. It was deleted after the run. Result under
  V33-1.
- **SwiftLint:** clean on the six Swift files `5305ba12` changed.
- **Removed lines:** the 37 Swift lines `5305ba12` removes all belong to T390 or T393: the Clear
  App Data body that moved to `eraseAppData`, the removal's old clear, the old dialog text and
  the old `radioRemoved` handler. Nothing earlier is undone.
- **Editor:** early in this review the editor served `a5e5a360` copies of two of the changed
  files while the disk had `5305ba12`. It matches the disk now (see minor 4).

## The V32 minors

| Minor | Status | Notes |
|---|---|---|
| 1 `HANDOFF.md:567` is 124 characters | Open | It's 142 now (see minor 1). |
| 2 The status note counts the review files | Done | It now says they're committed with T386–T395 (`a5e5a360`). |

## Findings

### V33-1 (low): after a store reset, the tracker loses the radio windows, and extra Connect windows open

**Cause.** Every radio window's `RadioWindowRoot` sits under `.id(appState.databaseResetID)`
(`MeshtasticApp.swift:320-321`). Each `resetDatabaseAfterClear` (`AccessoryManager.swift:222`)
and each renumber (`AccessoryManager+FromRadio.swift:324`) swaps the view for a new one with the
same `deviceId`. SwiftUI runs the new view's `onAppear` before the old view's `onDisappear`. The
probe recorded `appear-8656`, then `appear-5693, disappear-8656`, `appear-2385, disappear-5693`,
and so on, and its set was empty after the swaps with the view on screen.

So `windowAppeared` inserts an id that is already in `shownWindows`, then `windowDisappeared`
removes it (`RadioWindowViews.swift:58-66`). The window stays on screen but is no longer counted
until it closes and opens again. The error only ever under-counts, so T393's own case (the last
window closes) still opens the Connect window. What breaks is the other direction: a Connect
window opens when it shouldn't.

**Effect 1: Clear App Data with two or more radio windows and no Connect window open.**
- `eraseAppData` resets the store (`AccessoryManager+AppData.swift:32`), then calls
  `forgetRadiosNotInStore` (`:36`).
- That function makes three `MeshPackets` calls before it sends anything
  (`AccessoryManager+ServiceRadios.swift:134,136`, `AccessoryManager+AdditionalRadios.swift:116`).
  So the swap commits first, and the tracker has none of the windows when they're told.
- Each `closesLastWindow` then returns true. `connectWindowCount` doesn't see a Connect window
  that an earlier window opened in the same send loop, because scene activation is asynchronous.
- In practice this opens one Connect window per radio window. The HANDOFF check at line 541
  ("with two radio windows, Clear App Data leaves exactly one Connect window") should catch it.

**Effect 2: any removal later in a session in which the store was reset.**
- Example: with A alone, Reset NodeDB or the config-only factory reset (`DeviceConfig.swift:320`,
  `:346`) bumps the ID. A reconnects into its window, which the tracker no longer counts.
- B then connects, and its window is counted. The user removes B: `closesLastWindow(B)` sees no
  other window and opens a Connect window, though A's window is open.
- The same happens after a renumber with several radios.

**Not affected.**
- The backup restore unmounts every window under `isDatabaseResetting` and mounts them again
  (`Connect.swift:1285-1290`, with the bump at `:1342` while they're unmounted). The order is
  right there, and it puts back windows lost earlier.
- Removing the only radio still opens exactly one Connect window. Its `radioRemoved` goes out
  before the erase (`AccessoryManager+RadioRemoval.swift:119-122`), and it is the last window
  either way.

**Suggested fix.** Count each device id in the tracker (`[UUID: Int]`): `windowAppeared` adds one
and `windowDisappeared` takes one away, and a window counts while its count is above zero. Clear
`closingWindows` only when the count goes from 0 to 1 or drops to 0, so a swap of a closing
window doesn't clear the mark. Another option is to attach the two modifiers outside the `.id`
in the `WindowGroup` closure, from `window?.deviceId`.

Add a case to `lastWindowClosing`: `windowAppeared(a)` twice, then `windowDisappeared(a)` once,
then `closesLastWindow(b, connectWindows: 0)` is false.

## Minors

1. `HANDOFF.md:567` is 142 characters: the V31 device check (Factory reset and shut down name
   the radio…) is still unwrapped. V32 minor 1 measured it before the T390/T393 edits.
2. T134's string list in T388 (`tasks.md:410`) still names the old only-radio message
   ("Removes %@ and its messages and nodes from this device…"). T390 replaced it with "Removes %@
   and erases all app data on this device, as Clear App Data does: …". T134 should take the new
   one.
3. `settings.md:42` calls the action **Erase All App Data**, but the button is **Clear App Data**
   (its confirmation button reads "Erase all app data?"). `bluetooth.md:98` says **Clear App
   Data**, and the two pages now link to each other. The label predates this work, but T390
   rewrote the line. Also in `bluetooth.md:98`, "(favorites are kept)" comes before the sentence
   saying that removing the only radio erases favorites. Scope it to the case where other radios'
   data is kept.
4. The editor's stale copies: before the next edit in Xcode, make sure it has reloaded the files
   `5305ba12` changed. Saving a stale buffer would quietly revert T390 or T393, as HANDOFF warns
   (V28-4, T389).

## Checked and found fine

- **`eraseAppData` matches the Clear App Data it replaces, step for step.** It clears the
  translation caches, deletes the backups, flushes, clears with routes, resets the container,
  resets the service radios, forgets the radios, clears notifications and refills the bundled
  catalog, and starts the network pass in its own `Task`. The only addition is the returned
  `cleared`, which Clear App Data ignores, as before.
- **Under the handshake gate.** Nothing `eraseAppData` calls takes the gate. Only the handshake
  (`AccessoryManager+Connect.swift:115`), the launch merge (`MeshtasticApp.swift:163`), the
  restore (`BackupManagement.swift:242`) and the removal (`AccessoryManager+RadioRemoval.swift:150`)
  take it, so there's no deadlock. `refreshBundledDevicesData` is local only
  (`MeshtasticAPI.swift:741-745`). The network pass isn't awaited. Holding the gate also keeps a
  restore from running while the backups are deleted.
- **The removed radio's window is told once.** `removeRadio` drops its `knownNodeNums` entries
  and sends `radioRemoved` before the erase (`:119-122`). So `forgetRadiosNotInStore`, inside
  `eraseAppData`, doesn't send it again and can't open a second Connect window for it. The
  part-way fallback (`!cleared`) still removes its data on the fresh store's actor.
- **Dialog text and decision.** The message follows `hasSeveralRadios` (`knownRadios`); the
  clear follows `storedRadios`, uncounted data and the active radios.
  - The several-radios text never comes with a clear: every radio in `knownRadios` has
    `lastConnected`, so `storedRadios` counts it.
  - The only-radio text can come without a clear, for example while another radio is in its
    first connect, or when uncounted data stops it. It then warns of more than is erased, which is
    still the safe direction (T387, V27 minor 3).
- **The Mesh Map window.** `MapWindow` dismisses itself when a scene disconnects and at most one
  scene is left (`MapWindow.swift:53-58`), so leaving it out of the count is right. With the map
  open beside the last radio window, the Connect window opens and the map stays, as two scenes
  remain.
- **W-01.** A window closed by hand is a closed scene (the radio stays connected), so
  `onDisappear` runs and the tracker doesn't count it.
- **`connectWindowCount`** uses the same filter as `showConnectWindow()`
  (`RadioWindowViews.swift:408-410`).
- **Docs and spec.** D-18, W-02, `bluetooth.md:98` and `settings.md:42` match the code, apart
  from minor 3. HANDOFF's Blocked section no longer lists T390 and T393, and the device checklist
  has the T390 and T393 checks.

## Still open

- V33-1, and the minors above.
- Strings: T134, with the new only-radio message (minor 2).
- Docs HTML: T122.
- The device checklist, including the T393 checks.
- Committing this review.
