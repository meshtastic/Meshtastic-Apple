---
title: Nodes List
parent: User Guide
nav_order: 4
---

# Nodes List

The Nodes tab shows every device your radio has heard on the mesh. Tap any node for details.

## Node Status

| Element | Meaning |
|---------|---------|
| ![Node circle](../assets/screenshots/circleTextDefault.png) | **Short Name & Long Name** — each node has a short name (up to 4 bytes) shown in the coloured circle and a long name displayed next to it. The circle colour is derived from the node number. The short name can be an emoji or initials. |
| ![Online](../assets/screenshots/nodeOnline.png) | **Online** — the node has been heard recently and is considered online. |
| ![Idle / Sleeping](../assets/screenshots/nodeIdle.png) | **Idle / Sleeping** — the node has not been heard from recently and may be asleep or out of range. |
| ![Hops Away](../assets/screenshots/hopsAway.png) | **Hops Away** — the number of intermediate nodes relaying messages between you and this node. No hops means direct communication. |

## Encryption

| Icon | Meaning |
|------|---------|
| ![Shared Key](../assets/screenshots/lockOpen.png) | **Shared Key** — direct messages are using the shared key for the channel. |
| ![Public Key Encryption](../assets/screenshots/lockClosed.png) | **Public Key Encryption** — direct messages use public key infrastructure. Requires firmware 2.5+. |
| ![PKI Mismatch](../assets/screenshots/keySlash.png) | **Public Key Mismatch** — public key does not match the previously recorded key. Verify the contact out-of-band. |

## Device Roles

Each node is configured with a role that determines how it behaves on the mesh. Roles are shown in the node detail view.

| Icon | Role | Description |
|------|------|-------------|
| ![](../assets/screenshots/roleClient.png) | Client | Standard end-user device. Sends and receives messages, shares position. |
| ![](../assets/screenshots/roleClientMute.png) | Client Mute | Like Client but does not forward packets from other devices. Reduces mesh traffic near congested areas. |
| ![](../assets/screenshots/roleClientHidden.png) | Client Hidden | Only broadcasts as needed for stealth or power savings. |
| ![](../assets/screenshots/roleClientBase.png) | Client Base | Rooftop node that distributes messages widely from nearby Client Mute nodes. |
| ![](../assets/screenshots/roleRouter.png) | Router | Dedicated infrastructure node — prioritises packet forwarding. Not for rooftops or mobile nodes. |
| ![](../assets/screenshots/roleRouterLate.png) | Router Late | Like Router but rebroadcasts once after all other nodes. Better suited to rooftop deployments. |
| ![](../assets/screenshots/roleTracker.png) | Tracker | Broadcasts GPS position packets as priority. Optimised for frequent location reporting. |
| ![](../assets/screenshots/roleSensor.png) | Sensor | Broadcasts telemetry packets as priority. Optimised for sensor data. |
| ![](../assets/screenshots/roleTak.png) | TAK | Optimised for ATAK system communication. Reduces routine broadcasts. |
| ![](../assets/screenshots/roleTakTracker.png) | TAK Tracker | Enables automatic TAK PLI broadcasts. Reduces routine broadcasts. |
| ![](../assets/screenshots/roleLostAndFound.png) | Lost and Found | Broadcasts location as a message to the default channel to assist with device recovery. |

