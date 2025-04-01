# Meshtastic Apple Clients

## Overview

SwiftUI client applications for iOS, iPadOS and macOS.

## Getting Started

This project always uses the latest release version of XCode.

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

## Technical Standards

### Supported Operating Systems

The last two major operating system versions are supported on iOS, iPadOS and macOS.

### Code Standards

- Use SwiftUI
- Use SFSymbols for icons
- Use Core Data for persistence

## Updating Protobufs:

1. run
```bash
./scripts/gen_protos.sh
```
2. Build, test, and commit the changes.

## Release Process

For more information on how a new release of Meshtastic is managed, please refer to [RELEASING.md](./RELEASING.md)

## License

This project is licensed under the GPL v3. See the [LICENSE](LICENSE) file for details.
