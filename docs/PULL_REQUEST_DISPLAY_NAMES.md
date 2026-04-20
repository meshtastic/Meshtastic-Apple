# Local display names for nodes

Users can set a **local display name** for any node. That name is shown in the app instead of the device’s long/short name, and is stored only on the device (not sent over the mesh).

---

## Summary

<table>
<tr><td><strong>Storage</strong></td><td><code>NodeDisplayNameStore</code> (UserDefaults), keyed by <strong>node number</strong></td></tr>
<tr><td><strong>Scope</strong></td><td>Node list, node detail, messages (user list &amp; relay), compass waypoint name</td></tr>
<tr><td><strong>Edit entry points</strong></td><td>Long-press node → “Set display name”; Node detail → “Display name” row</td></tr>
</table>

---

## UI

<ul>
<li><strong>Node list</strong> – Rows show the custom display name when set, otherwise the device long/short name.</li>
<li><strong>Long-press menu</strong> – “Set display name” opens a sheet to set or clear the name.</li>
<li><strong>Node detail</strong> – Navigation title and a “Display name” row; tapping the row opens the edit sheet.</li>
<li><strong>Edit sheet</strong> – Text field for the local name, with options to save or clear the display name.</li>
<li><strong>Messages</strong> – User list and relay text use <code>displayLongName</code> / <code>displayShortName</code>.</li>
</ul>

---

## Technical details

- **Key:** Display names are stored and looked up by <strong>node number</strong> (<code>num</code>), the unique node ID.
- **Persistence:** UserDefaults key <code>nodeDisplayNames</code>; JSON dictionary <code>[String: String]</code> with node num as string key.
- **Model:** <code>UserEntity</code> extensions <code>displayLongName</code> and <code>displayShortName</code>; they return the stored name if set, otherwise the existing <code>longName</code> / <code>shortName</code>.
- **UI refresh:** <code>NodeDisplayNameStore.didChangeNotification</code> is posted when a name is set or cleared; detail view subscribes to refresh the title.

---

## Checklist

- [x] Display name keyed by node number only
- [x] Shown in list, detail, and messages; editable from list context menu and detail row
- [x] Clear display name restores device name
- [x] No change to device identity or protocol; local-only
