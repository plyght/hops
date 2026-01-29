#!/bin/bash
set -e

echo "Hops User Launch Agent Installation"
echo "===================================="
echo ""

PLIST_TEMPLATE="$(dirname "$0")/com.hops.daemon.user.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/com.hops.daemon.plist"

if [ ! -f "$PLIST_TEMPLATE" ]; then
	echo "ERROR: Cannot find com.hops.daemon.user.plist in $(dirname "$0")"
	exit 1
fi

if ! command -v hopsd &>/dev/null; then
	echo "ERROR: hopsd binary not found in PATH"
	echo "Please install hopsd to /usr/local/bin/ first"
	exit 1
fi

echo "Creating user directories..."
mkdir -p "$HOME/.hops/logs"
mkdir -p "$HOME/.hops/profiles"

echo "Expanding HOME in plist..."
sed "s|\$HOME|$HOME|g" "$PLIST_TEMPLATE" >"$PLIST_DEST"
chmod 644 "$PLIST_DEST"

if launchctl list | grep -q "com.hops.daemon"; then
	echo "Unloading existing agent..."
	launchctl unload "$PLIST_DEST" 2>/dev/null || true
fi

echo "Loading launch agent..."
launchctl load "$PLIST_DEST"

echo "Starting agent..."
launchctl start com.hops.daemon

sleep 2

if launchctl list | grep -q "com.hops.daemon"; then
	echo ""
	echo "SUCCESS: Hops user agent installed and running"
	echo ""
	echo "Verify with:"
	echo "  ps aux | grep hopsd"
	echo "  ls -la $HOME/.hops/hops.sock"
	echo ""
	echo "View logs:"
	echo "  tail -f $HOME/.hops/logs/hopsd.log"
	echo "  tail -f $HOME/.hops/logs/hopsd.error.log"
else
	echo ""
	echo "WARNING: Agent may not have started correctly"
	echo "Check logs at $HOME/.hops/logs/"
	exit 1
fi
