import Containerization
import Foundation
import HopsCore
import Logging
import NIOCore
import NIOPosix

actor SandboxManager {

  // Container Cleanup Mechanism:
  // When a container exits, handleContainerExit() is called with the exit code.
  // If the container was created with keep=false (default), cleanupContainer() removes
  // the container directory at ~/.hops/containers/{id}/ including the rootfs.ext4 copy.
  // If keep=true, the directory persists for inspection/debugging.
  // The --keep flag in RunCommand.swift line 52 controls this behavior.
  // Verified: cleanupContainer() is called at line 352 when !info.keep is true.
  // Container directories are created at line 80 and copied at line 88.
  // Cleanup removes the entire directory tree at line 369.

  private var vmm: VZVirtualMachineManager?
  private var eventLoopGroup: MultiThreadedEventLoopGroup?
  private var containers: [String: LinuxContainer] = [:]
  private var containerInfo: [String: ContainerMetadata] = [:]
  private var stdinWriters: [String: GRPCStdinReader] = [:]
  private let logger: Logger
  private weak var daemon: HopsDaemon?

  init(daemon: HopsDaemon? = nil) async throws {
    var logger = Logger(label: "ai.hops.SandboxManager")
    logger.logLevel = .info
    self.logger = logger
    self.daemon = daemon

    try await initializeVMM()
    cleanupStaleContainers()
  }

  private func initializeVMM() async throws {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser
    let hopsDir = homeDir.appendingPathComponent(".hops")

    let vmlinuxPath = hopsDir.appendingPathComponent("vmlinux")
    let initfsPath = hopsDir.appendingPathComponent("initfs")

    guard FileManager.default.fileExists(atPath: vmlinuxPath.path) else {
      throw SandboxManagerError.missingKernel(vmlinuxPath.path)
    }

    guard FileManager.default.fileExists(atPath: initfsPath.path) else {
      throw SandboxManagerError.missingInitfs(initfsPath.path)
    }

    let kernel = Kernel(path: vmlinuxPath, platform: .linuxArm)
    let initfsMount = Mount.block(
      format: "ext4",
      source: initfsPath.path,
      destination: "/",
      options: ["ro"]
    )

    let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    self.eventLoopGroup = group

    self.vmm = VZVirtualMachineManager(
      kernel: kernel,
      initialFilesystem: initfsMount,
      group: group
    )

    logger.info(
      "VirtualMachineManager initialized",
      metadata: [
        "kernel": "\(vmlinuxPath.path)",
        "initfs": "\(initfsPath.path)"
      ])
  }

  func runSandbox(
    id: String,
    policy: Policy,
    command: [String],
    rootfs: URL,
    keep: Bool,
    allocateTty: Bool = false
  ) async throws -> SandboxStatus {
    guard let vmm = vmm else {
      throw SandboxManagerError.vmmNotInitialized
    }

    if containers[id] != nil {
      throw SandboxManagerError.containerAlreadyExists(id)
    }

    let homeDir = FileManager.default.homeDirectoryForCurrentUser
    let hopsDir = homeDir.appendingPathComponent(".hops")
    let containersDir = hopsDir.appendingPathComponent("containers")
    let containerDir = containersDir.appendingPathComponent(id)

    try? FileManager.default.createDirectory(at: containersDir, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: containerDir, withIntermediateDirectories: true)

    let containerRootfsPath = containerDir.appendingPathComponent("rootfs.ext4")
    
    try FileManager.default.copyItem(at: rootfs, to: containerRootfsPath)

    logger.info(
      "Creating container with writable rootfs",
      metadata: [
        "id": "\(id)",
        "policy": "\(policy.name)",
        "baseRootfs": "\(rootfs.path)",
        "containerRootfs": "\(containerRootfsPath.path)"
      ])

    let rootfsMount = Mount.block(
      format: "ext4",
      source: containerRootfsPath.path,
      destination: "/"
    )

    let stdinReader = allocateTty ? EmptyStdinReader() : nil

    let container = try LinuxContainer(id, rootfs: rootfsMount, vmm: vmm) { config in
      try CapabilityEnforcer.configure(
        config: &config,
        policy: policy,
        command: command,
        stdin: stdinReader,
        allocateTty: allocateTty
      )
    }

    containers[id] = container
    containerInfo[id] = ContainerMetadata(
      policyName: policy.name,
      command: command,
      pid: generateContainerPid(id),
      startedAt: Date(),
      keep: keep
    )

    await daemon?.incrementActiveSandboxCount()

    try await container.create()
    logger.info("Container created", metadata: ["id": "\(id)"])

    try await container.start()
    logger.info("Container started", metadata: ["id": "\(id)"])

    Task {
      do {
        let status = try await container.wait()
        await handleContainerExit(id: id, exitCode: Int(status.exitCode))
      } catch {
        logger.error(
          "Container wait failed",
          metadata: [
            "id": "\(id)",
            "error": "\(error.localizedDescription)"
          ]
        )
        await handleContainerExit(id: id, exitCode: -1)
      }
    }

    return SandboxStatus(
      id: id,
      pid: containerInfo[id]?.pid ?? 0,
      state: "running",
      exitCode: nil,
      startedAt: containerInfo[id]?.startedAt,
      finishedAt: nil
    )
  }

  func runSandboxStreaming(
    id: String,
    policy: Policy,
    command: [String],
    rootfs: URL,
    keep: Bool,
    allocateTty: Bool = false
  ) -> AsyncThrowingStream<StreamingOutputChunk, Error> {
    AsyncThrowingStream { continuation in
      Task {
        do {
          guard let vmm = vmm else {
            throw SandboxManagerError.vmmNotInitialized
          }

          if containers[id] != nil {
            throw SandboxManagerError.containerAlreadyExists(id)
          }

          let homeDir = FileManager.default.homeDirectoryForCurrentUser
          let hopsDir = homeDir.appendingPathComponent(".hops")
          let containersDir = hopsDir.appendingPathComponent("containers")
          let containerDir = containersDir.appendingPathComponent(id)

          try? FileManager.default.createDirectory(
            at: containersDir, withIntermediateDirectories: true)
          try? FileManager.default.createDirectory(
            at: containerDir, withIntermediateDirectories: true)

          let containerRootfsPath = containerDir.appendingPathComponent("rootfs.ext4")
          
          try FileManager.default.copyItem(at: rootfs, to: containerRootfsPath)

          logger.info(
            "Creating container with writable rootfs",
            metadata: [
              "id": "\(id)",
              "policy": "\(policy.name)",
              "baseRootfs": "\(rootfs.path)",
              "containerRootfs": "\(containerRootfsPath.path)"
            ])

          let rootfsMount = Mount.block(
            format: "ext4",
            source: containerRootfsPath.path,
            destination: "/"
          )

          let stdoutWriter = StreamingWriter(
            continuation: continuation,
            sandboxId: id,
            type: .stdout,
            logger: logger
          )
          let stderrWriter = StreamingWriter(
            continuation: continuation,
            sandboxId: id,
            type: .stderr,
            logger: logger
          )

          let grpcStdinReader = GRPCStdinReader()
          stdinWriters[id] = grpcStdinReader
          let stdinReader: (any ReaderStream)? = grpcStdinReader

          let container = try LinuxContainer(id, rootfs: rootfsMount, vmm: vmm) { config in
            try CapabilityEnforcer.configure(
              config: &config,
              policy: policy,
              command: command,
              stdout: stdoutWriter,
              stderr: stderrWriter,
              stdin: stdinReader,
              allocateTty: allocateTty
            )
          }

          containers[id] = container
          containerInfo[id] = ContainerMetadata(
            policyName: policy.name,
            command: command,
            pid: generateContainerPid(id),
            startedAt: Date(),
            keep: keep
          )

          await self.daemon?.incrementActiveSandboxCount()

          try await container.create()
          logger.info("Container created", metadata: ["id": "\(id)"])

          try await container.start()
          logger.info("Container started", metadata: ["id": "\(id)"])

          let status = try await container.wait()
          let exitCode = Int(status.exitCode)

          await handleContainerExit(id: id, exitCode: exitCode)

          continuation.yield(
            StreamingOutputChunk(
              sandboxId: id,
              type: .exit,
              data: Data(),
              timestamp: Int64(Date().timeIntervalSince1970 * 1000),
              exitCode: Int32(exitCode)
            ))

          continuation.finish()
        } catch {
          logger.error("ERROR in runSandboxStreaming: \(error)")
          print("ERROR in runSandboxStreaming: \(error)")
          fflush(stdout)
          continuation.finish(throwing: error)
        }
      }
    }
  }

  func stopSandbox(id: String) async throws {
    guard let container = containers[id] else {
      throw SandboxManagerError.containerNotFound(id)
    }

    logger.info("Stopping container", metadata: ["id": "\(id)"])

    try await container.stop()
    containers.removeValue(forKey: id)

    if var info = containerInfo[id] {
      info.finishedAt = Date()
      info.exitCode = nil
      containerInfo[id] = info
    }

    logger.info("Container stopped", metadata: ["id": "\(id)"])
  }

  func listSandboxes() -> [SandboxInfo] {
    return containerInfo.map { id, metadata in
      SandboxInfo(
        id: id,
        policyName: metadata.policyName,
        command: metadata.command,
        pid: metadata.pid,
        state: containers[id] != nil ? "running" : "stopped",
        startedAt: metadata.startedAt
      )
    }
  }

  func getStdinWriter(id: String) -> GRPCStdinReader? {
    return stdinWriters[id]
  }

  private func generateContainerPid(_ id: String) -> Int32 {
    var hasher = Hasher()
    hasher.combine(id)
    let hash = abs(hasher.finalize())
    return Int32(10000 + (hash % 50000))
  }

  func getStatus(id: String) async throws -> SandboxStatus {
    guard let metadata = containerInfo[id] else {
      throw SandboxManagerError.containerNotFound(id)
    }

    let isRunning = containers[id] != nil

    return SandboxStatus(
      id: id,
      pid: metadata.pid,
      state: isRunning ? "running" : "stopped",
      exitCode: metadata.exitCode,
      startedAt: metadata.startedAt,
      finishedAt: metadata.finishedAt
    )
  }

  func getStatistics(id: String) async throws -> ContainerStatistics? {
    guard let container = containers[id] else {
      return nil
    }

    let stats = try await container.statistics()

    let cpuNanos = (stats.cpu?.usageUsec ?? 0) * 1000
    let memoryBytes = stats.memory?.usageBytes ?? 0
    let networkRx = stats.networks?.first?.receivedBytes ?? 0
    let networkTx = stats.networks?.first?.transmittedBytes ?? 0

    return ContainerStatistics(
      cpuUsageNanos: cpuNanos,
      memoryUsageBytes: memoryBytes,
      networkRxBytes: networkRx,
      networkTxBytes: networkTx
    )
  }

  func cleanup() async {
    for (id, container) in containers {
      logger.info("Cleaning up container", metadata: ["id": "\(id)"])
      try? await container.stop()
    }
    containers.removeAll()
    vmm = nil

    try? await eventLoopGroup?.shutdownGracefully()
    eventLoopGroup = nil
  }

  private func handleContainerExit(id: String, exitCode: Int) async {
    logger.info(
      "Container exited",
      metadata: [
        "id": "\(id)",
        "exitCode": "\(exitCode)"
      ])

    containers.removeValue(forKey: id)
    
    if let stdinWriter = stdinWriters.removeValue(forKey: id) {
      stdinWriter.finish()
    }
    
    await daemon?.decrementActiveSandboxCount()

    if var info = containerInfo[id] {
      info.finishedAt = Date()
      info.exitCode = exitCode
      containerInfo[id] = info

      if !info.keep {
        cleanupContainer(id: id)
      }
    }
  }

  private func cleanupContainer(id: String) {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser
    let containerDir =
      homeDir
      .appendingPathComponent(".hops")
      .appendingPathComponent("containers")
      .appendingPathComponent(id)

    guard FileManager.default.fileExists(atPath: containerDir.path) else {
      return
    }

    do {
      try FileManager.default.removeItem(at: containerDir)
      logger.info("Container directory cleaned up", metadata: ["id": "\(id)"])
    } catch {
      logger.error(
        "Failed to cleanup container directory",
        metadata: [
          "id": "\(id)",
          "error": "\(error)"
        ])
    }
  }

  private func cleanupStaleContainers() {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser
    let containersDir =
      homeDir
      .appendingPathComponent(".hops")
      .appendingPathComponent("containers")

    guard FileManager.default.fileExists(atPath: containersDir.path) else {
      return
    }

    do {
      let containerDirs = try FileManager.default.contentsOfDirectory(
        at: containersDir,
        includingPropertiesForKeys: nil
      )

      for containerDir in containerDirs where containerDir.hasDirectoryPath {
        let containerId = containerDir.lastPathComponent

        do {
          try FileManager.default.removeItem(at: containerDir)
          logger.info("Cleaned up stale container", metadata: ["id": "\(containerId)"])
        } catch {
          logger.warning(
            "Failed to cleanup stale container",
            metadata: [
              "id": "\(containerId)",
              "error": "\(error)"
            ])
        }
      }
    } catch {
      logger.warning("Failed to enumerate container directories", metadata: ["error": "\(error)"])
    }
  }
}

