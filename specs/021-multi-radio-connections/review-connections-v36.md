# Review V36: the V35 fixes (T399) and Remove Them under D-18 (T400)

Branch `feature/multi-radio` at `93dbe4ef`, working tree clean. This review checks the two commits
since V35 against the files.

## What changed since V35

- **`951802a2` (T399), the V35 fixes.**
  - `HeardOnCurrentLoraAnswers` records which radio the stored answers belong to, across launches.
  - `claimHeardOnCurrentLora(for:)` makes them the radio's own when it's connected alone,
    clearing another radio's first. It runs at MyInfo, before its NodeInfo and before each packet.
  - A second radio connecting clears every answer.
  - The notice's candidates (`UnheardNodesRemoval.candidates`) leave out the user's radios. In a
    store with other radios' observations, only nodes the window's radio has observed count.
  - Also: the heard-now answer is now set on the aggregated path of `updateAnyPacketFrom` too.
- **`93dbe4ef` (T400), the owner's call.**
  - **Remove Them** follows D-18: a node another radio has observed stays in the app. Only the
    window's radio's observation and answer go, and `NodeObservationEntity.reaggregate` (moved
    out of `removeRadioData`) rewrites the node.
  - `sendRemoveNode` is split out of `removeNode`.
  - New confirmation text when other radios' nodes are in the app.

## How it was checked

- **Tests:** one run of `MultiRadioUnheardOnCurrentLoraTests`, `RadioSessionTests`,
  `RadioRemovalTests`, `MultiRadioConnectFlowTests`, `MultiRadioConnectLifecycleTests` and
  `MultiRadioIngestTests` in the iOS Simulator. 132 tests in 6 suites, all passed. The build
  changed no tracked files.
- **SwiftLint:** the changed Swift files linted at `2cbbc821` and at HEAD give the same
  violations.
- **Removed lines:** the 72 app-code lines removed are the old observed-only clear, the
  notice's old predicate and delete, `removeNode`'s body (now split in two) and `reaggregate`'s
  body (moved). Nothing else is undone. Every touched file ends in a newline.

## The V35 findings

| Finding | Status | Notes |
|---|---|---|
| V35-1 the notice offered the other radios' nodes | Fixed | Candidates and removal, below. |
| V35-2 another radio's answers counted as the next radio's | Fixed | The answers are claimed, below. |
| Minor 1 stale editor copies | Done | Edits made on disk and checked with `git diff` (T399). |
| Minor 2 doc comments off their functions | Fixed | Both are back. |

How V35-1 is fixed:

- `candidates` (`UnheardNodesBanner.swift:65-80`) leaves out every `MyInfoEntity` radio, so the
  other radios' own node rows can't be offered.
- Once any other radio has observations, only nodes the window's radio has observed count. A's
  dump creates A's observation for every node in it (`recordNodeDBObservation`), so A's reported
  nodes are always included.
- A store from before feature 021 joined by another radio gets observations at Step 3c, before
  that radio's dump. So the single-radio branch (`main`'s list) only runs while the store really
  is one radio's.
- A node nobody else observed is deleted with its observations (`deleteFromApp`), as Delete Node
  does (T146).
- A node another radio observed loses only this radio's observation and answer (T400).
- Favorites stay excluded: a node is a favorite if any radio has it as one.

How V35-2 is fixed:

- `heardOnCurrentLoraSession` (`AccessoryManager.swift:1694`) needs the recorded radio to be the
  session's. So nothing is stored, shown or offered for a radio until it has claimed the answers.
- The MyInfo claim runs after `updateDevice` sets the session's node number and after the
  renumber, which moves the record (`HeardOnCurrentLoraAnswers.renumber`).
- A radio's packets are handled in order on its event task (`AccessoryManager+Connect.swift:304`).
  So the claim's clear finishes before anything that radio reports is stored.
