# Review V37: the V36 fix (T401), T402, and per-radio heard-on-current-LoRa (T403)

Branch `feature/multi-radio` at `b9801569`, working tree clean. This review checks the three commits
since V36 (`0cf439a2`) against the files.

## What changed since V36

- **`4c44a75e` (T401), the V36 fix.** Remove Them's app side runs on the packet actor
  (`MeshPackets.removeUnheardNode`): it saves pending writes, reads the node's observations as they
  are now, and either deletes the node with its user and every observation, or deletes only this
  radio's observation and rewrites the node (`NodeObservationEntity.reaggregate`). The loop stops
  once the window's radio no longer counts.
- **`42bbf6d9` (T402).** Remove Them also kept a node when another stored radio was on the window's
  radio's network, D-18's second half.
- **`b9801569` (T403), the owner's call.** Each radio's answer lives on its own
  `NodeObservationEntity.heardOnCurrentLora`, a new optional field:
  - it comes from the radio's node database (`recordNodeDBObservation`);
  - it's set true when the radio hears the node over LoRa (`updateAnyPacketFrom`);
  - it's cleared for nodes its download leaves out (`markAbsentFromRadio(presentNums:radioNum:)`).

  Downloads are tracked per `RadioSession`, and `nodeDatabaseSavedAt` and
  `radiosAwaitingNodeDatabaseAfterLoRaChange` are published by radio. Views read the window's
  radio's answers through `RadioLoraAnswers` (a fresh context): the node list, map and contacts
  through `UnheardOnCurrentLoraRefresh`, and node detail and the notice directly.

  Gone: the one-radio claim (T399), the clear when a second radio connects, and T402's same-network
  keep. The bundled docs were rebuilt.

## How it was checked

- **Tests:** one run of `MultiRadioUnheardOnCurrentLoraTests`, `UnheardOnCurrentLoraTests`,
  `RadioRemovalTests`, `SchemaHistoryUpgradeTests`, `NodeBackupRestoreFieldTests`,
  `RadioSessionTests`, `MultiRadioConnectLifecycleTests`, `MultiRadioIngestTests` and
  `NodeListRowRefreshDecisionTests` in the iOS Simulator. 107 tests in 9 suites, all passed. The
  build changed no tracked files.
- **A temporary probe** (deleted afterwards) for V37-1: a `NavigationSplitView` in a regular-width
  window whose detail column shows the same child view type for the selected item, as
  `NodeList.detailContent` does. After the selection changed from 1 to 2, the child's body ran with
  2, but its `.task(id:)` keyed without the item didn't run again (`shown=[1]`, `bodies=[1, 1, 2]`).
- **SwiftLint:** the 25 Swift files changed since `0cf439a2`, linted at both commits, give the same
  violations (body lengths that were already over).
- **Removed lines:** every app-code line removed since `0cf439a2` belongs to T401–T403: the claim,
  `HeardOnCurrentLoraAnswers`, `soleConnectedSession`, `heardOnCurrentLoraSession`, the
  several-radio clear, the manager-wide download tracking, T402's `sharesNetworkWithAnotherRadio`,
  and the views' reads of the node's own answer. Nothing else is undone.
- **Bundled docs:** a rebuild into a temporary folder matches `Meshtastic/Resources/docs`
  exactly, apart from the screenshots and `.gitkeep` files the build doesn't produce.

## The V36 findings

| Finding | Status | Notes |
|---|---|---|
| V36-1 Remove Them's keep path on the main context, from a snapshot | Fixed (T401) | On the actor, from current observations; `removalUsesCurrentObservations`. |
| Minor 1 `nodes.md` on when markers come back | Done, then rewritten by T403 | Matches per-radio answers now. |
| Minor 2 the result count | Left as `main` has it | The confirmation says what stays. |
| T402 same-network keep | Undone by T403 | The owner's call; see minor 3. |

## Findings

