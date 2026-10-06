# Review V26: the V25 fixes

Branch `feature/multi-radio` at `8ee8902b`. Checks `896c3d02` (removal and the backfill drain read
channels as saved). `8ee8902b` only commits the V21 and V23 reports. Read only; nothing built or
run.

## Where the V25 findings stand

| V25 | Fix | Verdict |
|---|---|---|
| V25-1 | Removal saves the actor's context, then takes each radio's mesh (`savedNetworks`) and channel keys (`storedChannelKeys` merged with `computedChannelKeys`) from throwaway contexts. | Fixed. The keys are read before anything is deleted, while the removed radio's MyInfo and channels are still saved. `myInfos` from the actor's context is only used for node numbers, which don't go stale. |
| Note | The drain computes keys and the `c1` maps from `reader`: a throwaway context, or the given context when that has unsaved work (a backup merge's staging context). | Fixed for merges and for a drain whose context is clean. One caveat below. |

## Findings

None that need fixing.

- Low, upgrade-time only: in the packet actor the drain's context often has unsaved work (the
  debounced position and telemetry saves), so `reader` falls back to that context's own copies,
  which the note was about. It only matters for filling rows that have no key and for `c1` rows,
  once per upgraded store. Saving first when the context isn't a merge staging context, as removal
  now does, would make it the same everywhere.

## Checked and found fine

- In removal, saving first leaves the operation unchanged: it was going to save anyway, and
  nothing before the save depends on unsaved state.
- The kept messages' new slots and the preferred radio's slots come from the saved keys
  (R13-2 still holds).
- `savedNetworks` uses the failable `MeshNetwork(radio:)`, as before. A radio without LoRa
  settings has no mesh and shares none.
- The new `RadioRemovalTests` cover removal reading channels saved by another context.
- Across V22 to V26, every channel-key read and write in the preset-change flow now goes through
  saved values:
  - conversation, list, "Via", sends and links;
  - Siri, CarPlay and TAK;
  - ingest, the key refresh and the staged refresh;
  - the editor, discovery, settings forms and removal.
  
  The rest holds too: the change rows (dedupe, coalesce, pause) and the stretch rules (own rows by
  key at any time, other radios' rows bounded). With one radio, conversations use the slot query
  with the change note between old and new messages.
