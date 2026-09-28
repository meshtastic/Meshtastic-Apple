# Review V7: data, messages and services (feature/multi-radio)

Branch `feature/multi-radio` at `d89664e6`. This pass re-checks the fix for `review-data-v6.md`
(R6-1 → T222) and the backfill change that came with the connection fixes (T220), and takes a
fresh look at how the store-wide limits behave now that every radio shares one store. I read the
HANDOFF.md and tasks.md changes first, and every claim below was re-read in the files.

Tests: the full suite passes in the iOS Simulator (iPhone 17 Pro) at `d89664e6`: 3,473 Swift
Testing tests in 599 suites and 29 XCTests. I started it only once no other `xcodebuild` was
running, and ran it once. No tracked file changed. The finding below isn't covered by a test.

## Status of the sixth review

| | Status |
|---|---|
| R6-1 a removed radio's kept channel messages in the wrong channel | Fixed: on removal, each kept message moves to a remaining radio that has its channel (the preferred radio first), with that radio's slot and the key filled in. A reset leaves them on the radio, which stays. |

Also checked: T220 decides "another radio already has observations" once, before the drain's
first chunk, so packets let through between chunks no longer stop the store radio's observations
halfway. Background passes still decide per chunk, which is right there (nothing else joins
mid-pass).

## Findings

### R7-1. All radios now share one 50,000-message cap, so merged history can be pruned straight away

- `Helpers/MeshPackets.swift:720` (`maxTotalMessages = 50_000`), `:741`
  (`messagePruneInterval = 256`), `:2162-2180` (the prune in the text handler),
  `Persistence/BackupMerge.swift` (the merge adds messages without looking at the cap).
- Every 256 incoming texts the handler counts all messages and, above 50,000, deletes the
  oldest by timestamp, direct messages included, whichever radio they belong to. That's `main`'s
  policy, but on `main` the store held one radio and each radio's history sat in its own backup,
  so each radio effectively had its own 50,000. Now the radios share one.
- Two consequences:
  - The backup merge (D-09) can take the store over the cap at once. A store with 45,000 messages
    that merges a backup of 20,000 is 15,000 over; about 256 texts later the 15,000 oldest go,
    which are mostly the history the merge just brought in. The backup is marked merged, so it
    isn't brought in again (the file stays, for a full restore). FR-027 says existing data
    upgrades without loss.
  - Afterwards, a radio on a busy mesh pushes out the other radios' oldest messages, their direct
    messages included.
- Scenario: if the owner's always-on Mac radio has a history close to the cap (I haven't seen the
  store), the other radios' backups in that container are merged at the first launch of the new
  build, and within the next few hundred messages most of what the merge added is deleted again.
- The fix is a policy choice for the owner, so here are the options:
  - Raise the cap with the number of radios in the store (for example 50,000 per radio): closest
    to `main` per radio, but the store can grow to four times its size today.
  - Prune per radio (`localNodeNum`), each radio keeping its newest 50,000: the same budget per
    radio as `main`, costs one count per radio at each prune pass.
  - Keep one cap but never prune direct messages first: keeps conversations, and channel traffic
    absorbs the limit.
  - Whichever it is, the merge should not add more than the cap leaves room for, or it should add
    the newest first so that what a prune removes is the oldest.
- Sure: high for the code path; how often it bites depends on history size (people who reach
  50,000 on one radio today).

## Checked and found fine

- T222: kept messages get the remaining radio's `localNodeNum`, its slot for the key and the key
  itself when the row had none; every kept key has a slot (the shared-key set and the slot map
  come from the same radios); the preferred radio's slot is used first, then the lowest radio
  number's; direct messages are still deleted; a moved message that the removed radio sent is
  now shown as another node's (the radio is no longer the user's), with no resend offered.
- T220: the drain passes the decision to every chunk; `runChunk`'s default (`nil`) still checks
  each time for the background pass.
- The other shared caps: the node cap (10,000, least recently heard first, favorites kept) evicts
  merged backups' old nodes first, which is the right order; the position and telemetry caps are
  per node, so sharing the store doesn't change them; receptions have their own retention.
