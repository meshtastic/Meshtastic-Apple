# Review V5: data, messages and services (feature/multi-radio)

Branch `feature/multi-radio` at `7fbaf895`. This pass re-checks the fixes for `review-data-v4.md`
(R4-1 → T204, R4-2 → T205), the backfill change that came with the connection fixes (T203: the
check moved into `handleMyInfo` and matches by node number), and the rest of what changed in my
area since `5ff31a3b`. I read the HANDOFF.md and tasks.md changes first.

Tests: the full suite passes in the iOS Simulator (iPhone 17 Pro) at `7fbaf895`: 3,468 Swift
Testing tests in 599 suites and 29 XCTests, on a quiet Simulator. No tracked file changed. Neither
finding below is covered by a test.

## Status of the fourth review

| | Status |
|---|---|
| R4-1 handlers overwrote the aggregate's hops and slot | Fixed: `upsertNodeInfoPacket` and `upsertPositionPacket` skip those writes when several radios observe the node (`nodeFieldsAreAggregated`); with one radio they write as before. |
| R4-2 a failed chunk could roll back packet writes | Fixed: the drain saves what packets wrote before each next chunk. |

## Findings

### R5-1. After a 2.8 renumber, the backfill credits the old rows to the radio's old number

- `Accessory Manager/AccessoryManager+FromRadio.swift:191-200` (`renumberIfSameRadio`, then
  `backfillBeforeAnotherRadioJoins`), `:298-327` (`renumberStore` moves `PreferredRadio` but not
  `BackfillOwner`), `AccessoryManager+AdditionalRadios.swift:184`,
  `Radio Session/BackfillOwner.swift:24-36`, `MeshtasticApp.swift:167,256`.
- `BackfillOwner` records the store's radio by node number once, at launch. When that radio comes
  back from a firmware upgrade under a new node number (the 2.8 change the renumber path exists
  for), `handleMyInfo` first renumbers the store (old number → new), then calls
  `backfillBeforeAnotherRadioJoins(radioNum: new)`. The owner is still the old number, so the
  check "is this the store's own radio" fails and the drain runs with `ownRadio` = the old
  number. The old rows get a `localNodeNum` that no longer belongs to any radio, and their channel
  keys come from a radio with no `MyInfoEntity` (so none). The background pass uses the same
  stale owner.
- T203's premise is that "a peripheral id changes on a new phone, a node number doesn't"; the
  2.8 renumber is the case where it does.
- Effect: invisible while the store has one radio (the queries aren't filtered). Once a second
  radio joins, the radio's own old DMs are under a radio that isn't in the list, so they drop out
  of its filtered thread; its old channel messages have no key, so they only show in its own
  slot.
- Scenario: a Mac user with one radio (the app stays in front, so the old rows are still waiting)
  updates the radio to 2.8 firmware. At the next connect the rows are credited to the old number.
  Later they add a second radio: the first radio's old conversations are gone from its thread.
- Fix direction: in `renumberStore`, move `BackfillOwner` along with `PreferredRadio` when it is
  the renumbered radio (or run the backfill before the renumber, which then rewrites the old
  number to the new one).
- Sure: high for the code path; how many people hit it depends on how many still have old rows
  waiting when they update to 2.8.

### R5-2. Minor: other saved radio choices aren't renumbered either

- `AccessoryManager+ServiceRadios.swift:44` (`serviceRadio.<service>`),
  `Views/Nodes/Helpers/NodeFilterParameters.swift:88,195` (`nodeFilter.heardByRadio`).
- The TAK / CarPlay & Siri / Watch radio and the Heard By radio are stored by node number. After
  a renumber they name a number no radio has, so they fall back (focused radio; filter off), and
  the user has to pick the radio again. Harmless, but the same `renumberStore` place could move
  them.
- Sure: high; low impact.

## Checked and found fine

- `nodeFieldsAreAggregated` uses the keyed observation lookup (a handful of index lookups per
  NodeInfo or position packet). With several radios the node's slot now only changes with the
  focused radio's node DB (observations don't take the slot from live packets); that is the
  radio's own view of the node, which the firmware uses too, and what `channelSlot(toReach:)`
  sends on.
- The drain's save after each yield: a failing chunk only rolls back itself.
- The backfill in `handleMyInfo`: it runs with the connect's handshake gate held, before the
  radio's `MyInfoEntity` and data are stored, for a radio added alongside or switched to; the
  store's own radio (same node number) doesn't wait; later MyInfo messages (reboot refresh) only
  pay one count.
- The connection-side changes that touch data (`stopBringingBack` clearing a pending handover,
  the restore give-back marker, `PreferredRadio` after a restore hand-over) write nothing to the
  store beyond `autoConnect`.
