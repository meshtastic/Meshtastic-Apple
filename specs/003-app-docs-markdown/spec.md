# Feature Specification: App Documentation (Jekyll Site + In-App AI)

**Feature Branch**: `003-app-docs-markdown`  
**Created**: 2026-05-05  
**Status**: Implemented  
**Input**: User description: "Complete markdown documentation for the Meshtastic Apple app — served as a GitHub Pages Jekyll site, bundled in-app for offline browsing and Foundation Models Q&A, with GitHub Actions CI auto-regeneration on push to main. Covers both end users and developers. Uses existing snapshot test images."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - End User Reads Docs on the Web (Priority: P1)

A new Meshtastic user visits the GitHub Pages site to learn how to connect their first device, send a message, and read a map. They can navigate a structured doc site with screenshots, find the topic they need, and return when they have a question.

**Why this priority**: This delivers immediate value to the largest audience (end users) and has zero app-side complexity — it's a standalone deliverable.

**Independent Test**: Navigate the deployed GitHub Pages URL, find "Getting Started", follow the steps end to end, and reach the Nodes tab successfully.

**Acceptance Scenarios**:

1. **Given** a user visits the GitHub Pages site root, **When** they click "Getting Started", **Then** they see a step-by-step guide to connecting a Meshtastic device with at least one screenshot per major step.
2. **Given** a user is on any doc page, **When** they use the navigation sidebar, **Then** they can reach any other doc page in two clicks or fewer.
3. **Given** a user lands on a feature page (e.g., "Messages"), **Then** they see at least one screenshot of the relevant screen and a plain-language explanation of every visible control.

---

### User Story 2 - End User Browses Docs Inside the App (Priority: P2)

A user already running the app taps "Help" or a docs link and sees the same markdown documentation rendered natively, without needing a network connection.

**Why this priority**: High-value because it meets users exactly where they are. Bundling at build time means no runtime fetch failures.

**Independent Test**: Put the device in airplane mode, open the in-app doc browser, navigate to "Messages", and read the full article.

**Acceptance Scenarios**:

1. **Given** the app is installed, **When** the user opens the in-app Help browser, **Then** a table of contents with all doc sections is shown within 1 second.
2. **Given** a doc page contains images, **When** the page renders, **Then** screenshots from the snapshot test suite appear inline.
3. **Given** the device has no internet connection, **When** the user opens any doc page, **Then** all content loads successfully from the bundle.

---

### User Story 3 - End User Asks the App a Question with AI (Priority: P3)

A user types "How do I set a channel password?" into the in-app AI assistant. Using the bundled documentation as its knowledge base, the app answers using only on-device Foundation Models — no data leaves the device.

**Why this priority**: High novelty and user delight, but depends on Stories 1 & 2. iOS 26+ only.

**Independent Test**: On an iOS 26+ device, open the doc assistant, ask "How do I add a waypoint?", and receive an accurate answer sourced from the bundled docs.

**Acceptance Scenarios**:

1. **Given** an iOS 26+ device, **When** the user submits a question, **Then** a response appears within 5 seconds sourced exclusively from bundled documentation.
2. **Given** an iOS 17/18 device (no Foundation Models), **When** the user opens the Help tab, **Then** a standard doc browser is shown with no AI elements visible.
3. **Given** a question outside the scope of the docs, **When** answered, **Then** the response acknowledges the limitation rather than hallucinating.

---

### User Story 4 - Developer Reads Architecture Docs (Priority: P4)

A contributor to the codebase navigates to the `/docs/developers/` section of the GitHub Pages site to understand the architecture, how to add a new tab, or how the BLE stack works.

**Why this priority**: Valuable for the contributor community, but lower urgency than end-user content.

**Independent Test**: A developer with no prior Meshtastic experience reads the Architecture doc and can describe the flow from BLE packet receipt to SwiftData persistence.

**Acceptance Scenarios**:

1. **Given** the docs site, **When** a developer visits "Developer Guide", **Then** they see separate pages for Architecture, Contributing, Testing, and Adding Features.
2. **Given** a developer looks at any API/module page, **Then** the key types and their responsibilities are described without requiring source code access.

---

### User Story 5 - Docs Stay Current Automatically (Priority: P5)

