# Review V8: connections and focus (feature/multi-radio)

Branch `feature/multi-radio` at `e1f27349`. V7 (`review-connections-v7.md`) reviewed `81456eb5`;
this pass checks the fixes since (T230–T232). T232 (per-radio message pruning) is data handling,
left to the data review.

Files read (diff since `81456eb5`, then the code around it): `+Connect` (Step 0, Step 3c, Step 5),
`+AdditionalRadios`, `+Discovery`, `+Focus`, `AccessoryManager.swift`, `PreferredRadio.swift`;
`MeshPackets+BackupMerge.swift`; `BLETransport.swift` (the restore choice and
`completeFocusedRestore`); `Settings.swift` and the aggregate's callers for what reads
`PreferredRadio`; `BackupMergeTests.swift` for the failure below.

## Tests

The full suite passes in the iOS Simulator (iPhone 17 Pro): 3,476 Swift Testing tests in 599
suites and 29 XCTests, with the simulator to itself.

The first full run had one failure: `BackupMergeTests.strayRadioRowDoesNotBlockMerge` (the merge
skipped the backup: "its checksum doesn't match"). The suite then passed six times on its own and
the next full run passed. It's the same cause HANDOFF notes for `attemptCountedPerBackup`: the
test helper hashes the backup store (`BackupMergeTests.swift:226`) as soon as its container goes
out of scope, before SQLite has necessarily finished writing the file. Both tests share that
helper, so closing the container, or checkpointing, before hashing would settle both.

## Where the V7 findings stand

| V7 | What | Now |
|---|---|---|
| I1 | The joining radio's packets were recorded before the backfill decided | Fixed: Step 0 asks before the event stream starts and keeps the answer for the attempt. One edge noted below. |
| I2 | Whichever radio was seen first at launch took the focus | Fixed for the hand-over restore; the other restore path has the J1 gap. |

## Findings

### J1. A restore that picks a radio still connected leaves the preferred radio on the absent one

- `BLETransport.swift:773-779` (a connected radio is the focused restore ahead of the preferred
  one), `668` and `679-681` (restored with `wantConfig`/`wantDatabase` false),
  `AccessoryManager+Connect.swift:399-430` (Step 5 returns before recording the preferred radio,
  "focused this run" and the override when there's no node-DB request); readers:
  `Settings.swift:959, 985`, `UpdateSwiftData.swift:308`, `MeshPackets+MultiRadio.swift:352`.
- In the T155 case, where B was still connected at relaunch and A (preferred) was still
  connecting, B is restored as the focused radio without a handshake. No MyInfo arrives and Step 5
  exits early, so `PreferredRadio` still names A, and B isn't in `radiosFocusedThisRun`. That's
  V5's G3 again, on the path its fix didn't cover (G3's fix handled only the hand-over path, which
  runs a full handshake):
  - Settings selects A, the radio that isn't connected, when it first appears.
  - Each node's channel slot comes from A's observation, not the focused B's.
  - If B drops, discovery won't reconnect it at once: it's neither the connect-first radio nor
    the preferred one (T221/T231's case), so it waits for the 30 s fallback, and only with no
    other radio connected.
- Scenario: A left at home, B carried; iOS relaunches the app for B. The user opens the app: B is
  focused, Settings shows A's configuration.
- It has been there since T155. I checked only the hand-over path in V5.
- Sure: high on the code. This path could do what the hand-over does: make B preferred and
  "focused this run", and set the connect-first override to A.

### Edge: a joining radio's observations from an earlier, unfinished connect

- `AccessoryManager+Connect.swift:260`.
- Step 0's answer is fresh for each connect. If an earlier connect of the same radio delivered
  packets and ended before its drain finished (the app killed mid-drain, say), that radio's
  observations are already in the store, the next connect answers "yes", and the store's radio
  gets no observations. Rare; noted for completeness.

## Checked and found fine

- Step 0's check: holds the handshake gate, runs before Step 1 creates the event stream, only on
  the first try (a retry keeps the first answer), only with a backfill owner, defaults to "yes"
  on a fetch error (the safe side); Step 3c passes it through, and background passes still decide
  for themselves.
- "Focused this run": filled by a focused connect's Step 5 and by every focus change; at launch
  discovery auto-connects only the connect-first radio, and after a drop it also reconnects a radio
  that has been focused in this run. With no override, the connect-first radio is the preferred
  one, so a single-radio user sees no change.