final class StreamingWriter: Writer, Sendable {
  private let continuation: AsyncThrowingStream<StreamingOutputChunk, Error>.Continuation
  private let sandboxId: String
  private let type: StreamingOutputType
  private let logger: Logger

  init(
    continuation: AsyncThrowingStream<StreamingOutputChunk, Error>.Continuation,
    sandboxId: String,
    type: StreamingOutputType,
    logger: Logger
  ) {
    self.continuation = continuation
    self.sandboxId = sandboxId
    self.type = type
    self.logger = logger
  }

  func write(_ data: Data) throws {
    guard !data.isEmpty else { return }

    let chunk = StreamingOutputChunk(
      sandboxId: sandboxId,
      type: type,
      data: data,
      timestamp: Int64(Date().timeIntervalSince1970 * 1000)
    )

    continuation.yield(chunk)

    logger.debug(
      "Streamed output chunk",
      metadata: [
        "sandboxId": "\(sandboxId)",
        "type": "\(type)",
        "bytes": "\(data.count)"
      ])
  }

  func close() throws {
    logger.debug(
      "Closing writer",
      metadata: [
        "sandboxId": "\(sandboxId)",
        "type": "\(type)"
      ])
  }
}

private struct ContainerMetadata {
  let policyName: String
  let command: [String]
  let pid: Int32
  let startedAt: Date
  let keep: Bool
  var finishedAt: Date?
  var exitCode: Int?
}

