# Review V6: data, messages and services (feature/multi-radio)

Branch `feature/multi-radio` at `1e8a6ac9`. This pass re-checks the fixes for `review-data-v5.md`
(R5-1 → T213, R5-2 → T214), the data side of the connection fixes (T210: the join backfill as
connect Step 3c; T211: Messages follows the focused radio), and takes another look at what the
removal code leaves behind. I read the HANDOFF.md and tasks.md changes first.

Tests: the full suite passes in the iOS Simulator (iPhone 17 Pro) at `1e8a6ac9`: 3,471 Swift
Testing tests in 599 suites and 29 XCTests. I started it only once no other `xcodebuild` was
running and ran it once, since another review was using the same Simulator. No tracked file
changed. The finding below isn't covered by a test.

## Status of the fifth review

| | Status |
|---|---|
| R5-1 backfill owner after a 2.8 renumber | Fixed: `renumberStore` moves `BackfillOwner` with the radio; the Step 3c check then sees the store's own radio under its new number. |
| R5-2 saved radio choices after a renumber | Fixed: the TAK / CarPlay & Siri / Watch radio, the Heard By radio and the connect-first override move too. |

## Findings

### R6-1. After Remove This Radio leaves one radio, the removed radio's kept channel history shows in the wrong channel

- `Helpers/MeshPackets+RadioRemoval.swift:176-189` (`deleteMessagesOfRadio` keeps channel
  messages on channels another radio has, unchanged), `Persistence/ChannelMessageQuery.swift:30,60,87`
  and `:109-111` (`isMultiRadio`: more than one `MyInfoEntity`).
- Removing radio C keeps C's messages on channels another of the user's radios has, as D-18 says,
  but leaves them as they were: `localNodeNum` C and `channel` = C's slot. Removal also deletes
  C's `MyInfoEntity`. When that leaves one radio, `isMultiRadio` turns false and every channel
  query falls back to the single-radio one, `channel == index`, with no key and no radio. C's
  kept messages then show in whatever channel sits in their slot number on the remaining radio,
  and drop out of their own channel there. Unread badges, CarPlay and Siri follow the same
  single-radio match.
- With two or more radios left, the keyed query still finds them, except rows without a
  `channelKey`: they only match their own radio's slot (`bySlot`), and that radio is gone, so they
  vanish from every timeline.
- Your Radios (T187) exists mainly to clear out radios from merged backups and radios that died,
  so this is the likely path: a switcher removes the old radio from the backup merge and is back to
  one radio.
- Scenario: A has "Family" in slot 1 and "Hiking" in slot 2; the old radio C (from a merged
  backup) had "Family" in slot 2. Remove C in App Settings › Your Radios. A's "Hiking" now shows
  C's old Family messages, and A's "Family" no longer does.
- Fix direction: when a channel message is kept, move it to a remaining radio that has its key:
  set `localNodeNum` to that radio, `channel` to its slot for the key, and `channelKey` if it was
  nil. That also covers the keyless rows.
- Sure: high for the code path.

## Checked and found fine

- `BackfillOwner.renumber` and `moveSavedRadioChoices` in `renumberStore`; the Heard By change
  clears the old set so it's looked up again.
- Step 3c: after the config (so the radio's node number is known) and before its node DB; for
  focused and added radios alike; not run by a config refresh outside a connect; the store's own
  radio doesn't wait. The drain still sees only the old rows (the new radio's messages carry
  `fromNum` from the start).
- Messages following the focused radio: the channel list and its selection change with the focus;
  a DM selection stays; channel deep links from another radio are still mapped by key.
