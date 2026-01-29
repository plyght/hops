#!/bin/bash

echo "======================================"
echo "Interactive Shell Prompt Test"
echo "======================================"
echo ""
echo "This test will start an interactive shell inside the sandbox."
echo "You should see a prompt like: / $ "
echo ""
echo "Try these commands:"
echo "  - ls"
echo "  - pwd  
echo "  - cd /tmp"
echo "  - echo hello"
echo "  - exit (to quit)"
echo ""
echo "Starting interactive shell in 3 seconds..."
sleep 3

.build/debug/hops run /tmp -- /bin/sh
