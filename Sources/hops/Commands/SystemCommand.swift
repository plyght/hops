import ArgumentParser
import Foundation
import GRPC
import HopsProto
import NIO

struct SystemCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "system",
    abstract: "Control the Hops daemon",
    discussion: """
      Manage the hopsd background daemon that handles sandbox execution.

      The daemon runs as a user service and handles all sandbox operations,
      including filesystem isolation, capability enforcement, and resource limits.

      Examples:
        hops system start
        hops system stop
        hops system status
        hops system restart
      """,
    subcommands: [
      StartDaemon.self,
      StopDaemon.self,
      StatusDaemon.self,
      RestartDaemon.self,
      CleanupContainers.self
    ]
  )
}

extension SystemCommand {
  struct StartDaemon: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "start",
      abstract: "Start the Hops daemon"
    )

    @Flag(name: .long, help: "Run daemon in foreground with verbose logging")
    var foreground: Bool = false

    func run() async throws {
      if try await isDaemonRunning() {
        print("Hops daemon is already running.")
        print("Use 'hops system status' for details.")
        return
      }

      if foreground {
        print("Starting Hops daemon in foreground mode...")
        print("Press Ctrl+C to stop.")
        print()
        try await launchDaemonForeground()
      } else {
        print("Starting Hops daemon...")
        try await launchDaemonBackground()

        try await Task.sleep(nanoseconds: 500_000_000)

        if try await isDaemonRunning() {
          print("Hops daemon started successfully.")
          print()
          let status = try await getDaemonStatus()
          printStatus(status)
        } else {
          throw ValidationError("Failed to start daemon. Check logs at ~/.hops/logs/hopsd.log")
        }
      }
    }

    private func launchDaemonBackground() async throws {
      let hopsdPath = findHopsdBinary()

      let process = Process()
      process.executableURL = URL(fileURLWithPath: hopsdPath)
      process.arguments = ["--daemon"]

      let logDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".hops/logs")
      try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

      let logFile = logDir.appendingPathComponent("hopsd.log")
      FileManager.default.createFile(atPath: logFile.path, contents: nil)

      let logHandle = try FileHandle(forWritingTo: logFile)
      process.standardOutput = logHandle
      process.standardError = logHandle

      try process.run()
      process.waitUntilExit()
    }

    private func launchDaemonForeground() async throws {
      let hopsdPath = findHopsdBinary()

      let process = Process()
      process.executableURL = URL(fileURLWithPath: hopsdPath)
      process.arguments = ["--foreground", "--verbose"]

      try process.run()
      process.waitUntilExit()
    }

    private func findHopsdBinary() -> String {
      let searchPaths = [
        "/usr/local/bin/hopsd",
        "/usr/bin/hopsd",
        FileManager.default.homeDirectoryForCurrentUser
          .appendingPathComponent(".local/bin/hopsd").path,
        ".build/debug/hopsd",
        ".build/release/hopsd"
      ]

      for path in searchPaths where FileManager.default.fileExists(atPath: path) {
        return path
      }

      return "hopsd"
    }
  }

  struct StopDaemon: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "stop",
      abstract: "Stop the Hops daemon"
    )

    @Flag(name: .long, help: "Force kill the daemon if graceful shutdown fails")
    var force: Bool = false

    func run() async throws {
      guard try await isDaemonRunning() else {
        print("Hops daemon is not running.")
        return
      }

      print("Stopping Hops daemon...")

      try await sendDaemonShutdown()

      for _ in 0..<10 {
        try await Task.sleep(nanoseconds: 500_000_000)
        if try await !isDaemonRunning() {
          print("Hops daemon stopped successfully.")
          return
        }
      }

      if force {
        print("Graceful shutdown timed out. Force killing daemon...")
        try await forceKillDaemon()
        print("Hops daemon killed.")
      } else {
        print("Warning: Daemon did not stop gracefully.")
        print("Use --force to force kill the daemon.")
      }
    }

    private func sendDaemonShutdown() async throws {
      let pidFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".hops/hopsd.pid")

      guard FileManager.default.fileExists(atPath: pidFile.path),
        let pidString = try? String(contentsOf: pidFile, encoding: .utf8),
        let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines))
      else {
        throw ValidationError("Could not read daemon PID")
      }

      kill(pid, SIGTERM)
    }

    private func forceKillDaemon() async throws {
      let pidFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".hops/hopsd.pid")

      guard FileManager.default.fileExists(atPath: pidFile.path),
        let pidString = try? String(contentsOf: pidFile, encoding: .utf8),
        let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines))
      else {
        throw ValidationError("Could not read daemon PID")
      }

      kill(pid, SIGKILL)
    }
  }

  struct StatusDaemon: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "status",
      abstract: "Show daemon status and statistics"
    )

    @Flag(name: .long, help: "Show detailed information")
    var verbose: Bool = false

    func run() async throws {
      if try await isDaemonRunning() {
        print("Hops daemon: running")

        let status = try await getDaemonStatus()
        printStatus(status)

        if verbose {
          print()
          print("Detailed Information:")
          print("  PID: \(status.pid)")
          print("  Socket: \(status.socketPath)")
          print("  Log: \(status.logPath)")
          print("  Active sandboxes: \(status.activeSandboxes)")
          print("  Total executions: \(status.totalExecutions)")
        }
      } else {
        print("Hops daemon: not running")
        print()
        print("Start the daemon with: hops system start")
      }
    }

    private func printStatus(_ status: DaemonStatus) {
      let formatter = DateFormatter()
      formatter.dateStyle = .medium
      formatter.timeStyle = .medium

      print()
      print("  Uptime: \(formatUptime(status.uptime))")
      print("  Started: \(formatter.string(from: status.startTime))")
      print("  Active sandboxes: \(status.activeSandboxes)")
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
      let hours = Int(seconds) / 3600
      let minutes = (Int(seconds) % 3600) / 60
      let secs = Int(seconds) % 60

      if hours > 0 {
        return String(format: "%dh %dm %ds", hours, minutes, secs)
      } else if minutes > 0 {
        return String(format: "%dm %ds", minutes, secs)
      } else {
        return String(format: "%ds", secs)
      }
    }
  }

  struct RestartDaemon: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "restart",
      abstract: "Restart the Hops daemon"
    )

    func run() async throws {
      if try await isDaemonRunning() {
        print("Stopping Hops daemon...")
        let stopCmd = StopDaemon()
        try await stopCmd.run()

        try await Task.sleep(nanoseconds: 1_000_000_000)
      }

      print("Starting Hops daemon...")
      let startCmd = StartDaemon()
      try await startCmd.run()
    }
  }

  struct CleanupContainers: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "cleanup",
      abstract: "Remove stopped containers and orphaned rootfs"
    )

    @Flag(name: .long, help: "Show what would be deleted without actually deleting")
    var dryRun: Bool = false

    @Flag(name: .long, help: "Delete orphaned rootfs images")
    var force: Bool = false

    func run() async throws {
      let homeDir = FileManager.default.homeDirectoryForCurrentUser
      let hopsDir = homeDir.appendingPathComponent(".hops")
      let containersDir = hopsDir.appendingPathComponent("containers")
      let rootfsDir = hopsDir.appendingPathComponent("rootfs")

      var totalContainerSize: UInt64 = 0
      var totalRootfsSize: UInt64 = 0
      var stoppedContainers: [(url: URL, size: UInt64)] = []
      var orphanedRootfs: [(url: URL, size: UInt64)] = []

      let runningContainerIds = try await getRunningContainerIds()

      if FileManager.default.fileExists(atPath: containersDir.path) {
        let contents = try FileManager.default.contentsOfDirectory(
          at: containersDir,
          includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
          options: [.skipsHiddenFiles]
        )

        for containerDir in contents {
          let isDirectory =
            (try? containerDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
          guard isDirectory else { continue }

          let containerId = containerDir.lastPathComponent
          if runningContainerIds.contains(containerId) {
            continue
          }

          let size = calculateDirectorySize(containerDir)
          stoppedContainers.append((url: containerDir, size: size))
          totalContainerSize += size
        }
      }

      if FileManager.default.fileExists(atPath: rootfsDir.path) {
        let referencedRootfs = try loadReferencedRootfs()

        let contents = try FileManager.default.contentsOfDirectory(
          at: rootfsDir,
          includingPropertiesForKeys: [.fileSizeKey],
          options: [.skipsHiddenFiles]
        )

        let rootfsImages = contents.filter { $0.pathExtension == "ext4" }

        if rootfsImages.count > 1 {
          for rootfsImage in rootfsImages {
            let rootfsName = rootfsImage.deletingPathExtension().lastPathComponent
            if !referencedRootfs.contains(rootfsName)
              && !referencedRootfs.contains(rootfsImage.lastPathComponent) {
              if let attrs = try? rootfsImage.resourceValues(forKeys: [.fileSizeKey]),
                let fileSize = attrs.fileSize {
                orphanedRootfs.append((url: rootfsImage, size: UInt64(fileSize)))
                totalRootfsSize += UInt64(fileSize)
              }
            }
          }
        }
      }

      if stoppedContainers.isEmpty && orphanedRootfs.isEmpty {
        print("No cleanup needed.")
        return
      }

      print("Cleanup summary:")
      if !stoppedContainers.isEmpty {
        print(
          "  Stopped containers: \(stoppedContainers.count) (\(formatBytes(totalContainerSize)))")
        if dryRun {
          for container in stoppedContainers {
            print("    - \(container.url.lastPathComponent)")
          }
        }
      }

      if !orphanedRootfs.isEmpty {
        print("  Orphaned rootfs: \(orphanedRootfs.count) (\(formatBytes(totalRootfsSize)))")
        if dryRun || !force {
          for rootfs in orphanedRootfs {
            print("    - \(rootfs.url.lastPathComponent)")
          }
        }
        if !force {
          print("  Use --force to delete orphaned rootfs images")
        }
      }

      if dryRun {
        print()
        print("Dry run mode: no files deleted")
        print(
          "Total space that would be reclaimed: \(formatBytes(totalContainerSize + totalRootfsSize))"
        )
        return
      }

      var deletedContainers = 0
      var deletedRootfs = 0
      var reclaimedContainerSpace: UInt64 = 0
      var reclaimedRootfsSpace: UInt64 = 0

      for container in stoppedContainers {
        do {
          try FileManager.default.removeItem(at: container.url)
          deletedContainers += 1
          reclaimedContainerSpace += container.size
        } catch {
          print("Warning: Failed to delete \(container.url.lastPathComponent): \(error)")
        }
      }

      if force {
        for rootfs in orphanedRootfs {
          do {
            try FileManager.default.removeItem(at: rootfs.url)
            deletedRootfs += 1
            reclaimedRootfsSpace += rootfs.size
          } catch {
            print("Warning: Failed to delete \(rootfs.url.lastPathComponent): \(error)")
          }
        }
      }

      print()
      if deletedContainers > 0 || deletedRootfs > 0 {
        var parts: [String] = []
        if deletedContainers > 0 {
          parts.append(
            "\(deletedContainers) stopped container\(deletedContainers == 1 ? "" : "s") (\(formatBytes(reclaimedContainerSpace)))"
          )
        }
        if deletedRootfs > 0 {
          parts.append(
            "\(deletedRootfs) orphaned rootfs (\(formatBytes(reclaimedRootfsSpace)))")
        }
        print("Removed \(parts.joined(separator: ", "))")
        print(
          "Total space reclaimed: \(formatBytes(reclaimedContainerSpace + reclaimedRootfsSpace))")
      } else {
        print("No files deleted")
      }
    }

    private func getRunningContainerIds() async throws -> Set<String> {
      guard try await isDaemonRunning() else {
        return []
      }

      do {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let socketPath =
          homeDir
          .appendingPathComponent(".hops")
          .appendingPathComponent("hops.sock")
          .path

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
          Task {
            try? await group.shutdownGracefully()
          }
        }

        let channel = try GRPCChannelPool.with(
          target: .unixDomainSocket(socketPath),
          transportSecurity: .plaintext,
          eventLoopGroup: group
        )

        let client = Hops_HopsServiceAsyncClient(
          channel: channel,
          defaultCallOptions: CallOptions()
        )

        let request = Hops_ListRequest()
        let response = try await client.listSandboxes(request)

        let runningIds = response.sandboxes
          .filter { $0.state == .running }
          .map { $0.sandboxID }

        return Set(runningIds)
      } catch {
        return []
      }
    }

    private func loadReferencedRootfs() throws -> Set<String> {
      var referenced = Set<String>()
      let homeDir = FileManager.default.homeDirectoryForCurrentUser
      let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

      let profileDirs = [
        homeDir.appendingPathComponent(".hops/profiles"),
        currentDir.appendingPathComponent("config/profiles"),
        currentDir.appendingPathComponent("config/examples")
      ]

      for profileDir in profileDirs {
        guard FileManager.default.fileExists(atPath: profileDir.path) else { continue }

        let contents = try? FileManager.default.contentsOfDirectory(
          at: profileDir,
          includingPropertiesForKeys: nil,
          options: [.skipsHiddenFiles]
        )

        guard let profiles = contents?.filter({ $0.pathExtension == "toml" }) else { continue }

        for profilePath in profiles {
          if let policyData = try? String(contentsOf: profilePath, encoding: .utf8),
            let rootfsMatch = policyData.range(
              of: #"rootfs\s*=\s*"([^"]+)""#, options: .regularExpression) {
            let match = String(policyData[rootfsMatch])
            if let valueMatch = match.range(of: #""([^"]+)""#, options: .regularExpression) {
              let rootfsValue = String(match[valueMatch]).trimmingCharacters(
                in: CharacterSet(charactersIn: "\""))
              referenced.insert(rootfsValue)
            }
          }
        }
      }

      return referenced
    }

    private func calculateDirectorySize(_ url: URL) -> UInt64 {
      var totalSize: UInt64 = 0

      guard
        let enumerator = FileManager.default.enumerator(
          at: url,
          includingPropertiesForKeys: [.fileSizeKey],
          options: [.skipsHiddenFiles]
        )
      else {
        return 0
      }

      for case let fileURL as URL in enumerator {
        if let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
          let fileSize = attrs.fileSize {
          totalSize += UInt64(fileSize)
        }
      }

      return totalSize
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
}

