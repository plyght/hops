import ArgumentParser
import Foundation
import GRPC
import HopsCore
import HopsProto
import NIO

struct DoctorCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "doctor",
    abstract: "Check system health and diagnose issues",
    discussion: """
      Runs comprehensive diagnostics to identify configuration or runtime issues.

      Checks:
        • Daemon status and connectivity
        • Required runtime files (vmlinux, initfs, rootfs)
        • File permissions
        • Socket accessibility
        • Profile availability

      Examples:
        hops doctor
        hops doctor --verbose
      """
  )

  @Flag(name: .long, help: "Show detailed diagnostic information")
  var verbose: Bool = false

  func run() async throws {
    print("Hops System Diagnostics")
    print("======================\n")

    var allPassed = true

    allPassed = checkDaemon() && allPassed
    print()

    allPassed = checkRuntimeFiles() && allPassed
    print()

    allPassed = checkPermissions() && allPassed
    print()

    allPassed = checkProfiles() && allPassed
    print()

    allPassed = checkBinaries() && allPassed
    print()

    if allPassed {
      print(ErrorMessages.formatInColor("All checks passed!", color: .green))
      print("\nYour Hops installation is healthy.")
    } else {
      print(ErrorMessages.formatInColor("Some checks failed", color: .red))
      print("\nRun the suggested fixes above to resolve issues.")
      print("For first-time setup, run: hops init")
      throw ExitCode.failure
    }
  }

  private func checkDaemon() -> Bool {
    print("Checking daemon...")

    let pidFile = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".hops/hopsd.pid")

    guard FileManager.default.fileExists(atPath: pidFile.path) else {
      print(
        ErrorMessages.formatInColor(
          "  ✗ Daemon PID file not found", color: .red))
      print("    Fix: hops system start")
      return false
    }

    guard let pidString = try? String(contentsOf: pidFile, encoding: .utf8),
      let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines))
    else {
      print(ErrorMessages.formatInColor("  ✗ Invalid PID file", color: .red))
      print("    Fix: rm ~/.hops/hopsd.pid && hops system start")
      return false
    }

    if kill(pid, 0) != 0 {
      print(
        ErrorMessages.formatInColor(
          "  ✗ Daemon process not running (PID \(pid))", color: .red))
      print("    Fix: hops system start")
      return false
    }

    print(
      ErrorMessages.formatInColor(
        "  ✓ Daemon is running (PID \(pid))", color: .green))

    let socketPath = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".hops/hops.sock")

    if FileManager.default.fileExists(atPath: socketPath.path) {
      print(
        ErrorMessages.formatInColor(
          "  ✓ Socket file exists", color: .green))
      if verbose {
        print("    Path: \(socketPath.path)")
      }
    } else {
      print(
        ErrorMessages.formatInColor(
          "  ✗ Socket file missing", color: .red))
      print("    Fix: hops system restart")
      return false
    }

    return true
  }

  private func checkRuntimeFiles() -> Bool {
    print("Checking runtime files...")

    let homeDir = FileManager.default.homeDirectoryForCurrentUser
    let hopsDir = homeDir.appendingPathComponent(".hops")

    let requiredFiles: [(name: String, path: URL, sizeApprox: String)] = [
      ("vmlinux", hopsDir.appendingPathComponent("vmlinux"), "~14MB"),
      ("initfs", hopsDir.appendingPathComponent("initfs"), "~256MB"),
      ("alpine-rootfs.ext4", hopsDir.appendingPathComponent("alpine-rootfs.ext4"), "~512MB")
    ]

    var allPresent = true

    for file in requiredFiles {
      if FileManager.default.fileExists(atPath: file.path.path) {
        let size = (try? file.path.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        print(
          ErrorMessages.formatInColor(
            "  ✓ \(file.name) (\(formatBytes(UInt64(size))))", color: .green))
        if verbose {
          print("    Path: \(file.path.path)")
        }
      } else {
        print(
          ErrorMessages.formatInColor(
            "  ✗ \(file.name) missing (expected \(file.sizeApprox))", color: .red))
        allPresent = false
      }
    }

    if !allPresent {
      print("\n  Fix: hops init")
      print("  Or manually download from: https://github.com/apple/container/releases")
    }

    return allPresent
  }

  private func checkPermissions() -> Bool {
    print("Checking permissions...")

    let homeDir = FileManager.default.homeDirectoryForCurrentUser
    let hopsDir = homeDir.appendingPathComponent(".hops")

    var allCorrect = true

    if FileManager.default.fileExists(atPath: hopsDir.path) {
      if FileManager.default.isWritableFile(atPath: hopsDir.path) {
        print(
          ErrorMessages.formatInColor(
            "  ✓ ~/.hops directory is writable", color: .green))
      } else {
        print(
          ErrorMessages.formatInColor(
            "  ✗ ~/.hops directory is not writable", color: .red))
        print("    Fix: chmod 755 ~/.hops")
        allCorrect = false
      }
    } else {
      print(
        ErrorMessages.formatInColor(
          "  ✗ ~/.hops directory does not exist", color: .red))
      print("    Fix: mkdir -p ~/.hops")
      allCorrect = false
    }

    let logDir = hopsDir.appendingPathComponent("logs")
    if FileManager.default.fileExists(atPath: logDir.path) {
      print(
        ErrorMessages.formatInColor(
          "  ✓ Log directory exists", color: .green))
    } else {
      print(
        ErrorMessages.formatInColor(
          "  ! Log directory will be created automatically", color: .yellow))
    }

    return allCorrect
  }

  private func checkProfiles() -> Bool {
    print("Checking profiles...")

    let homeDir = FileManager.default.homeDirectoryForCurrentUser
    let profileDir = homeDir.appendingPathComponent(".hops/profiles")

    guard FileManager.default.fileExists(atPath: profileDir.path) else {
      print(
        ErrorMessages.formatInColor(
          "  ! No profile directory (will use defaults)", color: .yellow))
      print("    Create profiles in: \(profileDir.path)")
      return true
    }

    let profiles =
      (try? FileManager.default.contentsOfDirectory(atPath: profileDir.path))
      ?? []
    let tomlProfiles = profiles.filter { $0.hasSuffix(".toml") }

    if tomlProfiles.isEmpty {
      print(
        ErrorMessages.formatInColor(
          "  ! No custom profiles found", color: .yellow))
      print("    You can create profiles with: hops profile create")
    } else {
      print(
        ErrorMessages.formatInColor(
          "  ✓ Found \(tomlProfiles.count) profile(s)", color: .green))
      if verbose {
        for profile in tomlProfiles {
          let name = (profile as NSString).deletingPathExtension
          print("    • \(name)")
        }
      }
    }

    return true
  }

  private func checkBinaries() -> Bool {
    print("Checking binaries...")

    let hops = findBinary("hops")
    let hopsd = findBinary("hopsd")

    var allFound = true

    if let hopsPath = hops {
      print(
        ErrorMessages.formatInColor(
          "  ✓ hops found", color: .green))
      if verbose {
        print("    Path: \(hopsPath)")
      }
    } else {
      print(
        ErrorMessages.formatInColor(
          "  ✗ hops not found in PATH", color: .red))
      allFound = false
    }

    if let hopsdPath = hopsd {
      print(
        ErrorMessages.formatInColor(
          "  ✓ hopsd found", color: .green))
      if verbose {
        print("    Path: \(hopsdPath)")
      }
    } else {
      print(
        ErrorMessages.formatInColor(
          "  ✗ hopsd not found", color: .red))
      print("    Fix: swift build && sudo cp .build/debug/hopsd /usr/local/bin/")
      allFound = false
    }

    return allFound
  }

  private func findBinary(_ name: String) -> String? {
    let searchPaths = [
      "/usr/local/bin/\(name)",
      "/usr/bin/\(name)",
      FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/bin/\(name)").path,
      ".build/debug/\(name)",
      ".build/release/\(name)"
    ]

    for path in searchPaths where FileManager.default.fileExists(atPath: path) {
      return path
    }

    return nil
  }

  private func formatBytes(_ bytes: UInt64) -> String {
    let kb = Double(bytes) / 1024.0
    let mb = kb / 1024.0
    let gb = mb / 1024.0

    if gb >= 1.0 {
      return String(format: "%.1fG", gb)
    } else if mb >= 1.0 {
      return String(format: "%.1fM", mb)
    } else if kb >= 1.0 {
      return String(format: "%.1fK", kb)
    } else {
      return "\(bytes)B"
    }
  }
}
