<h1 align="center">Meshtastic Apple</h1>

<p align="center">
  <strong>iOS · iPadOS · macOS · watchOS · visionOS</strong><br>
  Open-source LoRa mesh networking for Apple platforms
</p>

<p align="center">
  <a href="https://github.com/meshtastic/Meshtastic-Apple/actions"><img src="https://github.com/meshtastic/Meshtastic-Apple/actions/workflows/docs-deploy.yml/badge.svg" alt="Docs CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL%20v3-blue.svg" alt="License: GPL v3"></a>
  <img src="https://img.shields.io/badge/Swift-6-orange.svg" alt="Swift 6">
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS%20%7C%20macOS%20%7C%20watchOS%20%7C%20visionOS-lightgrey.svg" alt="Platforms">
</p>

<p align="center">
  <a href="https://meshtastic.github.io/Meshtastic-Apple/">User Guide</a> •
  <a href="https://meshtastic.github.io/Meshtastic-Apple/developer.html">Developer Guide</a> •
  <a href="#getting-started">Getting Started</a> •
  <a href="LICENSE">License</a>
</p>

---

## Overview

SwiftUI client applications for iOS, iPadOS, macOS, visionOS and watchOS that communicate with [Meshtastic](https://meshtastic.org) LoRa mesh radio devices over Bluetooth, TCP, and serial.

## Key Features

- **Mesh messaging** — channel and direct messages over LoRa, with CarPlay and Siri support for hands-free use while driving
- **Live map** — node positions, waypoints, and GeoJSON overlays with offline tile support
- **Node management** — signal meter, device roles, encryption status, trace routes, and telemetry
- **Full radio configuration** — LoRa, channels, security, Bluetooth, device, display, network, position, power, and all module configs
- **Apple Watch companion** — node list and fox hunt compass on your wrist
- **TAK integration** — CoT position relay and TAK server connectivity
- **In-app documentation** — full offline help browser with dark-mode support and AI-powered search (iOS 26+)

## What's New

### For Users

- **May 2026** — [Signal Meter](https://meshtastic.github.io/Meshtastic-Apple/user/signal-meter.html) — New deep-dive page explaining how the LoRa signal quality meter works, why negative SNR values are normal, and how to interpret RSSI vs. SNR for your mesh.
- **May 2026** — [Apple Watch App](https://meshtastic.github.io/Meshtastic-Apple/user/watch.html) — New page covering the companion watch app: node list, fox hunt compass, and how it syncs with your iPhone.

### For Developers

- **May 2026** — [Testing](https://meshtastic.github.io/Meshtastic-Apple/developer/testing.html) — Snapshot test conventions established: consolidated multi-state views into single combined images (light + dark pairs), use `assertViewSnapshot` helper with explicit `width`/`height` and `transparent: true` for icon snapshots.
- **May 2026** — [Architecture](https://meshtastic.github.io/Meshtastic-Apple/developer/architecture.html) — In-app documentation system added: markdown source under `docs/` is converted to HTML by `scripts/build-docs.sh` and bundled at `Meshtastic/Resources/docs/`. Navigation is driven by `index.json`.

## Getting Started

1. Clone the repo.
    ```sh
    git clone git@github.com:meshtastic/Meshtastic-Apple.git
    ```
2. Open the local directory.
    ```sh
    cd Meshtastic-Apple
    ```
3. Set up git hooks to automatically lint the project when you commit changes.
    ```sh
    ./scripts/setup-hooks.sh
    ```
4. Open `Meshtastic.xcworkspace`
    ```sh
    open Meshtastic.xcworkspace
    ```
5. Build and run the `Meshtastic` target.

See [docs/developer/contributing.md](docs/developer/contributing.md) for code style, branch naming, PR checklist, and all other contribution guidelines.

## Documentation

| Resource | Link |
|----------|------|
| User Guide | https://meshtastic.github.io/Meshtastic-Apple/ |
| Developer Guide | https://meshtastic.github.io/Meshtastic-Apple/developer.html |
| In-app | Settings → Help & Documentation |

## Release Process

For more information on how a new release of Meshtastic is managed, please refer to [RELEASING.md](./RELEASING.md).

## License

This project is licensed under the GPL v3. See the [LICENSE](LICENSE) file for details.

---

<p align="center">
  <a href="https://meshtastic.org">meshtastic.org</a> · 
  <a href="https://github.com/meshtastic">GitHub @meshtastic</a>
</p>

