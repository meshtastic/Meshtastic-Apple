---
title: Home
layout: default
nav_order: 0
---

# Meshtastic Apple App Documentation

User and developer documentation for the Meshtastic iOS, iPadOS, macOS, watchOS, and visionOS app.

Use the sidebar navigation to browse the **User Guide** for app features and the **Developer Guide** for contributing to the project.

---

## Quick Links

| Guide | Description |
|-------|-------------|
| [Getting Started](user/getting-started) | Connect your first radio and send a message |
| [Nodes List](user/nodes) | Understanding the mesh network node list |
| [Signal Meter](user/signal-meter) | How the LoRa signal quality meter works |
| [Units & Locale](user/units-and-locale) | How temperatures, distances, and times adapt to your region |
| [Architecture](developer/architecture) | App architecture overview for contributors |

---

## What's New

- **Docs Translation Pipeline** — Community-sourced translations: each device contributes translated docs that are shared via a CDN feed, so future users get instant localized results. [Learn more](user/translate)
- **Automatic Documentation Translation** — On iOS 26+, in-app docs are automatically translated into your device language using the Apple Translation framework. [Learn more](user/translate)
- **Message Formatting Toolbar** — Markdown formatting in message compose (iOS 18+/macOS 15+). Bold, italic, strikethrough, code, and links with live preview. [Learn more](user/messages)
- **Node List Layout** — Switchable Complete and Compact density modes for the node list. Compact mode reduces row height for large meshes. [Learn more](user/nodes)
- **Local Mesh Discovery** — Diagnostic tool that cycles through LoRa modem presets to audit the local RF environment, collecting nodes and telemetry across presets. [Learn more](user/discovery)

---

In **Ask Chirpy**, local source links open in the in-app documentation viewer. When internet is available, Chirpy may also augment answers with related `meshtastic.org` sources; without service, it continues using local docs only.
