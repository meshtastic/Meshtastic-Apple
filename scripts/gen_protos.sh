#!/bin/bash

# simple sanity checking for repo
if [ ! -d "./protobufs" ]; then
   echo 'Please check out the protobuf submodule by running: `git submodule update --init`'
  exit
fi

# simple sanity checking for executable
if [ ! -x "$(which protoc)" ]; then
  echo 'Please install swift-protobuf by running: `brew install swift-protobuf`'
  exit
fi

protoc --proto_path=./protobufs --swift_opt=Visibility=Public --swift_out=./MeshtasticProtobufs/Sources ./protobufs/meshtastic/*.proto 

echo "Done generating the swift files from the proto files."
echo "Build, test, and commit changes."
