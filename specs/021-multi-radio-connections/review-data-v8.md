# Review V8: data, messages and services (feature/multi-radio)

Branch `feature/multi-radio` at `e1f27349`. This pass re-checks the fix for `review-data-v7.md`
(R7-1 → T232, per-radio message pruning, the owner's choice) and the backfill change that came
with the connection fixes (T230), re-reading each in the files. I read the HANDOFF.md and
tasks.md changes first.

Tests: the full suite passes in the iOS Simulator (iPhone 17 Pro) at `e1f27349`: 3,476 Swift
Testing tests in 599 suites and 29 XCTests. I started it only once no other `xcodebuild` was
running, and ran it once. No tracked file changed.

## Status of the seventh review

| | Status |
|---|---|
| R7-1 one message cap shared by every radio | Fixed as the owner chose: with several radios in the store, each keeps its newest 50,000 (`localNodeNum`), rows on no radio count together; a store with one radio prunes the whole table as on `main`. A merged backup gets its own budget, so the merge no longer loses history to the next prune. |

Also checked: T230 asks "do other radios already have observations" in connect Step 0, before
the joining radio's event stream starts, keeps the answer on the `ConnectAttempt` (so a retry of
the same attempt reuses it), and Step 3c passes it to the drain. It skips the question for the
store's own radio when its number is known; for a radio whose number isn't known yet the answer
is computed and then unused, since Step 3c doesn't drain for the owner.

## Findings

No bugs this round. One thing to measure, which follows from the per-radio cap.

### R8-1. The message table can now be four times larger; the message screens' queries scan it

- `Helpers/MeshPackets.swift:849-877` (`pruneMessageHistory`), and the queries that read the whole
  table: `Persistence/ChannelMessageQuery.swift:114` and `DirectMessageQuery.swift:64` (sorted by
  `messageTimestamp`, filtered on `channelKey`, `localNodeNum`, `channel` or `fromUser?.num`, none
  of them indexed), `AppState.swift:88` (`refreshBadgeCount` fetches every unread row), and
  `ChannelEntity.unreadMessages` for each row of the channel list.
- With four radios at the cap the store holds up to 200,000 messages where `main` held 50,000.
  The channel and DM screens reload on every `.meshMessagesDidChange` on the main context, and
  each reload is a full scan and sort with a limit of 100. The prune pass itself is now one
  count per radio plus one for rows on no radio, every 256 texts, on the ingest actor.
- Not a defect: it's the cost of the owner's choice, and it only reaches that size for heavy
  users. T132 (memory and main-actor load under four sessions) is the place to measure it, with
  `PerformanceSeedData` seeded to four radios at the cap.
- Sure: high that the table can reach that size and the queries are unindexed; the actual cost
  needs measuring.

## Checked and found fine

- `pruneMessageHistory`: the radios come from `storedRadios()` (radios connected with this version
  or with observations, so stray rows from old stores don't split the budget); the "on no radio"
  predicate compares the optional column with an optional array, which SwiftData can express;
  a failure in the prune is caught after the message was saved, so notifications still go out,
  as before.
- A removed radio's kept channel messages (T222) now count toward the radio they moved to; its
  direct messages are deleted, so nothing is left under a radio that no longer exists.
- T230's Step 0 runs with the handshake gate already held, before any of the joining radio's
  packets, and only on the first try.
