# Implementation Plan: App Documentation (Jekyll Site + In-App AI)

**Branch**: `003-app-docs-markdown` | **Date**: 2026-05-05 | **Spec**: [spec.md](spec.md)  
**Status**: Implemented  
**Input**: Feature specification from `specs/003-app-docs-markdown/spec.md`

## Summary

Build a complete documentation system for the Meshtastic Apple app: (1) a GitHub Pages Jekyll site served via GitHub Actions, (2) an in-app offline doc browser (SwiftUI `NavigationStack` + `WKWebView`), and (3) an on-device AI assistant powered by Foundation Models (iOS 26+). Source content is derived from existing in-app help sheet views and TipKit tips. Docs are versioned per App Store release and per beta build. The build pipeline uses `cmark-gfm` to convert GFM markdown to HTML, injects dark-mode CSS, builds a keyword index JSON for AI retrieval, and enforces a 10 MB bundle size ceiling.

**Post-implementation additions (not in original spec):**
- `DocModels.swift` extracted as a dedicated file (DocPage, DocSection, KeywordIndexEntry, DocBundle) — not merged into DocBrowserView.
- `nav_order` field added to `KeywordIndexEntry` and `index.json`; `DocBundle.pagesBySection()` sorts by `navOrder` to preserve intended reading order.
- `build-docs.sh` strips YAML frontmatter and Kramdown `{: .xxx }` attribute lines before piping to `cmark-gfm`; Python post-processing converts blockquotes to `tips-callout` / `warning-callout` divs; beta banner uses `class="pre-release-banner"` instead of inline styles.
- CSS extended with `.tips-callout`, `.warning-callout`, `.pre-release-banner` using CSS custom properties for full dark-mode support; `img` rule added for in-WebView image sizing.
- AI assistant fully rebuilt as **Chirpy chat interface** (`AIDocAssistantView`): replaced `Form`-based layout with `ScrollView` + `LazyVStack` message bubbles, right-aligned user messages (accent fill), left-aligned Chirpy replies (secondary background), pinned bottom input bar (`TextField` + `Image(systemName: "arrow.up.circle.fill")` send button). Session message history maintained via `[ChirpyMessage]` `@State` array. `.scrollDismissesKeyboard(.interactively)` on `ScrollView` (not `Form`). Auto-scrolls to bottom on new messages and loading state. `@FocusState` wires the text field.
- **Chirpy SVG asset**: `chirpy.svg` downloaded from `github.com/meshtastic/design/tree/master/chirpy` and added to `Meshtastic/Assets.xcassets/Chirpy.imageset/` with `"preserves-vector-representation": true`. Welcome card renders the full-body vector at `height: 120` using the SVG's natural aspect ratio constant (`chirpyAspect = 1871.69 / 2607.94 ≈ 0.718`). Reply avatars render at 28pt tall using the same ratio. Dark variant thumbnail (`AppIcon_Chirpy_Dark_Thumb`) and `@Environment(\.colorScheme)` dependency removed — the SVG renders on any background.
- **Connection-status icon colours**: `btConnected` (custom.bluetooth), `tcpConnected` (network), `serialConnected` (cable.connector.horizontal) all changed to `.foregroundColor(Color(uiColor: .systemOrange))` — matching `btReconnecting` — so all four connection state icons are consistently visible on both light and dark backgrounds. `.renderingMode(.original)` and `.foregroundStyle(.primary)` removed. These three removed from `docs.css` dark-mode `filter: invert(1)` rule (they no longer render monochrome-dark).
- **Lock icon canvas sizing**: `lockClosed`, `lockOpen`, `lockOpenRed` re-recorded at `width: 30` (portrait 0.86:1 ratio at CSS 44px), `lockOpenMqtt` at `width: 38` (badge glyph wider). Fixes horizontal squish from the previous 44×44pt square canvas where the narrow padlock glyph left excess transparent horizontal space.
- **Compact node row colours**: `makeNode()` helper in `NodeListItemCompactSnapshotTests` extended with `num: Int64 = 0` parameter. The 5 doc-referenced snapshots assigned distinct hex node numbers: `directConnected_allInfo` 0xE75432 (red-orange), `multiHop` 0x3A9FD1 (sky blue), `mqtt` 0x5B2E8C (purple), `pkiMismatch` 0xC84A1F (burnt orange), `withPosition` 0x27B06E (teal green). Node circle `color` is derived from `node.num` via `Color(UIColor(hex: UInt32(node.num)))`.
- **discovery.md cleanup**: `radarInactive.png` (white-on-white inactive radar sweep — invisible on light backgrounds) removed from `docs/user/discovery.md`. Only the active radar sweep image remains.
- **Environment tile CSS**: `body[data-page="telemetry"]` per-page override added to `docs.css` for the four environment compact widget PNGs (`humidityWithDew`, `humidityNoDew`, `pressureHigh`, `pressureLow`) at `height: 132px` (3× the 44px baseline) with `border-radius: 8px` to match the tile card style.
- **Updated dark-mode invert list** (current state after icon colour changes): `logDeviceMetrics`, `logPositions`, `logEnvironment`, `logDetectionSensor`, `logTraceRoutes`, `longPress`, `hopsAway`, `channelBadge`, all 11 role PNGs (`roleClient` through `roleLostAndFound`), `signalGood`, `signalBad`, `signalNone`. Removed: `btConnected`, `tcpConnected`, `serialConnected` (now orange, not monochrome-dark).
- 57 screenshot PNGs embedded inline in 7 User Guide pages (nodes, messages, mqtt, telemetry, map, firmware, discovery).
- Two new snapshot test suites added: `NodeStatusIconSnapshotTests` (nodeOnline, nodeIdle, hopsAway, channelBadge) and `ChannelLockIconSnapshotTests` (lockClosed, lockOpen, lockOpenRed, lockOpenMqtt, keySlash) — 9 new PNGs generated and embedded.
- **Apple Watch App** page (`docs/user/watch.md`, `nav_order: 12`) added to User Guide covering Foxhunt, compass view, phone connectivity tab, and foxhunt target pinning.
- **Icon table standard (FR-032/FR-033/FR-034)**: All standalone groups of 2+ icon screenshots converted to 3-column reference tables (`| Icon | Name | Description |` or `| Icon | State | Description |`). Applied pages: nodes.md (Device Roles → 3-col, Channel badge row, Gradient meter row), messages.md (removed redundant `lockLegend.png` and `ackErrors.png` standalone blocks), mqtt.md (3 status icons → table), telemetry.md (battery, AQI/IAQ, environment → tables), firmware.md (4 progress states → table). Standalone duplicate blocks removed: `shortDistance.png`, `longDistance.png` from nodes.md; `lockLegend.png`, `ackErrors.png` from messages.md.
- **Transparent icon PNGs (FR-033)**: `assertViewSnapshot` helper extended with `transparent: Bool = false` parameter. When `true`, sets `hostingController.view.backgroundColor = .clear` and uses `UIGraphicsImageRendererFormat` with `opaque = false` plus `ctx.cgContext.clear(rect)` before drawing. All SF Symbol icon tests use `.font(.title).padding(2)` so glyphs fill the canvas correctly at CSS `height: 44px`. Icon tests MUST render plain `Image` views — never interactive wrapper components (`Button`, `MQTTIcon`, etc.) which inject opaque backgrounds. `MQTTIconSnapshotTests` updated to use raw SF Symbols (`arrow.up.arrow.down.circle.fill`, `arrow.up.circle.fill`) instead of `MQTTIcon`. Transparent suites: `NodeStatusIconSnapshotTests`, `ChannelLockIconSnapshotTests`, `NodeLogIconSnapshotTests`, `MessagesIconSnapshotTests`, `ConnectionStatusIconSnapshotTests`, `DeviceRoleIconSnapshotTests`, `LoRaSignalStrengthSnapshotTests`, `MQTTIconSnapshotTests`.
- **Global 44px icon height (FR-034)**: `docs.css` global `td img` default raised from 22px to 44px — nodes page is the reference standard and all pages now match it. Per-page `body[data-page]` overrides removed (`telemetry`, `firmware` no longer need exceptions). `body[data-page]` attribute remains in HTML for future per-page scoping if needed.
- **Dark-mode inversion (docs.css)**: Monochrome icon PNGs (rendered dark-on-transparent in light mode) listed in `@media (prefers-color-scheme: dark)` `filter: invert(1)` rule. Coloured icons excluded. Current list: btConnected, tcpConnected, serialConnected, logDeviceMetrics, logPositions, logEnvironment, logDetectionSensor, logTraceRoutes, longPress, hopsAway, channelBadge, all 11 role PNGs, signalGood/Bad/None.
- **New snapshot test suites added**: `DeviceRoleIconSnapshotTests` (11 tests, `systemOrange`), `ConnectionStatusIconSnapshotTests` (4 tests, all `systemOrange`), `NodeLogIconSnapshotTests` (6 tests), `MessagesIconSnapshotTests` (2 tests), `LoRaSignalStrengthMeterSnapshotTests.gradientMeterIcon` (compact meter, width 180, transparent). `makeNode()` extended with `num: Int64` to support distinct node circle colours per snapshot.
- Total bundle: **19 pages** (was 18 planned), **2.3 MB** (well within 10 MB ceiling).

