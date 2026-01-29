#!/bin/bash

echo "Testing immediate prompt appearance in interactive shell..."
echo "============================================================"
echo ""

(
  echo "PS1='HOPS> '"
  sleep 0.5
  echo "echo 'Command executed'"
  sleep 0.3
  echo "exit"
) | timeout 5 .build/debug/hops run /tmp -- /bin/sh -i 2>&1 | head -20

echo ""
echo "If you see 'HOPS>' prompt above and 'Command executed', the fix is working!"
