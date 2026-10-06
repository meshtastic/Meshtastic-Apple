# Review V35: the merge of `main` (T398)

Branch `feature/multi-radio` at `1efbaf6d`, the merge of `main` up to `8425daa6` (#2584), working
tree clean. This review checks how the conflicts were resolved, and whether `main`'s new code that
merged without a conflict still holds with several radios.

## What came in

- `main`'s 25 commits, `c3bb355b..8425daa6`. 22 files were in conflict. Of those that touch
  feature 021:
  - **Heard on current LoRa** (#2575, #2577, #2580–#2583): the radio's
    `NodeInfo.heard_on_current_lora` answers, stored on the shared node rows. They drive a marker
    on rows, a hide filter, and the unheard-nodes notice with **Remove Them**.
  - **#2404:** only an owned config completion stamps `lastConfigRefresh`.
  - **#2584:** a BLE radio iOS restores asks for its config again.
  - Also #2478 (DM summaries off the main actor), #2557 (scroll follow), #2566 (Wi-Fi OTA),
    #2569 (confirmed key replacement), and #2567 and #2568 (already on the branch).
- The merge's own additions:
  - `soleConnectedSession`, `heardOnCurrentLoraSession` and the
    `reportsHeardOnCurrentLora(on:)` / `(forRadio:)` pair.
  - `clearHeardOnCurrentLoraForSeveralRadios` and `MeshPackets.clearHeardOnCurrentLora`.
  - `MultiRadioUnheardOnCurrentLoraTests`.
  - Docs in `nodes.md` and `swiftdata.md`, and T398.

## How it was checked

- **Resolutions:** read with `git show --remerge-diff`, file by file, against both parents.
- **Silent conflicts:** listed `main`'s added lines that read single-radio state
  (`activeDeviceNum`, `activeConnection`, `isConnected`, `lastConfigRefresh`,
  `reportsHeardOnCurrentLora`, `nodeDatabaseSavedAt`, …) and checked each file where they
  survive.
- **Backup import:** a script compared the fields `main`'s inline copies set with the branch's
  `copied(_:)` helpers. None is missing, and `heardOnCurrentLora` was added to the node copy.
- **Tests:** one run of `MultiRadioUnheardOnCurrentLoraTests`, `RadioSessionTests`,
  `NodeBackupRestoreFieldTests`, `DirectMessageSummaryTests`, `MultiRadioConnectFlowTests`,
  `RadioRemovalTests` and `RadioWindowTrackerTests` in the iOS Simulator. 94 tests in 7 suites,
  all passed. The build changed no tracked files. The merge commit reports the full suite passing.
- **SwiftLint:** each parent's copy of the 20 resolved Swift files was linted against HEAD's.
  HEAD's violations match the branch parent's exactly, so there are no new ones.
- **Resources:** `Localizable.xcstrings` and `Resources/docs/index.json` are valid JSON. The
  catalog drops the stale "not heard since you changed settings" string, as `main` does.

## Findings

### V35-1 (medium): with one radio connected, the unheard-nodes notice offers to remove the user's other radios' nodes

**Where it comes from.** `main`'s notice counts two kinds of nodes as removable
(`UnheardNodesBanner.swift:194-200`):
- nodes the radio reported unheard, and
- "app only" nodes: no answer stored, once a node database has been saved this session.

On `main` the store is one radio's, so a node with no answer after that radio's dump is one the
radio dropped. Here the store also holds every other radio's nodes, and none of them has an
answer:
- only the radio connected alone stores answers;
- `markAbsentFromRadio` sets every node outside its dump back to unknown
  (`MeshPackets.swift:1184-1191`);
- `clearHeardOnCurrentLora` does the same for what the connected radios observed (`:1170-1182`).

The candidates are every node that isn't a favorite, except the window's own radio
(`UnheardNodesBanner.swift:211-214`). So with A connected alone, after A's dump, every node only
the user's other radios have heard counts as "app only". That includes those radios' own node
rows, unless A heard them too. Favorites are safe: a node is a favorite if any radio has it as
one (`MeshPackets+MultiRadio.swift:392`).

**When it shows.** A is alone, on firmware 2.8.1+, its dump is saved, and at least half of A's
answered nodes are reported unheard (`UnheardOnCurrentLora.swift:37-39`), as after a preset
change on A. The headline count then includes B's nodes. The text says "Your radio has not heard
them … or no longer has them", but A never had them.

**What Remove Them does to them.** The app-only branch (`UnheardNodesBanner.swift:250-254`)
deletes each node and its user from the store:
- **Another radio's own node row:** its cascading config rows go with it
  (`NodeInfoEntity.swift:53-80`: Device, Display, Bluetooth, Canned Message, Detection Sensor,
  Ambient Lighting, Audio, Mesh Beacon). That radio's `MyInfoEntity` also loses its node, until
  it reconnects.
- **The contacts' direct messages** lose their user, as Delete Node does to them.
- **Observations:** the node's `NodeObservationEntity` rows are left behind. `removeNode` deletes
  them (`AccessoryManager+ToRadio.swift:1502`, T146), but this path doesn't call it.

**Before the merge.** The branch's notice (`LoRaConfigChange`) also drew on the whole store:
nodes not heard since an in-app LoRa change on A. So B's nodes could be offered then too. The
merge widens it in two ways:
- the offer no longer needs an in-app change on A;
- the "app only" category takes in every other radio's node each time it shows.

**Suggested fix.**
- Limit the candidates to nodes the window's radio has an observation of
  (`NodeObservationEntity.radioNum == connectedNodeNum`). That keeps `main`'s meaning: nodes A
  had and dropped.
- Leave out every stored radio's own node.
- Delete the app-only nodes' observations with them (`NodeObservationEntity.delete(ofNodes:in:)`).
- The simpler, closest-to-`main` alternative: offer the notice only for a single-radio store
  (`storedRadios` count ≤ 1).
- Add a test with a node only B observed.

### V35-2 (low): the previous radio's answers count as the next radio's until its dump is saved

**The claim.** `reportsHeardOnCurrentLora(forRadio:)` (`AccessoryManager.swift:1706`) treats the
stored answers as `radioNum`'s whenever it's the only radio connected and sends the field. They
only become its own when its dump is saved (`markAbsentFromRadio`, `:1535`).

**When it's wrong.** If B answered before (connected alone earlier in this run, or at the last
launch), B's answers stay on the shared rows. A then connects alone. From when A reports its node
number until A's dump is saved (up to the 120 s Step 5a wait on a large mesh):
- A's rows show B's markers;
- the hide filter hides nodes by B's answers (`NodeList.swift:705`, `UserList.swift:471`);
- the notice can offer B's reported-unheard nodes under A. The app-only part waits for
  `nodeDatabaseSavedAt`, which `closeConnection` resets (`:828`).

**With several radios connected.** `clearHeardOnCurrentLora` only clears nodes the connected
radios observed. Nodes only an offline radio observed keep that radio's answers, and their
markers and the hide filter still apply in every window. `nodes.md:111` says the app keeps no
answers while several are connected.

**On `main`** this can't happen: the store holds one radio's data at a time.

**Suggested fix.** Record which radio the stored answers belong to. When a different radio
becomes `heardOnCurrentLoraSession`, or a second radio connects, clear every answer rather than
only those on observed nodes. `nodes.md:111` then holds as written.

## Minors

1. **The editor has stale copies again**, this time of three resolved files. Saving any of them
   from Xcode would undo the merge's resolution in that file:
   - `AccessoryManager.swift`: the editor serves 1,817 lines, the disk has 1,961.
   - `UpdateSwiftData.swift`: the editor still has the pre-merge `updateAnyPacketFrom` signature.
   - `MeshPackets.swift`: the editor has no `clearHeardOnCurrentLora`.

   Reload them before the next edit, and check with `git diff` (T389, T396).
2. **Two doc comments moved off their functions in the resolution.**
   - `AccessoryManager.swift:1681` ("Whether the connected radio reports
     NodeInfo.heard_on_current_lora") now heads `soleConnectedSession` (`:1684`). The
     `reportsHeardOnCurrentLora` property has none.
   - `MeshPackets.swift:1165-1167` (`markAbsentFromRadio`'s "After a full node database
     download…") now heads `clearHeardOnCurrentLora` (`:1170`). `markAbsentFromRadio` (`:1184`)
     has none.

## Checked and found fine

- **#2404 with sessions.**
  - The teardown cancels each session's own config refresh (`tearDown`), replacing `main`'s
    manager-wide cancel in `closeConnection`.
  - Every `wantConfig` registers an owner (`sendWantConfig`), so the owned-completion rule still
    stamps after a connect, a restore and a refresh.
  - A radio other than the first sends `objectWillChange` for the import's automatic check, and
    the import screen reads the window's radio.
- **Download tracking.**
  - Only the radio connected alone opens the tracking (`sendWantDatabase`, `:731-737`) and adds
    dump numbers (`AccessoryManager+FromRadio.swift:372`).
  - Only its requested dump runs `markAbsentFromRadio` (`:1519-1545`).
  - The clear runs at Step 1 once the second session is registered
    (`AccessoryManager+Connect.swift:315-324`). `connectedRadioCount` counts a radio still
    connecting (`AccessoryManager+AdditionalRadios.swift:54-56`), so it runs as soon as one starts.
- **LoRa change refresh.** `refreshNodeDatabaseAfterLoRaChange(forRadio:)` gets `to.num` from the
  LoRa screen, so a remote node's save doesn't trigger it, as with `main`'s check. It waits on
  the session rather than on `isConnected`.
- **`LoRaConfigChange` is gone on both sides.** The branch's `previous`/`updated` comparison in
  `LoRaConfig` only fed it, so dropping it is right.
- **Backup import.** The `copied(_:)` helpers set every field `main` copies, and node copies now
  include `heardOnCurrentLora`.
- **#2478.** The summary actor isn't per radio, and neither was the branch's previous summary.
  The window's radio is still left out of the list.
- **#2584.** `completeFirstRestore` always asks for the config. Radios restored alongside
  reconnect with a full connect.
- **#2566.** The window's radio is used throughout, and `releaseRadioForUpdate` replaces
  `disconnect()`.
- **#2557, #2569, #2578.** `main`'s scroll rule with the branch's radio arguments, the key
  replacement with `receivedBy`, and the Connect preset line on the window's radio.
- **#2568, #2567.** `main`'s test file and wording, as T398 says.

## Still open

- V35-1, V35-2 and the minors.
- Per-radio heard-on-current-LoRa answers: the owner's call, per T398. V35-1 and V35-2 are what
  remains while the answers are shared.
- Strings: T134. Docs HTML: T122 (`nodes.md`, `whats-new.md` and the docs index changed).
- The device checklist, with a check for V35-1 if fixed: A alone after a preset change, and a
  node only B has heard isn't offered.
- Committing this review.