When a developer merges a PR to `main`, GitHub Actions detects changes to doc-relevant source files and regenerates affected doc pages, re-runs snapshot tests to refresh screenshots, and commits updated files back to the repo.

**Why this priority**: This ensures the system remains maintainable long-term. Without this, docs go stale within weeks.

**Independent Test**: Merge a PR that renames a UI string. Within the CI run, the corresponding doc page is updated to use the new string and a fresh screenshot is committed.

**Acceptance Scenarios**:

1. **Given** a push to `main`, **When** the CI workflow runs, **Then** snapshot tests execute and any changed PNGs are committed to `docs/assets/screenshots/`.
2. **Given** a CI run, **When** complete, **Then** the GitHub Pages site reflects the latest content within 10 minutes.
3. **Given** CI fails (e.g., snapshot test fails), **When** the run completes, **Then** the workflow reports failure and does not publish broken docs.

---

### Edge Cases

- What if Foundation Models is unavailable mid-session (e.g., model unloaded)? Show a fallback message and offer to open the doc page directly.
- What if a snapshot image is missing for a doc page? Render the page without the image — do not block the page or show a broken image placeholder.
- What if the CI workflow runs on a branch without a simulator available? Skip snapshot regeneration and emit a warning; do not fail the full CI run.
- What if the user asks a question in a language other than English? Foundation Models should respond in the user's language where the model supports it; otherwise answer in English.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The documentation system MUST produce markdown files organised into at least two top-level sections: **User Guide** and **Developer Guide**.
- **FR-002**: Every User Guide page MUST include at least one screenshot sourced from the existing snapshot test suite where a corresponding snapshot exists.
- **FR-003**: The Jekyll site MUST be built and deployed via a GitHub Actions workflow using `actions/deploy-pages`. The workflow is responsible for all pre-processing steps (`cmark-gfm` conversion, versioned path assembly, size checks) before passing the output to the GitHub Pages deployment action. Native GitHub Pages Jekyll build MUST be disabled (`_config.yml` with `plugins: []` and a `.nojekyll` file in the output directory).
- **FR-004**: A `_config.yml` MUST configure Jekyll with the `just-the-docs` theme (or equivalent minimal theme) providing sidebar navigation, page search, and a navigation hierarchy matching the doc section structure.
- **FR-005**: All markdown documentation files MUST be co-located under `docs/` in the repository root so they are committed alongside source code and tracked in version control.
- **FR-006**: The app MUST expose Help & Documentation as a section within the Settings tab, presenting a full-screen doc browser. No new tab bar item is required.
- **FR-007**: The in-app doc browser MUST render **GitHub Flavored Markdown** (headings, bold, italic, tables, task lists, links, fenced code blocks, and inline images) by loading locally-bundled HTML files — converted from GFM at build time — in a `WKWebView`, without requiring network access.
- **FR-008**: Screenshot images used in docs MUST be sourced from `MeshtasticTests/__Snapshots__/` and copied to `docs/assets/screenshots/` as part of the build/CI process.
- **FR-009**: On iOS 26+, the Help & Documentation section (Settings sub-section per FR-006) MUST expose a text input field allowing the user to ask free-text questions answered by an on-device Foundation Model using the bundled docs as context.
- **FR-010**: On iOS 17/18, the Help & Documentation section MUST show only the standard doc browser — no AI input field or model loading indicators.
- **FR-011**: The Foundation Models integration MUST use a pre-built keyword index (a JSON file generated at build time) to retrieve the top 2–3 most relevant documentation pages for a given question. The combined token count of retrieved doc text passed as context MUST NOT exceed 3,000 tokens (measured via `SystemLanguageModel.tokenCount(for:)` before querying), leaving sufficient headroom within the 4,096-token session ceiling (per Apple TN3193) for the system instructions, user question, and model response. Only the text of those pages MUST be passed as context — not raw source code, private data, or the full documentation corpus.
- **FR-012**: A GitHub Actions workflow MUST trigger on every push to `main` and: (a) run snapshot tests, (b) copy updated PNGs to `docs/assets/screenshots/`, (c) deploy the Jekyll site to GitHub Pages.
- **FR-013**: When CI detects changed screenshot PNGs, it MUST open an automated PR from a `bot/update-snapshots` branch targeting `main` — it MUST NOT commit directly to `main`.
- **FR-014**: The doc system MUST cover the following feature areas at minimum: Getting Started / Onboarding, Bluetooth Device Connection, Messages & Channels, Nodes List, Map & Waypoints, Settings (Radio, LoRa, Bluetooth, Display, User), Telemetry & Sensors, TAK Integration, MQTT, Local Mesh Discovery, Firmware Updates, Apple Watch App.
- **FR-015**: Developer Guide MUST cover: Architecture Overview, Codebase Structure, Adding a New Tab/Feature, BLE / TCP Transport, SwiftData Schema & Migrations, Testing (unit + snapshot), Contributing & PR Workflow.
- **FR-016**: The build script that converts GFM documentation to bundled HTML MUST use `cmark-gfm` (installable via `brew install cmark-gfm`). The script MUST fail with a clear error if `cmark-gfm` is not installed, and the CI workflow MUST install it before invoking the script.
- **FR-025**: The `build-docs.sh` script MUST strip Jekyll YAML frontmatter (`--- … ---`) and Kramdown attribute lines (`{: .xxx }`) from markdown before passing it to `cmark-gfm`, so that neither artifact renders as literal text in the generated HTML.
- **FR-026**: The build script MUST post-process cmark-gfm output to convert Tip and Warning blockquotes (e.g., `> **Tip — …**`) into styled `<div class="tips-callout">` / `<div class="warning-callout">` elements. The pre-release beta banner MUST use `class="pre-release-banner"` (not inline styles) so that dark-mode CSS variables apply correctly.
- **FR-027**: The in-app bundled CSS MUST define `.tips-callout`, `.warning-callout`, and `.pre-release-banner` using CSS custom properties (`--tip-bg`, `--tip-border`, `--warning-bg`, `--warning-border`) so that all callout surfaces automatically adapt between light and dark mode.
- **FR-028**: Each `KeywordIndexEntry` in the generated `index.json` MUST include a `navOrder` integer field sourced from the page's YAML `nav_order:` frontmatter value (defaulting to 999 when absent). The in-app `DocBundle.pagesBySection()` MUST sort pages by `navOrder` ascending — not alphabetically — to preserve the intended reading order.
- **FR-029**: The AI assistant MUST be branded as **Chirpy** in all user-facing text and navigation titles. The assistant MUST be implemented as a **chat interface** — not a `Form` — with a `ScrollView` containing `LazyVStack` message bubbles, a pinned bottom input bar (text field + send button), and `.scrollDismissesKeyboard(.interactively)` so that scrolling the conversation dismisses the keyboard. Message bubbles MUST use a right-aligned filled style for user messages and a left-aligned neutral style for Chirpy replies, matching iMessage / Signal conventions per the Meshtastic Design Standards § 1 Node Identity. The assistant MUST maintain a message history for the current session (user and Chirpy turns displayed in order). The welcome state (empty conversation) MUST show Chirpy's full-body SVG avatar (`Chirpy` asset from `Chirpy.imageset`) — not a square thumbnail — sized to a natural portrait height using the SVG's correct aspect ratio (`1871.69 / 2607.94`). The same SVG avatar at 28pt height MUST appear beside every Chirpy reply bubble. The system prompt MUST establish Chirpy's persona as a friendly, concise expert on Meshtastic. *(Updated post-implementation)*
- **FR-035**: The `Chirpy.imageset` asset catalog entry MUST reference `chirpy.svg` sourced from the official Meshtastic design repository (`github.com/meshtastic/design/tree/master/chirpy`), with `"preserves-vector-representation": true` in `Contents.json` so the vector scales crisply at any rendered size. *(Added post-implementation)*
- **FR-036**: Connection-status icon PNGs (`btConnected`, `tcpConnected`, `serialConnected`) MUST use `systemOrange` foreground colour — matching the existing `btReconnecting` icon — so that all four connection state icons are consistently visible on both light and dark backgrounds without requiring a CSS `filter: invert(1)` override. The `custom.bluetooth` SF Symbol asset MUST be rendered using `.foregroundColor` (not `.renderingMode(.original)`) to honour the colour token. These three icons MUST be removed from the dark-mode invert list in `docs.css`. *(Added post-implementation)*
- **FR-037**: Lock icon PNGs (`lockClosed`, `lockOpen`, `lockOpenRed`) MUST be rendered at canvas `width: 30` so that the portrait aspect ratio (~0.86:1) is preserved correctly at CSS `height: 44px`. The `lockOpenMqtt` icon (wider badge glyph) MUST use `width: 38`. This avoids the horizontal-overflow squish caused by placing a narrow portrait glyph in a 44×44pt square canvas. *(Added post-implementation)*
- **FR-030**: All User Guide pages that have matching screenshot assets in `docs/assets/screenshots/` MUST embed those images inline using standard markdown image syntax (`![alt](../assets/screenshots/NAME.png)`). Images MUST be placed immediately after the heading or table they illustrate. The bundled CSS MUST include `img { max-width: 100%; height: auto; border-radius: 8px; }` to ensure correct rendering in the `WKWebView`.
- **FR-031**: The snapshot test suite MUST include dedicated suites for icon-level UI components: `NodeStatusIconSnapshotTests` (online/idle status, hops-away badge, channel badge) and `ChannelLockIconSnapshotTests` (lock closed/open/open-red/open-MQTT/key-slash). All generated PNGs MUST be copied to `docs/assets/screenshots/` and embedded in the relevant doc pages.
- **FR-032**: Any User Guide page that displays two or more icon or status indicator images as standalone `![]()` block elements MUST instead present those images in a reference table. The table MUST have at minimum an Icon column and a Description column. Feature tables where the icon represents a named role, state, or mode MUST use a 3-column layout: `| Icon | Name | Description |`. Standalone `![]()` blocks that duplicate information already present in a preceding reference table on the same page MUST be removed. *(Added post-implementation)*
- **FR-033**: Icon-level snapshot tests MUST pass `transparent: true` to `assertViewSnapshot` so that PNGs use RGBA (no opaque white fill). Icon views MUST be rendered as plain `Image` SwiftUI views — never as interactive wrapper components (e.g. `Button`, `MQTTIcon`) — to avoid framework-injected backgrounds. All SF Symbol icon tests MUST use `.font(.title).padding(2)` to ensure the glyph fills the canvas at 44px CSS height without squishing. Components with inherently coloured or complex backgrounds (AQI/IAQ gauges, circular progress indicators, large environment widgets) MAY retain opaque backgrounds. Transparent PNGs that render monochrome-dark in light mode MUST be listed in the `docs.css` dark-mode `filter: invert(1)` rule. Coloured icons MUST be excluded from inversion. *(Added post-implementation)*
- **FR-034**: The `build-docs.sh` `html_template()` function MUST accept a `page_id` parameter (the markdown file stem) and emit `<body data-page="{page_id}">` to enable per-page CSS scoping. The bundled `docs.css` MUST set the global default for inline table icons to `height: 44px` (matching the nodes page reference standard). Per-page `body[data-page]` overrides are only required for exceptions that cannot meet the global default. *(Added post-implementation)*
- **FR-024**: The Help & Documentation entry point MUST be accessible via the `meshtastic:///settings/helpDocs` deep link. A `helpDocs` case MUST be added to `SettingsNavigationState` in `Meshtastic/Router/NavigationState.swift`, and `Router.route(url:)` MUST dispatch this deep link to open the Help & Documentation section directly. The deep link MUST be documented in the README deep-link table.
- **FR-023**: The bundled doc corpus MUST be delivered to the app via an Xcode **Copy Files build phase** that copies the generated HTML files, screenshot assets, and keyword index JSON into a `docs/` subdirectory within the app's main bundle. Swift code MUST locate bundled files using `Bundle.main.url(forResource:withExtension:subdirectory: "docs")`. The build script MUST produce its output into a source-controlled `Meshtastic/Resources/docs/` directory so that Xcode's build phase can reference it statically.
- **FR-022**: The `cmark-gfm` build script MUST wrap every generated HTML page in a minimal CSS stylesheet that uses `prefers-color-scheme` media queries to support both light and dark appearances. At minimum, the stylesheet MUST set background colour (`--bg`), body text colour (`--text`), link colour (`--link`), and code block background (`--code-bg`) for both `light` and `dark` schemes using CSS custom properties. The `WKWebView` MUST also have `backgroundColor` and `underPageBackgroundColor` set to `UIColor.systemBackground` to eliminate flash-of-white during page load.
- **FR-021**: The total size of the bundled doc corpus (all HTML, text, keyword index JSON, and screenshot images combined) MUST NOT exceed 10 MB at build time. The build script MUST emit a warning — not a failure — when the bundle exceeds 8 MB, and a hard failure when it exceeds 10 MB. The 10 MB ceiling MAY be raised by updating a single constant in the build script; any increase MUST be noted in the PR description with a justification.
- **FR-020**: Documentation versions MUST be tied to app release versions (both App Store and TestFlight/beta), not firmware versions:
  - A git tag push matching `v*.*.*` MUST trigger a GitHub Actions workflow that publishes a versioned snapshot of the built doc output to a stable path on GitHub Pages (e.g., `/vX.Y.Z/`).
  - On every beta/TestFlight build (push to `main` without a version tag), the workflow MUST overwrite a `/beta/` path, marking all pages visibly as "Pre-release — subject to change".
  - The Jekyll site MUST expose a version selector allowing users to switch between any previously released App Store version and the current beta.
  - The in-app bundled doc corpus MUST always match the exact app version it shipped with — it MUST NOT be updated post-release.
  - The site root MUST redirect to the latest stable (non-beta) released version's docs by default.
