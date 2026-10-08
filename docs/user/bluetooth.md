---
title: Bluetooth Device Connection
parent: User Guide
nav_order: 2
---

# Bluetooth Device Connection

The Meshtastic app connects to your radio over Bluetooth Low Energy (BLE). You can keep up to four radios connected at once and switch between them without re-pairing.

## Connecting a Radio

1. Power on your Meshtastic radio.
2. Open the app and tap the **Connect** tab.
3. The app scans for nearby devices automatically when you are not connected.
4. Tap your device name in the list to connect.

The app remembers your preferred device and reconnects automatically when the radio is in range.

## Disconnecting a Radio

Swipe left on a connected radio in the Connect view and tap **Disconnect**. The radio continues operating on the mesh — it just stops syncing with the app.

With other radios connected, they stay connected, and the radio you disconnected isn't reconnected automatically.

## Powering Off a Radio

Long press a connected radio row and choose **Power Off** to shut the radio down completely. Unlike **Disconnect** — which only stops the app from syncing — Power Off turns the radio off entirely, and you must physically power it back on to use it again.

Because that is hard to undo on a roof, tower, or other remote node, the app asks you to confirm before sending the shutdown, so an accidental tap (or a misplaced finger) won't power the device off.

## Live Activity

Long press a connected radio row to start a Live Activity (iOS 16.2+). The Live Activity shows mesh status on your Lock Screen and in Dynamic Island.

## Managing Multiple Radios

You can connect up to four radios at once, over Bluetooth, TCP, or serial in any mix. All of them share one database: every message, node, and position they hear is stored once, and the app remembers which radio heard what.

Each window works with one radio, as if it were its own copy of the app. That radio is the one at the top of the window's Connect tab, the one whose settings you see and change, and the one its messages go through. A channel your radios share shows the same history in every window; direct messages belong to the radio that sent or received them. With **Share Location** on, every connected radio gets your phone's position, and each radio with MQTT **Proxy to Client** on gets its own MQTT connection (see [MQTT](mqtt.md)).

- **iPhone and iPad:** the window shows one radio at a time. The other connected radios keep receiving in the background and are listed under **Also Connected**, with their battery, Bluetooth signal and unread direct messages. In a conversation on a channel several of your radios share, **Via** sends through another of them (see [Messages](messages.md)).
- **Mac:** each radio has its own window, so your radios can sit side by side. Closing a radio's window only hides it: the radio stays connected, and the **Radios** menu or the Connect window opens it again.

![A radio listed under Also Connected](../assets/screenshots/additionalRadioRow_connected.png)

Radios connect one at a time: while one downloads its settings and node list, another waits its turn, so connecting several at once takes a little longer than one.

### Adding a Radio

While a radio is connected, the Connect tab lists nearby radios and your saved manual connections under **Add a Radio**. Tap one to connect it, or use **Manual** in the section header to enter a TCP radio's address. Adding a radio never disconnects another: the new radio connects alongside the ones you have. On iPhone and iPad the window then shows the new radio. On the Mac it opens in its own window, and **Radios › Add Radio…** (⇧⌘N) opens the Connect window to add one. With four radios connected, the section says so; disconnect one to add another.

### Showing Another Radio

On iPhone and iPad, the window switches between your connected radios. Switching never disconnects anything.

> **Tip — Show another radio**
> In **Also Connected**, tap the **⋯** button next to a radio and choose **Show This Radio**. The window switches to it, and the radio it showed before moves to **Also Connected**. Both keep receiving.

With more than one radio connected, the radio indicator at the top of each screen shows **+1**, **+2** or **+3** for the other radios. Tap it to see them all and show a different one. On the Mac, **Show This Radio** and the indicator open that radio's own window instead.

Some radios need you before they can be used, whether the window shows them or not. They stay connected, and the app asks about them by name:

- **A locked radio** (lock-down firmware) needs its passphrase. A radio with a passphrase the app has saved is unlocked on its own. Otherwise the app says the radio is locked; **Unlock** opens a passphrase sheet for that radio, and the window keeps showing the radio it was showing. The passphrase is saved for the radio once it unlocks. Its row under **Also Connected** says **Locked** until then.
- **A radio on firmware the app no longer supports** needs an update. **Update** shows it in the window, with the firmware update screen. Its row says **Needs a firmware update** until then.

With more than one radio connected, the passphrase sheet and the update screen show the name of the radio they're for. On the Mac, each radio's own window shows them.

### Reconnecting

