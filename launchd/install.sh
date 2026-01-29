#!/bin/bash
set -e

echo "Hops Launch Daemon Installation"
echo "================================"
echo ""

if [ "$EUID" -ne 0 ]; then
	echo "ERROR: This script must be run as root (use sudo)"
	exit 1
fi

PLIST_SOURCE="$(dirname "$0")/com.hops.daemon.plist"
PLIST_DEST="/Library/LaunchDaemons/com.hops.daemon.plist"

if [ ! -f "$PLIST_SOURCE" ]; then
	echo "ERROR: Cannot find com.hops.daemon.plist in $(dirname "$0")"
	exit 1
fi

if ! command -v hopsd &>/dev/null; then
	echo "ERROR: hopsd binary not found in PATH"
	echo "Please install hopsd to /usr/local/bin/ first"
	exit 1
fi

echo "Creating system directories..."
mkdir -p /var/run/hops
mkdir -p /usr/local/var/log/hops
mkdir -p /usr/local/etc/hops/profiles

echo "Setting directory ownership..."
chown -R "$SUDO_USER" /var/run/hops
chown -R "$SUDO_USER" /usr/local/var/log/hops
chown -R "$SUDO_USER" /usr/local/etc/hops

echo "Installing launch daemon plist..."
cp "$PLIST_SOURCE" "$PLIST_DEST"
chown root:wheel "$PLIST_DEST"
chmod 644 "$PLIST_DEST"

if launchctl list | grep -q "com.hops.daemon"; then
	echo "Unloading existing daemon..."
	launchctl unload "$PLIST_DEST" 2>/dev/null || true
fi

echo "Loading launch daemon..."
launchctl load "$PLIST_DEST"

echo "Starting daemon..."
launchctl start com.hops.daemon

sleep 2

if launchctl list | grep -q "com.hops.daemon"; then
	echo ""
	echo "SUCCESS: Hops daemon installed and running"
	echo ""
	echo "Verify with:"
	echo "  ps aux | grep hopsd"
	echo "  ls -la /var/run/hops/hops.sock"
	echo ""
	echo "View logs:"
	echo "  tail -f /usr/local/var/log/hops/hopsd.log"
	echo "  tail -f /usr/local/var/log/hops/hopsd.error.log"
else
	echo ""
	echo "WARNING: Daemon may not have started correctly"
	echo "Check logs at /usr/local/var/log/hops/"
	exit 1
fi
