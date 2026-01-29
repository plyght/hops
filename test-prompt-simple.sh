#!/bin/bash
set -e

echo "=== Testing Shell Prompt ==="
echo ""
echo "Starting daemon..."
pkill -9 hopsd 2>/dev/null || true
sleep 1
.build/debug/hopsd > /tmp/hopsd.log 2>&1 &
sleep 3

echo "Daemon started. Testing with simulated input..."
echo ""

printf "ls /\nexit\n" | .build/debug/hops run /tmp -- /bin/sh 2>&1 | head -20

echo ""
echo "=== Test Complete ===="
echo ""
echo "To test interactively from YOUR terminal, run:"
echo "  .build/debug/hops run /tmp -- /bin/sh"
echo ""
echo "You should see a prompt like:  / $ "
echo "And be able to type commands immediately"
