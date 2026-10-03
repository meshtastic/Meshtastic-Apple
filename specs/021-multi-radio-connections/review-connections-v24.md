# Review V24: preset changes, after the stale-context fix (T377–T382)

Branch `feature/multi-radio` at `2ab1ceed`. A full pass over what happens when a radio changes
preset (LongFast → LongTurbo or any other), now including `2ab1ceed` (T382). That commit fixes what
the owner's device test found: two "Switched" notes, and the other radio's LongFast message in
GoDG's LongTurbo conversation and preview.

**What V22 missed.** T382's cause is the main context keeping the channel key and LoRa settings
from before a change the packet actor saved. V22 looked at exactly this question for the Channels
editor and dropped it because the code alone couldn't settle how SwiftData's contexts behave. It
should have been reported as "needs a device check". This review treats T382's finding as
established, and looks for the same cause in the rest of the flow.

Read: the T382 diff, then the code around it:
- `MultiRadioBackfill`: `storedChannelKeys`, `computedChannelKeys`, `updateSavedChannelKeys`,
  `removeDuplicateChangeRows`;
- `ChannelChangeEvents.record`, `ChannelMessageQuery`, `ChannelEntityExtension`,
  `ChannelMessageList`, `ChannelList`;
- the staged channel refresh, message ingest and the actor's recycle (`MeshPackets`), and
  `AccessoryManager+ToRadio`;
- `IntentMessageConverters`, `WindowRouters`, `Messages`, `TAKServerManager`;
- `DiscoveryScanEngine` and `DiscoveryScanView`, and the LoRa settings form.

Nothing built or run.

## Findings, most serious first

### V24-1. Local Mesh Discovery can put the old preset back after a preset change

- `DiscoveryScanView.swift:107` hands the engine the view's `@Environment(\.modelContext)`, which
  is the main context.
- `DiscoveryScanEngine.swift:225-242` reads `getNodeInfo(id:context:)?.loRaConfig` from it at scan
  start. The result is both `homePreset` and `homeLoRaConfig`, the full snapshot `restoreHomePreset`
  sends back at the end.
- T382 found the main context still holding GoDG's LongFast LoRa settings after the switch to
  LongTurbo. A scan started in that state snapshots LongFast as "home" and restores it when it
  finishes. The radio silently goes back to LongFast, and with the V22-2 fix the next refresh
  records LongTurbo → LongFast.
- Not covered by T382, which only moved channel-key reads.
- Sure: high that the snapshot comes from the main context. Whether it's stale at that moment is
  T382's finding. One device check settles it: switch preset, then run a discovery scan, and see
  what it restores.
- Fix: read the home config in a throwaway context, as the T382 helpers do. With one radio the
  same code runs, so a stale snapshot would affect single-radio users too.

### V24-2. The reverse direction: the packet actor may miss what the main context saves (needs a device check)

- Main-context writes to channels:
  - the staged channel refresh (`MeshPackets.swift:~378`, which replaces the rows);
  - `applyLocalChannelMutation` (QR replace, beacon join);
  - the Channels editor.
- The packet actor keeps its own long-lived context between recycles (after each connect's node
  dump, and every few thousand packets). What it does with channels in between:
  - message ingest keys each broadcast with `channelKeysByIndex` on that context
    (`MeshPackets.swift:2092`);
  - LoRa ingest recomputes and stores keys there (`refreshChannelKeys`).
- If that context misses main-context saves the way the main context misses its own:
  - after a rename, key change or QR import, incoming messages are filed under the old key until
    the next recycle. Other radios' conversations for the new channel miss them, and an old
    channel another radio still has shows them;
  - a LoRa change shortly after a staged refresh computes over replaced channel rows and can write
    an old key back. That's T382 mirrored.
- The V22-1 rule (own rows by key, any time) hides part of this in the radio's own conversation,
  but not in the others.
- Sure: the code paths are verified; whether the actor's context is stale is the same open
  question T382 answered for the main context. Device check: rename a channel or import a QR, then
  receive a message on it from another radio before reconnecting. If it shows, reading channels as
  saved in `updateChannelKeys` (a throwaway context, as T382 does) would close it.

### V24-3. The channel list now does a lot of work on every render, also with one radio

- `ChannelList.swift:49`, `:53` and `:131`: each row reads `mostRecentPrivateMessage` twice and
  `unreadMessages` once.
- Each of those builds `messageQuery`, which now costs:
  - a throwaway `ModelContext` and a MyInfo fetch with its channels
    (`ChannelEntityExtension.swift:47`);
  - a radio count;
  - the change-row fetch (several radios only);
  - the timeline fetch.
- That's roughly 3 contexts and a dozen fetches per channel, on the main thread, each time the list
  re-renders (message traffic does that). Before, the preview was one small fetch.
- Line 47 reads the saved key even with one radio, where the query never uses it. So the
  single-radio list pays for it too: a change to `main`'s path, against the earlier "keep the
  multi-radio lookups out of view rendering" work (`afa9d9de`).
- Fix:
  - read the saved key only with several radios;
  - build each row's query once and reuse it for the preview and the count, or move both to a task.
- Sure: high on the code; impact depends on traffic, so it's a hitch rather than a fault.

### Worth checking on the device (same cause, code outside 021)

- The LoRa settings form (`MetadataConfigForm` with `node` from the main context) after switching
  preset: if it shows the old preset, saving another LoRa field there would send the old preset
  back. The same goes for the preset shown on Connect and in Settings.

## Checked and found fine

- T382's key reads all go through saved values:
  - the conversation (`savedChannelKey`), the list preview and delete warning;
  - "Via" (`slots`, computed);
  - sends (`computedChannelKeys`), deep links, `WindowRouters`, TAK;
  - Siri and CarPlay (stored merged with computed, computed winning).
  No other `ChannelEntity.channelKey` read is left outside the actor.
- The staged refresh takes each slot's previous key from the store, saves the replaced rows, then
  recomputes from the saved channels and LoRa in a throwaway context and saves. That's the stale
  write-back fixed. The Channels editor does the same after its save.
- `record` writes no row when the slot's latest row already ends on the new key. A genuine change
  back (LongFast → LongTurbo → LongFast) still records, because the latest row then ends on the
  other key. The 60 s coalescing still works.
- `removeDuplicateChangeRows` drops a row whose key repeats the previous row's for the same radio
  and slot. That's the T382 double ([LongFast → LongTurbo, LongFast → LongTurbo]); a real
  there-and-back keeps both rows. It only fetches change rows.
- The preview now uses the conversation's query, so another radio's channel in the same slot no
  longer shows as the preview. With one radio it's the slot query, as before.
- The earlier fixes still hold:
  - V22-1: own rows by key, any time;
  - V22-2: no stored-key update while a radio is paused;
  - V22-3: the delete warning checks other radios' history.
- With one radio, conversations still use the slot query, so a preset change shows the old and new
  messages with one note between them.