struct ContainerStatistics: Codable, Sendable {
  let cpuUsageNanos: UInt64
  let memoryUsageBytes: UInt64
  let networkRxBytes: UInt64
  let networkTxBytes: UInt64
}

struct StreamingOutputChunk: Sendable {
  let sandboxId: String
  let type: StreamingOutputType
  let data: Data
  let timestamp: Int64
  let exitCode: Int32?

  init(
    sandboxId: String, type: StreamingOutputType, data: Data, timestamp: Int64,
    exitCode: Int32? = nil
  ) {
    self.sandboxId = sandboxId
    self.type = type
    self.data = data
    self.timestamp = timestamp
    self.exitCode = exitCode
  }
}

enum StreamingOutputType: Sendable {
  case stdout
  case stderr
  case exit
}

enum SandboxManagerError: Error {
  case vmmNotInitialized
  case containerAlreadyExists(String)
  case containerNotFound(String)
  case missingKernel(String)
  case missingInitfs(String)
  case resourceLimitExceeded(String)
}

extension SandboxManagerError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .vmmNotInitialized:
      return "Virtual Machine Manager not initialized. The daemon may not have started correctly."
    case .containerAlreadyExists(let id):
      return
        "Container '\(id)' already exists. Choose a different container ID or stop the existing container."
    case .containerNotFound(let id):
      return "Container '\(id)' not found. It may have already been stopped or never started."
    case .missingKernel(let path):
      return """
        vmlinux not found at \(path)

        The Containerization framework requires a Linux kernel image to run containers.

        To install the kernel:
        1. Download from Apple Container releases: https://github.com/apple/container/releases
        2. Place the vmlinux file at: \(path)
        3. Set permissions: chmod 644 \(path)

        See docs/setup.md for detailed installation instructions.
        """
    case .missingInitfs(let path):
      return """
        initfs not found at \(path)

        The Containerization framework requires an initial filesystem to boot containers.

        To install the initfs:
        1. Download init.block from Apple Container releases: https://github.com/apple/container/releases
        2. Rename and place at: \(path)
        3. Set permissions: chmod 644 \(path)

        See docs/setup.md for detailed installation instructions.
        """
    case .resourceLimitExceeded(let reason):
      return """
        Resource limit exceeded: \(reason)

        The container violated configured resource constraints:
        - Out of Memory (OOM): Increase --memory limit
        - Process limit: Increase --max-processes limit
        - CPU quota exceeded: Reduce workload or increase --cpus

        Adjust resource limits in policy TOML or via CLI flags.
        """
    }
  }
}

extension UInt64 {
  func mib() -> UInt64 {
    return self * 1024 * 1024
  }
}

final class EmptyStdinReader: ReaderStream, Sendable {
  func stream() -> AsyncStream<Data> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

final class GRPCStdinReader: ReaderStream, @unchecked Sendable {
  private let continuation: AsyncStream<Data>.Continuation
  private let dataStream: AsyncStream<Data>
  private let lock = NSLock()
  private var isFinished = false
  
  init() {
    let (stream, continuation) = AsyncStream<Data>.makeStream()
    self.dataStream = stream
    self.continuation = continuation
  }
  
  nonisolated func stream() -> AsyncStream<Data> {
    return dataStream
  }
  
  nonisolated func write(_ data: Data) {
    lock.lock()
    let finished = isFinished
    lock.unlock()
    
    guard !finished else { return }
    continuation.yield(data)
  }
  
  nonisolated func finish() {
    lock.lock()
    let wasFinished = isFinished
    isFinished = true
    lock.unlock()
    
    guard !wasFinished else { return }
    continuation.finish()
  }
}
