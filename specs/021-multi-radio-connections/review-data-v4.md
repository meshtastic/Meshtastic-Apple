# Review V4: data, messages and services (feature/multi-radio)

Branch `feature/multi-radio` at `5ff31a3b`. This pass re-checks the fixes for `review-data-v3.md`
(R3-1–R3-5, T192–T195, T197, T198) and reviews what changed in my area since `23d68e36`:
channel matching by key for CarPlay and Siri (`IntentMessageConverters.channelMessage`),
`BackfillOwner` and the backfill before any other radio connects, the async backfill drain and
merge, `reaggregate`, Your Radios, the Heard By file, the retiring actor's saves, and the two
data-side pieces of the connection fixes (`rememberRadios`, `stopBringingBack`). I read the
HANDOFF.md and tasks.md changes first.

Tests: the full suite passes in the iOS Simulator (iPhone 17 Pro) at `5ff31a3b`: 3,465 Swift
Testing tests in 599 suites and 29 XCTests, on a quiet Simulator this time (I waited until no
other `xcodebuild` was running). No tracked file changed. Neither finding below is covered by a
test.

## Status of the third review

| | Status |
|---|---|
| R3-1 CarPlay and Siri scoped by the delivering radio | Fixed: channel messages match by the CarPlay radio's channel key, or its own slot for rows without one, as `ChannelMessageQuery` does; DMs stay per radio; one radio unchanged. |
| R3-2 Switch skipped the backfill | Fixed: `BackfillOwner` records the store's radio at launch, and every connect of another radio, focused or not, drains for it first; the launch drain, merge and background pass use it too. |
| R3-3 last heard moved back with several old observations | Fixed: skipped unless the newest remaining is current; last heard never moves back, first heard never forward. |
| R3-4 Remove offered for a radio that's connecting | Fixed: radios with a connect attempt aren't listed; the label is "Not connected since the update". |
| R3-5 Heard By in UserDefaults; double-stored packets across a recycle | Fixed: the set is in a small file in Caches; a retired actor saves receptions and node updates as they happen. |

## Findings

Nothing serious this round. What's left is small; ranked most serious first. "Sure" is how
confident I am that it happens as described.

### R4-1. NodeInfo and position packets still write the delivering radio's hops and slot onto the node

- `Persistence/UpdateSwiftData.swift:534` (`channel`) and `:611-617` (`hopsAway`) in
  `upsertNodeInfoPacket`'s existing-node branch; `:769` (`channel`) in `upsertPositionPacket`.
- `processFromRadio` runs `updateAnyPacketFrom` (which aggregates) before the handler, and then
  these handlers write the delivering radio's `hopsAway` (NodeInfo) and channel slot (NodeInfo
  and every position) straight onto the node. With A hearing N directly and B at 3 hops, a NodeInfo from N that B delivers first shows
  N at 3 hops until N's next packet re-aggregates it. The slot is the one T143 keeps to the
  focused radio; sends no longer use `node.channel` with several radios (`channelSlot(toReach:)`),
  so it only shows in the node row and App Settings.
- tasks.md T042 already lists this ("last-writer-wins until the next aggregate"). It's transient;
  I note it because T143 now promises the slot comes from the focused radio only.
- Sure: high; low impact.

### R4-2. A failed backfill chunk can roll back packet writes that came in during the drain

- `Helpers/MeshPackets+BackupMerge.swift` (`drainMultiRadioBackfill`, the `catch` with
  `modelContext.rollback()`), T194.
- The drain now yields the actor between chunks so packets get through. They're written to the
  same context and saved by the debounced save. If a later chunk throws, the rollback also
  discards any of those packet writes that weren't saved yet (receptions, observation updates,
  positions and telemetry waiting for the debounced save). Text messages save at once and aren't
  affected.
- Only on a chunk failure, which the drain logs; rare.
- Fix direction: save pending changes before each chunk, or roll back only on a context that
  holds nothing else.
- Sure: high for the code; low likelihood.

## Checked and found fine

- `channelMessage` / `channelKeys(ofRadio:)`: the CarPlay counts, read-back donation, Siri search
  and the notification mark-as-read agree with the app's channel timeline; with one radio they
  are the old slot match.
- `BackfillOwner`: recorded once at launch from the preferred radio (the store's own radio on an
  upgraded store), cleared when nothing is left; a connect of the owner itself doesn't wait; the
  drain runs with the handshake gate held; `hasPendingBackfill` per connect is one count.
- The async drain and merge: packets interleave between saved chunks; the merge still drains
  first and fetches the live keys after.
- `reaggregate`, Your Radios' filtering and label, the Heard By file (one shared filter instance),
  `saveIfRetiring` in `recordReception` and `updateAnyPacketFrom`.
- `rememberRadios` only turns `autoConnect` on for rows whose peripheral was restored;
  `stopBringingBack` stops a removed radio's reconnect loop and attempts.