- **FR-019**: The in-app doc browser MUST be implemented as a SwiftUI `NavigationStack` with a searchable `List` acting as the table of contents (grouped by `DocSection`). A search bar MUST appear above the list to filter pages by title and keyword. Tapping a page MUST push a `WKWebView` detail view that renders the bundled HTML for that page. Navigation MUST use standard iOS swipe-back and back-button behaviour.
- **FR-018**: In addition to help sheet views (FR-017), the documentation authoring process MUST incorporate TipKit tip text from every tip struct in `Meshtastic/Tips/` into the matching User Guide page. Each tip's `title` and `message` MUST appear under a "Tips" callout or equivalent highlighted block on the relevant page. Mapping: `ConnectionTip` → Bluetooth Device Connection; `ShareChannelsTip`, `CreateChannelsTip`, `AdminChannelTip` → Messages & Channels; `MessagesTip` → Messages & Channels; `DiscoveryScanTip` → Local Mesh Discovery.
- **FR-017**: The documentation authoring process MUST treat the following existing in-app help sheet views as authoritative source content for their corresponding User Guide pages. Content from these views (titles, subtitles, section headers) MUST be incorporated verbatim or adapted into the matching doc pages to ensure parity between in-app help and the doc site:
  - `Meshtastic/Views/Helpers/Help/NodeListHelp.swift` → **Nodes List** page: Node Status section (Short Name & Long Name, Online, Idle/Sleeping, Hops Away); Device Roles section (all `DeviceRoles` enum cases with name + description); Logs section (Distance & Bearing, Channel, Signal Good/Fair/Bad/Very Bad, Signal Strength Meter, Device Metrics, Positions, Environment, Detection Sensor, Trace Routes).
  - `Meshtastic/Views/Helpers/Help/ChannelsHelp.swift` → **Messages & Channels** page: Channel Index section (Primary Channel); Channel Security section (Securely Encrypted, Not Securely Encrypted, Insecure with Location, Insecure with MQTT).
  - `Meshtastic/Views/Helpers/Help/DirectMessagesHelp.swift` → **Messages & Channels** page: Contacts section (Favorites, Long Press Actions).
  - `Meshtastic/Views/Helpers/Help/LockLegend.swift` → **Messages & Channels** page: Encryption section (Shared Key, Public Key Encryption, Public Key Mismatch).
  - `Meshtastic/Views/Helpers/Help/AckErrors.swift` → **Messages & Channels** page: Message Status section (Acknowledged by another node, all `RoutingError` cases with display name + description, footer note about grey/orange/red colour semantics).

