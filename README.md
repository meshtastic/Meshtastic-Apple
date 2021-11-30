# Meshtastic Client

- Requires SwiftLint - see https://github.com/realm/SwiftLint

## To update protobufs:

- install swift-protobuf: *brew install swift-protobuf*
- check out the latest commit from master branch from here: https://github.com/meshtastic/Meshtastic-protobufs in a directory that is at the same level as this project
- run: *./gen_proto.sh*
- build, test, commit changes
- You may need to run *swiftlint --fix*
