import ArgumentParser
import Darwin
import Foundation
import GRPC
import HopsCore
import HopsProto
import NIO
import SwiftProtobuf

struct RunCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "run",
    abstract: "Run a command in a sandboxed environment",
    discussion: """
      Execute a command with filesystem, network, and resource isolation.

      The sandbox root directory defaults to the current directory (.).
      If not suitable for sandboxing, /tmp is used. You can override with --path.

      The daemon is automatically started if not running. Use --no-auto-start
      to disable this behavior and require manual daemon management.

      The -- separator is optional when the command is unambiguous. Use it when
      your command has flags that might conflict with hops options.

      Examples:
        hops run echo "Hello"
        hops run python script.py
        hops run --profile untrusted npm test
        hops run --network disabled --memory 512M cargo build
        hops run --path /tmp -- /bin/sh -c "ls -la"
        echo "ls -la" | hops run --no-interactive /bin/sh
      """
  )

  @Option(name: .long, help: "Root directory for the sandbox (defaults to current directory or /tmp)")
  var path: String?

  @Option(name: .long, help: "Named profile to use (default, untrusted, build, etc.)")
  var profile: String?

  @Option(name: .long, help: "Network capability: disabled, outbound, loopback, full")
  var network: String?

  @Option(name: .long, help: "CPU limit (number of cores, e.g., 2 or 0.5)")
  var cpus: Double?

  @Option(name: .long, help: "Memory limit (e.g., 512M, 2G)")
  var memory: String?

  @Option(name: .long, help: "Maximum number of processes")
  var maxProcesses: UInt?

  @Option(name: .long, help: "Path to custom policy TOML file")
  var policyFile: String?

  @Option(name: .long, help: "OCI image to use (e.g., alpine:3.19, ubuntu:22.04)")
  var image: String?

  @Flag(name: .long, help: "Enable verbose output")
  var verbose: Bool = false

  @Flag(name: .long, inversion: .prefixedNo, help: "Enable streaming output")
  var stream: Bool = true

  @Flag(name: .long, help: "Keep container directory after execution")
  var keep: Bool = false

  @Flag(name: .long, inversion: .prefixedNo, help: "Allocate TTY for interactive sessions (automatic when using a terminal)")
  var interactive: Bool = true

  @Flag(name: .long, help: "Disable automatic daemon startup")
  var noAutoStart: Bool = false

  @Argument(parsing: .remaining, help: "Command to execute inside the sandbox")
  var command: [String] = []

  func validate() throws {
    guard !command.isEmpty else {
      throw ValidationError(ErrorMessages.missingCommand())
    }
  }

  mutating func run() async throws {
    let sandboxPath = expandPath(determineDefaultPath())
    let allocateTty = interactive && isStdinTTY()

    if verbose {
      print("Hops: Preparing sandbox environment...")
      print("  Root: \(sandboxPath)")
      if let profile = profile {
        print("  Profile: \(profile)")
      }
      print("  Command: \(command.joined(separator: " "))")
      print("  TTY: \(allocateTty ? "enabled" : "disabled")")
      print("  Interactive: \(interactive ? "enabled" : "disabled")")
    }

    let policy = try await loadPolicy()

    if verbose {
      print("  Network: \(policy.capabilities.network)")
      if let resourceLimits = policy.resources {
        if let cpus = resourceLimits.cpus {
          print("  CPUs: \(cpus)")
        }
        if let memory = resourceLimits.memoryBytes {
          print("  Memory: \(formatBytes(memory))")
        }
        if let maxProcs = resourceLimits.maxProcesses {
          print("  Max Processes: \(maxProcs)")
        }
      }
    }

    let exitCode = try await executeViaDaemon(
      sandboxPath: sandboxPath,
      command: command,
      policy: policy,
      allocateTty: allocateTty
    )

    if exitCode != 0 {
      throw ExitCode(exitCode)
    }
  }

  private func loadPolicy() async throws -> Policy {
    var policy: Policy

    if let policyFile = policyFile {
      policy = try Policy.load(fromTOMLFile: policyFile)
    } else if let profileName = profile {
      let directories = profileDirectories()
      var foundPath: URL?

      for dir in directories {
        let candidate = dir.appendingPathComponent("\(profileName).toml")
        if FileManager.default.fileExists(atPath: candidate.path) {
          foundPath = candidate
          break
        }
      }

      guard let profilePath = foundPath else {
        let searchedPaths = directories.map { $0.path }
        throw ValidationError(ErrorMessages.profileNotFound(name: profileName, searchedPaths: searchedPaths))
      }

      policy = try Policy.load(fromTOMLFile: profilePath.path)
    } else {
      policy = Policy.default
    }

    if let imageString = image {
      policy.ociImage = imageString
    }

    if let networkOverride = network {
      guard let capability = NetworkCapability(rawValue: networkOverride) else {
        throw ValidationError(
          "Invalid network capability: \(networkOverride). Use: disabled, outbound, loopback, full")
      }
      policy.capabilities.network = capability
    }

    if let cpusOverride = cpus {
      if policy.resources == nil {
        policy.resources = ResourceLimits()
      }
      policy.resources?.cpus = UInt(cpusOverride.rounded())
    }

    if let memoryOverride = memory {
      if policy.resources == nil {
        policy.resources = ResourceLimits()
      }
      policy.resources?.memoryBytes = try parseMemoryString(memoryOverride)
    }

    if let maxProcsOverride = maxProcesses {
      if policy.resources == nil {
        policy.resources = ResourceLimits()
      }
      policy.resources?.maxProcesses = maxProcsOverride
    }

    return policy
  }

  private func executeViaDaemon(
    sandboxPath: String,
    command: [String],
    policy: Policy,
    allocateTty: Bool
  ) async throws -> Int32 {
    if !noAutoStart {
      try await ensureDaemonRunning()
    }
    
    let client = try await DaemonClient.connect()

    var originalTermios: termios?
    if allocateTty && isStdinTTY() {
      originalTermios = try setRawTerminalMode()
    }

    defer {
      if let originalTermios = originalTermios {
        restoreTerminalMode(originalTermios)
      }
    }

    if stream {
      return try await client.executeStreaming(
        sandboxPath: sandboxPath,
        command: command,
        policy: policy,
        keep: keep,
        allocateTty: allocateTty
      )
    } else {
      return try await client.execute(
        sandboxPath: sandboxPath,
        command: command,
        policy: policy,
        keep: keep,
        allocateTty: allocateTty
      )
    }
  }

  private func setRawTerminalMode() throws -> termios {
    var originalTermios: termios = termios()
    guard tcgetattr(STDIN_FILENO, &originalTermios) == 0 else {
      throw ValidationError("Failed to get terminal attributes")
    }

    var rawTermios = originalTermios
    cfmakeraw(&rawTermios)

    guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &rawTermios) == 0 else {
      throw ValidationError("Failed to set raw terminal mode")
    }

    return originalTermios
  }

  private func restoreTerminalMode(_ termios: termios) {
    var mutableTermios = termios
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &mutableTermios)
  }

  private func isStdinTTY() -> Bool {
    return isatty(STDIN_FILENO) != 0
  }

  private func determineDefaultPath() -> String {
    if let userPath = path {
      return userPath
    }
    
    let currentDir = FileManager.default.currentDirectoryPath
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    
    if currentDir.hasPrefix(homeDir) && currentDir != homeDir {
      return "."
    }
    
    if currentDir.hasPrefix("/Users/") || currentDir.hasPrefix("/home/") {
      return "."
    }
    
    return "/tmp"
  }
  
  private func expandPath(_ path: String) -> String {
    if path.hasPrefix("~") {
      return NSString(string: path).expandingTildeInPath
    }
    if path.hasPrefix("/") {
      return path
    }
    return FileManager.default.currentDirectoryPath + "/" + path
  }

  private func profileDirectories() -> [URL] {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    return [
      home.appendingPathComponent(".hops/profiles"),
      current.appendingPathComponent("config/profiles"),
      current.appendingPathComponent("config/examples")
    ]
  }

  private func parseMemoryString(_ memory: String) throws -> UInt64 {
    let upper = memory.uppercased()
    var multiplier: UInt64 = 1
    var numericPart = upper

    if upper.hasSuffix("K") || upper.hasSuffix("KB") {
      multiplier = 1024
      numericPart = String(upper.dropLast(upper.hasSuffix("KB") ? 2 : 1))
    } else if upper.hasSuffix("M") || upper.hasSuffix("MB") {
      multiplier = 1024 * 1024
      numericPart = String(upper.dropLast(upper.hasSuffix("MB") ? 2 : 1))
    } else if upper.hasSuffix("G") || upper.hasSuffix("GB") {
      multiplier = 1024 * 1024 * 1024
      numericPart = String(upper.dropLast(upper.hasSuffix("GB") ? 2 : 1))
    }

    guard let value = UInt64(numericPart) else {
      throw ValidationError("Invalid memory format: \(memory)")
    }

    return value * multiplier
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
  
  private func ensureDaemonRunning() async throws {
    let daemonManager = DaemonManager()
    
    if await daemonManager.isRunning() {
      return
    }
    
    try await daemonManager.ensureRunning(verbose: verbose)
  }
}