### V37-1 (low): on iPad and Mac, node detail keeps the previous node's "Not heard on current LoRa" when you select another node

**Before T403** the label read `node.isUnheardOnCurrentLora` in the body (`NodeDetail.swift:538`),
so it was always the shown node's.

**Now** it's `@State` (`:133`), set by `refreshUnheardOnCurrentLora()` (`:135-138`), which runs from:
- `.task(id: accessoryManager.radioLoraAnswersKey(for: windowRadio))` (`:179`): the window's radio
  and when its node database was last saved; the node isn't part of the key;
- `heardOnCurrentLoraDidChange` (`:182`).

**The problem.** In the split view (iPad at regular width, and the Mac), the detail column shows
`NodeDetail` for `router.selectedNodeNum` in the same place for every selection
(`NodeList.swift:87-94`), with no per-node `.id`. So SwiftUI keeps the view and its state when the
selection changes. The probe shows the body runs with the new node but the task doesn't run again.
The label then shows the previous node's answer:
- a node that is heard can show **Not heard on current LoRa**;
- a node that isn't heard can show nothing.

It stays wrong until the radio's next node database save or the next answer change anywhere.

**Not affected:** iPhone and compact width (the stack pushes a new `NodeDetail`), the map's sheet,
and Messages' pushed detail.

**Suggested fix.** Key the task on the node too: a small `Equatable` key holding `nodeNum` and
`radioLoraAnswersKey(for: windowRadio)`. Alternatively, give the split view's detail `.id(selectedNum)` in
`NodeList.detailContent`. That also covers `NodeDetail`'s other per-node `@State`
(`latestPosition` and the metrics), which today relies on `.onChange(of: node.lastHeard)`
happening to differ between the two nodes; that part is older than T403. Add a device check:
on iPad, select a node with the marker, then one without it.

## Minors

1. **Comments that still describe the one-radio claim or T402:**
   - `LoRaConfig.swift:170-172`: "(only when it's the only radio connected, feature 021)". Every
     connected radio is asked now.
   - `UnheardNodesBanner.swift:53-59` (`UnheardNodesRemoval`): "only the radio connected on its
     own has answers". Each radio has its own.
   - `MeshPackets+RadioRemoval.swift:257`: "`removeRadioData`'s rule for one node". Since T403,
     `removeRadioData` still keeps nodes on a shared network and Remove Them doesn't, so it's only
     the first half of that rule.
   - `NodeInfoEntity.swift:29` ("Whether the connected radio has heard this node…") and
     `NodeInfoEntityExtension.swift:332`. Every connected radio writes the field now, so with
     several radios it's whichever wrote last. Say that it's `main`'s copy and that views don't
     read it, as `swiftdata.md:121` does. Optionally, also drop it from `NodeRowRefreshKey`
     (`NodeListItem.swift:36-46`), where it only causes extra row refreshes when another radio's
     download rewrites it.
2. **HANDOFF's status note, lines 124-133.** It still says that "here only the only radio connected
   answers it, and a second radio puts the answers back to unknown (`heardOnCurrentLoraSession`)".
   It also says that per-radio answers "are left for the owner", and that the answers are recorded
   as one radio's (`HeardOnCurrentLoraAnswers`). Line 139 corrects all of this, but someone picking
   the work up reads the stale version first. Rewrite the paragraph to describe the current state,
   and keep T399's history as one clause.
3. **Record T403's Remove Them rule in `spec.md`.** D-18 (`spec.md:41`) still says nodes stay when
   another radio is on the same network. T402 was written to satisfy that line, and T403 undid it.
   Without a note at D-18, or a new decision row, the next reviewer will raise it again. The note:
   Remove Them keeps a node only while another radio still has it (its observation), not for a
   shared network (owner, 2026-10-05).
