# Review V5: connections and focus (feature/multi-radio)

Branch `feature/multi-radio` at `7fbaf895`. V4 (`review-connections-v4.md`) reviewed `5ff31a3b`;
this pass checks the fixes since (T200–T205) and what they touch: the restore's give-back marker
expiring, the preferred radio kept after a restore hand-over, the handover reading its radio when
it fires, the backfill moved into `handleMyInfo` and matched by node number, and the drain saving
between chunks.

Files read (diff since `5ff31a3b`, then the code around it): `+AdditionalRadios`, `+Connect`,
`+Focus`, `+FocusHandover`, `+FromRadio` (`handleMyInfo`, `renumberStore`), `+RadioRemoval`;
`BackfillOwner.swift`, `PreferredRadio.swift`; `BLETransport.swift`; the views that read
`PreferredRadio` (`Settings.swift`, `Messages.swift`, `ChannelList.swift`, `UserMessageList.swift`),
and `MultiRadioBackfill` for what `ownRadio` decides.

The full suite passes in the iOS Simulator (iPhone 17 Pro): 3,468 Swift Testing tests in 599
suites and 29 XCTests.

## Where the V4 findings stand

| V4 | What | Now |
|---|---|---|
| F1 | Restore give-back marker never expired | Fixed: cleared by any focus change, Disconnect, Remove, or the radio coming back focused. |
| F2 | The radio that took over a restore stayed preferred | Changed as asked, but see G3: the preferred radio and the focused radio now disagree, and several views read the preferred one. |
| F3 | A radio removed during its handover came back | Fixed (the handover reads `handoverPrevious` when it fires). |
| F4 | The own radio waited for the backfill on a new phone | Fixed by matching node numbers, but the move into `handleMyInfo` introduces G1 and exposes G4. |

## Findings, most serious first

### G1. The backfill now runs inside the connect's 30-second config step

- `AccessoryManager+FromRadio.swift:200`, `AccessoryManager+Connect.swift:279` (the event loop
  handles one event at a time) and `320` (Step 3's 30 s timeout).
- MyInfo is the first packet of the config handshake, so `handleMyInfo` runs while Step 3 waits for
  the config to complete. The drain is awaited inside it, which holds up that radio's event loop:
  the config and its completion wait behind it. A drain longer than about 30 s times Step 3 out.
  The attempt is torn down and retried, the first drain carries on regardless (its task's
  cancellation doesn't stop it), and the retry's MyInfo starts a second drain loop over the same
  table. On a large store the first connect of a second radio fails: "Couldn't Connect" for a tap,
  or a failed focused switch. It works on a later attempt once the drain is done.
- In V4 the drain ran before Step 0, where no step timeout was running. Running it in
  `handleMyInfo` was only needed for the node number, which could also be learnt without holding
  up the event loop (for example, start the drain there but await it before Step 5, or run it from
  the connect once the number is known).
- It also runs for a MyInfo outside a connect (the config refresh after a reboot), without the
  handshake gate the comment relies on. That's rare, since the first drain usually clears it.
- Sure: high on the mechanism. It fails only when the drain takes more than about 30 s; V3's R3
  assumed drains of that size on a long-lived store.

### G2. The Messages channel list doesn't follow the focus

- `Messages.swift:173-177` (`nodeNum` is set once, when nil), `ChannelList.swift:24`
  (`node?.myInfo.channels`), `AccessoryManager+Focus.swift` (a focus change doesn't reset it).
- The Messages tab picks its radio once, from `PreferredRadio`, the first time it appears. Only a
  database reset (`databaseResetID`) rebuilds it, and focusing another radio without reconnecting
  (T072) doesn't reset the database. So after Focus This Radio, the toolbar menu or a handover,
  Messages › Channels keeps listing the previous radio's channels until the app is relaunched. A
  channel only the new focused radio has can't be opened from the list.
- On `main` a switch cleared the store and rebuilt the views, which is why this used to work.
  T083 says the list is the focused radio's channels.
- Missed in earlier rounds: it has been there since T072.
- Sure: high.

### G3. After a restore hand-over, the preferred radio isn't the focused one, and views follow the preferred one

- `BLETransport.swift:729-735`; readers: `Settings.swift:949-953` (Settings selects the preferred
  radio when it changes), `Messages.swift:174` (G2's bootstrap), `UpdateSwiftData.swift:308`,
  `MeshPackets+MultiRadio.swift:352` and `MeshPackets+RadioRemoval.swift:207-217` (the aggregate
  takes a node's channel slot from `focusedRadio: PreferredRadio.nodeNum`); `PreferredRadio.swift`
  and HANDOFF describe it as the focused radio whenever one is connected.
- T201 puts `PreferredRadio` back to A after B's restore handshake while B stays focused and A
  isn't connected. Settings' `onChange(of: PreferredRadio.nodeNum)` then selects A, so Settings
  shows the radio that isn't connected. Messages bootstraps on A (G2). The aggregate takes each
  node's channel slot from A's observation rather than the focused B's (T143 says the focused
  radio's).
- Scenario: iOS relaunches the app for B with A out of range; B takes over the restore. The user
  opens the app: B is focused, but Settings shows A's configuration and Messages lists A's
  channels.
- Sure: high on the code. Keeping "the radio to connect first at launch" separate from the
  preferred-means-focused value (or restoring it only when the app goes to the background) would
  avoid it.

### G4. A renumbered radio's old rows go to its old node number

- `AccessoryManager+FromRadio.swift:191-200` (renumber, then backfill), `326` (`renumberStore`
  moves `PreferredRadio.nodeNum` but not `BackfillOwner`), `BackfillOwner.swift:24-36`,
  `MultiRadioBackfill.swift` (`ownRadio` fills `localNodeNum` and the channel keys).
- `BackfillOwner` is recorded at launch as the radio's node number then. When that radio reports a
  new number (the 2.8 upgrade `renumberIfSameRadio` exists for), the store is renumbered, but the
  owner isn't. Straight after, `backfillBeforeAnotherRadioJoins` sees a number that differs from
  the owner's and drains, attributing every old message to the old number: `localNodeNum` points
  at a radio no `MyInfoEntity` has, and channel keys come out empty (that radio has no channels
  any more). With one radio nothing shows it (single-radio queries aren't filtered by radio).
  Once a second radio joins, those old direct messages drop out of every radio's thread and the
  old channel messages can't be matched by key. The single-radio user also waits for the drain on
  that reconnect, under G1's timeout.
- It needs a store that was never backfilled (a Mac kept in front, or a single-radio store after
  T186) and a radio renumbered by a firmware update, both plausible for this release.
- Sure: high on the code. `renumberStore` could move the owner along with the preferred radio.

## Checked and found fine

- The give-back marker: cleared in `focusConnectedRadio` (every focus change, including a
  handover), on Disconnect/Remove, and when the radio reconnects as the focused one; the pending
  attention focus and the give-back don't fight (the first focus clears the marker).
- The handover reads its radio when it fires and `stopBringingBack` clears it for a removed radio;
  T171's carry-forward still works because `scheduleFocusHandover` always sets `handoverPrevious`
  before creating the task.
- The drain saves pending changes after each yield, so packets handled between chunks aren't
  rolled back by a later chunk's failure.
- Matching the owner by node number keeps the store's own radio from waiting, whatever its
  peripheral id (the F4 case), except after a renumber (G4).
- Single radio: no launch wait; connect steps unchanged; nothing in this round's changes runs for a
  single-radio store except the owner check, which skips, apart from G4.