### Key Entities

- **DocPage**: A single markdown file representing one documentation topic. Has a title, section (user/developer), optional screenshot references, and body content.
- **DocSection**: A grouping of DocPages (e.g., "User Guide > Messages"). Determines sidebar hierarchy on the Jekyll site and table-of-contents structure in-app.
- **ScreenshotAsset**: A PNG file in `docs/assets/screenshots/` sourced from the snapshot test suite. Referenced by DocPages using relative paths.
- **DocBundle**: The complete set of markdown files and assets copied into the app target at build time, available offline.
- **AIDocAssistant**: The in-app component (iOS 26+ only) that takes a user question, retrieves relevant DocPage content, and queries Foundation Models on-device.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All 14 feature areas listed in FR-014 have a published User Guide page with at least one screenshot within the initial release.
- **SC-002**: All 7 developer topics listed in FR-015 have a published Developer Guide page within the initial release.
- **SC-003**: The in-app doc browser opens and displays a table of contents within 1 second on any supported device.
- **SC-004**: A user can locate the answer to "How do I connect a device?" in 3 steps or fewer from the app's Help entry point.
- **SC-005**: The CI pipeline fully refreshes docs (snapshots + pages deploy) within 10 minutes of a push to `main`.
- **SC-006**: On iOS 26+, the AI assistant responds to a valid question within 5 seconds using only on-device processing.
- **SC-007**: Zero doc pages reference implementation details (framework names, file paths, database tables) in user-facing content.
- **SC-008**: The Jekyll site scores 90+ on Lighthouse accessibility for the home page.
- **SC-009**: Every User Guide page that has matching screenshot assets embeds at least one image inline, sourced from `docs/assets/screenshots/`. *(Added post-implementation — FR-030)*
- **SC-010**: The Apple Watch App User Guide page exists at `docs/user/watch.md` (`nav_order: 12`) and covers Foxhunt, compass view, distance colour coding, haptic feedback, Phone tab, and foxhunt target pinning. *(Added post-implementation — FR-014 updated)*
- **SC-011**: All User Guide pages that previously contained two or more standalone icon screenshot blocks have been converted to reference tables. No User Guide page contains a standalone `![]()` icon image that is not inside a Markdown table or serving as an illustrative full-page screenshot. *(Added post-implementation — FR-032)*
- **SC-012**: All icon-level snapshot test suites (`NodeStatusIconSnapshotTests`, `ChannelLockIconSnapshotTests`, `NodeLogIconSnapshotTests`, `MessagesIconSnapshotTests`, `ConnectionStatusIconSnapshotTests`, `DeviceRoleIconSnapshotTests`, `LoRaSignalStrengthSnapshotTests`, `MQTTIconSnapshotTests`) use `transparent: true` to produce RGBA PNGs. *(Added post-implementation — FR-033)*
- **SC-013**: The Chirpy AI assistant MUST be implemented as a chat interface (message bubbles, pinned input bar) using the official `chirpy.svg` vector asset. The welcome state MUST display the full-body Chirpy at correct portrait aspect ratio. The keyboard MUST dismiss when the scroll view is dragged. *(Added post-implementation — FR-029 updated, FR-035)*
- **SC-014**: All four connection-status icons (`btConnected`, `btReconnecting`, `tcpConnected`, `serialConnected`) use `systemOrange` and are visible on both light and dark backgrounds without CSS inversion. Lock icon PNGs for `lockClosed`, `lockOpen`, and `lockOpenRed` are rendered at `width: 30` to preserve portrait proportions. Compact node row example snapshots use 5 distinct `node.num` values producing 5 visibly different circle colours. The standalone `radarInactive.png` (invisible on light backgrounds) has been removed from `discovery.md`. *(Added post-implementation — FR-036, FR-037)*