- If a second radio connects while a claim awaits its clear, the claim doesn't record (`guard
  session === soleConnectedSession`), and the second radio's `set(0)` stands.
- The record is set at launch, before any connect (`MeshtasticApp.swift:151`). A store from
  `main` keeps its answers when its own radio connects.
- HANDOFF already records the one gap I'd have raised: a restore from Settings › Backups brings
  in the backup's answers without changing whose they're recorded as.

## Findings

### V36-1 (low): Remove Them's keep path rewrites the node on the main context, from observations read before the loop

`UnheardNodesBanner.removeUnheardNodes` keeps a node another radio observed. It works on the
view's context, the main context:
- it reads every other radio's observation once, before the loop (`:335`);
- then, per node, after awaiting the radio's acknowledgement (`sendRemoveNode`, `:351`), it
  deletes this radio's observation and rewrites the node with `reaggregate` (`:353`, `:124`).

`removeRadioData` runs the same `reaggregate` on the packet actor, the context that writes
observations (`MeshPackets+RadioRemoval.swift:263`).

On the main context:
- **Stale values.** T382 showed on device that the main context can keep values other contexts
  have since saved. Observation objects it has already loaded (Heard By,
  `NodeHeardBySection.swift:47`, or the notice's own fetch) can carry older hops, SNR, RSSI, MQTT
  flag, channel slot and last heard. The loop can take a while, one admin round trip per node.
  Meanwhile the actor keeps
  updating those observations as their radios hear the node. The kept node's fields are written
  from the older values, and the "only if current" check (`newest < shown - currentWindow`)
  compares them. It heals at the node's next packet, when the actor aggregates again.
- **Unsaved observations.** This radio's observation is found by a main-context fetch, which only
  sees saved rows. One the actor has inserted but not yet saved (its saves are debounced up to 5
  s) isn't deleted. It's saved later, and the node comes back to this radio's list and the next
  offer.
- **A radio connecting mid-loop.** The loop doesn't stop if a second radio connects. From then on
  no radio's answers are kept, and a node the new radio observes during the loop isn't in the
  snapshot, so it's deleted from the app.

Each of these needs timing, and the result is display fields until the next packet, or one
node offered again. It's low, but it's the stale-context class this branch has fixed elsewhere
(T382, V24).

**Suggested fix.**
- Do the app side on the packet actor: a `MeshPackets` method, called after `sendRemoveNode`,
  that flushes, deletes this radio's observation (saved or pending), clears the answer, and
  either rewrites the node from the others' current observations or deletes it with every
  observation. That's `removeRadioData`'s pattern, for one node.
- In the loop, stop once `reportsHeardOnCurrentLora(forRadio:)` is false for the window's radio.
- A test that the kept node's fields come from the other radio's latest observation would pin it.

## Minors

1. **`nodes.md:111`.** It says the marker and notice come back "once a radio connected on its
   own has sent its node list". When the second radio leaves, the radio left isn't asked for its
   node list again. That only happens at its next connect or a LoRa change in its window, as the
   HANDOFF device check says. The user page could say so.
2. **The result count.** After a partial run, "Removed N nodes." counts nodes kept in the app for
   other radios as removed. The confirmation explains it beforehand, so this is optional.

## Checked and found fine

- **`claimHeardOnCurrentLora` call sites.**
  - MyInfo: after the node number and the renumber.
  - NodeInfo: before `nodeInfoPacket` writes.
  - Each packet: before `updateAnyPacketFrom`.
  - These are the only paths that store an answer: `nodeInfoPacket`, `updateAnyPacketFrom` and
    `markAbsentFromRadio`, the last gated by `dumpWasRequested`, which needs the sole session.
  - Once claimed, each call is a cheap check.
- **Old firmware.** A radio alone on firmware without the field still claims, so the previous
  radio's answers are cleared. Nothing is stored for it.
- **Several radios.** `set(0)` plus a full clear. A packet from the first radio decided just
  before can still land after the clear, but it can only store `true` (heard), which hides a
  marker and offers nothing.
- **The aggregated path of `updateAnyPacketFrom`.** It now sets `true` when heard. Without that,
  a node several radios observed kept its marker until the next download, and the notice's
  re-check couldn't see it heard.
- **`removeNode` split.** Delete Node still sends first and deletes the node, user and every
  observation only if the send succeeds. It throws without a connected radio, as before.
- **The keep path against D-18.** It mirrors removing a radio:
  - this radio's observation goes, and the node stays with the others' view;
  - `reaggregate` is moved unchanged;
  - favorite, ignored and the verified key aren't recomputed, as with radio removal;
  - the answer is cleared, so the node isn't offered again.
- **Removing every node of a single-radio store.** Same as `main`, plus the observations.
- **Docs.** `swiftdata.md` and `nodes.md` describe the claim, the candidates and D-18 removal.
  HANDOFF has device checks for both commits. T400's new confirmation string is listed for T134.

## Still open

- V36-1 and the minors.
- Per-radio answers on `NodeObservationEntity`: the owner's call.
- Strings: T134 (with T400's confirmation). Docs HTML: T122.
- The device checklist (T399, T400).
- Committing this review.
