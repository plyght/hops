#!/bin/bash
set -e

echo "Building Hops..."
swift build "$@"

echo "Signing hopsd with virtualization entitlement..."
codesign -s - --entitlements hopsd.entitlements --force .build/debug/hopsd

echo "Build complete!"
echo ""
echo "To run daemon:"
echo "  .build/debug/hopsd"
echo ""
echo "To test:"
echo "  .build/debug/hops system status"
echo "  .build/debug/hops run /tmp -- /bin/sh"