4. **Optional: Remove Them's re-check reads saved answers only.** `RadioLoraAnswers.answer`
   (`UnheardNodesBanner.swift:299`) reads through a fresh context. A node the radio heard in the
   last few seconds, whose `true` is still waiting in the actor's debounced save, still gets
   removed, from the radio too. Before T403 the main-context node had the same delay, and the node
   comes back when it's next heard, so this isn't a regression. If it's worth closing, ask the actor
   for the answer after it saves pending writes, before `sendRemoveNode`.

## Checked and found fine

- **Downloads per session.**
  - Every connect (Step 5) and every LoRa-change refresh goes through `sendWantDatabase(on:)`,
    which resets the session's tracking.
  - `handleNodeInfo` collects the dump's numbers on the session.
  - At `NONCE_ONLY_DB`, `markAbsentFromRadio(presentNums:radioNum:)` clears only that radio's
    observations.
  - `nodeDatabaseSavedAt[radioNum]` is set only for the session's current request while it's still
    the radio's connection (`isStillConnected`). That includes a radio still connecting, which is
    already in `additionalRadios`.
- **Two radios downloading at once.** Each writes its own observations. Only the unread shared field
  is last-writer-wins.
- **Teardown.** `forgetNodeDatabaseState` clears the radio's published state in `tearDown` and in
  `closeConnection`'s branch without a session. A completion that lands after the teardown publishes
  nothing.
- **LoRa change.** Both callers pass the radio's node number (`LoRaConfig` `to.num`, the beacon
  join's `deviceNum`), so `connectedSession(forRadio: nil)`'s fall-back to the first radio isn't
  reached. A remote node's save finds no session and does nothing.
- **Older firmware alongside.** No answers on its observations, no heard-now, and
  `reportsHeardOnCurrentLora(forRadio:)` is false, so there's no notice in its window.
- **A disconnected window.** It keeps its radio's markers (`answeringRadioNum` falls back to
  `radioNodeNum`). The notice needs the radio connected.
- **Views.**
  - Every app call site of `NodeListItem` and `NodeListItemCompact` passes the window's answer;
    only previews fall back to the node's.
  - The node list re-filters every 350 ms and rows re-key on the answer.
  - The map's cache key includes the set while hiding.
  - Contacts filter by the set.
  - The lookup runs from a view task, not a body (T163), on the same main-thread pattern as
    Heard By.
- **The notice.**
  - The denominator, the reported-unheard count and app-only are all the window's radio's, with its
    own `nodeDatabaseSavedAt` and LoRa-change wait.
  - The loop now stops only when the radio goes. That's right: a second radio connecting no longer
    changes this radio's answers.
- **Remove Them (T403).**
  - `removeUnheardNode` keeps a node while another radio has an observation of it, and deletes only
    this radio's observation and answer.
  - Otherwise it deletes the node, its user and every observation.
  - It posts the change so the windows look the answers up again.
- **Schema.** An optional attribute added to a live model is D-16's rule (HANDOFF:326).
  `SchemaHistoryUpgradeTests` pass, and backups copy the field (`NodeBackupManager+Copies.swift:341`).
- **Upgrade from `main`.** The backfill doesn't copy the node's answer into the radio's observation,
  so a window shows no markers until that radio's first node database. The notice waits for that
  download anyway, so nothing is offered from missing data.
- **Renumber.** The answers move with the observations (`NodeRenumber`).
- **The old `multiRadio.heardOnCurrentLoraRadioNum` default.** Only builds of T399–T402 wrote it,
  and none shipped. It's harmless.
- **Docs.** `nodes.md:105-111` and `swiftdata.md:121` describe per-radio answers and Remove Them as
  the code does. HANDOFF's T403 device check covers the A/B LongFast to LongTurbo case.

## Still open

- V37-1 and the minors.
- Strings: T134 (with T400/T403's confirmation text).
- T122: the bundle matches its sources at `b9801569`. The owner's "rebuild as the last step before
  the PR" still applies to any later doc change.
- The device checklist (T399–T403), plus V37-1's check if fixed.
- Committing this review.
