# Review V25: the V24 fixes (T383)

Branch `feature/multi-radio` at `a7df3c42`. Checks the fixes for V24-1 to V24-3 and the
settings-form device item, and looks again for the stale-context cause (T382) in the preset-change
flow. Read only; nothing built or run.

## Where the V24 findings stand

| V24 | Fix | Verdict |
|---|---|---|
| V24-1 | Local Mesh Discovery reads its home LoRa snapshot, home primary channel and each scan preset as saved (`withSavedNode`, `savedLoRaConfig`, `savedPrimaryChannel`, throwaway context; only value types leave it). | Fixed. Setting `modemPreset` on the saved config is what `presetOverride` did; `usePreset` and the rest come from the saved entity either way. |
| V24-2 | `refreshChannelKeys` saves the actor's ingest, then stores keys and change rows with `updateSavedChannelKeys`. Received broadcasts are keyed with `computedChannelKeys`. The backfill drain no longer stores keys. | Fixed for ingest, the key refresh and the drain. One actor path left: V25-1. |
| V24-3 | One query per channel row (`listSummary`) for the preview, the count and the menu. With one radio, `messageQuery` and `savedChannelKey` read no stored keys. | Fixed. The unread count is only read when there's a preview, which is what the row did before. |
| Device item | `MetadataConfigForm.load` reads the config as saved, for every settings form. | Fixed. Same values on the single-radio path, just never older than the store. |

## Findings

### V25-1. Remove This Radio and resets still decide which channels are shared from the actor's own channel objects (low to medium)

- `MeshPackets+RadioRemoval.swift:163-190`: `deleteMessagesOfRadio` fetches every radio in the
  actor's `modelContext` and takes stored keys merged with `channelKeysByIndex(...)` computed
  there. That decides which messages stay because another radio has the channel, and the slot they
  move to.
- `:92`: `sharesNetwork` compares `MeshNetwork(radio:)` from the same objects. The primary
  channel's name feeds the frequency.
- V24-2's premise is that the actor's context can miss channels the main context saved: a rename,
  key change, QR import or staged refresh. In that case, removing or resetting another radio (with
  its messages deleted) judges "shared" from the old channels. Messages on a channel the other
  radio now has can be deleted instead of kept, or moved to the wrong slot.
- It's the same cause, in the one destructive path the fix didn't reach. The actor's recycle
  (after each connect's node dump, every few thousand packets) narrows the window.
- Fix: read the radios' keys as saved there (`storedChannelKeys`, `computedChannelKeys`), as
  ingest now does.

### Note (low)

- The backfill drain still reads keys from the actor's context: for filling rows that have no key,
  and for the `c1` maps. Both only matter once, when a store is upgraded, so this is unlikely to
  matter. Reading them as saved would make every key path the same.

## Checked and found fine

- `refreshChannelKeys` saves its context before computing. Every caller runs inside an ingest
  that saves right after, so saving a moment earlier changes nothing. The reload notice is posted
  on the main actor.
- Received broadcasts read the saved settings. The actor's own LoRa and channel changes are saved
  by `refreshChannelKeys` before any message after them is keyed.
- The discovery restore sends the saved snapshot. A completed scan leaves no row (V22-2), and the
  radio ends on the preset it started on.
- `listSummary`, `messageQuery` and `savedChannelKey`: several radios read the saved key; one radio
  uses the slot query as on `main`, with no store read for the key.
- The earlier fixes hold: T382's key reads, V22-1 to V22-3, the duplicate-row guard and its
  cleanup.
