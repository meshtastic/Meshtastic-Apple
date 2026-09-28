# Review V7: connections and focus (feature/multi-radio)

Branch `feature/multi-radio` at `d89664e6`. V6 (`review-connections-v6.md`) reviewed `1e8a6ac9`;
this pass checks the fixes since (T220–T222). T222 (a removed radio's kept channel messages) is data
handling, left to the data review; the connection side of removal is unchanged.

Files read (diff since `1e8a6ac9`, then the code around it): `+Discovery`, `AccessoryManager.swift`
(`connectToPreferredDevice`, the event loop's `updateAnyPacketFrom` call), `+Connect` (Steps 3–5),
`PreferredRadio.swift`; `MeshPackets+BackupMerge.swift` (`drainMultiRadioBackfill`),
`MultiRadioBackfill.swift` (`runChunk`, `backfillObservations`, `otherRadiosHaveObservations`),
`UpdateSwiftData.swift` (observation writes); `MultiRadioBackfillTests.observationGateDecidedAtStart`.

The full suite passes in the iOS Simulator (iPhone 17 Pro): 3,473 Swift Testing tests in 599
suites and 29 XCTests, run with the simulator to itself.

## Where the V6 findings stand

| V6 | What | Now |
|---|---|---|
| H1 | The joining radio's packets stopped the owner's observation backfill | Partly fixed: the answer is fixed when the drain starts, but the joining radio can record observations before that. See I1. |
| H2 | The focused radio wasn't reconnected at once while the override was set | Fixed: auto-connect takes the connect-first radio or the preferred one. Side effect in I2. |

## Findings

### I1. The joining radio usually records an observation before the drain decides, so the owner gets none

- `MeshPackets+BackupMerge.swift:45` (decided at the drain's start),
  `AccessoryManager+Connect.swift:279` (the event loop runs on its own),
  `368-375` (Step 3c), `335` (Step 3a, focused connects only), `AccessoryManager.swift:1123`
  (every packet writes the receiving radio's observation).
- The firmware delivers the packets it queued during the handshake as soon as the config is
  complete. The event loop handles them straight away, and each one writes the joining radio's
  observation. The stepper takes several more hops to reach the drain: the step returns, the
  `SequentialSteps` actor starts Step 3c, Step 3c awaits `hasPendingBackfill()` on the ingest
  actor, then awaits the drain, which only then asks whether another radio has observations. On a
  switch to a new focused radio, Step 3a's catalog refresh widens the gap further.
  If one queued packet was handled in that time, `othersObserved` is true and the drain creates no
  observations for the store's radio at all, where V6's version at least created the first
  2,000. The consequences are H1's, for every node: after the joining radio's node DB, the
  favorite, ignored and verified flags the user set through the first radio take the joining
  radio's values until the first radio's next node DB.
- The new test starts from "the first chunk runs before anything else", which is the part in
  doubt; nothing tests Step 3c's timing.
- Scenario: as H1, busy mesh, first time adding B. B's queued packets arrive with its config
  complete; the drain finds B's observations and creates none for A.
- Sure: medium-high. It's a race, but the event loop has the shorter path, and a busy mesh (the
  case that matters) always has packets queued. Leaving the joining radio out of the check
  (`otherRadiosHaveObservations(than: owner, excluding: radioNum)`), or asking before its first
  packet is handled, would close it.

### I2. With both radios in range at launch, whichever is seen first wins, and the override goes

- `PreferredRadio.swift:56` (`connectsAutomatically`: the override or the preferred radio),
  `AccessoryManager+Connect.swift:416` (a focused connect's Step 5 clears the override).
- The override exists so the radio the restore passed over (A) connects first at the next launch.
  Discovery now auto-connects either A or B, whichever it sees first. If B advertises first, B
  connects as focused and its Step 5 clears the override, so A comes back alongside, not as the
  focus. The give-back marker from the restore is in memory, so it's gone after the relaunch too.
- Sure: high; low impact (both radios still connect). Taking the preferred radio only once the
  focused radio has dropped mid-session, or waiting a moment for the override radio at launch,
  would keep T212's order.

## Checked and found fine

- H2's fix: a focused radio that drops while the override is set is reconnected by discovery at
  once; `connectToPreferredDevice` with a discovered device connects that device, and without one
  tries the override and then the preferred radio.
- The drain's other parts (messages, channel keys) don't depend on the gate decision and still
  complete across chunks; background passes still check afresh each chunk.
- Single radio: no override and no joining radio, so neither change applies; the owner check skips
  the store's own radio.
