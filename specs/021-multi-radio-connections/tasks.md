# Tasks: Multiple Radios Connected at Once

**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

The feature is developed on `feature/multi-radio` and reaches `main` one layer at a time (D-20,
plan.md › Delivery in layers). This file lists the layers, and the earlier tasks the code that has
reached `main` refers to. The full task history stays with the feature branch; the other task numbers in `plan.md` and
`windows.md` refer to it.

## Layers

- [ ] T441 Layer 1, the per-radio data model: every schema change, the writers filling the new
  columns for the connected radio, the backfill, backups and renumbering, channel identity, message
  lists keyed by sender and packet id, the channel-change note, settings read as saved.
- [ ] T443 The connected radio as a `RadioSession`, every event tagged with its connection.
- [ ] T444 A discovered radio's RSSI updates at most every 2 seconds.
- [ ] T445 A connect's config download saves at its end.
- [ ] T447 Layer 2a: one database, switching as on `main` without the copy and clear; every screen
  shows the connected radio's data (D-21); the backup merge (D-09); per-radio resets (D-18).
- [ ] T453 Layer 2b: several radios at once, every radio's data together, services per radio.
- [ ] T449 Layer 3: one window per radio on the Mac (D-19).

## Earlier tasks cited in the code

- T020 Uniqueness moves from `messageId` to `messageKey` through lightweight migration
  (`MessageKeyMigrationTests`).
- T140 Lookups go by unique key: the node-number columns have no index (iOS 17, no `#Index`).
- T142 The backfill copies observations from node rows only while no other radio has observations.
- T144 A radio's channel keys are recomputed when its channels or LoRa settings arrive.
- T146 Observations go with the nodes they describe (eviction, removal).
- T173 Stale-node pruning deletes the pruned nodes' observations.
- T220 A backfill drain decides once whether other radios had observations.
- T232 Message history is capped per radio once the store holds several.
- T377 A real change of a slot's channel leaves a note in its conversation; Local Mesh Discovery
  pauses recording while it steps presets.
- T379 A channel key includes the radio's mesh (region, modulation, frequency).
- T382 Channel keys are read and stored as saved, not from a long-lived context's older copy.
- T383 Local Mesh Discovery and the settings forms read the LoRa settings as saved.
- T452 `receivedBy` records which radios received each row stored once for several radios.
