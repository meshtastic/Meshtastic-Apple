# Review V9: data, messages and services (feature/multi-radio)

Branch `feature/multi-radio` at `1b300de9`. Since `e1f27349` the commits are: the connection fix
J1 (a focused connect without a handshake, a BLE restore iOS kept connected, is now recorded as
the preferred radio; `AccessoryManager+Connect.swift`, `PreferredRadio.swift`,
`BLETransport.swift`), a test-only fix for the backup merge tests (`BackupMergeTests.settle`),
and notes for review-data-v8's R8-1 (under T132) and the connection review's edge (HANDOFF
gotchas). Nothing in the data, message or service code changed. I read the HANDOFF.md and
tasks.md changes and the code diff.

Tests: the full suite passes in the iOS Simulator (iPhone 17 Pro) at `1b300de9`: 3,477 Swift
Testing tests in 599 suites and 29 XCTests. I started it only once no other `xcodebuild` was
running, and ran it once. No tracked file changed.

## Status of the eighth review

| | Status |
|---|---|
| R8-1 message table up to four times larger, unindexed message queries | Recorded under T132 (measure four radios at the cap), as suggested. No code change expected. |

## Findings

None in my area this round.

## Checked

- J1's data side: Step 5 now sets `PreferredRadio.nodeNum` from the device when there was no
  config handshake. The backfill owner is recorded from `PreferredRadio` once at launch
  (`BackfillOwner.recordIfNeeded`, in the app's init, before any restore can reach Step 5), and
  after that only moves with a renumber, so a restore that picks another radio doesn't change who
  the old rows belong to. The launch drain, the merge and the background pass keep reading the
  recorded owner.
- The merge tests' `settle`: it checkpoints the test backup store and switches it to
  `journal_mode=DELETE` before hashing, so the file doesn't change after its checksum. Test code
  only; the app's merge opens the backup through the staged container as before.
- The accepted edge in HANDOFF (a joining radio's observations left by an earlier connect that was
  killed mid-drain): as described there, the store's radio then gets no backfilled observations;
  its own node DB dump creates them at its next connect, so the effect is limited to Heard By
  missing some of its nodes until then.