## Technical Context

**Language/Version**: Swift (latest stable) for app code; bash for build scripts; YAML for GitHub Actions workflows  
**Primary Dependencies**: WebKit (`WKWebView`), FoundationModels (iOS 26+), `cmark-gfm` CLI (Homebrew), GitHub Actions (`actions/deploy-pages`), `just-the-docs` Jekyll theme  
**Storage**: Main app bundle — `Meshtastic/Resources/docs/` copied via Xcode Copy Files build phase; no SwiftData models required  
**Testing**: Swift Testing (`@Suite`, `@Test`, `#expect`); existing snapshot test infrastructure for screenshot sourcing  
**Target Platform**: iOS 17.5+ / iPadOS 17.5+ / macOS Catalyst 17.5+ (app); macOS GitHub Actions runner (CI pipeline)  
**Project Type**: Mobile app feature + CI/CD pipeline + static site  
**Performance Goals**: TOC loads within 1 second (SC-003); AI responds within 5 seconds (SC-006); CI pipeline completes within 10 minutes (SC-005)  
**Constraints**: Bundle ≤ 10 MB (FR-021, warn at 8 MB); AI context ≤ 3,000 tokens per query (FR-011); fully offline in-app (FR-007); no new tab bar item (FR-006)  
**Scale/Scope**: ~25 doc pages (12 User Guide + 7 Developer Guide + index), 66+ screenshot PNGs, 1 keyword index JSON, 2 GitHub Actions workflows, 1 SVG vector asset (`Chirpy.imageset`)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. SwiftUI-Native | ✅ PASS | `DocBrowserView`, `AIDocAssistantView`, `DocTOCView` are pure SwiftUI. `WKWebView` is wrapped in a `UIViewRepresentable` — unavoidable, no SwiftUI equivalent. |
| II. SwiftData Persistence | ✅ N/A | No persistent models needed. Doc content lives in the bundle. |
| III. Protocol-Oriented Transport | ✅ N/A | No device transport involved. |
| IV. Structured Logging | ✅ PASS | New `Logger.docs` category added to `Meshtastic/Extensions/Logger.swift`. |
| V. Protobuf Contract Fidelity | ✅ N/A | No protobuf usage. |
| VI. Lint-Clean Commits | ✅ PASS | All Swift code passes SwiftLint. Build scripts are bash (not linted). |
| VII. Platform Parity | ✅ PASS | `WKWebView` is available on iOS and macCatalyst. `FoundationModels` gated with `#available(iOS 26, *)`. macCatalyst shows doc browser without AI input on macOS < 26. |
| VIII. Design Standards | ✅ REQUIRED | Must fetch and review Meshtastic Client Design Standards before implementing any UI. |

