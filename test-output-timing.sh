#!/bin/bash

echo "Testing output timing (should appear within ~2 seconds)..."
echo "Start time: $(date +%T.%3N)"
echo ""

(
  sleep 0.1
  echo "echo 'OUTPUT RECEIVED'"
  sleep 0.2
  echo "exit"
) | .build/debug/hops run /tmp -- /bin/sh 2>&1 | while IFS= read -r line; do
  echo "[$(date +%T.%3N)] $line"
done

echo ""
echo "End time: $(date +%T.%3N)"
