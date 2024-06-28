# Meshtastic Apple Clients

<a href="https://apple.co/3Auysep">
    <img alt="Meshtastic App Store Launch Image" src="meshtastic-1080x1080.png" />
</a>

## Overview

SwiftUI client applications for iOS, iPadOS and macOS.

## Getting Started

This project is currently using **Xcode 15.4**. 

1. Clone the repo.
2. Open `Meshtastic.xcworkspace`
2. Build and run the `Meshtastic` target.

```sh
git clone git@github.com:meshtastic/Meshtastic-Apple.git
cd Meshtastic-Apple
open Meshtastic.xcworkspace
```

## Technical Standards

### Supported Operating Systems

* iOS 16+
* iPadOS 16+
* macOS 13+

### Code Standards

- Use SwiftUI
- Use SFSymbols for icons
- Use Core Data for persistence

## Updating Protobufs:
- run:
  ```bash
  scripts/gen_protos.sh
  ```
- build, test, commit changes

## License

This project is licensed under the GPL v3. See the [LICENSE](LICENSE) file for details.