A radio you've connected is remembered. If it drops out of range or restarts, the app reconnects it as soon as it sees it again, and its window keeps showing it meanwhile. When you open the app and your usual radio connects, the other remembered radios are connected again too. A network radio that isn't found right then is connected when the app next sees it. Choosing **Disconnect** on a radio stops this until you connect it again yourself.

If iOS closes the app in the background while Bluetooth radios are connected, it relaunches the app when one of them has something to send. The app reconnects your radios, and the window keeps the radio it was showing. A radio the app doesn't bring back within a few minutes is let go, so it's free for another connection.

If your usual radio isn't around when you open the app, a remembered radio that's in range is connected after about 30 seconds, and your usual radio joins when it appears.

### Disconnecting a Radio

**Disconnect** disconnects only that radio, and it isn't reconnected until you connect it again. With more than one radio, its window stays on it: the Connect tab shows the radio as **Not connected**, with **Connect** and **Remove**, until you pick another radio. **Connect** is available once the app sees the radio nearby; until then the radio shows **Looking for it…**. On iPhone and iPad with a single radio, the Connect tab shows **No device connected** and the radios nearby, as before.

On the Mac, the radio's window stays open after **Disconnect**. The Connect window lists **Your Radios**, connected or not, each with **Open**, and the **Radios** menu lists them too. macOS reopens the radio windows that were open when you quit.

### Resetting or Removing a Radio

With one radio, **Reset NodeDB** and **Factory Reset** (in the radio's **Device** settings) clear the app's data as they always have. After a factory reset that also clears the radio's Bluetooth bonds, the radio no longer counts as one of your radios, and on the Mac its window closes; connect it again to add it back. When the app holds more than one radio's data, a reset only affects the radio you reset:

- Only that radio disconnects, and your other radios stay connected. A reset radio restarts and reconnects on its own, except after a factory reset that also clears its Bluetooth bonds.
- Nodes stay when another of your radios is on the same mesh: the same region, the same preset (or bandwidth, spreading factor and coding rate) and the same frequency. When the reset radio is on a mesh of its own, the nodes only it heard are removed, keeping favorites if you chose to preserve them.
- The app asks whether to delete the radio's messages too. If you do, its direct messages are deleted, and so are its messages on channels none of your other radios has. A channel another radio has keeps all its messages.

**Remove Radio** takes a radio out of the app without resetting it. You'll find it:

- On the Connect tab: in the menu of the connected radio at the top (touch and hold it, or right-click on the Mac), and in the **⋯** menu of a radio under **Also Connected**, next to **Disconnect**.
- On a radio that isn't connected, as **Remove**.
- On the Mac, in the Connect window's **Your Radios**, and in the **Radios** menu for the radio of the window in front.
- In the radio's **Device** settings, as **Remove This Radio**.

It isn't offered while the radio is still connecting. The app asks first. The radio disconnects and isn't reconnected, its window closes, and it no longer counts as one of your radios. On the Mac, if that was the last window open, the Connect window opens in its place. While the app holds another radio's data, the removed radio's data is removed as for a reset with its messages deleted, and favorites are kept. Its messages on channels another of your radios has are kept, and move to that radio's channel. When the app holds no other radio's data, removing a radio erases all app data, as **Clear App Data** in App Settings does: messages, nodes, favorites, saved routes and backups. Your app settings are kept. The radio itself isn't changed: connect it again to add it back.

> **Warning — Removing deletes data**
> Removing a radio deletes its direct messages and anything only it heard. This can't be undone.

A radio that isn't connected (one that stopped working, one you gave away, or one only known from an earlier version's backup) can also be removed from **Settings › App Settings › Your Radios**, which lists the radios the app knows that aren't connected or connecting now.

### Switching Radios

Switching the radio a window shows never disconnects a radio, and adding one never replaces another; disconnecting is always its own action. The database stays as it is, so every radio's messages and nodes remain in the app. When a radio finishes its initial config handshake with no other radio connected, the app first reapplies the bundled Meshtastic hardware catalog that ships with the app, then refreshes the same catalog from the Meshtastic API in the background so hardware names, images, and firmware-target metadata stay current.

> **Warning — Restoring a backup**
> Restoring a backup from **Settings › Backups** replaces the whole database, so all your radios disconnect first.

Earlier versions kept each radio's messages and nodes in a separate backup and swapped them in when you switched radios. The first time you open this version, those backups are merged into the one database, so every radio's history is there at once. Anything already in the database is kept as it is; only messages, nodes and history it doesn't have are added. A backup of a radio the database already holds isn't merged, so messages you deleted don't come back. The backup files themselves aren't changed or deleted. A backup that can't be merged after three launches is left alone; you can still restore it from **Settings › Backups**.

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
