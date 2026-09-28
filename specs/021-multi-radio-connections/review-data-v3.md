# Review V3: data, messages and services (feature/multi-radio)

Branch `feature/multi-radio` at `23d68e36`. This pass re-checks the fixes for `review-data-v2.md`
(V2-1–V2-8, T170 and T173–T177, T184, T186, T187) and reviews what changed in my area since
`2e029fab`: the reset gating in `DeviceConfig.swift`, `StoredRadiosSection.swift`, the per-backup
merge attempts, the Purge Stale Nodes cleanup, `reaggregate`, the stored-key sharing rule, the
CarPlay list and Siri search scoping, the TAK channel move, the persisted Heard By set, the radio
cache reset, the recycled actor's saves, and the backfill that now waits for a second radio
(T186). I read the HANDOFF.md and tasks.md changes first.

Tests: see the last section. No tracked file changed.

## Status of the second review

| | Status |
|---|---|
| V2-1 reset before the radio list loads | Fixed: the buttons wait for the list, and another connected radio counts. |
| V2-2 Siri read-back and the CarPlay list | Fixed for the radio of DMs. The channel side now drops messages another radio delivered first, R3-1. |
| V2-3 Purge Stale Nodes | Fixed. |
| V2-4 merge attempts | Fixed: counted and saved per backup, right before it merges. |
| V2-5 removing a radio that isn't connected | Fixed (App Settings › Your Radios). Small gap, R3-4. |
| V2-6 old single observation after a reset | Fixed for one observation; the same happens with two or more old ones, R3-3. |
| V2-7 merged radio's channels | Fixed: stored keys count. |
| V2-8 minors | Fixed. |

## New and remaining findings

Ranked most serious first. "Sure" is how confident I am that it happens as described.

### R3-1. CarPlay and Siri drop a shared channel's messages that another radio delivered first

- `CarPlay/CarPlaySceneDelegate.swift:424-434` (`carPlayMessageRadio`, `belongs`), `:478`
  (channel unread counts), `:571` (read-back donation),
  `Intents/SearchForMessagesIntentHandler.swift:39-52`, `MeshtasticAppDelegate.swift:74-76`.
- With several radios, the CarPlay list scopes channel messages by `localNodeNum`, the radio that
  delivered the message first. A message on a channel both radios have is stored once, with
  whichever radio's BLE link was faster. So on the CarPlay radio's "LongFast" row, the unread
  count, the read-back donation, Siri's search and the mark-as-read after it only see the messages
  that radio happened to deliver first; the rest never show in CarPlay. The app's own timeline
  groups the same channel by `channelKey` (`ChannelMessageQuery`), so the two disagree.
- For DMs, scoping by `localNodeNum` is right (a DM only arrives through its radio); the problem
  is only the channel side.
- Scenario: A (CarPlay radio) and B, both on LongFast. About half of LongFast messages come in
  through B first. In the car, LongFast shows no unread for them, Siri doesn't read them, and they
  stay unread in the app afterwards.
