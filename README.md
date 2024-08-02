# Meshtastic Apple Clients

## Overview

SwiftUI client applications for iOS, iPadOS and macOS.

## Getting Started

This project is currently using **Xcode 15.4**. 

1. Clone the repo.
2. Set up git hooks to automatically lint the project when you commit changes.
2. Open `Meshtastic.xcworkspace`
2. Build and run the `Meshtastic` target.

```sh
git clone git@github.com:meshtastic/Meshtastic-Apple.git
cd Meshtastic-Apple
./scripts/setup-hooks.sh
open Meshtastic.xcworkspace
```

## Technical Standards

### Supported Operating Systems

The last two operating system versions are supported. Currently that is 16 and 17.

* iOS 16.6+
* iPadOS 16.6+
* macOS 13+

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
