# Review V20: merge of main into feature/multi-radio

Merge commit `3e3d204c` ("Merge main into feature/multi-radio"), 2026-10-02. Its parents are
`8eb367a5` (the branch) and `c3bb355b` (main, v2.7.23 docs rebuild). The merge base is `ed36762c`.
Main brought 11 commits since then. Not pushed; `feature/multi-radio` has no upstream.
`backup/multi-radio-pre-rebase` still points at `8eb367a5`. The earlier rebase attempt is gone and
the working tree is clean.

Checked in the files only; nothing built or run, nothing changed.

## How it was checked

- Files changed only on main (43) or only on the branch (226): compared with that side's version.
  Every difference was checked to be a deliberate adaptation.
- The 18 conflicted files: read through `git show --remerge-diff`, which shows each resolution
  against the automatic merge.
- Conflict markers: searched the whole merged tree.
- Main's new code: searched for reads of the first radio (`activeDeviceNum`, `isConnected`,
  `connectedVersion`, `checkIsVersionSupported`, `appState.router`) where the branch reads the
  window's radio.
- Bundled docs: compared with their sources.

## Findings

### M1. The `protobufs` submodule points at the old commit, undoing main's bump

- Base and branch: `e6e1d1a9`. Main: `ad0bf31e` (#2551, which bumps the protobufs and holds the
  beacon message to 60 bytes). Merge: `e6e1d1a9`.
- The remerge diff shows the automatic merge took `ad0bf31e`. The commit records `e6e1d1a9`, most
  likely because the local submodule checkout was still on the old commit when the merge was
  staged.
- The generated sources (`MeshtasticProtobufs/Sources/meshtastic/*.pb.swift`) are main's,
  identical to `c3bb355b`, so the app builds and behaves as main. But the `.proto` sources the
  submodule points at no longer match them:
  - the next regeneration would undo main's protobuf changes;
  - merging this branch into main would move main's submodule back.
- Fix: check out `ad0bf31e` in the submodule (the commit is present locally), stage `protobufs`,
  and commit. Since nothing is pushed, amending the merge works too.

### M2. Main's new coding-rate rows check the first radio's firmware (low)

- `LoRaConfig.swift:376-378`: `CodingRateRows.supportsOverride` uses
  `accessoryManager.checkIsVersionSupported(forVersion: CodingRates.overrideFirmwareVersion)`,
  which is the first radio's version. Main added it in #2548, "Hide the coding rate override on
  firmware that ignores it".
- In another radio's window, the override's toggle and slider are shown or hidden by the other
  radio's firmware. The "needs firmware 2.7.18" note can then describe the wrong radio. It changes
  only what's shown; `config.codingRate` is only written by the controls.
- Fix: `@Environment(\.windowRadio)` and
  `isVersionSupported(forVersion: CodingRates.overrideFirmwareVersion, for: windowRadio)`, as
  `supports2_8` in the same file does. With one radio the result is the same.
- This was the only first-radio read in main's new code that hadn't been switched over. The other
  four, in `BackupRestoreSection`, were adapted.

## Checked and found fine

- No conflict markers in the merged tree.
- Window routing. Main #2545 gave each window its own router and filters; the branch routes links
  to the window of their radio and adds a window per radio on the Mac. The merge combines them:
  - `WindowRouters` is the only registry. `SceneRouters`, `AppState.router`, `pendingRoute` and
    `claimPendingRoute` are gone, with no references left.
  - It takes over `SceneRouters`' jobs:
    - `popAllStacks()` pops every window and leaves each on its tab, for the store reset, the
      restore and the renumber;
    - the Mesh Map window registers as pop-only;
    - a link that arrives with no window open is held for the first window (`heldLink`).
  - The Mac's radioless link still opens a connected radio's window first (V12 Y4).
  - `MainScene` is main's, with the branch's `RadioListWindow` (Mac) and `OneWindowRadioScope` /
    `ContentView` inside it.
  - The contact-import sheet, the channel-link sheet, the badge refresh and TipKit setup all
    remain. The branch's `pendingContactToAdd` went with main's replacement; `ContactURLHandler`
    is main's.
  - Notification taps go through `windows.route(url:manager:)`. File opens go to the window last
    used.
- Node filters: Mac radio windows own a `NodeFilterParameters`. A radio renumber moves Heard By in
  every open window and in the saved choice (`moveHeardByRadio`); `.shared` no longer exists.
- Siri/CarPlay send: the conversation's radio first, then main's `Destination` switch with the
  branch's channel slots and its "no default radio" guard (R10-5). Spoken group names are logged
  `.private` (main).
- MeshPackets: store-and-forward replays dedupe on the replayed id (main), matched per sender by
  `messageKey` (branch). New rows store that id.
- Connect: main's safe-area Disconnect bar, using `link.canDisconnect` and `disconnectRadio`.
  `switchToDevice` keeps the branch's flow (no backup, clear or restore) with both
  `keepPreviousRadio` and the caller's `router`.
- Backup and restore moved from Tools to `BackupRestoreSection` (main) and read the window's radio.
  Tools' Settings link is NFC-only, as on main.
- Sent-message save: logs the sending radio (branch) and posts `meshMessagesDidChange` (main).
- `DiscoverySummaryView` has main's `offeredFrequencySlot` and the branch's `isConnected(windowRadio)`.
- Tests keep both sides:
  - main's pop-all test moved onto `WindowRouters`, with the Mesh Map window;
  - a new test for a link held until a window opens;
  - both snapshot suites (`AdditionalRadioRow`, `BackupRestoreSection`).
- Bundled docs: all 32 bundled markdown files now match their sources; on the branch 17 were
  stale. HTML and `index.json` were regenerated with them. The `copilot-instructions.md` line and
  `architecture.md` describe the window routers.
- The merge message's own count (18 files conflicted) matches the remerge diff.
