#!/bin/bash

echo "Testing interactive shell prompt timing..."
echo "=========================================="
echo ""
echo "Starting shell (prompt should appear immediately)..."
echo ""

(
  sleep 1
  echo "ls -la"
  sleep 1
  echo "pwd"
  sleep 1
  echo "exit"
) | timeout 10 .build/debug/hops run /tmp -- /bin/sh

echo ""
echo "Test complete!"
