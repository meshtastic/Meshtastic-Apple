---
title: Apple Watch App
parent: User Guide
nav_order: 13
---

# Apple Watch App

The Meshtastic Apple Watch app is a companion to the iPhone app that puts two features on your wrist: a **Foxhunt compass** for radio direction-finding and a **phone connectivity panel** to confirm your Watch is in sync.

Node data is pushed to the Watch automatically whenever the iPhone app is in range via WatchConnectivity. No Bluetooth connection to your Meshtastic radio is required on the Watch itself.

## Requirements

| Requirement | Details |
|-------------|---------|
| Apple Watch | watchOS paired with iPhone |
| iPhone app | Meshtastic iPhone app open and connected to a radio |
| Location | Watch Location Services enabled for direction-finding |
| Proximity | Watch and iPhone within normal Bluetooth/Wi-Fi range of each other |

## Tabs

The Watch app uses a vertical page layout. Swipe up or down to switch between the two tabs.

### Foxhunt

The Foxhunt tab lists mesh nodes that are within **½ mile (≈ 800 m)** of your current Watch location and have a known GPS position. Nodes marked as foxhunt targets from the iPhone app always appear at the top of the list, regardless of distance.

Each row shows:

| Element | Meaning |
|---------|---------|
| Colored circle | Node short name, color derived from node number |
| Name | Node long name |
| Distance | Distance from your current location, color-coded by proximity |
| Arrow | Mini bearing arrow pointing toward the node, rotates with your heading |

Tap any row to open the **Foxhunt Compass** for that node.

#### Foxhunt Compass

The compass points toward the selected node using your Watch's heading sensor. It is designed for radio direction-finding (foxhunting) — walk until the arrow points straight ahead and the distance reads zero.

| Element | Meaning |
|---------|---------|
| Rotating dial | Cardinal directions (N/NE/E…) rotate with your physical heading |
| Orange triangle | Fixed north indicator at the top of the ring |
| Colored arrow | Bearing arrow pointing toward the target node |
| Direction cone | Translucent wedge highlighting the target direction |
| Center circle | Current heading in degrees, bearing to target, and distance |
| Node circle | Short name badge of the target node |

**Distance color coding:**

| Color | Distance |
|--------|----------|
| Red | Far (> ⅔ of ½ mile) |
| Yellow | Mid-range (⅓ – ⅔ of ½ mile) |
| Green | Close (< ⅓ of ½ mile) |

**Haptic feedback:** The Watch taps your wrist when you are facing within 10° of the target node's bearing — useful when you can't look at the screen.

### Phone

The Phone tab shows the connectivity status between your Watch and the companion iPhone app.

| State | Meaning |
|-------|---------|
| Phone Connected (green) | iPhone app is reachable; node count shown |
| Phone Not Reachable | Watch is out of range or iPhone app is not running |

Tap **Refresh** to request an updated node list from the iPhone app. If the phone is temporarily unreachable, the Watch falls back to the most recently received node data.

## Setting Foxhunt Targets

From the iPhone app, mark a node as a foxhunt target from its detail view. Marked nodes are pushed to the Watch and pinned at the top of the Foxhunt list regardless of distance — useful when you know which node you are hunting before you are within ½ mile range.

## Notifications

The Watch app does not create notifications. Every Meshtastic alert on your wrist is a notification from the **iPhone** app that watchOS mirrored across, so it arrives whether or not the Watch app is running.

**Removing the Watch app does not stop them.** Mirroring is a function of the pairing rather than of the Watch app, so deleting Meshtastic from the Watch leaves the alerts exactly as they were. Installing or removing the Watch app and silencing Watch alerts are two separate decisions.

### Silence Meshtastic on the Watch only

On your iPhone, open the **Watch** app → **My Watch** → **Notifications** → **Meshtastic** → **Custom**:

| Option | Effect |
|--------|--------|
| Allow Notifications | Alerts appear on the Watch |
| Send to Notification Center | Delivered silently — no haptic, no screen wake |
| Notifications Off | No Meshtastic alerts on the Watch at all |

Your iPhone keeps alerting normally under all three.

### Silence a category on both devices

To stop a *kind* of alert everywhere, use **Settings → Meshtastic → Notifications** on the iPhone. Turning a category off there stops the notification being created at all, so nothing reaches the Watch either.
