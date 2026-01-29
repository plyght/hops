import ArgumentParser
import Foundation
import HopsProto
import GRPC
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
            RestartDaemon.self
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
            
            for path in searchPaths {
                if FileManager.default.fileExists(atPath: path) {
                    return path
                }
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
                  let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw ValidationError("Could not read daemon PID")
            }
            
            kill(pid, SIGTERM)
        }
        
        private func forceKillDaemon() async throws {
            let pidFile = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".hops/hopsd.pid")
            
            guard FileManager.default.fileExists(atPath: pidFile.path),
                  let pidString = try? String(contentsOf: pidFile, encoding: .utf8),
                  let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
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
                var stopCmd = StopDaemon()
                try await stopCmd.run()
                
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
            
            print("Starting Hops daemon...")
            var startCmd = StartDaemon()
            try await startCmd.run()
        }
    }
}

private func isDaemonRunning() async throws -> Bool {
    let pidFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".hops/hopsd.pid")
    
    guard FileManager.default.fileExists(atPath: pidFile.path),
          let pidString = try? String(contentsOf: pidFile, encoding: .utf8),
          let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        return false
    }
    
    return kill(pid, 0) == 0
}

private func getDaemonStatus() async throws -> DaemonStatus {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser
    let socketPath = homeDir
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
