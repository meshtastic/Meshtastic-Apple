# Review V21: quick check after the merge fixes (feature/multi-radio)

Branch `feature/multi-radio` at `503e2210`. V20 (`review-connections-v20.md`) checked the merge
commit `3e3d204c`. Since then:
- `bc10c084` points the protobufs submodule back at main's commit;
- `e75ddbcf` checks the window's radio for the coding-rate override;
- `503e2210` records V20 and data V15.

Not pushed (no upstream). Working tree clean apart from two untracked files that aren't part of
this (`xcodecloud/`, `research/hang-risks-2026-10-02.md`). No merge or rebase in progress.

Checked in the files only; nothing built or run, nothing changed.

## Where the V20 findings stand

| V20 | What | Now |
|---|---|---|
| M1 | `protobufs` pointed at the branch's old `e6e1d1a9` | Fixed: `ad0bf31e`, main's, both in the tree and checked out. |
| M2 | `CodingRateRows` checked the first radio's firmware | Fixed: `isVersionSupported(forVersion:for: windowRadio)`, as `supports2_8` does. |

## Findings

None in the code.

One stale reference in the docs: `review-data-v15.md:11` and `:38` name `review-merge-main.md` as
the other review. That file no longer exists; it's `review-connections-v20.md`. It's the data
reviewer's file, so I left it alone.

## Checked and found fine

- V20's whole-merge checks, re-run at the branch tip:
  - The files only main changed differ from main only in the four deliberate adaptations
    (`MainScene`, `MapWindow`, `BackupRestoreSection`, the docs index). `protobufs` now matches
    main.
  - The files only the branch changed differ from the branch only in the deliberate adaptations
    (`WindowRouters`, `RadioWindowViews`, three tests, the architecture doc, the Copilot
    instructions).
  - No conflict markers anywhere.
  - The generated protobuf Swift is identical to main's, and matches the pointer again (the fix
    commit says regenerating against `ad0bf31e` changes nothing).
  - No first-radio version check is left in main's new code.
- `e75ddbcf` only adds `@Environment(\.windowRadio)` and swaps the one call. With one radio, or in
  the first radio's window, `isVersionSupported(forVersion:for:)` is exactly
  `checkIsVersionSupported`, so nothing changes there.
- `503e2210` commits `review-connections-v20.md` as written, `review-data-v15.md`, T375 and T376,
  and the handoff note. The tasks describe both fixes as they are in the code.
