# Contract: docs-release-gate.yml

**Phase 1 output for plan.md**  
**Workflow**: `.github/workflows/docs-release-gate.yml`  
**Date**: 2026-06-05

---

## Purpose

Advisory validation workflow that fires on every `v*.*.*` tag push and confirms
that no bundled HTML file in `Meshtastic/Resources/docs/` contains the
`pre-release-banner` string. Fails loudly to alert the developer; does not block
any other pipeline.

---

## Trigger

```yaml
on:
  push:
    tags:
      - 'v*.*.*'
```

---

## Runner

`ubuntu-latest` — no macOS runner needed; this is a plain `grep` operation.

---

## Inputs

None. The workflow reads from the tag's committed state (the checked-out repo).

---

## Steps

| # | Step | Action |
|---|---|---|
| 1 | Checkout | `actions/checkout@v4` at the pushed tag |
| 2 | Scan HTML files | `grep -rl "pre-release-banner" Meshtastic/Resources/docs/ --include="*.html"` |
| 3 | Report results | Output matching file list; fail if any found |

> **Note**: The scan MUST be scoped to `*.html` files. `Meshtastic/Resources/docs/assets/docs.css`
> always contains `.pre-release-banner` as a CSS class selector — an unscoped grep produces
> a false-positive failure on every tag push.

---

## Outputs

### On success (no banner found)

```
✓ No pre-release-banner found in Meshtastic/Resources/docs/
  Scanned: <N> HTML files
```
Workflow exits 0.

### On failure (banner found)

```
✗ pre-release-banner found in the following files:
  Meshtastic/Resources/docs/user/messages.html
  Meshtastic/Resources/docs/developer/architecture.html
  ...

Run 'bash scripts/cut-release-docs.sh <version>' and push the updated commit,
then delete and recreate this tag.
```
Workflow exits 1.

---

## Advisory nature

This workflow is **informational only**. It is not configured as a required
status check on any branch protection rule. A failed run does not block:
- The `docs-release.yml` Jekyll/GitHub Pages deploy
- Xcode Cloud builds triggered by the same tag
- App Store Connect submission

The developer is responsible for observing the failure and recutting the tag.

---

## Relationship to docs-release.yml

| Property | `docs-release.yml` | `docs-release-gate.yml` (new) |
|---|---|---|
| Trigger | `v*.*.*` tag push | `v*.*.*` tag push |
| Purpose | Deploy Jekyll site to GitHub Pages | Validate in-app HTML has no beta banner |
| Runner | `ubuntu-latest` (+ `macos-15` for snapshots) | `ubuntu-latest` |
| Blocking | No | No (advisory) |
| Target artifact | `docs/` Jekyll source → GitHub Pages | `Meshtastic/Resources/docs/*.html` |

The two workflows are independent; neither depends on the other.