**Gate result: PASS.** No constitution violations. Proceed to Phase 0.

## Project Structure

### Documentation (this feature)

```text
specs/003-app-docs-markdown/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   ├── keyword-index-schema.json   # JSON schema for keyword index
│   ├── deep-link-contract.md       # meshtastic:///settings/help routing contract
│   └── ci-workflow-contract.md     # GitHub Actions workflow interface contract
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
# App source additions
Meshtastic/
├── Resources/
│   └── docs/                        # Generated HTML bundle (git-tracked, built by script)
│       ├── index.json               # Keyword index JSON (AI retrieval)
│       ├── user/                    # User Guide HTML pages
│       │   ├── getting-started.html
│       │   ├── bluetooth.html
│       │   ├── messages.html
│       │   ├── nodes.html
│       │   ├── map.html
│       │   ├── settings.html
│       │   ├── telemetry.html
│       │   ├── tak.html
│       │   ├── mqtt.html
│       │   ├── discovery.html
│       │   ├── firmware.html
│       │   └── watch.html           # Apple Watch App (added post-spec, nav_order: 12)
│       ├── developer/               # Developer Guide HTML pages
│       │   ├── architecture.html
│       │   ├── codebase.html
│       │   ├── adding-features.html
│       │   ├── transport.html
│       │   ├── swiftdata.html
│       │   ├── testing.html
│       │   └── contributing.html
│       └── assets/
│           ├── docs.css             # Light/dark CSS (prefers-color-scheme); callout classes; img rule
│           └── screenshots/         # 66 PNGs: 57 original + 9 new icon snapshots
├── Views/
│   └── Settings/
│       └── HelpAndDocumentation/
│           ├── DocModels.swift               # DocPage, DocSection, KeywordIndexEntry, DocBundle (@Observable)
│           ├── DocBrowserView.swift          # NavigationStack TOC + search; destination-form NavigationLink
│           ├── DocPageView.swift             # WKWebView detail view
│           └── AIDocAssistantView.swift      # iOS 26+ Chirpy chat interface (bubbles + pinned input bar; Chirpy SVG avatar)
├── Extensions/
│   └── Logger.swift                 # Add Logger.docs category (extend existing file)
└── Router/
    └── NavigationState.swift        # Add helpDocs case to SettingsNavigationState

# Markdown source (authored content)
docs/
├── _config.yml                      # Jekyll config (just-the-docs theme, .nojekyll)
├── index.md                         # Site root → redirects to latest version
├── user/                            # 12 GFM source pages (11 original + watch.md)
└── developer/                       # 7 GFM source pages

# Build scripts
scripts/
├── build-docs.sh                    # cmark-gfm → HTML, CSS injection, keyword index, size check
└── copy-snapshots.sh                # Copies PNGs from MeshtasticTests/__Snapshots__/ → docs/assets/screenshots/

# GitHub Actions workflows
.github/workflows/
├── docs-deploy.yml                  # Triggers on push to main → builds + deploys /beta/ path
└── docs-release.yml                 # Triggers on v*.*.* tag push → builds + deploys /vX.Y.Z/ path

# Tests
MeshtasticTests/
├── DocBundleTests.swift             # Swift Testing: bundle completeness, keyword index validity, token budget (13 tests)
└── SwiftUIViewSnapshotTests.swift   # Extended with NodeStatusIconSnapshotTests, ChannelLockIconSnapshotTests (+9 tests)
```

**Structure Decision**: Single project (mobile app + scripts + static site). No new SPM packages or separate targets. The doc bundle is a static resource in the main target. The Jekyll site is source-controlled in `docs/` and deployed by GitHub Actions.

## Complexity Tracking

*No constitution violations — table omitted.*
