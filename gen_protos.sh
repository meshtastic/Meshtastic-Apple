#!/bin/bash

# simple sanity checking for repo
if [ ! -d "../Meshtastic-protobufs" ]; then
  echo "Please check out the https://github.com/meshtastic/Meshtastic-protobufs the parent directory."
  exit
fi

# simple sanity checking for executable
if [ ! -x "`which protoc`" ]; then
  echo "Please install swift-protobuf by running: brew install swift-protobuf"
  exit
fi

protoc --proto_path=./protobufs --swift_out=./Meshtastic/Protobufs ./protobufs/meshtastic/*.proto

echo "Done generating the swift files from the proto files."
echo "Build, test, and commit changes."