struct DaemonClient {
  private let client: Hops_HopsServiceAsyncClient
  private let group: MultiThreadedEventLoopGroup
  private let channel: GRPCChannel

  private init(
    client: Hops_HopsServiceAsyncClient, group: MultiThreadedEventLoopGroup, channel: GRPCChannel
  ) {
    self.client = client
    self.group = group
    self.channel = channel
  }

  static func connect() async throws -> DaemonClient {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser
    let socketPath =
      homeDir
      .appendingPathComponent(".hops")
      .appendingPathComponent("hops.sock")
      .path

    guard FileManager.default.fileExists(atPath: socketPath) else {
      throw DaemonClientError.connectionFailed(
        ErrorMessages.daemonNotRunning()
      )
    }

    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    do {
      let channel = try GRPCChannelPool.with(
        target: .unixDomainSocket(socketPath),
        transportSecurity: .plaintext,
        eventLoopGroup: group
      )

      let client = Hops_HopsServiceAsyncClient(
        channel: channel,
        defaultCallOptions: CallOptions()
      )

      return DaemonClient(client: client, group: group, channel: channel)
    } catch {
      throw DaemonClientError.connectionFailed(
        ErrorMessages.daemonConnectionFailed(socketPath: socketPath, error: error.localizedDescription)
      )
    }
  }