private func isDaemonRunning() async throws -> Bool {
  let pidFile = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".hops/hopsd.pid")

  guard FileManager.default.fileExists(atPath: pidFile.path),
    let pidString = try? String(contentsOf: pidFile, encoding: .utf8),
    let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines))
  else {
    return false
  }

  return kill(pid, 0) == 0
}

private func getDaemonStatus() async throws -> DaemonStatus {
  let homeDir = FileManager.default.homeDirectoryForCurrentUser
  let socketPath =
    homeDir
    .appendingPathComponent(".hops")
    .appendingPathComponent("hops.sock")
    .path

  let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

  let channel = try GRPCChannelPool.with(
    target: .unixDomainSocket(socketPath),
    transportSecurity: .plaintext,
    eventLoopGroup: group
  )

  let client = Hops_HopsServiceAsyncClient(
    channel: channel,
    defaultCallOptions: CallOptions()
  )

  let request = Hops_DaemonStatusRequest()
  let response = try await client.getDaemonStatus(request)

  try await group.shutdownGracefully()

  let startTime = Date(timeIntervalSince1970: TimeInterval(response.startTime))
  let uptime = Date().timeIntervalSince(startTime)

  return DaemonStatus(
    pid: response.pid,
    uptime: uptime,
    startTime: startTime,
    activeSandboxes: Int(response.activeSandboxes),
    totalExecutions: 0,
    socketPath: "~/.hops/hops.sock",
    logPath: "~/.hops/logs/hopsd.log"
  )
}

private func printStatus(_ status: DaemonStatus) {
  let formatter = DateFormatter()
  formatter.dateStyle = .medium
  formatter.timeStyle = .medium

  print()
  print("  Uptime: \(formatUptime(status.uptime))")
  print("  Started: \(formatter.string(from: status.startTime))")
  print("  Active sandboxes: \(status.activeSandboxes)")
}

private func formatUptime(_ seconds: TimeInterval) -> String {
  let hours = Int(seconds) / 3600
  let minutes = (Int(seconds) % 3600) / 60
  let secs = Int(seconds) % 60

  if hours > 0 {
    return String(format: "%dh %dm %ds", hours, minutes, secs)
  } else if minutes > 0 {
    return String(format: "%dm %ds", minutes, secs)
  } else {
    return String(format: "%ds", secs)
  }
}

struct DaemonStatus {
  let pid: Int32
  let uptime: TimeInterval
  let startTime: Date
  let activeSandboxes: Int
  let totalExecutions: Int
  let socketPath: String
  let logPath: String
}
