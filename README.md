# Meshtastic Apple Clients

[![CLA assistant](https://cla-assistant.io/readme/badge/meshtastic/Meshtastic-Apple)](https://cla-assistant.io/meshtastic/Meshtastic-Apple)
[![Fiscal Contributors](https://opencollective.com/meshtastic/tiers/badge.svg?label=Fiscal%20Contributors&color=deeppink)](https://opencollective.com/meshtastic/)
[![Vercel](https://img.shields.io/static/v1?label=Powered%20by&message=Vercel&style=flat&logo=vercel&color=000000)](https://vercel.com?utm_source=meshtastic&utm_campaign=oss)

## Overview

A description about the project

**[Getting Started Guide](https://example.com)**

**[Documentation/API Reference](https://example.com)**


## Stats

<!--Repobeats image here (avaliable when public)-->

## OS Requirements

* iOS App Requires iOS 15 +
* iPadOS App Requires iPadOS 15 +
* Mac App Reguires macOS 12 +

## Code Standards

- Use SwiftUI
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
