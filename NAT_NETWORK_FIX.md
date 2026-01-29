# NAT Network Fix Documentation

## Problem Summary

Outbound and full network modes were not working. Testing showed:
- ❌ **disabled mode**: ✅ worked (no network access)
- ❌ **loopback mode**: ✅ worked (127.0.0.1 accessible)  
- ❌ **outbound mode**: ❌ NAT gateway not forwarding packets
- ❌ **full mode**: ❌ Same NAT forwarding issue

## Root Causes

### 1. Incorrect IP Address Range
The original configuration used `10.0.0.0/24` subnet for NAT networking:
```swift
let natInterface = try NATInterface(
  ipv4Address: CIDRv4("10.0.0.5/24"),
  ipv4Gateway: IPv4Address("10.0.0.1")
)
```

**Issue**: The macOS vmnet framework's NAT implementation had routing issues with the `10.0.0.0/24` range, causing packets to be dropped at the NAT gateway (10.0.0.1).

**Fix**: Changed to `192.168.65.0/24` (Docker Desktop's standard range):
```swift
let natInterface = try NATInterface(
  ipv4Address: CIDRv4("192.168.65.5/24"),
  ipv4Gateway: IPv4Address("192.168.65.1")
)
```

### 2. DNS Configuration I/O Error
The Containerization framework's `config.dns = DNS(nameservers: [...])` API attempted to write to `/etc/resolv.conf` inside the rootfs **before** starting the container, causing:
```
Error: configure-dns: Error Domain=NSCocoaErrorDomain Code=512
NSFilePath=/run/container/.../rootfs/etc/resolv.conf
NSUnderlyingError=Error Domain=NSPOSIXErrorDomain Code=5 "I/O error"
```

**Root Cause**: The framework tries to mount and modify the ext4 rootfs file on macOS to inject DNS configuration, but encounters I/O errors when accessing the filesystem.

**Fix**: Removed automatic DNS configuration from the framework config and implemented runtime DNS setup by wrapping user commands:
```swift
let dnsSetup = "echo 'nameserver 8.8.8.8' > /etc/resolv.conf && echo 'nameserver 8.8.4.4' >> /etc/resolv.conf"
if command[0] == "/bin/sh" && command[1] == "-c" {
  config.process.arguments = ["/bin/sh", "-c", "\(dnsSetup) && \(command[2])"]
}
```

### 3. Per-Container Writable Rootfs
Each container needed its own writable copy of the rootfs to allow DNS configuration and other filesystem modifications.

**Fix**: Implemented per-container rootfs copying in `SandboxManager.swift`:
```swift
let containerRootfsPath = containerDir.appendingPathComponent("rootfs.ext4")
try FileManager.default.copyItem(at: rootfs, to: containerRootfsPath)
```

## Changes Made

### Files Modified

1. **Sources/hopsd/CapabilityEnforcer.swift**
   - Changed NAT IP range from `10.0.0.0/24` to `192.168.65.0/24`
   - Removed `config.dns` configuration (causes I/O error)
   - Added automatic DNS setup via command wrapping for outbound/full modes
   - Properly handles shell command wrapping to avoid breaking user commands

2. **Sources/hopsd/SandboxManager.swift**
   - Implemented per-container rootfs copying instead of shared read-only rootfs
   - Each container gets its own writable `rootfs.ext4` copy
   - Cleaned up automatically when container exits (unless `--keep` flag used)

3. **Sources/hops/Commands/RunCommand.swift** (no changes needed)

### Test Results

**Before Fix:**
```
✓ PASS: Network disabled
✓ PASS: Loopback  
❌ FAIL: Outbound - NAT gateway not forwarding
❌ FAIL: Full - Same NAT issue
❌ FAIL: DNS resolution
```

**After Fix:**
```
✓ PASS: Network disabled works
✓ PASS: Loopback interface works
✓ PASS: External network blocked
✓ PASS: Outbound network works
✓ PASS: Full network works
✓ PASS: DNS resolution works
```

## Technical Details

### NAT Networking Configuration

The working NAT configuration:
```swift
case .outbound, .full:
  do {
    let natInterface = try NATInterface(
      ipv4Address: CIDRv4("192.168.65.5/24"),
      ipv4Gateway: IPv4Address("192.168.65.1")
    )
    config.interfaces = [natInterface]
    // DNS configured at runtime, not via config.dns
  } catch {
    fatalError("Failed to create NAT interface: \(error)")
  }
```

### DNS Runtime Configuration

DNS is configured automatically before user commands:
```swift
let needsDNS = capabilities.network == .outbound || capabilities.network == .full
if needsDNS && !command.isEmpty {
  let dnsSetup = "echo 'nameserver 8.8.8.8' > /etc/resolv.conf && echo 'nameserver 8.8.4.4' >> /etc/resolv.conf"
  
  if command.count >= 2 && command[0] == "/bin/sh" && command[1] == "-c" {
    let userScript = command.count > 2 ? command[2] : ""
    config.process.arguments = ["/bin/sh", "-c", "\(dnsSetup) && \(userScript)"]
  } else {
    // Handle other command formats...
  }
}
```

### Network Interface Status

Inside container with outbound/full mode:
```
2: eth0: <BROADCAST,UP,LOWER_UP> mtu 1500
    inet 192.168.65.5/24 scope global eth0
    
Routes:
default via 192.168.65.1 dev eth0
192.168.65.0/24 dev eth0 scope link src 192.168.65.5
```

## Known Limitations

1. **IP Range Fixed**: The `192.168.65.0/24` range is hardcoded. Other ranges may not work reliably due to macOS vmnet framework quirks.

2. **DNS Servers Fixed**: Uses Google DNS (8.8.8.8, 8.8.4.4). Could be made configurable in future.

3. **Runtime DNS Setup**: DNS configuration happens at container startup, not during container creation. This means containers without network modes don't get unnecessary DNS setup.

4. **macOS vmnet Issues**: NAT forwarding reliability depends on macOS vmnet framework, which has known bugs in macOS 26.x (port forwarding issues, VPN disconnections).

## Testing Commands

```bash
# Build with proper entitlements
./build-and-sign.sh

# Restart daemon
pkill -9 hopsd
.build/debug/hopsd > /tmp/hopsd.log 2>&1 &

# Test each network mode
.build/debug/hops run --network disabled /tmp -- /bin/ping -c 1 8.8.8.8  # Should fail
.build/debug/hops run --network loopback /tmp -- /bin/ping -c 1 127.0.0.1  # Should work
.build/debug/hops run --network outbound /tmp -- /bin/ping -c 1 8.8.8.8  # Should work
.build/debug/hops run --network outbound /tmp -- /bin/wget -O- example.com  # Should work
.build/debug/hops run --network full /tmp -- /bin/ping -c 1 google.com  # Should work

# Run comprehensive test suite
bash Tests/Scripts/test-network.sh
```

## References

- **Apple Containerization Framework**: https://github.com/apple/containerization
- **macOS vmnet NAT Issues**: Known bugs in macOS 26.1 with packet forwarding
- **Related Issues**: VirtualBuddy NAT connectivity problems on macOS 14.6+

## Summary

The NAT networking fix required three key changes:
1. ✅ Using `192.168.65.0/24` IP range instead of `10.0.0.0/24`
2. ✅ Runtime DNS configuration instead of framework-level config
3. ✅ Per-container writable rootfs copies

All network modes now work correctly with full DNS resolution and internet connectivity.
