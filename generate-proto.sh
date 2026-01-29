#!/bin/bash
set -e

protoc \
    --swift_out=Sources/hopsd/Generated \
    --grpc-swift_out=Sources/hopsd/Generated \
    --grpc-swift_opt=Client=true,Server=true \
    proto/hops.proto

echo "Proto generation complete"
