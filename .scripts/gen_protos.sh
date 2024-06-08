#!/bin/bash

# simple sanity checking for repo
if [ ! -d "./../protobufs" ]; then
  git submodule update --init
fi

# simple sanity checking for executable
if [ ! -x "$(which protoc-gen-swift)" ]; then
  brew install swift-protobuf
fi

protoc --proto_path=./protobufs --swift_out=./Meshtastic/Protobufs ./protobufs/meshtastic/*.proto

echo "Done generating the swift files from the proto files."
echo "Build, test, and commit changes."
