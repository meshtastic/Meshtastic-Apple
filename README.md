# Meshtastic Apple Clients

<a href="https://apple.co/3Auysep">
    <img alt="Meshtastic App Store Launch Image" src="meshtastic-1080x1080.png" />
</a>

## Overview

SwiftUI client applications for iOS, iPadOS and macOS.

## OS Requirements

* iOS App Requires iOS 16 +
* iPadOS App Requires iPadOS 16 +
* Mac App Reguires macOS 13 +

## Code Standards

- Use SwiftUI (Maps are the exception)
- Use Hierarchical icons
- Use Core Data for persistence
- Requires SwiftLint - see https://github.com/realm/SwiftLint

## To update protobufs:

- install swift-protobuf:
  ```bash
  brew install swift-protobuf
  ```
- check out the latest protobuf commit from the master branch
- run:
  ```bash
  ./gen_proto.sh
  ```
- build, test, commit changes
- You may need to run:
  ```bash
  swiftlint --fix
  ```
