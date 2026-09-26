---
title: Bluetooth Device Connection
parent: User Guide
nav_order: 2
---

# Bluetooth Device Connection

The Meshtastic app connects to your radio over Bluetooth Low Energy (BLE). You can keep up to four radios connected at once and switch which one is focused without re-pairing.

## Connecting a Radio

1. Power on your Meshtastic radio.
2. Open the app and tap the **Connect** tab.
3. The app scans for nearby devices automatically when you are not connected.
4. Tap your device name in the list to connect.

The app remembers your preferred device and reconnects automatically when the radio is in range.

## Disconnecting a Radio

Swipe left on a connected radio in the Connect view and tap **Disconnect**. The radio continues operating on the mesh — it just stops syncing with the app.

With other radios connected, one of them becomes the focused radio, and the radio you disconnected isn't reconnected automatically.

## Powering Off a Radio

Long press a connected radio row and choose **Power Off** to shut the radio down completely. Unlike **Disconnect** — which only stops the app from syncing — Power Off turns the radio off entirely, and you must physically power it back on to use it again.

Because that is hard to undo on a roof, tower, or other remote node, the app asks you to confirm before sending the shutdown, so an accidental tap (or a misplaced finger) won't power the device off.

## Live Activity

Long press a connected radio row to start a Live Activity (iOS 16.2+). The Live Activity shows mesh status on your Lock Screen and in Dynamic Island.

## Managing Multiple Radios

You can connect up to four radios at once, over Bluetooth, TCP, or serial in any mix. All of them share one database: every message, node, and position they hear is stored once, and the app remembers which radio heard what.

One connected radio is the **focused** radio. It is the one shown at the top of the Connect tab, and the one that settings and MQTT use. Messages go through the focused radio too, unless you pick another radio with **Via** in a conversation (see [Messages](messages.md)). With **Share Location** on, every connected radio gets your phone's position. The other connected radios keep receiving in the background and are listed under **Also Connected**, with their battery, Bluetooth signal and unread direct messages.

Radios connect one at a time: while one downloads its settings and node list, another waits its turn, so connecting several at once takes a little longer than one.

### Adding a Radio

While a radio is connected, the Connect tab lists nearby radios under **Add a Radio**. Tap one to connect it. The app asks what you want to do:

- **Keep [radio] and Add [new radio]** connects the new radio and keeps the current one.
- **Switch to [new radio]** disconnects the focused radio and connects the new one in its place. Nothing is deleted.

To stop the question, choose a default in **Settings › App Settings › Connecting Another Radio**: Ask Each Time, Keep Both Connected, or Switch Radios. With four radios connected, only switching is offered.

> **Tip — Focus another radio**
> In **Also Connected**, tap the **⋯** button next to a radio and choose **Focus This Radio** to make it the focused radio. The previously focused radio reconnects under **Also Connected** a moment later. Choose **Disconnect** to disconnect only that radio.

With more than one radio connected, the radio indicator at the top of each screen shows **+1**, **+2** or **+3** for the other radios. Tap it to see them all and focus a different one from anywhere in the app.

### Reconnecting

A radio connected alongside the focused one is remembered. If it drops out of range or restarts, the app keeps trying to reconnect it, backing off to once a minute. The next time the focused radio connects — for example when you open the app — the remembered radios are connected again too. Choosing **Disconnect** on a radio stops this until you connect it again yourself.

### Switching Radios

Switching the focused radio disconnects it and connects the new one. The database stays as it is, so the previous radio's messages and nodes remain in the app. After the new radio finishes its initial config handshake, the app first reapplies the bundled Meshtastic hardware catalog that ships with the app, then refreshes the same catalog from the Meshtastic API in the background so hardware names, images, and firmware-target metadata stay current.

> **Warning — Restoring a backup**
> Restoring a backup from **Settings › Backups** replaces the whole database, so the app disconnects any radios connected alongside the focused one first.

## BLE Signal Strength

The app displays the Bluetooth signal strength of nearby devices during scanning:

![BLE Signal Strength](../assets/screenshots/bleSignalStrength.png)

## Connection Status Icons

| Icon | Meaning |
|------|---------|
| ![BLE connected](../assets/screenshots/btConnected.png) | Connected via BLE |
| ![Reconnecting](../assets/screenshots/btReconnecting.png) | Reconnecting / retrying |
| ![TCP connected](../assets/screenshots/tcpConnected.png) | Connected via TCP/IP |
| ![Serial connected](../assets/screenshots/serialConnected.png) | Connected via serial (macOS) |

## Troubleshooting

**Radio not appearing in the list**
- Ensure Bluetooth is enabled in iOS Settings → Bluetooth. If Bluetooth is off, the Connect tab's Available Radios section shows a "Bluetooth is off" row — tap it to jump straight to Settings.

  ![Bluetooth is off row](../assets/screenshots/bluetoothOff.png)
- Move within 10 meters of the radio.
- Restart the radio.
- The app continuously listens for BLE advertisements — nearby radios should appear within a few seconds. If a device disappears from the list, it will reappear automatically when next heard.

**Connection drops repeatedly**
- Check battery level on the radio.
- Try forgetting the device in iOS Settings → Bluetooth and reconnecting.

**App asks for Bluetooth permission**
- Grant permission in iOS Settings → Privacy & Security → Bluetooth → Meshtastic.

---

{: .tip }
> **Tip — Connected Radio**
> Swipe left to disconnect. Long press to start the Live Activity or to power off the radio (you'll be asked to confirm).
