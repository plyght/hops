# Hops Launch Daemon Configuration

Launch daemon and agent configurations for running `hopsd` as a background service on macOS.

## Files

- `com.hops.daemon.plist` - System-wide LaunchDaemon (requires root)
- `com.hops.daemon.user.plist` - User-specific LaunchAgent (no root required)
- `install.sh` - System-wide installation script
- `install-user.sh` - User-specific installation script

## System-Wide Installation (Recommended)

Uses system paths and runs with elevated privileges. Survives user logout.

### Quick Install

```bash
sudo ./install.sh
```

### Manual Install

```bash
sudo mkdir -p /var/run/hops
sudo mkdir -p /usr/local/var/log/hops
sudo mkdir -p /usr/local/etc/hops/profiles
sudo chown -R $USER /var/run/hops
sudo chown -R $USER /usr/local/var/log/hops
sudo chown -R $USER /usr/local/etc/hops

sudo cp com.hops.daemon.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.hops.daemon.plist
sudo chmod 644 /Library/LaunchDaemons/com.hops.daemon.plist

sudo launchctl load /Library/LaunchDaemons/com.hops.daemon.plist
sudo launchctl start com.hops.daemon
```

### Paths
- Socket: `/var/run/hops/hops.sock`
- Logs: `/usr/local/var/log/hops/`
- Config: `/usr/local/etc/hops/`

## User-Specific Installation

Runs in user space without root. Stops when user logs out.

### Quick Install

```bash
./install-user.sh
```

### Manual Install

```bash
mkdir -p "$HOME/.hops/logs"
mkdir -p "$HOME/.hops/profiles"

sed "s|\$HOME|$HOME|g" com.hops.daemon.user.plist > "$HOME/Library/LaunchAgents/com.hops.daemon.plist"
chmod 644 "$HOME/Library/LaunchAgents/com.hops.daemon.plist"

launchctl load "$HOME/Library/LaunchAgents/com.hops.daemon.plist"
launchctl start com.hops.daemon
```

### Paths
- Socket: `~/.hops/hops.sock`
- Logs: `~/.hops/logs/`
- Config: `~/.hops/profiles/`

## Configuration Details

### Socket Path

The daemon listens on a Unix domain socket:
- **System**: `/var/run/hops/hops.sock`
- **User**: `~/.hops/hops.sock`

The `hops` CLI must connect to the same socket path.

### Log Files

Two log files are created:
- `hopsd.log` - Standard output (info, debug)
- `hopsd.error.log` - Standard error (errors, warnings)

Logs rotate automatically by macOS when they exceed size limits.

### Environment Variables

- `HOPS_CONFIG_DIR` - Configuration directory
- `HOME` - User home directory (user agent only)

### Launch Behavior

- `RunAtLoad: false` - Does not start automatically at boot/login
- `KeepAlive: true` - Restarts if crashes
- `ThrottleInterval: 10` - Waits 10 seconds between restart attempts
- `ProcessType: Background` - Runs as low-priority background process

## Management Commands

### Start Daemon

System-wide:
```bash
sudo launchctl start com.hops.daemon
```

User-specific:
```bash
launchctl start com.hops.daemon
```

### Stop Daemon

System-wide:
```bash
sudo launchctl stop com.hops.daemon
```

User-specific:
```bash
launchctl stop com.hops.daemon
```

### Restart Daemon

System-wide:
```bash
sudo launchctl stop com.hops.daemon
sudo launchctl start com.hops.daemon
```

User-specific:
```bash
launchctl stop com.hops.daemon
launchctl start com.hops.daemon
```

### Check Status

```bash
launchctl list | grep com.hops.daemon
ps aux | grep hopsd
```

### Unload Daemon

System-wide:
```bash
sudo launchctl unload /Library/LaunchDaemons/com.hops.daemon.plist
```

User-specific:
```bash
launchctl unload "$HOME/Library/LaunchAgents/com.hops.daemon.plist"
```

### Load Daemon

System-wide:
```bash
sudo launchctl load /Library/LaunchDaemons/com.hops.daemon.plist
```

User-specific:
```bash
launchctl load "$HOME/Library/LaunchAgents/com.hops.daemon.plist"
```

## Troubleshooting

### Daemon Won't Start

Check if hopsd binary exists:
```bash
which hopsd
ls -la /usr/local/bin/hopsd
```

Verify socket directory exists:
```bash
ls -la /var/run/hops/  # system
ls -la ~/.hops/        # user
```

Check logs:
```bash
tail -f /usr/local/var/log/hops/hopsd.error.log  # system
tail -f ~/.hops/logs/hopsd.error.log             # user
```

### Permission Errors

System-wide:
```bash
sudo chown -R $USER /var/run/hops
sudo chown -R $USER /usr/local/var/log/hops
```

User-specific:
```bash
chmod -R 755 ~/.hops
```

### Socket Already Exists

Remove stale socket:
```bash
sudo rm /var/run/hops/hops.sock  # system
rm ~/.hops/hops.sock             # user
```

Then restart daemon.

### Process Already Running

Kill existing process:
```bash
pkill hopsd
```

Then restart daemon.

### Path Expansion Issues

**IMPORTANT**: The system-wide plist uses absolute paths. If you see errors about `~/.hops`, the plist was not installed correctly.

User-specific plist requires `$HOME` expansion via `sed`:
```bash
sed "s|\$HOME|$HOME|g" com.hops.daemon.user.plist > output.plist
```

## Uninstallation

### System-Wide

```bash
sudo launchctl unload /Library/LaunchDaemons/com.hops.daemon.plist
sudo rm /Library/LaunchDaemons/com.hops.daemon.plist
sudo rm -rf /var/run/hops
sudo rm -rf /usr/local/var/log/hops
sudo rm -rf /usr/local/etc/hops
```

### User-Specific

```bash
launchctl unload "$HOME/Library/LaunchAgents/com.hops.daemon.plist"
rm "$HOME/Library/LaunchAgents/com.hops.daemon.plist"
rm -rf "$HOME/.hops"
```

## Security Considerations

- System-wide daemon runs with user privileges (not root)
- Socket files should be owned by the user running hopsd
- Log files may contain sensitive information - restrict permissions
- Config directory should only be writable by trusted users

## Advanced Configuration

### Custom Socket Path

Edit the plist and change the `--socket` argument:

```xml
<key>ProgramArguments</key>
<array>
    <string>/usr/local/bin/hopsd</string>
    <string>--socket</string>
    <string>/custom/path/hops.sock</string>
</array>
```

Update `HOPS_SOCKET` environment variable for CLI:
```bash
export HOPS_SOCKET=/custom/path/hops.sock
```

### Enable Auto-Start

Change `RunAtLoad` to `true`:

```xml
<key>RunAtLoad</key>
<true/>
```

### Disable Auto-Restart

Change `KeepAlive` to `false`:

```xml
<key>KeepAlive</key>
<false/>
```

### Additional Arguments

Add more arguments to `ProgramArguments` array:

```xml
<key>ProgramArguments</key>
<array>
    <string>/usr/local/bin/hopsd</string>
    <string>--socket</string>
    <string>/var/run/hops/hops.sock</string>
    <string>--verbose</string>
    <string>--debug</string>
</array>
```

## See Also

- [Setup Guide](../docs/setup.md) - Complete installation instructions
- [Apple Launch Services](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) - Official documentation
