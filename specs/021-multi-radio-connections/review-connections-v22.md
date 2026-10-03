# Review V22: a channel's history across preset and channel changes (T377–T380)

Branch `feature/multi-radio` at `2c173885`. This reviews `9efd65fa` ("Keep a channel's history
across preset and channel changes", T377–T379) and `2c173885` (snapshot and docs, T380): what
happens to a radio's conversations when it moves from LongFast to LongTurbo, or changes region,
frequency, channel name or key.

Files read: `ChannelChangeEvents`, `ChannelMessageQuery`, `ChannelIdentity`, `MeshNetwork.identity`
(`LoRaChannelCalculator`), `MessageEntity`, `MultiRadioBackfill`, `MeshPackets` (staged channel
refresh, message ingest), `MeshPackets+MultiRadio`, `MeshPackets+RadioRemoval`, `UpdateSwiftData`
(LoRa ingest), `DiscoveryScanEngine` (pause, restore), `Channels.swift` (editor),
`AccessoryManager+ToRadio` (`saveLoRaConfig`, `saveChannelSet`, `applyLocalChannelMutation`,
sends), `ChannelChangeRow`, `ChannelMessageList`, `ChannelList`, `ChannelEntityExtension`,
`NodeBackupManager+Copies`, `NodeRenumber`, `CarPlaySceneDelegate`, `MessageSearch`, the Siri
search intent, the spec, tasks and docs changes, and the tests.

Checked in the files only; nothing built or run. The owner ran the suite (3562 tests).

## Findings, most serious first

### V22-1. Messages a radio delivers at connect, after a change made while the app was away, are missing from that radio's conversation

- `ChannelChangeEvents.swift:66-68`: a change row is dated `now`.
- `ChannelMessageQuery.swift:47-58`: each stretch shows its key's messages only from the row's time
  onwards.
- `MeshPackets.swift:2092`: a received message gets the slot's current key.
- `MeshPackets.swift:2095`: it's dated by the radio's `rxTime`.
- Suppose the radio's preset (or channel) was changed while the app wasn't connected: from another
  client, the radio's own menu, or another phone. At the next connect, this is the order:
  1. The firmware sends the config first, before any queued packets.
  2. LoRa ingest sees the new key and writes the change row at connect time, `t`.
  3. Then the packets the radio queued while the app was away arrive. They get the new key, but
     keep their earlier `rxTime`.
- They're earlier than `t`, so they fall outside the new stretch, and they don't match the old key
  either. Nothing in that radio's conversation shows them. This covers messages received on the
  new preset before the reconnect, and older ones received on the old preset (keyed by the current
  config, as before).
- Before T378, the rule that showed this radio's rows in the slot kept them visible. With one radio
  the query is by slot, so it isn't affected.
- Smaller cases of the same thing: a message on the new channel that the radio received between
  applying a change and the app recording it, or the first message after a change that's only
  noticed when that message is ingested.
- Scenario: A and B connected. A is set from LongFast to LongTurbo in the web client while the
  phone is away, and receives a few LongTurbo messages. The phone reconnects: A's LongTurbo
  conversation starts with the change note and lacks those messages.
- Sure: high on the code; medium impact (messages silently missing from the conversation they
  arrived in; needs a change made outside this app session).
- Options:
  - match this radio's own rows by key without the time bounds, since its rows carry the key its
    slot had when it stored them, and keep the bounds for other radios' rows;
  - or date a change found in a radio's config no later than that radio's last activity known to
    the app.
- No test covers it: `ChannelChangeEventsTests` only creates changes with messages after them.

### V22-2. A change that leaves no row hides the history before it, and an interrupted discovery scan leaves one

- `MultiRadioBackfill.swift:98-111`: while a radio is paused, `record` returns 0, but the stored key
  is still updated.
- `ChannelChangeEvents.swift:137-148`: the stretches come only from rows. The last stretch is "the
  slot's channel now", from the last row onwards; before the first row is the first row's previous
  key.
- `DiscoveryScanEngine.swift`: `restoreHomePreset` puts the home preset back. `cleanupAndIdle`
  resumes recording.
- The conversation relies on an unbroken chain of rows. When Local Mesh Discovery's restore doesn't
  happen, the radio stays on a scan preset: the app is killed or loses the radio mid-scan, or the
  restore's send throws before the local update. The stored key is then already the scan preset's,
  and there's no row:
  - A's conversation shows only the scan preset's channel, and the home channel's history is no
    longer in it.
  - When the user puts the home preset back, the row says MediumFast → LongFast. The LongFast
    history from before the scan is outside the LongFast stretch, which starts at that row, so it
    stays hidden.
- Before T378 the slot rule kept it visible. Multi-radio only.
- Same root, test stores only: rows with `c1` keys from before an earlier preset change are
  converted to the unknown-mesh key when no radio has that channel now, and no conversation shows
  them. `c1` never shipped; stores from `main` have no keys and are filled from the current
  config, so this is limited to the owner's test stores.
- Sure: high on the code; low to medium impact (needs an interrupted scan).
- Suggestion: don't update the stored key while a radio is paused. Then the first refresh after the
  pause compares the pre-scan key with the actual one:
  - a completed restore leaves no row, as now;
  - an interrupted one writes home → scan when the radio is next heard, which also explains its
    state.

  Messages during the scan get computed keys either way.

### V22-3. The delete warning only looks at other radios' current channels (low)

- `ChannelEntityExtension.swift:62-71`: `sharesMessagesWithOtherRadios` compares this
  conversation's keys with the other radios' current keys.
- Deleting A's conversation deletes every message in A's stretches. If B had one of those channels
  earlier, B shows them in one of its own older stretches, and the confirmation doesn't say so.
  Comparing against the other radios' history keys (their change rows' keys) as well would cover
  it.
