import ArgumentParser
import Foundation

struct InitCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "init",
    abstract: "Initialize Hops environment and download runtime files",
    discussion: """
      Check if Hops is properly set up and download missing runtime files.

      This command verifies that all required files are present:
      - vmlinux (Linux kernel)
      - initfs (init filesystem)
      - alpine-rootfs.ext4 (Alpine Linux root filesystem)

      It will download missing files and create the necessary directory structure.

      Examples:
        hops init
        hops init --check-only
        hops init --force
      """
  )

  @Flag(name: .long, help: "Only check setup without downloading anything")
  var checkOnly: Bool = false

  @Flag(name: .long, help: "Force re-download of all runtime files")
  var force: Bool = false

  @Flag(name: .long, help: "Show verbose output")
  var verbose: Bool = false

  func run() async throws {
    print("Hops Environment Check")
    print("======================")
    print()

    let homeDir = FileManager.default.homeDirectoryForCurrentUser
    let hopsDir = homeDir.appendingPathComponent(".hops")

    var hasIssues = false

    hasIssues = !checkMacOSVersion() || hasIssues
    hasIssues = !checkArchitecture() || hasIssues

    print()
    print("Directory Structure:")
    hasIssues = !checkDirectoryStructure(hopsDir) || hasIssues

    print()
    print("Runtime Files:")
    let vmlinuxPresent = checkFile(
      path: hopsDir.appendingPathComponent("vmlinux"),
      name: "vmlinux",
      description: "Linux kernel"
    )
    let initfsPresent = checkFile(
      path: hopsDir.appendingPathComponent("initfs"),
      name: "initfs",
      description: "Init filesystem"
    )
    let rootfsPresent = checkFile(
      path: hopsDir.appendingPathComponent("alpine-rootfs.ext4"),
      name: "alpine-rootfs.ext4",
      description: "Alpine Linux rootfs"
    )

    hasIssues = !vmlinuxPresent || !initfsPresent || !rootfsPresent || hasIssues

    print()
    print("Binaries:")
    checkBinary("hops")
    checkBinary("hopsd")
    checkBinary("hops-create-rootfs")

    print()

    if checkOnly {
      if hasIssues {
        print("Setup incomplete. Run 'hops init' to fix.")
        throw ExitCode.failure
      } else {
        print("✓ All checks passed!")
        return
      }
    }

    if !hasIssues && !force {
      print("✓ Environment already set up!")
      print()
      print("Use 'hops init --force' to re-download runtime files.")
      return
    }

    print("Setting up environment...")
    print()

    try setupDirectoryStructure(hopsDir)

    if !vmlinuxPresent || force {
      try await downloadVmlinux(to: hopsDir)
    }

    if !initfsPresent || force {
      try await downloadInitfs(to: hopsDir)
    }

    if !rootfsPresent || force {
      try await createAlpineRootfs(hopsDir: hopsDir)
    }

    print()
    print("========================")
    print("Setup Complete!")
    print("========================")
    print()
    print("Next steps:")
    print("  1. Start the daemon:    hops system start")
    print("  2. Run a command:       hops run /tmp -- /bin/echo 'Hello Hops!'")
    print("  3. Check status:        hops system status")
    print()
  }

  private func checkMacOSVersion() -> Bool {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    let majorVersion = version.majorVersion

    if majorVersion >= 15 {
      print("✓ macOS version: \(majorVersion).\(version.minorVersion).\(version.patchVersion)")
      return true
    } else {
      print("✗ macOS version: \(majorVersion).\(version.minorVersion).\(version.patchVersion)")
      print("  Error: Requires macOS 15 (Sequoia) or later")
      return false
    }
  }

  private func checkArchitecture() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/uname")
    process.arguments = ["-m"]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    try? process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    if output == "arm64" {
      print("✓ Architecture: \(output)")
      return true
    } else {
      print("✗ Architecture: \(output)")
      print("  Error: Requires Apple Silicon (arm64)")
      return false
    }
  }

  private func checkDirectoryStructure(_ hopsDir: URL) -> Bool {
    let requiredDirs = ["profiles", "logs", "containers", "rootfs"]
    var allPresent = true

    for dir in requiredDirs {
      let dirPath = hopsDir.appendingPathComponent(dir)
      let exists = FileManager.default.fileExists(atPath: dirPath.path)

      if exists {
        print("  ✓ \(dir)/")
      } else {
        print("  ✗ \(dir)/ (missing)")
        allPresent = false
      }
    }

    return allPresent
  }

  private func checkFile(path: URL, name: String, description: String) -> Bool {
    let exists = FileManager.default.fileExists(atPath: path.path)

    if exists {
      if let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
        let size = attrs[.size] as? UInt64 {
        print("  ✓ \(name) (\(formatBytes(size)))")
      } else {
        print("  ✓ \(name)")
      }
      return true
    } else {
      print("  ✗ \(name) (missing) - \(description)")
      return false
    }
  }

  private func checkBinary(_ name: String) {
    let searchPaths = [
      "/usr/local/bin/\(name)",
      "/usr/bin/\(name)",
      FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/bin/\(name)").path
    ]

    for path in searchPaths {
      if FileManager.default.fileExists(atPath: path) {
        print("  ✓ \(name) (\(path))")
        return
      }
    }

    print("  ✗ \(name) (not found in PATH)")
  }

  private func setupDirectoryStructure(_ hopsDir: URL) throws {
    let requiredDirs = ["profiles", "logs", "containers", "rootfs"]

    try FileManager.default.createDirectory(
      at: hopsDir,
      withIntermediateDirectories: true
    )

    for dir in requiredDirs {
      let dirPath = hopsDir.appendingPathComponent(dir)
      try FileManager.default.createDirectory(
        at: dirPath,
        withIntermediateDirectories: true
      )
    }

    print("✓ Directory structure created")
  }

  private func downloadVmlinux(to hopsDir: URL) async throws {
    let vmlinuxPath = hopsDir.appendingPathComponent("vmlinux")
    let url = "https://github.com/apple/container/releases/latest/download/vmlinux"

    print("Downloading vmlinux...")
    if verbose {
      print("  URL: \(url)")
    }

    try await downloadFile(from: url, to: vmlinuxPath)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o644],
      ofItemAtPath: vmlinuxPath.path
    )

    if let attrs = try? FileManager.default.attributesOfItem(atPath: vmlinuxPath.path),
      let size = attrs[.size] as? UInt64 {
      print("✓ vmlinux downloaded (\(formatBytes(size)))")
    } else {
      print("✓ vmlinux downloaded")
    }
  }

  private func downloadInitfs(to hopsDir: URL) async throws {
    let initfsPath = hopsDir.appendingPathComponent("initfs")
    let url = "https://github.com/apple/container/releases/latest/download/init.block"

    print("Downloading initfs...")
    if verbose {
      print("  URL: \(url)")
    }

    try await downloadFile(from: url, to: initfsPath)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o644],
      ofItemAtPath: initfsPath.path
    )

    if let attrs = try? FileManager.default.attributesOfItem(atPath: initfsPath.path),
      let size = attrs[.size] as? UInt64 {
      print("✓ initfs downloaded (\(formatBytes(size)))")
    } else {
      print("✓ initfs downloaded")
    }
  }

  private func createAlpineRootfs(hopsDir: URL) async throws {
    let tarballPath = hopsDir.appendingPathComponent("alpine-minirootfs.tar.gz")
    let url = "https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/aarch64/alpine-minirootfs-3.19.1-aarch64.tar.gz"

    print("Downloading Alpine minirootfs...")
    if verbose {
      print("  URL: \(url)")
    }

    try await downloadFile(from: url, to: tarballPath)

    print("Creating rootfs image...")
    
    let process = Process()
    process.executableURL = URL(fileURLWithPath: findBinary("hops-create-rootfs"))

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()
    process.waitUntilExit()

    if process.terminationStatus == 0 {
      try? FileManager.default.removeItem(at: tarballPath)
      
      if let attrs = try? FileManager.default.attributesOfItem(
        atPath: hopsDir.appendingPathComponent("alpine-rootfs.ext4").path
      ),
        let size = attrs[.size] as? UInt64 {
        print("✓ Alpine rootfs created (\(formatBytes(size)))")
      } else {
        print("✓ Alpine rootfs created")
      }
    } else {
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""
      throw ValidationError("Failed to create rootfs: \(output)")
    }
  }

  private func downloadFile(from urlString: String, to destination: URL) async throws {
    guard let url = URL(string: urlString) else {
      throw ValidationError("Invalid URL: \(urlString)")
    }

    let (tempURL, response) = try await URLSession.shared.download(from: url)

    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode)
    else {
      throw ValidationError("Download failed with response: \(response)")
    }

    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }

    try FileManager.default.moveItem(at: tempURL, to: destination)
  }

  private func findBinary(_ name: String) -> String {
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

    return name
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
