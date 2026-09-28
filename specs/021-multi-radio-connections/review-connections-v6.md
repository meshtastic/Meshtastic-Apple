# Review V6: connections and focus (feature/multi-radio)

Branch `feature/multi-radio` at `1e8a6ac9`. V5 (`review-connections-v5.md`) reviewed `7fbaf895`;
this pass checks the fixes since (T210–T214): the backfill as connect Step 3c, Messages following
the focused radio, the connect-first override kept apart from the preferred radio, and the
backfill owner and saved radio choices following a renumber.

Files read (diff since `7fbaf895`, then the code around it): `+Connect` (Step 3c, Step 5),
`+AdditionalRadios`, `+Discovery`, `+Focus`, `+FocusHandover`, `+FromRadio` (`renumberStore`,
`moveSavedRadioChoices`), `+RadioRemoval`; `PreferredRadio.swift`, `BackfillOwner.swift`;
`BLETransport.swift`; `Messages.swift`; and for Step 3c, `MultiRadioBackfill.runChunk` /
`backfillObservations`, `drainMultiRadioBackfill`, and `updateAnyPacketFrom`'s observation writes.

The full suite passes in the iOS Simulator (iPhone 17 Pro): 3,471 Swift Testing tests in 599
suites and 29 XCTests. Another session was running the suite on the same simulator when this
round started; this run waited until it had finished and ran alone.

## Where the V5 findings stand

| V5 | What | Now |
|---|---|---|
| G1 | Backfill inside the 30 s config step | Fixed: Step 3c has no timeout and doesn't hold up the radio's event loop. See H1 for what running it after the config changes. |
| G2 | Messages channel list didn't follow the focus | Fixed (`onChange(of: activeDeviceNum)`; bootstrap from the focused radio). |
| G3 | Preferred radio ≠ focused radio after a restore hand-over | Fixed: the preferred radio stays the focused one; a separate connect-first override decides launch order. One side effect in H2. |
| G4 | Renumber left the backfill owner behind | Fixed (`BackfillOwner.renumber`), and the saved radio choices move too. |

## Findings

### H1. On a store with more than 2,000 nodes, the joining radio's live packets stop the owner's observation backfill

- `AccessoryManager+Connect.swift:368-376` (Step 3c, after the config),
  `MeshPackets+BackupMerge.swift:44-49` (chunks of 2,000, yielding between them),
  `MultiRadioBackfill.swift:124-128` (`backfillObservations` creates nothing once any other radio
  has an observation), `UpdateSwiftData.swift:296` (every packet creates the receiving radio's
  observation).
- Once the config handshake is complete, the firmware starts sending the joining radio's live
  mesh packets, and Step 3c now runs after that. The drain gives the actor back after each chunk,
  so the joining radio's first packet creates its observation of that node. The next chunk's
  `backfillObservations` sees "another radio has an observation" and creates nothing more. Only the
  first 2,000 nodes (by node number) get the store's radio's observation. In V4 and V5 the drain
  ran before the joining radio had delivered anything.
- What that changes: for the nodes left out, the store's radio has no observation, so when the
  joining radio's node DB arrives, each of them has one observation, the joining radio's, and the
  node is written straight from it (T042). A favorite, ignore or verified flag the user set through
  the first radio goes to the joining radio's value. It comes back only at the first radio's next
  node DB. Heard By for the first radio also leaves those nodes out.
- Scenario: the user's always-on radio A on a busy mesh, store never backfilled (a Mac kept in
  front), 3,000 nodes. They add B for the first time. B's node DB arrives, and favorites on nodes
  above the first 2,000 disappear until A reconnects.
- Sure: high on the code path; it needs over 2,000 nodes and a pending backfill. Deciding "another
  radio has observations" once, when the drain starts, or leaving out the radio being joined, would
  keep it whole.

### H2. While the connect-first override is set, the focused radio isn't reconnected straight away after a drop

- `AccessoryManager+Discovery.swift:75` (auto-connect only for `connectFirstPeripheralId`),
  `AccessoryManager.swift` (`connectToPreferredDevice`), `PreferredRadio.swift:35-51`,
  `BLETransport.swift:734`, `AccessoryManager+FocusHandover.swift:105-112` (the fallback, 30 s,
  only with no other radio connected).
- After a restore hand-over, B is focused and preferred, and the override names A (not back). The
  override lasts until a focus is chosen or a radio connects as the focused one. Meanwhile
  discovery's auto-connect only looks for A. If B drops (out of range for a moment, a reboot after
  a config save), discovery sees B again but doesn't reconnect it. B comes back only through the
  remembered-radio fallback 30 s later, and that fallback runs only when no other radio is
  connected. At the next launch the same applies: B waits 30 s for the fallback.
- Sure: high; low-medium impact. Letting auto-connect accept the focused (preferred) radio as well
  as the override would keep both.

## Checked and found fine

- Step 3c: no timeout, never throws (errors are logged), runs for every attempt but only drains once
  (`hasPendingBackfill`), holds the handshake gate. A config refresh outside a connect no longer
  runs it.
- Messages: follows `activeDeviceNum` changes only to a non-nil, different radio; a dropped focus
  keeps the list; the open channel closes because it belongs to the previous radio, while an open DM
  stays.
- Connect-first override: cleared by any focus change and by a focused connect's Step 5 (the
  restore's own takeover connect clears it, then the hand-over sets it again once that connect
  returns); moved by a renumber; cleared when its radio is removed; used for launch order, the
  restore choice and the fallback's exclusion.
- Renumber: `BackfillOwner` moves only when it named the old number; the service radios, Heard By
  and the override move with it.
- Single radio: no override without a restore hand-over; the owner check skips the store's own
  radio; connect steps unchanged apart from the no-op Step 3c.
