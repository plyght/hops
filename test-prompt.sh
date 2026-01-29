#!/bin/bash
set -e

echo "Testing interactive shell with prompt..."
echo "This should show the shell prompt immediately:"
echo ""

timeout 5 .build/debug/hops run /tmp -- /bin/sh <<EOF
echo "Hello from shell"
ls /
exit
EOF

echo ""
echo "Test completed!"
