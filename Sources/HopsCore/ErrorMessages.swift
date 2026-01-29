import Foundation

public struct ErrorMessages {
  public static func daemonNotRunning() -> String {
    """
    Daemon is not running

    The Hops daemon (hopsd) manages all sandbox operations but is not currently active.

    To start the daemon:
      hops system start

    To check daemon status:
      hops system status

    For troubleshooting:
      hops doctor
    """
  }

  public static func daemonConnectionFailed(socketPath: String, error: String) -> String {
    """
    Failed to connect to daemon

    Could not connect to the Hops daemon at: \(socketPath)
    Error: \(error)

    This usually means:
      1. The daemon is not running
      2. The socket file has incorrect permissions
      3. The daemon crashed or is unresponsive

    To fix:
      1. Start the daemon: hops system start
      2. Check socket permissions: ls -la \(socketPath)
      3. View daemon logs: tail -50 ~/.hops/logs/hopsd.log

    For full diagnostics:
      hops doctor
    """
  }

  public static func missingRuntimeFiles(missing: [String]) -> String {
    let fileList = missing.map { "  • \($0)" }.joined(separator: "\n")
    return """
    Required runtime files are missing

    Hops needs these files to run sandboxes:
    \(fileList)

    To download and set up all required files:
      hops init

    These files are required:
      • vmlinux: Linux kernel for virtualization (~14MB)
      • initfs: Init system (~256MB)
      • alpine-rootfs.ext4: Base filesystem (~512MB)

    Manual setup:
      See: https://github.com/apple/container/releases
    """
  }

  public static func permissionDenied(path: String, operation: String) -> String {
    """
    Permission denied

    Cannot \(operation): \(path)

    This file or directory requires different permissions.

    To fix:
      chmod 644 \(path)     # For regular files
      chmod 755 \(path)     # For executables/directories

    If the file is owned by another user:
      sudo chown $USER \(path)

    Check current permissions:
      ls -la \(path)
    """
  }

  public static func invalidPolicyFile(path: String, reason: String) -> String {
    """
    Invalid policy file

    File: \(path)
    Error: \(reason)

    Policy files must be valid TOML with required fields.

    Minimal valid policy:
      name = "example"
      version = "1.0.0"

      [capabilities]
      network = "disabled"
      filesystem = ["read"]

      [sandbox]
      root_path = "/"

    View examples:
      ls ~/.hops/profiles/
      ls config/examples/

    Check syntax:
      cat \(path)
    """
  }

  public static func invalidPathInPolicy(path: String, reason: String) -> String {
    """
    Invalid path in policy

    Path: \(path)
    Issue: \(reason)

    Security requirements:
      • All paths must be absolute (start with /)
      • No relative paths (../, ./)
      • No symlinks to sensitive locations
      • Cannot write to: /etc/shadow, /etc/passwd, /root/.ssh

    Examples of valid paths:
      allowed_paths = ["/usr", "/tmp", "/home/user/project"]
      denied_paths = ["/etc/shadow", "/root/.ssh"]

    Examples of invalid paths:
      ../secrets          # Relative path
      ~/config            # Must expand to absolute path
      /etc/shadow         # Cannot allow write access
    """
  }

  public static func networkCapabilityRequired(capability: String) -> String {
    """
    Network access denied

    This operation requires network capability: \(capability)

    Current policy has network disabled.

    To enable network access:
      hops run --network \(capability) /path -- command

    Network options:
      • disabled:  No network access (default)
      • loopback:  Only localhost (127.0.0.1)
      • outbound:  Internet access with NAT and DNS
      • full:      Complete network access

    Examples:
      hops run --network outbound /tmp -- wget example.com
      hops run --network loopback /tmp -- python server.py
    """
  }

  public static func resourceLimitExceeded(resource: String, limit: String, requested: String) -> String {
    """
    Resource limit exceeded

    Resource: \(resource)
    Limit: \(limit)
    Requested: \(requested)

    The sandbox policy restricts this resource below what was requested.

    To increase limits:
      hops run --\(resource) \(requested) /path -- command

    Or edit the policy file to increase resource_limits.\(resource)

    Example policy:
      [capabilities.resource_limits]
      cpus = 4
      memory_bytes = 4294967296  # 4GB
      max_processes = 256
    """
  }