## Clarifications

### Session 2026-05-05

- Q: Should the CI workflow auto-commit changed screenshots directly to `main`, or open a PR? → A: Open a PR automatically from a `bot/update-snapshots` branch (preserves branch protection and review gate for visual regressions).
- Q: How should the in-app doc browser render markdown with images? → A: `WKWebView` loading locally-bundled HTML files converted from **GitHub Flavored Markdown** at build time (fully offline, full image support, no runtime parsing).
- Q: Where should the in-app Help entry point live? → A: Settings sub-section — Settings → Help & Documentation (avoids adding a 6th tab; contextual per-screen links deferred to a later iteration).
- Q: Which tool should convert GFM to HTML at build time? → A: `cmark-gfm` CLI (GitHub's own GFM parser, installed via Homebrew — no Node.js runtime required, matches GitHub's rendering exactly).
- Q: How should the AI assistant retrieve relevant documentation before querying the model? → A: Pre-built keyword index (JSON file generated at build time); at runtime the app term-matches the user's question against the index and feeds the top 2–3 matching doc pages as context to Foundation Models.
- Q: Should existing in-app help sheet content be incorporated into the docs? → A: Yes — the five existing help views (`NodeListHelp`, `ChannelsHelp`, `DirectMessagesHelp`, `LockLegend`, `AckErrors`) are authoritative source content and MUST be incorporated verbatim or adapted into their matching User Guide pages (FR-017).
- Q: Should TipKit tip text also be treated as source content for doc pages? → A: Yes — all TipKit tips from `Meshtastic/Tips/` MUST be incorporated into their matching User Guide pages as a "Tips" callout block (FR-018).
- Q: How does the user navigate between doc pages inside the app? → A: SwiftUI `NavigationStack` TOC list with a search bar above it (filtering by title/keyword), pushing a `WKWebView` detail view per page — standard iOS swipe-back nav (FR-019).
- Q: What is the maximum token budget for doc context passed to Foundation Models per query? → A: 3,000 tokens (leaves ~1,096 headroom within the 4,096-token session ceiling per Apple TN3193, covering instructions + question + response). Measured at runtime via `SystemLanguageModel.tokenCount(for:)` before querying (FR-011 updated).
- Q: Should the doc site carry versioning or always show latest? → A: Versioned per release — stable git-tagged snapshots under `docs/vX.Y.Z/` for every App Store release, plus a continuously-updated `docs/beta/` path for TestFlight builds (marked pre-release). Version selector on Jekyll site; in-app bundle always matches the shipped version (FR-020).
- Q: What is the maximum bundled doc corpus size? → A: 10 MB hard ceiling (warn at 8 MB); ceiling is a single build-script constant that can be raised with PR justification (FR-021).
- Q: Does the Jekyll site use native GitHub Pages build or a GitHub Actions pipeline? → A: GitHub Actions owns the full pipeline (`cmark-gfm` → HTML, versioned paths, size check, `actions/deploy-pages`). Native Jekyll build is disabled via `.nojekyll`. FR-003 corrected to remove the "no additional tooling" constraint.
- Q: What event triggers versioned doc snapshot publication? → A: Git tag push matching `v*.*.*` triggers the versioned release workflow; pushes to `main` without a version tag overwrite `/beta/` (FR-020 updated).
- Q: How should the in-app WKWebView handle dark mode? → A: Build-time CSS injection with `prefers-color-scheme` light/dark variables in every generated HTML page; `WKWebView.backgroundColor` set to `UIColor.systemBackground` at runtime (FR-022).
- Q: How is the doc bundle delivered into the app target? → A: Xcode Copy Files build phase copying from `Meshtastic/Resources/docs/` into the main bundle `docs/` subdirectory; accessed via `Bundle.main.url(forResource:withExtension:subdirectory:)` (FR-023).
- Q: Where does the Help entry point live in the app and is a deep link needed? → A: Settings sub-section only (no new tab — fixes contradictory Assumption); `meshtastic:///settings/helpDocs` deep link added via `SettingsNavigationState.helpDocs` case (FR-024). README deep-link table updated.

## Assumptions

- The `just-the-docs` Jekyll theme is compatible with GitHub Pages' native Jekyll build environment; if not, the minimal `minima` theme with a custom `_data/navigation.yml` will be used instead.
- Snapshot test images are already in `MeshtasticTests/__Snapshots__/SwiftUIViewSnapshotTests/` and are committed to the repo; additional snapshots covering gaps will be added as part of this feature.
- Foundation Models (iOS 26+) availability is gated at runtime via `#available(iOS 26, *)` — no minimum deployment target change is needed.
- The Help & Documentation section lives within the Settings tab as a `NavigationLink` entry (FR-006). No new tab bar item is added. A `meshtastic:///settings/helpDocs` deep link provides direct routing from other parts of the app (FR-024).
- CI runs on macOS Xcode Cloud or a macOS GitHub Actions runner with a simulator available; if no simulator is available, snapshot regeneration is skipped non-fatally.
- Doc content will be written in English; localisation of doc content is out of scope for this feature.
- The `docs/` folder will be on the `main` branch (not a `gh-pages` orphan branch) to keep docs co-located with source.
