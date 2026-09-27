---
title: Architecture Overview
parent: Developer Guide
nav_order: 1
---

# Architecture Overview

The Meshtastic Apple app targets iOS, iPadOS, and macOS (via Mac Catalyst). It communicates with Meshtastic radios over BLE, TCP/IP, and (on macOS) serial.

## App Entry Point

`Meshtastic/MeshtasticApp.swift` is the `@main` `App` struct. On launch it:

1. Creates `PersistenceController.shared` (SwiftData `ModelContainer`)
2. Instantiates `AppState` (wraps `Router`)
3. Instantiates `AccessoryManager` (BLE/TCP/serial connectivity)
4. Instantiates `AccessoryManager.shared` as an `@EnvironmentObject` for the view hierarchy

`MeshtasticAppDelegate.swift` handles `UIApplicationDelegate` hooks for SiriKit CarPlay messaging intents.

## Router & Navigation

`Router` (`Meshtastic/Router/Router.swift`) is a `@MainActor` `ObservableObject` that owns a `NavigationState` struct. It drives tab selection and deep-link routing.

```
Router
└── NavigationState
    ├── MessagesNavigationState   (tab 0)
    ├── MapNavigationState        (tab 1)
    ├── NodesNavigationState      (tab 2)
    └── SettingsNavigationState   (tab 3)
```

Deep links use the `meshtastic:///` URL scheme. `Router.route(url:)` parses the path and sets the appropriate navigation state. See [Deep Links](deep-links) for the full URL reference.

## AppState

`AppState` wraps `Router` and is injected as an `@EnvironmentObject` at the root of the SwiftUI view hierarchy. Views that need to navigate programmatically read `@EnvironmentObject var router: Router` directly — or more commonly `@EnvironmentObject var appState: AppState` and access `appState.router`.

## AccessoryManager

`AccessoryManager` is the central connectivity manager split across extension files. Up to four radios can be connected at once. Each has a `RadioSession` (`Meshtastic/Accessory/Radio Session/`) holding everything that belongs to that connection, and every radio runs the same connect steps and packet handling. One is focused (`activeConnection`): the default for Settings, sending and the services that follow it. The others are in `additionalRadios`. See [Transport Layer › Several Radios at Once](transport.md) for the details.

| File | Responsibility |
|------|---------------|
| `AccessoryManager+Discovery.swift` | BLE scanning, device discovery |
| `AccessoryManager+Connect.swift` | The connect steps every radio runs, reconnect logic |
| `AccessoryManager+AdditionalRadios.swift` | Radios connected alongside the focused one: events, disconnect, reconnect, remembered radios |
| `AccessoryManager+Focus.swift` | Moving the focus between connected radios without reconnecting |
| `AccessoryManager+FocusHandover.swift` | Another radio takes the focus when the focused one drops |
| `AccessoryManager+RadioAttention.swift` | A locked or outdated radio that isn't focused: the prompt naming it |
| `AccessoryManager+RadioRemoval.swift` | Resetting or removing one of several radios: it leaves while the others stay (D-18) |
| `AccessoryManager+RadioChoice.swift` | Sending, and admin messages, through a chosen radio |
| `AccessoryManager+ServiceRadios.swift` | The radio TAK, CarPlay & Siri and the Watch use |
| `AccessoryManager+ToRadio.swift` | Packets sent to the radio |
| `AccessoryManager+FromRadio.swift` | Packets received from the radio |
| `AccessoryManager+Position.swift` | GPS position sharing, to every connected radio |
| `AccessoryManager+MQTT.swift`, `+RadioMQTT.swift` | Each radio's MQTT client proxy |
| `AccessoryManager+TAK.swift` | TAK/CoT integration |

Transport protocols are in `Meshtastic/Accessory/Transports/`. `PreferredRadio` is the radio reconnected at launch.

## Persistence

SwiftData is the sole persistence layer. `PersistenceController.shared` owns the `ModelContainer`. Views use `@Environment(\.modelContext)` or `@Query`. Background writes use the `MeshPackets` `@ModelActor`.

Model types are defined with `@Model` in `Meshtastic/Model/`. Schema evolution uses `VersionedSchema` and `SchemaMigrationPlan` in `MeshtasticSchema.swift`.

`EventFirmwareEntity` is a global, rebuildable display cache seeded from the app bundle and
refreshed from the event-firmware API. It persists event identity, lifecycle text, links, and
theme values, including primary, secondary, and accent colors. Per-device database clears
preserve it; a full app-data reset removes it. Executable OTA artifact URLs are deliberately
outside this model and require the separate signed event OTA contract.

## Services

Application services that are not tied to radio connectivity live in `Meshtastic/Services/`.

| File | Responsibility |
|------|---------------|
| `DocTranslationService.swift` | On-device documentation translation using the Apple Translation framework (primary) with FoundationModels fallback. Translates bundled English markdown source files, caches translated `.md`, converts to HTML via `MarkdownConverter`, and triggers auto-upload after prefetch. iOS 26+. |
| `TranslationCache.swift` | File-based cache for translated `.md` content stored in Application Support. Tracks content hashes for staleness detection and enforces a 50 MB per-language LRU eviction policy. |
| `MarkdownConverter.swift` | GFM-compatible markdown→HTML converter. Supports headings, paragraphs, lists, code fences, inline code, tables, links, images, HTML passthrough (`<picture>`, `<img>`), blockquote callouts (tip/warning), bold, italic, strikethrough, horizontal rules, and `.md` → `.html` link rewriting. Strips YAML front matter and Jekyll inline attributes. |
| `DocsTranslationUploader.swift` | Automatically commits translated `.md` files to `meshtastic/translations` repo after background prefetch completes. Performs read-only checks against `meshtastic/meshtastic` and `meshtastic/translations` (no auth), then commits via GitHub Contents API using a fine-grained PAT from `Secrets.json`. Per-file tracking enables retry of failed uploads. |
| `CommunityTranslationFetcher.swift` | Downloads existing community translations from the GitHub Pages CDN feed (`index.json`) before falling back to on-device translation. Fetches `nav-labels.json` and `search-index.json` for translated UI strings and search keywords. Builds a pre-rendered translated folder so `DocBundle` can load translated pages directly. |

## Protobufs

The `MeshtasticProtobufs` Swift Package (`MeshtasticProtobufs/Package.swift`) wraps protobuf-generated Swift sources. Regenerate with `./scripts/gen_protos.sh` after updating the `protobufs/` submodule.
