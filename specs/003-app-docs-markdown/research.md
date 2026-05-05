# Research: App Documentation (Jekyll Site + In-App AI)

## R-001: GitHub Actions Pipeline Architecture (resolves FR-003 conflict)

**Decision**: Use a single macOS GitHub Actions runner (`macos-15`) for all doc build steps. The pipeline: (1) installs `cmark-gfm` via Homebrew, (2) runs `scripts/build-docs.sh` to convert GFM → HTML with CSS injection and build the keyword index, (3) runs `scripts/copy-snapshots.sh`, (4) deploys via `actions/deploy-pages` (artifact upload + `actions/deploy-pages@v4`). Native GitHub Pages Jekyll build is disabled via a `.nojekyll` file in the output directory.

**Rationale**: A macOS runner is required because the snapshot test step (FR-012a) needs Xcode + iOS Simulator. Using the same runner for all steps avoids cross-runner artifact sharing complexity. `cmark-gfm` is a standard Homebrew formula and installs in < 5 seconds.

**Alternatives considered**:
- ubuntu-latest runner: Rejected — cannot run Xcode/iOS Simulator for snapshot tests. `cmark-gfm` is available on Linux but snapshot regeneration would require a separate macOS job, adding complexity.
- Native GitHub Pages Jekyll: Rejected — does not support `cmark-gfm` pre-processing, versioned paths, or size enforcement.
- Separate jobs for build vs. snapshot: Considered for parallelism. Deferred — the 10-minute SC-005 target is achievable in a single serial job for the initial scope (~25 pages, ~57 screenshots).

**Implementation path**: Two workflow files: `docs-deploy.yml` (push to `main` → `/beta/` deploy) and `docs-release.yml` (tag `v*.*.*` push → `/vX.Y.Z/` deploy + update `latest` symlink).

---

## R-002: `just-the-docs` Version Selector Support

**Decision**: Use `just-the-docs` v0.11+ which natively supports a version dropdown via `_data/versions.yml`. The site root `index.md` uses a Jekyll redirect plugin (`jekyll-redirect-from`) to point `/ → /latest/`.

**Rationale**: `just-the-docs` 0.11 added built-in version selector support. The `_data/versions.yml` file lists all published versions; the CI pipeline appends a new entry on each release. `jekyll-redirect-from` is whitelisted on GitHub Pages but since we use Actions deployment there is no plugin restriction.

**Alternatives considered**:
- Custom version dropdown in `_includes/`: Viable but more maintenance. Rejected in favour of native theme support.
- Separate Jekyll sites per version: Rejected — exponential maintenance cost as versions accumulate.
- `minima` fallback theme: Reserved as fallback assumption in spec. Not needed — `just-the-docs` 0.11 is stable.

**Implementation path**: `_config.yml` sets `theme: just-the-docs`. `_data/versions.yml` is updated by the release workflow. The `docs-release.yml` workflow appends the new version entry and redeploys.

---

## R-003: `cmark-gfm` HTML Output + CSS Injection Strategy

**Decision**: `scripts/build-docs.sh` calls `cmark-gfm --extension=table,strikethrough,autolink,tasklist,tagfilter --unsafe` per `.md` file, then wraps the output in a minimal HTML template that includes a `<link rel="stylesheet" href="../assets/docs.css">` tag. The CSS file (`Meshtastic/Resources/docs/assets/docs.css`) uses `prefers-color-scheme` CSS variables for light and dark themes.

**Rationale**: `cmark-gfm` with the above extensions covers all GFM features required by FR-007 (tables, task lists, fenced code, inline images, strikethrough, autolinks). The `--unsafe` flag is required to allow raw HTML in source (used by existing help content). The CSS is a single shared file — not inlined per page — to keep HTML files small and the total bundle within 10 MB.

**CSS colour variables (minimum required)**:
```css
:root { --bg: #fff; --text: #1a1a1a; --link: #0070f3; --code-bg: #f4f4f5; }
@media (prefers-color-scheme: dark) {
  :root { --bg: #1c1c1e; --text: #f0f0f0; --link: #66b2ff; --code-bg: #2c2c2e; }
}
body { background: var(--bg); color: var(--text); }
a { color: var(--link); }
pre, code { background: var(--code-bg); }
```

**Alternatives considered**:
- Pandoc: More powerful but adds a large dependency. Rejected for simplicity.
- `marked` (Node.js): Rejected — FR-016 explicitly chose `cmark-gfm` to avoid Node.js runtime.
- Inline CSS per page: Rejected — increases bundle size unnecessarily.

**Implementation path**: `build-docs.sh` uses a `TEMPLATE` heredoc containing `<html><head><link rel="stylesheet" ...><meta name="viewport" ...></head><body>{{CONTENT}}</body></html>`, substituting `{{CONTENT}}` with `cmark-gfm` stdout.

---

## R-004: Keyword Index JSON Structure for Foundation Models Retrieval

**Decision**: The keyword index is a JSON array of page descriptor objects. Each object has: `id` (page filename stem), `title`, `section` (user/developer), `keywords` (array of significant terms extracted from the page), and `charCount` (pre-computed character count for token budget estimation at ~3.5 chars/token).

