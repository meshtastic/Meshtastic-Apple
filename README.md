# Meshtastic Apple Clients

[![CLA assistant](https://cla-assistant.io/readme/badge/meshtastic/Meshtastic-Apple)](https://cla-assistant.io/meshtastic/Meshtastic-Apple)
[![Fiscal Contributors](https://opencollective.com/meshtastic/tiers/badge.svg?label=Fiscal%20Contributors&color=deeppink)](https://opencollective.com/meshtastic/)

## Overview

SwiftUI client applicaitons for iOS, iPadOS and macOS.

## Stats

<!--Repobeats image here (avaliable when public)-->

## OS Requirements

* iOS App Requires iOS 16 +
* iPadOS App Requires iPadOS 16 +
* Mac App Reguires macOS 13 +

## Code Standards

- Use SwiftUI (Maps are an exception)
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
