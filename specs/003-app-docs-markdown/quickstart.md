# Quickstart: App Documentation Feature (003-app-docs-markdown)

## Prerequisites

- Xcode (latest release)
- Homebrew (`brew install cmark-gfm`)
- GitHub CLI (`brew install gh`) — for PR creation
- Node.js is **not** required

## 1. Install `cmark-gfm`

```bash
brew install cmark-gfm
cmark-gfm --version   # Should print cmark-gfm 0.29.x or later
```

## 2. Write or edit a doc page

Markdown source lives in `docs/user/` (User Guide) or `docs/developer/` (Developer Guide).

```bash
# Example: edit the Messages doc
open docs/user/messages.md
```

Each page uses standard GFM. Front matter is optional (used by Jekyll for the web site):

```markdown
---
title: Messages & Channels
parent: User Guide
nav_order: 3
---

# Messages & Channels

...your content here...
```

## 3. Build the in-app HTML bundle

```bash
bash scripts/build-docs.sh --output Meshtastic/Resources/docs
```

This:
- Converts every `.md` in `docs/user/` and `docs/developer/` to HTML using `cmark-gfm`
- Injects the shared CSS (`Meshtastic/Resources/docs/assets/docs.css`)
- Builds `Meshtastic/Resources/docs/index.json` (keyword index)
- Prints bundle size; warns if > 8 MB, fails if > 10 MB

**On success** you'll see:
```
✅ Built 25 pages → Meshtastic/Resources/docs/
📦 Bundle size: 3.2 MB / 10 MB limit
```

## 4. Copy screenshots into the bundle

```bash
bash scripts/copy-snapshots.sh --output Meshtastic/Resources/docs/assets/screenshots
```

Copies all PNGs from `MeshtasticTests/__Snapshots__/SwiftUIViewSnapshotTests/` into the bundle assets directory.

## 5. Build and run the app

Open `Meshtastic.xcworkspace` in Xcode and run on a simulator or device. Navigate to **Settings → Help & Documentation** to browse the docs.

To test the deep link:

```
meshtastic:///settings/helpDocs
```

## 6. Preview the Jekyll site locally (optional)

```bash
cd docs
bundle exec jekyll serve --livereload
# Open http://localhost:4000
```

Requires `gem install bundler jekyll just-the-docs jekyll-redirect-from`.

## 7. Commit generated assets

The generated HTML and JSON are **source-controlled** and must be committed alongside the markdown source:

```bash
git add Meshtastic/Resources/docs/
git commit -m "Rebuild doc bundle: add messages page"
```

The CI pipeline also regenerates assets on every push to `main`, but committing locally ensures the bundle is always in sync with the source.

## Key file locations

| File | Purpose |
|------|---------|
| `docs/user/*.md` | User Guide markdown source |
| `docs/developer/*.md` | Developer Guide markdown source |
| `docs/_config.yml` | Jekyll config (just-the-docs theme) |
| `Meshtastic/Resources/docs/index.json` | Keyword index (generated) |
| `Meshtastic/Resources/docs/assets/docs.css` | Light/dark CSS |
| `Meshtastic/Resources/docs/assets/screenshots/` | Screenshot PNGs (copied from test snapshots) |
| `scripts/build-docs.sh` | GFM → HTML conversion script |
| `scripts/copy-snapshots.sh` | PNG copy script |
| `.github/workflows/docs-deploy.yml` | CI: continuous beta deploy |
| `.github/workflows/docs-release.yml` | CI: versioned release deploy |
| `Meshtastic/Views/Settings/HelpAndDocumentation/` | App UI views |
| `Meshtastic/Router/NavigationState.swift` | `helpDocs` deep link case |

## Troubleshooting

**`cmark-gfm: command not found`**  
Run `brew install cmark-gfm`.

**Bundle size exceeds 10 MB**  
Reduce screenshot resolution or remove lower-priority snapshots from `copy-snapshots.sh`. Raise the limit by editing `DOCS_SIZE_LIMIT_BYTES` in `build-docs.sh` with a PR justification.

**AI assistant not visible**  
Foundation Models requires iOS 26+ and an Apple Intelligence-capable device. The AI input is hidden on iOS 17/18 and on macOS by design (FR-010).

**`WKWebView` shows white flash in dark mode**  
Ensure `backgroundColor` and `underPageBackgroundColor` are set to `UIColor.systemBackground` in `DocPageView.swift`.
