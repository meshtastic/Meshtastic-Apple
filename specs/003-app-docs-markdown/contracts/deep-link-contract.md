# Deep Link Contract: Help & Documentation

## URL

```
meshtastic:///settings/helpDocs
```

## Routing Behaviour

| Component | Value |
|-----------|-------|
| Scheme | `meshtastic` |
| Host | (empty) |
| Path | `/settings/helpDocs` |
| Query params | None |

### Dispatch path

1. `Router.route(url:)` receives the URL.
2. `components.path.hasPrefix("/settings")` → calls `routeSettings(_:)`.
3. `routeSettings` extracts first path segment: `"helpDocs"`.
4. `SettingsNavigationState.init(rawValue: "helpDocs")` → `.helpDocs`.
5. `selectedTab = .settings`, `settingsState = .helpDocs`.
6. `Settings.swift` `.navigationDestination(for: SettingsNavigationState.self)` case `.helpDocs` pushes `DocBrowserView`.

## Code change requirements

| File | Change |
|------|--------|
| `Meshtastic/Router/NavigationState.swift` | Add `case helpDocs` to `SettingsNavigationState` |
| `Meshtastic/Views/Settings/Settings.swift` | Add `NavigationLink(value: .helpDocs)` + `.navigationDestination` case |
| `README.md` | Add row to deep-link table |

## README entry

| Deep Link | Description |
|-----------|-------------|
| `meshtastic:///settings/helpDocs` | Opens Help & Documentation browser in Settings |

## Acceptance test

```swift
// DocBrowserDeepLinkTests.swift
@Test func helpDocsDeepLinkRoutesToSettings() {
    let router = Router(selectedTab: .connect)
    router.route(url: URL(string: "meshtastic:///settings/helpDocs")!)
    #expect(router.selectedTab == .settings)
    #expect(router.settingsState == .helpDocs)
}
```
