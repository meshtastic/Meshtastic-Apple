# Review V30: the V29 fixes (T389)

Branch `feature/multi-radio`, uncommitted work on top of `58671b92`. This review checks T389, the
fixes for review V29, against the files.

Since V29 there is one code change, in `DeviceConfig.swift` (`DeviceResetSection.factoryReset`),
plus edits to `docs/user/bluetooth.md`, `HANDOFF.md` and `tasks.md`, which also adds T390 and
T391. I ran `MultiRadioConnectFlowTests`, `RadioRemovalTests` and `RadioWindowTrackerTests` once
in the iOS Simulator: 65 tests, all passed, and the build changed no tracked files. SwiftLint on
`DeviceConfig.swift` is clean. `git diff -U0` was checked again. Every removed line belongs to
T386–T389, and every changed file still ends in a newline.

## The V29 findings

| Finding | Status | Notes |
|---|---|---|
| V29-1 ghost window after a full factory reset of the only radio | Fixed, with one case left: V30-1 | After the clear, `forgetRadiosNotInStore()` runs only when `resetDevice` is true (`DeviceConfig.swift:341-346`). That's right: Reset NodeDB and the config-only reset reconnect and store the radio again. It runs after `resetDatabaseAfterClear`, as in Clear App Data, so it reads the fresh store. Either the old or the re-identified radio window is subscribed when `radioRemoved` goes out. |
| Minor 1 HANDOFF | Done | Status note (lines 109-116), device checks (lines 529-552: Settings › Device, the Mac restore, the factory reset, V28-3, minor 2). T388's lost HANDOFF edits are back. |
| Minor 2 single-radio resets vs removal | Deferred | T390, the owner's call. Also recorded in HANDOFF (lines 221-226). |
| Minor 3 before the commit | Unchanged | Strings stay with T134 and the docs HTML with T122. The review files go in with the commit. |

Docs: `bluetooth.md` › Resetting or Removing a Radio now says:
- After a factory reset that clears its bonds, the only radio stops counting as one of yours, and
  its window on the Mac closes.
- With several radios, the others stay connected. The old "another connected radio takes the
  focus" was wrong since T316.

Both statements match the code. T391 takes the remaining focus-era sections.

## Findings

### V30-1. When the only radio isn't the first radio, a full factory reset doesn't disconnect it (low)

- **The cause.** With `resetDevice`, the single-radio path disconnects with
  `accessoryManager.disconnect()` (`DeviceConfig.swift:330-331`). That always acts on the first
  radio (`activeConnection`). The config-only branch next to it uses
  `session(for: windowRadio)`.
- **How the only radio ends up connected alongside.**
  - Start with A connected first and B alongside, then remove A.
  - `removeRadio` makes B the preferred radio, and nothing takes A's place (T316). B stays in
    `additionalRadios` with `activeConnection == nil`. The test "Removing the first radio with
    another connected makes that one the preferred radio" covers this state.
  - B's window still offers the resets: `isConnectedNode` counts radios alongside.
  - `hasOtherRadios` is false: no other stored radio and no other connected radio. So B's full
    factory reset takes the single-radio path.
- **What happens then.**
  - `disconnect()` finds no first radio and does nothing to B.
  - The store is cleared while B's session is still up.
  - B then reboots. That drop isn't the user's, so B's reconnect loop starts, and with its bonds
    cleared it keeps failing.
  - `forgetRadiosNotInStore()` skips B while it's connected or mid-attempt. So T389's fix may not
    apply: the window stays on a radio whose reconnect keeps failing, and that `knownRadios` no
    longer has.
  - Even when the forget lands between two attempts, the loop isn't stopped and will bring the
    window back if B ever connects.
- **Why it's low.** The reset's own Disconnect predates feature 021 (on `main` there was only one
  radio). It matters here only because T389's fix relies on that Disconnect having taken the
  radio offline.
- **Suggested fix.**
  - Capture `node.num` up front.
  - Replace the `resetDevice` branch's `disconnect()` with
    `await accessoryManager.takeRadioOffline(radioNum, reconnect: false)`, as `resetOneOfSeveral`
    does. That covers both cases: for the first radio it's `disconnect()` with auto-connect off
    and a stand-in's preferred radio restored; for a radio alongside it's a user Disconnect that
    stops its reconnect loop.
  - One behaviour change: `takeRadioOffline` swallows the Disconnect's error, so the `catch` no
    longer reports it. The reset has been sent by then, so that's fine.

## Minors

1. **The last window on the Mac.** When the removed or forgotten radio's window was the only one
   open, closing it leaves the app with no window. This now covers Remove Radio (T386), Clear App
   Data (V27-4) and the full factory reset (T389). Radios › Add Radio… and the Dock icon still get
   the user back.
   - Opening the Connect window in its place would be friendlier: `showConnectWindow()`'s check
     at `RadioWindowViews.swift:368-381`, done before `dismissWindow()` when no other window is
     attached.
   - This is the owner's call. If it's left as is, add it to the device check.
2. **HANDOFF upkeep.**
   - The status note (line 115) says "commit the three review files". With this one there are
     four (V27–V30).
   - Two checklist lines were edited without rewrapping (lines 525 and 536) and now run well past
     the file's width.

## Checked and found fine

- **Where the forget runs.**
  - Not for Reset NodeDB or the config-only factory reset. Their reconnect may not have an
    attempt yet, so forgetting there would close the window and reopen it.
  - With several radios, `resetOneOfSeveral` keeps the radio's `MyInfoEntity` (`.reset`, not
    `.remove`). After a full reset the radio still counts as one of yours and shows as off. That
    matches the docs, which only describe the forget for the single-radio case.
- **iPhone and iPad.** The forget drops the radio from `knownNodeNums`. `PreferredRadio` keeps it,
  as on `main` after a factory reset. The `.firstRadio` window shows "No device connected", as
  before.
- **Service radios.** A stale choice of radio for a service needs nothing: `radioNum(for:)`
  ignores a radio `knownRadios` doesn't have, as T389 says.
- **Tests.** Leaving out a test for `DeviceResetSection` (a view task on the shared store and
  radio) is consistent with the earlier reset paths. `radiosNotInStoreAreForgotten` covers the
  forget itself. If V30-1 is fixed by moving the radio's part into the manager, a manager-level
  test becomes possible: the only radio alongside, reset with bonds cleared, ends up offline and
  forgotten.
