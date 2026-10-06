# Review V38: the V37 fix (T404)

Branch `feature/multi-radio` at `d58c7711`, working tree clean. This review checks the one commit
since V37 against the files.

## What changed since V37

`d58c7711` (T404) fixes V37-1 and the four minors:
- **V37-1.** Node detail's heard-on-current-LoRa lookup is keyed on the node too
  (`NodeLoraAnswerKey`, `AccessoryManager.nodeLoraAnswerKey(of:for:)`, `NodeDetail.swift:180`).
- **Minor 1.** The comments in `LoRaConfig`, `UnheardNodesRemoval`, `removeUnheardNode`,
  `NodeInfoEntity.heardOnCurrentLora` and `isUnheardOnCurrentLora` describe per-radio answers.
  `NodeRowRefreshKey` follows the node's own answer only when the row isn't given the window's.
- **Minor 2.** HANDOFF's T398 paragraph describes the current state.
- **Minor 3.** D-18 in `spec.md` records Remove Them's rule.
- **Minor 4.** Remove Them's re-check asks the packet actor (`MeshPackets.loraAnswer`), which saves
  pending writes first.

## How it was checked

- **Tests:** one run of `MultiRadioUnheardOnCurrentLoraTests`, `UnheardOnCurrentLoraTests`,
  `RadioRemovalTests`, `NodeListRowRefreshDecisionTests` and `MultiRadioIngestTests` in the iOS
  Simulator. 72 tests in 5 suites, all passed, including the three new ones. The build recompiled
  the touched files with no compiler warnings and changed no tracked files.
- **SwiftLint:** the 9 Swift files changed, linted at `b9801569` and `d58c7711`, give the same
  violations (one: `NodeDetail`'s existing type body length).
- **Removed lines:** only the replaced comments, the old task key, the old row key line and the old
  re-check. Nothing else is undone. Every touched file ends in a newline. No docs changed, so the
  bundle still matches its sources.

## The V37 findings

| Finding | Status | Notes |
|---|---|---|
| V37-1 node detail kept the previous node's marker in a split view | Fixed | Below. |
| Minor 1 stale comments | Done | Each now matches the code. |
| Minor 2 HANDOFF's T398 paragraph | Done | Describes per-radio answers, with T399 as history. |
| Minor 3 Remove Them's rule in `spec.md` | Done | Recorded in D-18 (`spec.md:41`). |
| Minor 4 the re-check missed unsaved answers | Done | `loraAnswer`, below. |

How V37-1 is fixed:
- `NodeDetail` is initialised with the selected `nodeNum`, and V37's probe showed its body runs
  again with the new value when the selection changes. The task's id now includes it, so the
  lookup runs for each node shown, and still when the radio's node database is saved.
- `refreshUnheardOnCurrentLora` reads the current `nodeNum`, and the
  `heardOnCurrentLoraDidChange` refresh is unchanged.
- No other view looks up one node's answer: the lists and the map use the per-radio set
  (`UnheardOnCurrentLoraRefresh`), which isn't per node.
- `nodeDetailKeyFollowsTheNode` covers the key. HANDOFF has the device check (iPad at regular
  width or the Mac, a marked node, then an unmarked one).

How minor 4 is fixed:
- `loraAnswer` (`MeshPackets+RadioRemoval.swift:259`) runs on the packet actor and flushes the
  debounced save first. It reads through `observations(ofNode:radioNum:)`, which puts the window's
  radio first (`lookupRadios(first:)`) and also returns observations inserted but not yet saved.
- So a node the radio heard moments ago counts as heard and isn't removed, from the radio or the
  app. `recheckSeesUnsavedAnswer` covers it.
- The extra save per node costs nothing that matters:
  - the loop already waits on one admin round trip per node;
  - `removeUnheardNode` already saved once per node;
  - a node database download that is ingesting meanwhile already saves at least every 5 s
    (`deferSave`).
- `RadioLoraAnswers.Answer` holds a `Bool?` and a `Bool`, so returning it from the actor is
  `Sendable`. The target has no default main-actor isolation.

## Findings

None.

## Checked and found fine

- **The row key.** `heardOnCurrentLora` drops out of `NodeRowRefreshKey` whenever the window's
  answer is given, which every app call site does. So another radio's download no longer re-keys
  rows, and previews still re-key on the node's own answer. `rowKeyFollowsTheWindowsAnswer` covers
  it.
- **D-18's new sentence matches the code.** `removeUnheardNode` keeps a node while any other radio
  has an observation of it (`stays = !others.isEmpty`), not for a shared network. "Still has it"
  means an observation. That includes one whose radio's last download left the node out (its answer
  is then nil): the node stays for that radio until its own window's Remove Them takes it. Radio
  removal counts observations the same way, and nodes.md's "Once the last radio that had it removes
  it too, it leaves the app" says so.
- **The new comments** on `NodeInfoEntity.heardOnCurrentLora`, `isUnheardOnCurrentLora` and
  `removeUnheardNode` match the code: `main`'s copy is last-writer-wins and views don't read it, and
  Remove Them is `removeRadioData`'s rule for a radio on a network of its own.
- **HANDOFF.** The status note and the T403 device check are current, the full-suite baseline is
  T404's, and the new lines stay within the file's wrap width.

## Still open

- Strings: T134 (with T400/T403's confirmation text).
- T122: the bundle matches its sources at `d58c7711`. Rebuild once more as the last step before the
  PR if docs change again.
- The device checklist (T399–T404).
- Committing this review.
