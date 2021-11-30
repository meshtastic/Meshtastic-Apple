#!/bin/bash

# simple sanity checking for repo
if [ ! -d "../Meshtastic-protobufs" ]; then
  echo "Please check out the https://github.com/meshtastic/Meshtastic-protobufs the parent directory."
  exit
fi

# simple sanity checking for executable
if [ ! -x "`which protoc`" ]; then
  echo "Please install switf-protobuf by running: brew install switf-proto"
  exit
fi

pdir=$(realpath "../Meshtastic-protobufs")
sdir=$(realpath "./MeshtasticClient/Protobufs")
echo "pdir:$pdir sdir:$sdir"
pfiles="radioconfig.proto channel.proto deviceonly.proto portnums.proto remote_hardware.proto environmental_measurement.proto admin.proto mqtt.proto mesh.proto storeforward.proto"
for pf in $pfiles
do
  echo "Generating $pf..."
  protoc --swift_out=${sdir} --proto_path=${pdir} $pf
done
echo "Done generating the swift files from the proto files."
echo "Build, test, and commit changes."
