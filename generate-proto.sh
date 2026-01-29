#!/bin/bash
set -e

swift build --product protoc-gen-grpc-swift

protoc \
	--swift_opt=Visibility=Public \
	--swift_out=Sources/HopsProto \
	--grpc-swift_opt=Visibility=Public,Client=true,Server=true \
	--grpc-swift_out=Sources/HopsProto \
	--plugin=protoc-gen-grpc-swift=$(pwd)/.build/debug/protoc-gen-grpc-swift \
	proto/hops.proto

if [ -d "Sources/HopsProto/proto" ]; then
	mv Sources/HopsProto/proto/*.swift Sources/HopsProto/
	rmdir Sources/HopsProto/proto
fi

echo "Proto generation complete"
