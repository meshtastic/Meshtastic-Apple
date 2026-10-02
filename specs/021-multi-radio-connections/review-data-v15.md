# Data review V15: the merge of main into feature/multi-radio

Merge commit `03632328` ("Merge main into feature/multi-radio"), parents `b13061ec` (the branch)
and `c3bb355b` (`main`, docs rebuild for v2.7.23). The repo has no `develop` branch; `main` is the
upstream. The merge base is `ed36762c`. Not pushed yet (the branch has no upstream).

An earlier attempt rebased the branch onto `main` and stopped on conflicts at commit 176 of 240.
It was aborted, so the branch went back to `b13061ec` before the merge. Nothing from the rebase
is left in the history.

This is the data reviewer's check. The other reviewer's is `review-merge-main.md`.

Read only: no tracked file changed.

## Findings

### M-1. The merge moved the protobufs submodule back to the old commit

- `protobufs` at the merge base and on the branch is `e6e1d1a9`. `main` moved it to `ad0bf31e`
  (#2551, "Bump the protobufs and hold the beacon message to 60 bytes": the beacon frequency slots
  and `ack_proof_status`). Only `main` changed it, so the merge should have taken `ad0bf31e`. It
  records `e6e1d1a9` instead (`git show --remerge-diff 03632328 -- protobufs`).
- The submodule folder on disk was still at `e6e1d1a9`, so this most likely came from staging
  everything for the merge commit, which records what's checked out.
- The generated Swift in `MeshtasticProtobufs/` is `main`'s, generated from `ad0bf31e`, so the app
  builds and behaves correctly. But the pointer and the generated code no longer match. The next
  regeneration from the submodule would drop `main`'s beacon changes. A pull request from this
  branch would show the pointer going backwards.
- Fix: check out `ad0bf31e` in `protobufs` and commit the pointer, either amending the merge
  commit (it isn't pushed) or as a commit on top:

  ```bash
  git -C protobufs checkout ad0bf31e82886d794334dcc62abb80da862a8ec7
  ```

### M-2. Main's new coding-rate rows check the first radio's firmware (low)

- Found by the other review (`review-merge-main.md`, M2), confirmed in the file. I missed it: my
  search for first-radio reads in `main`'s new code didn't include `checkIsVersionSupported`.
- `Views/Settings/Config/Forms/LoRaConfig.swift:376-378`: `CodingRateRows.supportsOverride` calls
  `accessoryManager.checkIsVersionSupported(forVersion: CodingRates.overrideFirmwareVersion)`, the
  first radio's version. `main` added it in #2548, "Hide the coding rate override on firmware that
  ignores it".
- In another radio's window the override controls are shown or hidden by the first radio's
  firmware, not the window's. It only changes what's shown.
- Fix: read `windowRadio` and use `isVersionSupported(forVersion:for:)`, as `supports2_8` does a
  few lines above (`LoRaConfig.swift:209, 284`). With one radio nothing changes.

## Checked and found fine

- Files only one side changed:
  - Of the 43 files only `main` changed, all are `main`'s exact copies except `protobufs` (M-1) and
    four that had to change. Three were adapted to the branch: `MainScene.swift`, `MapWindow.swift`,
    and `BackupRestoreSection.swift` (which now reads the window's radio). The fourth,
    `Resources/docs/index.json`, was regenerated.
  - Of the 226 files only the branch changed, all are the branch's exact copies except the window
    routing (`WindowRouters.swift`), the Mac radio windows (`RadioWindowViews.swift`, which now
    gives each window its own node filters), test set-up (`AppState()` without a router) and the
    docs.
- The bundled docs under `Meshtastic/Resources/docs/markdown` match their sources in `docs/`.
- No conflict markers anywhere. The changed JSON is valid. `Localizable.xcstrings` is the branch's,
  and `main` didn't change it.
- Every conflict resolution, read in `git show --remerge-diff 03632328`:
  - Window routing: `main`'s `SceneRouters`, `AppState.router` and `pendingRoute` are folded into
    `WindowRouters`. That means `popAllStacks()` across windows, pop-only registration for the Mesh
    Map window, and a link that arrives with no window open waiting for the first window.
    Notification taps go through `windows.route(url:manager:)`.
  - `MainScene` holds the branch's changes to the app-level view code it replaced:
    `RadioListWindow` on the Mac, `OneWindowRadioScope` elsewhere, and links routed through
    `windows.route`. The scene keeps `WindowLockdownScope`. Every window still gets a router, node
    filters and lock-down state.
  - `MeshPackets`: store-and-forward replays are stored and deduped under the original id
    (`main`), keyed per sender with `messageKey` (branch). The sender is `packet.from` in both, so
    a replay lands on the live message's row.
  - Siri and CarPlay send: `main`'s `Destination` switch, with the branch's conversation radio
    first and its slot and default-radio checks in every case. The branch's conversation
    identifiers ("channel-2:r…") still parse in `main`'s destination code.
  - Backup and restore moved to `BackupRestoreSection` (`main`), with the branch's window-radio
    reads ported.
  - Connect: `main`'s Disconnect bar on the Mac, with the branch's per-radio disconnect. Switching
    radios still doesn't clear and restore the shared store.
  - A radio renumber moves Heard By in every open window's filters and in the saved choice.
  - The sent-message save posts `meshMessagesDidChange` (`main`) and logs the sending radio
    (branch).
- Mac Catalyst build at `03632328`: succeeds (own build folder, signing off; built, not run). This
  matters because the merge commit's test run (3,550 tests, iPhone 17 Pro simulator) doesn't
  compile the Mac-only code it touched, such as the Disconnect bar in `Connect.swift`. I didn't
  re-run the tests.

## Not a merge problem, for the owner

- `main` (#2545) now gives each iPad window its own tabs, filters and conversation, while 021
  treats the iPad as one window (W-04). With two iPad windows open, each shows its own radio, but
  they share `oneWindowShownRadio` and the other radios' prompts. That predates this merge.
