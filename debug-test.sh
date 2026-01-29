#!/bin/bash
pkill -9 hopsd 2>/dev/null || true
sleep 1
.build/debug/hopsd > /tmp/hopsd.log 2>&1 &
sleep 3
echo "Starting interactive test..."
# Send a command that should produce output immediately
(sleep 0.5; echo "echo TESTING"; sleep 1; echo "exit") | .build/debug/hops run --verbose /tmp -- /bin/sh 2>&1 | tee /tmp/hops-debug.log
echo "---"
echo "Daemon log:"
tail -30 /tmp/hopsd.log
