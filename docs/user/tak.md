---
title: TAK Integration
parent: User Guide
nav_order: 9
---

# TAK Integration

The Meshtastic app supports Team Awareness Kit (TAK) integration, enabling interoperability with ATAK (Android Team Awareness Kit), iTAK, and other CoT (Cursor-on-Target) compatible systems.

## What is TAK?

TAK is a situational awareness platform widely used in tactical, emergency management, and outdoor recreation contexts. It displays the positions and status of team members on a shared map. Meshtastic bridges TAK users over LoRa mesh radio without requiring cellular or internet connectivity.

## Supported Device Roles

TAK integration works with two device roles:

| Icon | Role | Description |
|------|------|-------------|
| ![TAK](../assets/screenshots/roleTak.png) | TAK | Full TAK role — sends CoT position reports and can relay TAK data packets. |
| ![TAK Tracker](../assets/screenshots/roleTakTracker.png) | TAK Tracker | Lightweight position-only TAK role. Lower power consumption, no packet relay. |

Set the device role in **Settings → Device**.

## TAK Server screen

**Settings → TAK Server** is the single destination for everything TAK-related. The screen is divided into sections:

### TAK Identity (firmware module config)

The first section, **TAK Identity**, controls the firmware-level team / role identity the radio attaches to every PLI:

- **Team** — the team color shown to TAK clients (Cyan default, plus every standard ATAK team color).
- **Role** — Team Member, Team Lead, HQ, Sniper, Medic, Forward Observer, RTO, or K9.

These values only have effect when the device role is TAK or TAK Tracker — the section will tell you if the connected node is configured differently. A **Save TAK Identity** button appears in the section only when there are unsaved changes, and dispatches the update as an admin message to the connected node.

Previously this lived on its own **Settings → TAK Module** screen; it is now embedded in TAK Server so that team / role and the in-app server controls live on one page.

### Server status, Enable, and channel

Below the identity section:

- A status indicator showing whether the in-app TAK Server is running and whether the primary channel is suitable for TAK use (it needs a non-default name plus a non-default encryption key).
- A toggle to **Enable TAK Server**.
- A picker for the LoRa channel the server bridges between TAK clients and the mesh.
- A read-only-mode toggle and a mesh-to-CoT relay toggle.

### Certificates

Import a P12 (PKCS#12) or PEM bundle for mTLS-protected ATAK / iTAK connections. The app keeps the certificates encrypted in the keychain.

### Data Package

Export a TAK data package zip you can sideload into ATAK / iTAK so the client can connect to the app's local server without manual server entry.

Route packets received over the mesh (CoT `b-m-r`) are also automatically converted to KML data packages and saved to `Documents/TAK Routes/`, accessible via the iOS Files app, so you can import them manually into iTAK (which doesn't render route CoT from streaming).

## CoT Message Format

Meshtastic supports two on-wire formats, picked per-send based on the connected radio's firmware version:

- **V2 (firmware ≥ 2.8.0)** — Full typed CoT payload (PLI, GeoChat, shapes, markers, routes, casevac, emergency, task) on ATAK_PLUGIN_V2 = port 78, compressed with zstd dictionary compression for maximum range.
- **V1 (firmware ≤ 2.7.x)** — Bare `TAKPacket` protobuf for PLI / GeoChat on ATAK_PLUGIN = port 72, plus zlib + Fountain-coded CoT XML on ATAK_FORWARDER = port 257 for everything else (Apple-only fallback when interoperating with other iOS devices on the legacy stack).

## Requirements

- Firmware 2.3 or later on your radio (2.8.0 or later for full TAK V2 wire format)
- An ATAK / iTAK / TAK-compatible client app on your phone or tablet
- Device configured with the TAK or TAK Tracker role