  public static func profileNotFound(name: String, searchedPaths: [String]) -> String {
    let pathList = searchedPaths.map { "  • \($0)" }.joined(separator: "\n")
    return """
    Profile not found: \(name)

    Searched in:
    \(pathList)

    Available profiles:
      hops profile list

    To create a new profile:
      hops profile create \(name) --template restrictive

    To use a custom policy file:
      hops run --policy-file path/to/policy.toml /path -- command
    """
  }

  public static func commandFailed(exitCode: Int32, command: String) -> String {
    """
    Command failed with exit code \(exitCode)

    Command: \(command)

    The sandboxed command exited with an error. This is not a Hops error.

    To debug:
      • Check the command output above for error messages
      • Verify the command works outside the sandbox
      • Check if required files/capabilities are accessible
      • Use --verbose for detailed execution info

    Common issues:
      • Missing files: Add paths to allowed_paths in policy
      • Network errors: Use --network outbound
      • Permission issues: Check file ownership and modes
    """
  }

  public static func daemonStartupFailed(logPath: String) -> String {
    """
    Failed to start daemon

    The Hops daemon failed to start. This could be due to:
      • Missing runtime files (vmlinux, initfs, rootfs)
      • Port/socket already in use
      • Insufficient system resources
      • Missing required entitlements

    Check daemon logs:
      tail -50 \(logPath)

    Verify setup:
      hops doctor

    If files are missing:
      hops init

    If socket is stuck:
      rm ~/.hops/hops.sock
      hops system start
    """
  }

  public static func binaryNotFound(name: String) -> String {
    """
    Binary not found: \(name)

    The \(name) executable is not in the expected locations.

    Expected locations:
      • /usr/local/bin/\(name)
      • /usr/bin/\(name)
      • ~/.local/bin/\(name)
      • .build/debug/\(name)
      • .build/release/\(name)

    To install:
      swift build
      sudo cp .build/debug/\(name) /usr/local/bin/
      sudo cp .build/debug/hopsd /usr/local/bin/

    To use without installing:
      ./.build/debug/\(name) [args]
    """
  }

  public static func firstTimeWelcome() -> String {
    """
    Welcome to Hops!

    Hops provides lightweight sandboxing for untrusted code on macOS.

    Getting started:
      1. Download required files: hops init
      2. Start the daemon: hops system start
      3. Run your first sandbox: hops run /tmp -- echo "Hello!"

    Check system health:
      hops doctor

    View available profiles:
      hops profile list

    Documentation:
      https://github.com/plyght/hops
    """
  }

  public static func missingCommand() -> String {
    """
    No command specified

    You must provide a command to execute in the sandbox.

    Usage:
      hops run [options] <path> -- <command> [args...]

    Examples:
      hops run /tmp -- echo "Hello"
      hops run /tmp -- /bin/sh -c "ls -la"
      hops run --profile untrusted /project -- npm test

    Use -- to separate hops options from the command.

    For interactive shell:
      hops run /tmp -- /bin/sh
    """
  }

  public static func doctorCheckFailed(check: String, issue: String, fix: String) -> String {
    """
    [\(check)] FAILED

    Issue: \(issue)

    To fix:
      \(fix)
    """
  }

  public static func doctorCheckPassed(check: String) -> String {
    "[\(check)] OK"
  }

  public static func formatInColor(_ message: String, color: TerminalColor) -> String {
    if isColorSupported() {
      return "\(color.code)\(message)\(TerminalColor.reset.code)"
    }
    return message
  }

  private static func isColorSupported() -> Bool {
    guard let term = ProcessInfo.processInfo.environment["TERM"] else {
      return false
    }
    return term != "dumb" && isatty(STDOUT_FILENO) != 0
  }
}

public enum TerminalColor: String {
  case red = "\u{001B}[31m"
  case green = "\u{001B}[32m"
  case yellow = "\u{001B}[33m"
  case blue = "\u{001B}[34m"
  case reset = "\u{001B}[0m"

  var code: String { rawValue }
}