- Sure: high; low impact.

## Notes

- The new strings ("Switched from %@ to %@.", "The channel key changed.", the delete warning, and
  so on) are only in the uncommitted `Localizable.xcstrings` change.
  - That change is Xcode's catalog sync for the whole branch: 31 strings added, 66 stale entries
    removed, 10 updated in place.
  - None of the removed entries has a translation, so nothing translated is lost. It should be
    committed.
- With one radio, the change note now appears in conversations (T377, "also with one radio"). It's
  the one deliberate change on the single-radio path, so it's worth naming in the PR for upstream
  reviewers.

## Checked and found fine

- The key (`c2:<mesh>:<digest>:<name>`):
  - `MeshNetwork.identity` has no colons, and `parts(of:)` splits at most three times, so names
    with colons survive.
  - A secondary channel changes key when the preset, region or frequency changes. A primary rename
    moves every slot when the frequency comes from the name.
  - Two radios share a channel only on the same mesh (D-14 as changed).
  - The spec (D-14, FR-023) and `swiftdata.md` match the code.
- Recording (`record`):
  - Only a real change writes a row: not a first fill, not a `c1` → `c2` conversion, not while
    paused.
  - A change undone within 60 s deletes its row; a further change within the window updates it.
  - There's one row per affected slot.
  - Rows are read and have no sender. They use negative ids (`messageId` isn't unique) and an
    `event:` message key.
- Where rows get recorded:
  - LoRa ingest and channel ingest.
  - The staged channel refresh, which now carries each slot's old key across the row replacement.
  - The Channels editor, right after its save.
  - Message ingest and the backfill pass also record a change they're first to see.
- Channel-set saves (QR replace, the Shortcuts intent) always send a want-config afterwards, so
  their change is recorded within seconds.
- Local Mesh Discovery pauses the scan's own radio (`scanRadioNum`). `saveLoRaConfig` awaits the
  local LoRa update, so keys are refreshed before `cleanupAndIdle` resumes recording, and a
  completed scan leaves no row.
- The conversation (multi-radio):
  - Each stretch has the right key and bounds, plus this radio's unkeyed rows in the slot and its
    change rows.
  - `c1` rows match their stretch until converted.
  - Unread counts, the unread query and the `tapbacks` query leave change rows out (they're read).
  - The other radio's conversation is untouched by A's change.
  - With one radio it's the slot query, so old and new messages show with the note between them,
    as stock does plus the note.
- Elsewhere:
  - The last-message preview, CarPlay (unread only), Siri search and in-app search leave rows out.
    In-app search can't match an empty payload.
  - Removing a radio deletes its rows. A renumber moves them (`localNodeNum`). Backup restore and
    merge copy `systemEvent` and `previousChannelKey`.
  - The thread view shows `ChannelChangeRow` with no menu.
  - The text: presets first ("Switched from LongFast to LongTurbo."), then rename, then key, then
    mesh, with a fallback for unreadable keys.
- `rekeyLegacyMessages` filters `channelKey != nil`, sorts by key and checks the prefix in Swift,
  avoiding the string-prefix predicate that crashed. `c1:` sorts before `c2:`, so leftovers come
  first.
- Schema: `systemEvent` (default 0) and `previousChannelKey` (optional) are additive (D-16).
