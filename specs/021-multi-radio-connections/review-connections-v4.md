# Review V4: connections and focus (feature/multi-radio)

Branch `feature/multi-radio` at `5ff31a3b`. V3 (`review-connections-v3.md`) reviewed `23d68e36`;
this pass checks the fixes since (T190–T198) and the code they added: the restore remembering
the radios alongside it and giving the preferred radio its focus back (`noteRestoredAlongside`,
`restoreDisplacedPreferred`), `stopBringingBack` for a removed radio, `BackfillOwner` and the
backfill before any other radio connects, the chunked drain, the unlock sheet's backoff and send
errors, Your Radios leaving out connecting radios, and the recycle's retiring flag.

Files read (diff since `23d68e36`, then the code around it): `AccessoryManager.swift`, `+Connect`,
`+AdditionalRadios`, `+FocusHandover`, `+RadioAttention`, `+RadioRemoval`; `BackfillOwner.swift`,
`RadioSession.swift`; `BLETransport.swift`; `LockdownSheet.swift`, `StoredRadiosSection.swift`;
`MeshtasticApp.swift`; in `MeshPackets` `rememberRadios`, `peripheralId(ofRadio:)`,
`drainMultiRadioBackfill`, `mergeBackups` and the retiring flag.

The full suite passes in the iOS Simulator (iPhone 17 Pro): 3,465 Swift Testing tests in 599
suites and 29 XCTests, in one clean run.

## Where the V3 findings stand

| V3 | What | Now |
|---|---|---|
| R1 | A restore that picked another radio never brought the preferred one back | Fixed: radios restored alongside are remembered and claimed; the preferred one takes the focus back when it rejoins. Leftovers in F1 and F2. |
| R2 | Removing a disconnected radio didn't stop its reconnects | Fixed (`stopBringingBack`). One gap in F3. |
| R3 | The first backfill stopped every radio's ingest | Fixed: the drain yields the actor after each 2,000-row chunk, so heartbeats are answered between chunks. |
| R4 | Unlock sheet ignored backoff and failed sends | Fixed: countdown until the radio's backoff ends; the sheet stays open with the reason when a send fails. |

## New findings, most serious first

### F1. The "take the focus back after a restore" marker never expires

- `AccessoryManager+AdditionalRadios.swift:129-134, 200-205`, `AccessoryManager.swift:335`.
- `restoreDisplacedPreferred` is set by the restore and cleared only when that radio next connects
  alongside. Nothing clears it when the user picks a focus themselves, disconnects or removes that
  radio, or when it comes back as the focused radio instead. Whenever it does connect alongside,
  possibly hours later or after the user added it back by hand, it takes the focus. That overrides
  the user's own choice and sends Settings back to its first screen.
- Scenario: after a background restore focused B, the user focuses C on purpose and is editing
  C's settings. A (the old preferred radio) comes back in range: the focus jumps to A and the
  Settings screen closes.
- Sure: high; low-medium impact. Clearing it on any focus change the user makes (and in
  `disconnectAdditionalRadio(byUser: true)`) would keep it to its purpose.

### F2. After a restore hand-over, the radio that took over stays preferred unless A returns that session

- `BLETransport.swift:716-717`, `AccessoryManager+Connect.swift:403`.
- In the T178 path the radio that connected first runs a full handshake, and Step 5 makes it the
  preferred radio. A only gets the preference back by rejoining in the same session (F1's marker is
  in memory). If A doesn't come back before the app is closed, every later launch connects B first
  and A joins alongside. HANDOFF describes the intent as the app being "as it was before iOS
  closed it".
- Sure: high; low impact (A still comes back, just not as the focus).

### F3. A radio removed while its focus handover is pending comes back

- `AccessoryManager+FocusHandover.swift:67-88`, `AccessoryManager+RadioRemoval.swift:56-66`.
- The handover task captured the dropped radio when it was scheduled. If the user removes that
  radio in App Settings › Your Radios within the 30 s (it's listed, since it's not connected),
  `stopBringingBack` finds no loop to cancel yet. The handover then fires, sets the radio's
  `autoConnect` and schedules its reconnect, so the removed radio rejoins when it's next in range.
- Scenario: focused A dies with B connected; the user removes A at once from Your Radios; 30 s
  later B takes the focus and A's reconnect loop starts; if A is revived nearby, it rejoins.
- Sure: high; low likelihood. `stopBringingBack` could also clear `handoverPrevious` for that radio.

### F4. A single-radio user's own radio can wait for the backfill on a new phone

- `AccessoryManager+AdditionalRadios.swift:175-193`.
- The check that the connecting radio isn't the store's own goes by peripheral id, because a
  discovered device has no node number yet. A BLE peripheral id is per phone, so after a phone
  migration (the app's data moved to a new iPhone), the user's only radio looks like another
  radio and its first connect waits for the whole backfill. The rows still go to the right radio
  (the owner's node number). One-time, and the drain now yields to live traffic, but that radio
  is the one waiting, so the first connect on the new phone takes as long as the drain.
- Sure: high on the code; low impact.

## Checked and found fine

- Restore: `noteRestoredAlongside` remembers only peripherals iOS restored with this app's
  central, and the displaced-preferred check reads `PreferredRadio` before the takeover's Step 5
  changes it. A remembered radio still connecting is tried through the normal reconnect, which
  replaces its old pending connect.
- `stopBringingBack`: finds the radio by its stored peripheral id before `removeRadioData` deletes
  it, and by any attempt for its number; Disconnect-by-user cancels the loop, the discovery wait
  and a connect in progress. Your Radios doesn't list radios that are connecting, so a focused
  connect can't be caught mid-way.
- Backfill: `BackfillOwner` is recorded at launch before anything connects and cleared once nothing
  is pending; the store's own radio skips the drain (no single-radio change); the drain holds the
  handshake gate, so no recycle or node dump runs during it; yielding between chunks is safe
  because live inserts already carry `fromNum`, so the drain never picks them up.
- Recycle: the retiring flag is set under the lock at the swap, before anything else runs on the
  old instance; its receptions and node updates save as they happen, so the new instance finds
  them.
- Unlock sheet: backoff read from the radio's own status and cleared on unlock; the countdown
  refreshes each second; a sent passphrase closes the sheet, the answer arrives as the radio's
  status.
- Single radio: no launch wait, connect steps unchanged, resets and Clear App Data as on `main`.