[Choosing the Right Device Role →](https://meshtastic.org/blog/choosing-the-right-device-role/)

## Complete Node Row Examples

The full node row shows the circle avatar, battery level, encryption status, last-heard time, device role, signal strength, and log indicators all at once.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../assets/screenshots/standard_directConnected_dark.png" />
  <img src="../assets/screenshots/standard_directConnected.png" alt="Directly connected node, favorite, with signal meter" />
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../assets/screenshots/standard_multiHop_dark.png" />
  <img src="../assets/screenshots/standard_multiHop.png" alt="Multi-hop node 4 hops away" />
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../assets/screenshots/standard_mqtt_dark.png" />
  <img src="../assets/screenshots/standard_mqtt.png" alt="MQTT-bridged node" />
</picture>

## Compact Node Row Examples

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../assets/screenshots/compact_directConnected_allInfo_dark.png" />
  <img src="../assets/screenshots/compact_directConnected_allInfo.png" alt="Directly connected node with all telemetry info" />
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../assets/screenshots/compact_multiHop_dark.png" />
  <img src="../assets/screenshots/compact_multiHop.png" alt="Multi-hop node 7 hops away" />
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../assets/screenshots/compact_withPosition_dark.png" />
  <img src="../assets/screenshots/compact_withPosition.png" alt="Node with position, 1 hop" />
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../assets/screenshots/compact_pkiMismatch_dark.png" />
  <img src="../assets/screenshots/compact_pkiMismatch.png" alt="PKI key mismatch node" />
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../assets/screenshots/compact_mqtt_dark.png" />
  <img src="../assets/screenshots/compact_mqtt.png" alt="MQTT-bridged node" />
</picture>

## Context Menu Actions

Long-press any node in the list to access quick actions:

- **Add to favorites / Remove from favorites** — star important nodes so they appear at the top of the list
- **Mute notifications / Unmute** — silence alerts from this node
- **Message** — open a direct message conversation with this node
- **Trace Route** — discover the path messages take to reach this node
- **Ignore / Remove from ignored** — hide this node from normal views
- **Remove** — remove the node from your local database

## Filtering & Search

Tap the filter icon above the list to narrow which nodes are shown. Filters apply across the Nodes list, the contacts picker in Messages, and the map, so a filter set in one place takes effect everywhere.

| Filter | What it shows |
|--------|---------------|
| **Online** | Only nodes heard in the last two hours. |
| **Favorites** | Only nodes you have starred. |
| **Public Key Encryption** | Only nodes using PKI-encrypted direct messages. |
| **Environment** | Only nodes reporting environment telemetry (temperature, humidity, pressure). |
| **Hops Away** | Limit to nodes within a chosen number of hops, including direct (0-hop) only. |
| **Distance** | Limit to nodes within a chosen radius of your location. Falls back to the connected device's last position when phone location is unavailable. |
| **Roles** | Show only the device roles you select. |
| **Connection** | Show nodes reachable via LoRa, via MQTT, or both. At least one is always kept on. |

Filters are **remembered between launches** — the app reopens with the same filters applied. Search text is the exception: it is intentionally cleared on relaunch so you never reopen into a stale search that hides most of your nodes. Use the **reset** affordance to clear every filter and the search text at once.

## Additional Icons

Tap a node and scroll to the Logs section for detailed metrics:

| Log | Description |
|-----|-------------|
| ![Distance & Bearing](../assets/screenshots/logDistance.png) | Direction and distance to the node based on GPS. Requires both devices to share location. |
| ![Channel badge](../assets/screenshots/channelBadge.png) | The numbered circle shows which channel the node uses. Only shown for secondary channels (not primary channel 0). |
| ![Device Metrics](../assets/screenshots/logDeviceMetrics.png) | Battery level, voltage, channel utilisation, and airtime reported by the node. |
| ![Positions](../assets/screenshots/logPositions.png) | GPS position data including latitude, longitude, and altitude. |
| ![Environment](../assets/screenshots/logEnvironment.png) | Sensor data: temperature, humidity, barometric pressure. |
| ![Detection Sensor](../assets/screenshots/logDetectionSensor.png) | Motion or door open/close alerts from the node. |
| ![Trace Routes](../assets/screenshots/logTraceRoutes.png) | Recorded trace route paths showing the hops a message took through the mesh. |

## Local Stats and Noise Floor

Local Stats show radio diagnostics reported by a node, including packets received, packets transmitted, duplicate packets, relayed packets, bad receives, canceled packets, online node count, total node count, and noise floor.

Noise floor is displayed in dBm when the node reports it. Treat it as a directional diagnostic instead of an absolute site score: readings can vary quickly, and external filters can lower or skew the displayed value because of insertion loss or in-band interference.

## Node Detail View

Tap any node to see the full detail view with hardware info, signal metrics, environment sensors, and log navigation:

![Node Detail](../assets/screenshots/nodeDetail.png)

### Hardware Info

The hardware section shows information about the physical device running the node. The section title reflects the device's support status:

| Status | Meaning |
|--------|---------|
| **Supported Hardware** | Device is actively supported with firmware updates. |
| **Discontinued Hardware** | Device is no longer supported and does not receive firmware updates. |

For supported devices, the support tier is shown below the hardware name:

| Tier | Description |
|------|-------------|
| Flagship | Recommended device with full feature support and active development. |
| Niche | Supported device with active firmware updates and a specialised form factor. |
| Legacy | Older device that still receives firmware updates but may lack some features. |

### Where to Buy

For devices with known purchase links, an **I want one** section appears below the hardware info. It shows the official vendor link and regional marketplace options (Amazon, Rokland, AliExpress, and others) sourced from [msh.to](https://msh.to).

Marketplace links are filtered to your device region, so only stores that ship to your area are shown. Vendor links (directly from the device manufacturer) are always shown regardless of region.

> **Tip — No purchase links shown**
> Purchase links require an internet connection on first launch and after clearing app data. Connect the app to update the device catalog.

[Device Configuration Docs →](https://meshtastic.org/docs/configuration/radio/device/)