- Fix direction: for a channel conversation, match the CarPlay radio's channel by key, as
  `ChannelMessageQuery` does (`channelKey == key`, or this radio's slot for rows without one).
- Sure: high.

### R3-2. Switching to a second radio skips the backfill, which then credits the old rows to it

- `Accessory Manager/AccessoryManager+Connect.swift:118-123` (the join backfill only for
  `!asFocused`), `AccessoryManager+AdditionalRadios.swift:167`,
  `Views/Connect/Connect.swift:1376-1377,1405` (`switchToDevice` moves `PreferredRadio` to the new
  radio, then connects it as focused), `MeshtasticApp.swift:171,254`.
- Since T186, a single-radio store isn't backfilled at launch; the backfill runs when a second
  radio joins, but only in the additional-radio connect. A radio connected as the focused one
  never triggers it: Switch (the dialog choice or the Connecting Another Radio setting), or
  connecting B from Available Radios while A is off. `switchToDevice` also sets
  `PreferredRadio` to B before connecting. The next launch drain (now two stored radios) or the
  next background pass then runs with `ownRadio = PreferredRadio` = B: A's old DMs get
  `localNodeNum` B, and A's old channel messages get their `channelKey` from B's slots.
- Until that drain, A's old rows have no `localNodeNum`, so they show in B's DM threads and in
  B's same-numbered channel slots (the documented "rows without a radio show everywhere").
- Scenario: a Mac user with one radio A upgrades; the app stays in front, so no background pass
  ran. They tap radio B and choose Switch. Next launch: A's old conversations are B's, a reply
  goes out from B, and A's old "Hiking" (slot 1) messages land in B's slot-1 "Family" timeline.
  On iOS the same happens if the switch comes before the background passes finished.
- The owner's own Mac store is safe: it has backups to merge, and the merge drains the backfill
  at first launch with A as owner.
- Fix direction: drain with the store's radio as owner before any connect of a radio that isn't
  it (focused or not), before `switchToDevice` moves `PreferredRadio`.
- Sure: high for the code path.

### R3-3. Resetting a radio can still move a node's last heard back, with two or more old observations left

- `Helpers/MeshPackets+RadioRemoval.swift:199-214` (`reaggregate`).
- T176 guards the case of one remaining observation. With two or more remaining,
  `applyAggregate` still sets `lastHeard` to the newest of them and takes hops and signal from
  those, however old. A switcher with two merged backups that both know node N, who resets their
  only live radio, sees N's last heard jump back to the newer backup's date; online filters hide
  it and Purge Stale Nodes can delete it.
- Fix direction: apply the same rule as for one (take over only within `currentWindow` of the
  node's last heard, and never move it back).
- Sure: high for the code; narrow case.

### R3-4. Your Radios offers Remove for a radio that's connecting, and mislabels the store's own radio

- `Views/Settings/StoredRadiosSection.swift:22-24,43`.
- "Not connected" is `!isRadioConnected`, so a radio still connecting (at launch, or during its
  node DB) is listed with Remove. Removing it deletes its `MyInfoEntity` and data while its
  connect goes on writing channels and observations for a radio the store no longer has.
- A radio with no `lastConnected` is labelled "Known from an earlier version's backup". That also
  fits the store's own radio after the upgrade until its first connect with this version, and
  stray rows from old stores; with merged backups present the section shows, so the user's main
  radio can appear there as a backup-only ghost.
- Sure: high for the code; low impact (the dialog asks first).

### R3-5. Minor

- `Views/Nodes/Helpers/NodeFilterParameters.swift:124-133`: the Heard By set is kept in
  UserDefaults as an array of up to the whole node list (thousands of numbers) and rewritten
  whenever it changes (checked every 15 s). UserDefaults loads its whole file at launch; a small
  file or the observations themselves would do.
- `Helpers/MeshPackets.swift` (`recreateShared`, T172): for up to 2 s after a recycle the retired
  and the new actor both write. A packet another radio delivers in that window doesn't see the
  retired actor's unsaved reception, so it's handled again (positions and telemetry stored twice;
  messages are protected by `messageKey`). HANDOFF records the overlap; this is what it costs.

## Checked and found fine

- The reset gating: buttons disabled until the radio list arrives; `hasOtherRadios` counts any
  other connected radio; the single-radio path is unchanged for a store holding one radio.
- `clearStaleNodes` deletes the purged nodes' observations.
- The per-backup merge attempt: counted and saved before each backup's merge, marked and saved
  after, so one failing backup no longer spends the others' attempts.
- `reaggregate` with one remaining observation; `deleteMessagesOfRadio` with stored keys.
- Siri search and the CarPlay list for DMs: ids carry the CarPlay radio with several radios;
  read-back, mark-as-read and list replies stay on it; single-radio ids unchanged.
- The radio cache reset on a new `MyInfoEntity` and on a first connect; the TAK channel move.
- `StoredRadiosSection` removal of an offline radio through `removeRadio`, which handles a radio
  with no session; only shown with more than one radio.
- The launch hook: merges still drain the backfill first with the store's radio; the launch drain
  only runs with several stored radios, so a single-radio launch doesn't wait.

## Tests

Full suite in the iOS Simulator (iPhone 17 Pro), `xcodebuild test` at `23d68e36`: 3,486 of 3,488
tests passed; none failed an assertion. The other two ended with "Test crashed with signal kill".
Another session was running its own test runs on the same Simulator at the same time (its result
bundles are in the same DerivedData, started 18:57:36, 18:58:19, 19:02:09 and 19:04:26), and each of its runs
reinstalls and relaunches the test host. Across my three attempts a different handful of tests was
killed each time (timer, snapshot, lock-down and connect-flow tests), and there's no crash report
for any of them, so I read the kills as that interference rather than a fault in the code. A clean
run needs the Simulator to itself.
