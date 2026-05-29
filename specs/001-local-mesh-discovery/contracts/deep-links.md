# Deep Link Contract: Local Mesh Discovery

## URL Scheme

### Open Discovery Screen

```
meshtastic:///settings/localMeshDiscovery
```

**Behavior**: Navigates to the Settings tab, then pushes the Local Mesh Discovery view. If a scan is in progress, shows the active scan with map and timer. If no scan is active, shows the preset picker / scan configuration.

**Router handling**: `Router.route(url:)` matches path segment `localMeshDiscovery` under the `settings` path. Sets `selectedTab = .settings` and pushes `SettingsNavigationState.localMeshDiscovery`.

### Open Session History

```
meshtastic:///settings/localMeshDiscovery/history
```

**Behavior**: Navigates to Settings > Local Mesh Discovery > Session History list.

**Router handling**: Same as above but additionally pushes the history sub-view.

## Navigation State

```swift
// In SettingsNavigationState enum:
case localMeshDiscovery
```

## Settings Section

Added to `developersSection` in `Settings.swift`:

```swift
NavigationLink(value: SettingsNavigationState.localMeshDiscovery) {
    Label {
        Text("Local Mesh Discovery")
    } icon: {
        Image(systemName: "antenna.radiowaves.left.and.right")
    }
}
```
