# Spec: Multiple Radios Connected at Once

**Feature**: 021-multi-radio-connections | **Plan**: [plan.md](./plan.md) | **Tasks**: [tasks.md](./tasks.md) | **Handoff**: [HANDOFF.md](./HANDOFF.md)
**Branch**: `feature/multi-radio` (single pull request, opened only when the feature is complete)
**Background research**: [research/multi-radio-connections-report.md](../../research/multi-radio-connections-report.md), §13 is the chosen design.

## Summary

Let the app stay connected to up to four radios at the same time, over any mix of BLE, TCP and
serial. All radios share one database. Traffic that several radios hear is stored once. Data that
belongs to one radio (direct messages, how that radio sees each node, admin sessions, per-radio
reception details) is kept per radio.

## Users and scenarios

- One person with several radios in the same place (the maintainer's setup: four BLE radios and
  one TCP radio). They want one node list and one channel timeline, and to see which radio heard what.
- Someone who connects a second radio and only wants to switch to it, as today.

## Decisions (from the planning discussion, 2026-09-25)

| ID | Decision |
|---|---|
| D-01 | Work on `feature/multi-radio`, rebased onto `origin/main`. Commit locally; the owner pushes. |
| D-02 | One pull request for the whole feature. Nothing ships until all of it is done. |
| D-03 | Tracking lives in this folder (`spec.md`, `plan.md`, `tasks.md`, `HANDOFF.md`). |
| D-04 | Implementation order and bundling are up to the implementer. No intermediate releases. |
| D-05 | No global feature flag. When a radio is already connected and the user connects another, ask: keep both connected, or switch. A setting remembers the answer (Ask / Keep both / Switch). |
| D-06 | Deployment targets stay as they are (iOS 17.5, Mac Catalyst 14.6). No iOS 18-only SwiftData APIs (`#Unique`, `#Index`). |
| D-07 | Existing data must not be at risk while this is developed. The owner's main data is in the Mac App Store app (the radio always connected to the Mac). A side-by-side Mac build (own bundle ID, data container and signing team) runs next to it, and a script copies the App Store app's data into it when the owner asks. Mac only: the owner's phones, tablets and watches are never accessed. Local only: never part of the pull request. See `plan.md` › Side-by-side build. |
| D-08 | Add a per-radio reception table in the schema change, with a retention cap. |
| D-09 | On first launch of the new build, automatically merge backups from other radios into the shared database. Keep the backup files. |
| D-10 | Up to 4 radios at once. Must support four BLE radios together, plus TCP. |
| D-11 | Favorite and ignore apply to every connected radio that knows the node, with a per-radio override in node details. |
| D-12 | Services: each radio runs its own MQTT proxy. Phone position goes to every radio. TAK, CarPlay, Siri and Watch use a radio the user picks, defaulting to "follow the focused radio". |
| D-13 | Sending on a channel several radios share goes through the focused radio by default, with a "send via" picker. A DM reply always goes through the radio that is part of that conversation. |
| D-14 | Two radios have "the same channel" when the display name and key match. For an unnamed primary channel the modem preset must also match. |
| D-15 | Test hardware: several BLE radios, possibly one TCP radio. Simulator covers unit, migration and replay tests. A manual checklist covers devices. |

## Functional requirements

Connection
- FR-001 Connect up to 4 radios at once, over BLE, TCP and serial in any mix.
- FR-002 Discovery keeps running while radios are connected. Available radios stay listed.
- FR-003 Connecting a radio while another is connected shows the keep-both / switch choice (D-05). At the cap, only switch is offered, and the user picks which radio to replace.
- FR-004 Each radio reconnects on its own after it drops. Auto-connect remembers a set of radios, not just one.
- FR-005 BLE background restoration reconnects every restored radio.
- FR-006 A radio that needs a firmware update, is in lockdown, or is doing OTA only blocks that radio. The rest of the app keeps working.

Focus and navigation
- FR-010 One radio is focused at a time. It drives Settings, and it is the default for sending and for services that follow it.
- FR-011 A radio switcher changes focus without disconnecting anything.
- FR-012 Notifications name the radio. Deep links can carry `radio=<id>` and focus that radio first.

Data
- FR-020 One shared database for all radios. Switching or adding radios never clears data.
- FR-021 Node identity (user, keys, positions, telemetry) is shared and stored once per originating packet.
- FR-022 Per-radio view of each node: hops, SNR, RSSI, last heard, via MQTT, channel index, next hop, favorite, ignored, manually verified key, admin session. The node row keeps combined values: latest last heard, fewest hops, favorite or ignored if any radio says so.
- FR-023 Channel messages are grouped by channel identity (D-14), not by index, and stored once.
- FR-024 Messages are unique by sender and packet id, not packet id alone.
- FR-025 DMs are scoped to the local radio in the conversation.
- FR-026 Each radio's reception of a packet (SNR, RSSI, hops, relay, rx time) is recorded, up to a retention cap.
- FR-027 Existing data upgrades without loss. Backups from other radios are merged on first launch (D-09).

Messaging
- FR-030 Channel list shows each channel once, marked with the radios that have it.
- FR-031 Composer shows the radio it will send through, with a picker (D-13).
- FR-032 DM list can be filtered or grouped by local radio. Replies go through that radio.
- FR-033 Messages sent by any local radio show as "mine", labelled with the radio when more than one is configured.
- FR-034 A broadcast from one of the user's own radios, heard by another of them, does not notify.

Nodes and map
- FR-040 Node list and map show the combined view, with a "heard by" filter.
- FR-041 Node details show a per-radio table.
- FR-042 Favorite and ignore follow D-11.

Services
- FR-050 MQTT proxy per radio.
- FR-051 Phone position shared to every radio, each on its own interval.
- FR-052 Radio picker for TAK, CarPlay, Siri/App Intents and Watch (D-12).

## Non-goals

- Bridging or relaying traffic between radios or meshes.
- A tvOS version (possible follow-up).
- Changing firmware behaviour.

## Open items

- None. Resolved 2026-09-25:
  - D-07 details: see the decision table.
  - The standalone restore fix and the string-catalog sync each get their own small pull request
    (branches `fix/restore-dropped-backup-fields` and `chore/sync-string-catalog`, each one commit on
    `origin/main`). They stay in this branch too; once they merge upstream, a rebase drops them.
    The owner is discussing with a project admin how the large feature pull request gets merged; it
    can be split into smaller pull requests later if asked.
