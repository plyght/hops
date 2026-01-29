#!/bin/bash

set -e

echo "=== Hops Interactive Terminal Test Suite ==="
echo ""

HOPS_BIN=".build/debug/hops"

if [ ! -f "$HOPS_BIN" ]; then
    echo "Error: $HOPS_BIN not found. Run ./build-and-sign.sh first."
    exit 1
fi

# Check if hopsd is running
if ! pgrep -q hopsd; then
    echo "Error: hopsd is not running. Start it with:"
    echo "  .build/debug/hopsd > /tmp/hopsd.log 2>&1 &"
    exit 1
fi

echo "✓ hopsd is running"
echo ""

echo "=== Test 1: Piped Input (Buffered Mode) ==="
echo "Command: echo 'echo Hello' | $HOPS_BIN run /tmp -- /bin/sh"
OUTPUT=$(echo "echo Hello" | $HOPS_BIN run /tmp -- /bin/sh 2>&1)
if [ "$OUTPUT" = "Hello" ]; then
    echo "✓ Piped input works"
else
    echo "✗ Piped input failed. Output: $OUTPUT"
    exit 1
fi
echo ""

echo "=== Test 2: Multiple Piped Commands ==="
echo "Command: echo -e 'ls /bin\necho test\npwd' | $HOPS_BIN run /tmp -- /bin/sh"
OUTPUT=$(echo -e "ls /bin\necho test\npwd" | $HOPS_BIN run /tmp -- /bin/sh 2>&1)
if echo "$OUTPUT" | grep -q "test"; then
    echo "✓ Multiple commands work"
else
    echo "✗ Multiple commands failed"
    exit 1
fi
echo ""

echo "=== Test 3: EOF Handling ==="
echo "Command: echo 'echo before EOF' | $HOPS_BIN run /tmp -- /bin/sh"
OUTPUT=$(echo "echo before EOF" | $HOPS_BIN run /tmp -- /bin/sh 2>&1)
if echo "$OUTPUT" | grep -q "before EOF"; then
    echo "✓ EOF handling works"
else
    echo "✗ EOF handling failed"
    exit 1
fi
echo ""

echo "=== Test 4: Empty Input ==="
echo "Command: echo '' | $HOPS_BIN run /tmp -- /bin/sh -c 'echo empty test'"
OUTPUT=$(echo "" | $HOPS_BIN run /tmp -- /bin/sh -c "echo empty test" 2>&1)
if echo "$OUTPUT" | grep -q "empty test"; then
    echo "✓ Empty input works"
else
    echo "✗ Empty input failed"
    exit 1
fi
echo ""

echo "=== Test 5: Large Input (Buffering) ==="
LARGE_INPUT=$(printf 'echo line%d\n' {1..100})
OUTPUT=$(echo "$LARGE_INPUT" | $HOPS_BIN run /tmp -- /bin/sh 2>&1)
if echo "$OUTPUT" | grep -q "line100"; then
    echo "✓ Large input buffering works"
else
    echo "✗ Large input buffering failed"
    exit 1
fi
echo ""

echo "==================================="
echo "✓ All automated tests passed!"
echo "==================================="
echo ""
echo "=== Manual Interactive Test ==="
echo ""
echo "To test interactive mode, run the following command in a real terminal:"
echo ""
echo "  $HOPS_BIN run /tmp -- /bin/sh"
echo ""
echo "Then try:"
echo "  1. Type 'ls /' and press Enter"
echo "  2. Type 'echo hello' and press Enter"
echo "  3. Type 'pwd' and press Enter"
echo "  4. Press ctrl-d to exit (or type 'exit')"
echo ""
echo "Expected: Commands should execute immediately as you type them,"
echo "          just like SSH or a local terminal session."
echo ""
