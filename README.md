# Meshtastic Apple Clients

## Overview

SwiftUI client applications for iOS, iPadOS and macOS.

## Getting Started

This project always uses the [latest Xcode release version](https://xcodereleases.com/?scope=release).

1. Clone the repo.
   ```zsh
   git clone git@github.com:meshtastic/Meshtastic-Apple.git
   ```
2. Set up git hooks to automatically apply formatting and fix lint issues on commit:
   ```zsh
   ./scripts/setup-hooks.sh
   ```
3. Add your team and bundle idenfiers in a externalized configuration file:
   ```zsh
   echo """
    //
    //  Local.xcconfig
    //  Meshtastic
    //
    //  Created by $(whoami) on $(date -u -R +"%m/%d/%Y").
    //

    DEVELOPMENT_TEAM = GCH7VS5Y9R
    PRODUCT_BUNDLE_IDENTIFIER = gvh.Meshtastic
   """ > Meshtastic/Configuration/Local.xcconfig
   ```

   > Note: Ensure to update the [`DEVELOPMENT_TEAM`](https://developer.apple.com/documentation/xcode/build-settings-reference#Development-Team) to your team and [`PRODUCT_BUNDLE_IDENTIFIER`](https://developer.apple.com/documentation/xcode/build-settings-reference#Product-Bundle-Identifier) to your bundle identifier in reverse-DNS format. The `Local.xcconfig` configuration file is ignored in `.gitignore`.
4. Generate Protobufs:
   ```zsh
   ./scripts/gen_protos.sh
   ```
5. Open `Meshtastic.xcworkspace`:
   ```zsh
   xed Meshtastic.xcworkspace
   ```
6. Build and run the `Meshtastic` target.

> Note: if you use a personal or non-premium Apple Developer account, you will be unable to build as `WeatherKit`, `CarKit` and `Associated Domains` require a premium account. In order to build, change the entitlements for `Debug` builds to `MesthtasticDebug.entitlements`:
> <img width="1482" alt="image" src="https://github.com/user-attachments/assets/af72b371-40ec-4a44-bae7-a36752dfd19c" />

## Technical Standards

### Supported Operating Systems

The last two major operating system versions are supported on iOS, iPadOS and macOS.

### Code Standards

- Use SwiftUI
- Use SFSymbols for icons
- Use Core Data for persistence

## Updating Protobufs:

1. run:
  ```zsh
  ./scripts/gen_protos.sh
  ```
2. Build, test, and commit the changes.

## Release Process

For more information on how a new release of Meshtastic is managed, please refer to [RELEASING.md](./RELEASING.md)

## License

This project is licensed under the GPL v3. See the [LICENSE](LICENSE) file for details.