  func execute(
    sandboxPath: String,
    command: [String],
    policy: Policy,
    keep: Bool,
    allocateTty: Bool
  ) async throws -> Int32 {
    var runRequest = Hops_RunRequest()
    runRequest.command = command
    runRequest.workingDirectory = sandboxPath
    runRequest.inlinePolicy = buildProtoPolicy(policy)
    runRequest.keep = keep
    runRequest.allocateTty = allocateTty

    let response = try await client.runSandbox(runRequest)

    guard response.success else {
      throw DaemonClientError.executionFailed(response.error)
    }

    return 0
  }

  func executeStreaming(
    sandboxPath: String,
    command: [String],
    policy: Policy,
    keep: Bool,
    allocateTty: Bool
  ) async throws -> Int32 {
    var runRequest = Hops_RunRequest()
    runRequest.command = command
    runRequest.workingDirectory = sandboxPath
    runRequest.inlinePolicy = buildProtoPolicy(policy)
    runRequest.keep = keep
    runRequest.allocateTty = allocateTty

    let call = client.makeRunSandboxStreamingCall()
    var inputChunk = Hops_InputChunk()
    inputChunk.type = .run
    inputChunk.runRequest = runRequest
    try await call.requestStream.send(inputChunk)

    let shouldForwardStdin = allocateTty || isatty(STDIN_FILENO) == 0
    
    if shouldForwardStdin {
      Task {
        if allocateTty && isatty(STDIN_FILENO) != 0 {
          await forwardStdinInteractive(to: call.requestStream)
        } else {
          await forwardStdinBuffered(to: call.requestStream)
        }
      }
    } else {
      call.requestStream.finish()
    }

    let responseStream = call.responseStream
    var exitCode: Int32 = 1

    if allocateTty {
      let signalSource = setupWindowResizeHandler()

      defer {
        signalSource?.cancel()
      }

      for try await chunk in responseStream {
        switch chunk.type {
        case .stdout:
          if !chunk.data.isEmpty {
            FileHandle.standardOutput.write(chunk.data)
            try? FileHandle.standardOutput.synchronize()
          }
        case .stderr:
          if !chunk.data.isEmpty {
            FileHandle.standardError.write(chunk.data)
            try? FileHandle.standardError.synchronize()
          }
        case .exit:
          if chunk.hasExitCode {
            exitCode = chunk.exitCode
          }
        case .UNRECOGNIZED:
          break
        }
      }
    } else {
      for try await chunk in responseStream {
        switch chunk.type {
        case .stdout:
          if !chunk.data.isEmpty {
            FileHandle.standardOutput.write(chunk.data)
            try? FileHandle.standardOutput.synchronize()
          }
        case .stderr:
          if !chunk.data.isEmpty {
            FileHandle.standardError.write(chunk.data)
            try? FileHandle.standardError.synchronize()
          }
        case .exit:
          if chunk.hasExitCode {
            exitCode = chunk.exitCode
          }
        case .UNRECOGNIZED:
          break
        }
      }
    }

    return exitCode
  }