**Rationale**: At query time, the app tokenizes the user's question, lowercases and stems it, and counts keyword matches against each page's `keywords` array. The top 2–3 pages by match count are selected. Token budget is enforced by summing `charCount / 3.5` for selected pages and trimming until under 3,000 tokens.

**Index entry format**:
```json
{
  "id": "messages",
  "title": "Messages & Channels",
  "section": "user",
  "keywords": ["channel", "message", "direct", "encryption", "key", "ack", "lock", "primary", "broadcast"],
  "charCount": 4820
}
```

**Alternatives considered**:
- Full-text search index (e.g., Lunr.js style): Overkill for ~25 pages on-device. Rejected.
- Vector embeddings (NaturalLanguage framework): TN3193 suggests this for large corpora. At 25 pages, keyword matching is sufficient and avoids CoreML complexity.
- Store full page text in index: Rejected — bloats the index and duplicates the HTML files in the bundle.

**Implementation path**: `build-docs.sh` extracts keywords from each HTML file using a grep pipeline (strip tags, lowercase, sort, dedup, take top 30 words excluding stop words). `charCount` is computed with `wc -c`. The index is written to `Meshtastic/Resources/docs/index.json`.

---

## R-005: WKWebView on macCatalyst

**Decision**: `WKWebView` is fully available on macCatalyst with no special entitlements. `underPageBackgroundColor` is available from macOS 12+ (Catalyst 15+). The `UIViewRepresentable` wrapper is usable without `#if !targetEnvironment(macCatalyst)` guards.

**Rationale**: `WKWebView` is part of WebKit, which is available on all Apple platforms including macCatalyst. Unlike some UIKit APIs, `WKWebView` does not require `#if canImport(UIKit)` guarding on Catalyst — it bridges automatically. `underPageBackgroundColor` was introduced in iOS 15 / macOS 12, both within the deployment target.

**Alternatives considered**:
- `SFSafariViewController`: Rejected — cannot load local bundle resources offline.
- SwiftUI native HTML renderer: Does not exist — `WKWebView` via `UIViewRepresentable` is the standard approach.

**Implementation path**: `DocPageView` is a `UIViewRepresentable` wrapping `WKWebView`. Sets `backgroundColor = .systemBackground`, `underPageBackgroundColor = .systemBackground`. Loads via `webView.loadFileURL(_:allowingReadAccessTo:)` with the `docs/` bundle subdirectory as the allowed access root.

---

## R-006: Xcode Copy Files Build Phase — `docs/` Bundle Subdirectory

**Decision**: Add a "Copy Files" build phase to the `Meshtastic` target with destination "Resources" and subpath `docs`. All files in `Meshtastic/Resources/docs/` are added as build phase members. Swift accesses them via `Bundle.main.url(forResource: "messages", withExtension: "html", subdirectory: "docs/user")`.

**Rationale**: The Copy Files build phase is the simplest Xcode-native mechanism for copying a directory tree into the app bundle. No additional SPM package or resource bundle target is needed. The `Meshtastic/Resources/docs/` directory is source-controlled, so the generated HTML is committed and the build phase is stable across developer machines.

**Alternatives considered**:
- `Bundle.module` (SPM resource): Rejected — the app target is not a Swift Package, and adding one just for docs is over-engineering.
- Run Script build phase to copy at build time: Rejected — this would require `cmark-gfm` to be installed on every developer machine. Instead, the HTML is pre-generated and committed.

**Implementation path**: In Xcode project editor: Target → Build Phases → + Copy Files → Destination: Resources, Subpath: `docs`. Add `Meshtastic/Resources/docs/**` as members. The `build-docs.sh` script is run separately by developers and CI — not as an Xcode build phase.

---

## R-007: Navigation Integration — `helpDocs` in `SettingsNavigationState`

**Decision**: Add `case helpDocs` to `SettingsNavigationState` (raw value `"helpDocs"`). In `Settings.swift`, add a `NavigationLink(value: SettingsNavigationState.helpDocs)` entry in a new "Help" section at the bottom of the Settings list. In `Router.routeSettings(_:)`, the existing `rawValue` init on `SettingsNavigationState` already handles the new case automatically — no code change needed in `Router.swift`.

**Rationale**: The `routeSettings(_:)` function already does `SettingsNavigationState.init(rawValue: segment)` — adding the new enum case with a matching raw value string is sufficient for deep link routing. The `NavigationLink(value:)` pattern used by all other Settings rows is established and consistent.

**Implementation path**:
1. Add `case helpDocs` to `SettingsNavigationState` in `NavigationState.swift`.
2. Add `.navigationDestination(for: SettingsNavigationState.self)` case `.helpDocs` in `Settings.swift` to push `DocBrowserView`.
3. Add `NavigationLink(value: SettingsNavigationState.helpDocs)` with SF Symbol `questionmark.circle` in a new "Help" `Section` in `Settings.swift`.
4. Update README deep-link table with `meshtastic:///settings/helpDocs`.