  private func forwardStdinInteractive(to requestStream: GRPCAsyncRequestStreamWriter<Hops_InputChunk>) async {
    let stdinFD = STDIN_FILENO
    
    let flags = fcntl(stdinFD, F_GETFL)
    _ = fcntl(stdinFD, F_SETFL, flags | O_NONBLOCK)
    
    defer {
      _ = fcntl(stdinFD, F_SETFL, flags)
    }
    
    var buffer = [UInt8](repeating: 0, count: 64)
    
    while true {
      let bytesRead = read(stdinFD, &buffer, buffer.count)
      
      if bytesRead < 0 {
        let error = errno
        if error == EINTR {
          continue
        }
        if error == EAGAIN || error == EWOULDBLOCK {
          try? await Task.sleep(nanoseconds: 10_000_000)
          continue
        }
        break
      }
      
      if bytesRead == 0 {
        break
      }
      
      var chunk = Hops_InputChunk()
      chunk.type = .stdin
      chunk.data = Data(buffer[..<bytesRead])
      
      do {
        try await requestStream.send(chunk)
      } catch {
        break
      }
    }
    
    requestStream.finish()
  }
  
  private func forwardStdinBuffered(to requestStream: GRPCAsyncRequestStreamWriter<Hops_InputChunk>) async {
    do {
      let stdin = FileHandle.standardInput
      var buffer = Data()
      buffer.reserveCapacity(4096)
      
      for try await byte in stdin.bytes {
        buffer.append(byte)
        
        if buffer.count >= 4096 {
          var stdinChunk = Hops_InputChunk()
          stdinChunk.type = .stdin
          stdinChunk.data = buffer
          
          do {
            try await requestStream.send(stdinChunk)
            buffer.removeAll(keepingCapacity: true)
          } catch {
            break
          }
        }
      }
      
      if !buffer.isEmpty {
        var stdinChunk = Hops_InputChunk()
        stdinChunk.type = .stdin
        stdinChunk.data = buffer
        try? await requestStream.send(stdinChunk)
      }
      
      requestStream.finish()
    } catch {
      requestStream.finish()
    }
  }
  
  private func setupWindowResizeHandler() -> DispatchSourceSignal? {
    let signalSource = DispatchSource.makeSignalSource(
      signal: SIGWINCH,
      queue: DispatchQueue.global()
    )

    signalSource.setEventHandler {
    }

    signal(SIGWINCH, SIG_IGN)
    signalSource.resume()

    return signalSource
  }

  func close() async throws {
    try await group.shutdownGracefully()
  }

  private func buildProtoPolicy(_ policy: Policy) -> Hops_Policy {
    var protoPolicy = Hops_Policy()

    var capabilities = Hops_Capabilities()
    capabilities.network = convertNetworkCapability(policy.capabilities.network)

    var filesystem = Hops_FilesystemCapabilities()
    filesystem.read = Array(policy.capabilities.allowedPaths)
    filesystem.write = Array(policy.capabilities.allowedPaths)
    filesystem.execute = Array(policy.capabilities.allowedPaths)
    capabilities.filesystem = filesystem

    protoPolicy.capabilities = capabilities

    let resourceLimits = policy.capabilities.resourceLimits
    var protoResources = Hops_ResourceLimits()

    if let cpus = resourceLimits.cpus {
      protoResources.cpus = Int32(cpus)
    }

    if let memory = resourceLimits.memoryBytes {
      protoResources.memory = formatBytes(memory)
    }

    if let maxProcs = resourceLimits.maxProcesses {
      protoResources.maxProcesses = Int32(maxProcs)
    }

    protoPolicy.resources = protoResources

    return protoPolicy
  }

  private func convertNetworkCapability(_ capability: NetworkCapability) -> Hops_NetworkAccess {
    switch capability {
    case .disabled:
      return .disabled
    case .outbound:
      return .outbound
    case .loopback:
      return .loopback
    case .full:
      return .full
    }
  }

  private func formatBytes(_ bytes: UInt64) -> String {
    let kb = Double(bytes) / 1024.0
    let mb = kb / 1024.0
    let gb = mb / 1024.0

    if gb >= 1.0 {
      return String(format: "%.0fG", gb)
    } else if mb >= 1.0 {
      return String(format: "%.0fM", mb)
    } else if kb >= 1.0 {
      return String(format: "%.0fK", kb)
    } else {
      return "\(bytes)B"
    }
  }
}

enum DaemonClientError: Error, CustomStringConvertible {
  case executionFailed(String)
  case connectionFailed(String)

  var description: String {
    switch self {
    case .executionFailed(let message):
      return message
    case .connectionFailed(let message):
      return message
    }
  }
}
