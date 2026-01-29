import Foundation
import HopsCore
import Containerization
import Logging
import NIOCore
import NIOPosix

actor SandboxManager {
    private var vmm: VZVirtualMachineManager?
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var containers: [String: LinuxContainer] = [:]
    private var containerInfo: [String: ContainerMetadata] = [:]
    private let logger: Logger
    
    init() async throws {
        var logger = Logger(label: "ai.hops.SandboxManager")
        logger.logLevel = .info
        self.logger = logger
        
        try await initializeVMM()
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
        
        logger.info("VirtualMachineManager initialized", metadata: [
            "kernel": "\(vmlinuxPath.path)",
            "initfs": "\(initfsPath.path)"
        ])
    }
    
    func runSandbox(
        id: String,
        policy: Policy,
        command: [String],
        rootfs: URL
    ) async throws -> SandboxStatus {
        guard let vmm = vmm else {
            throw SandboxManagerError.vmmNotInitialized
        }
        
        if containers[id] != nil {
            throw SandboxManagerError.containerAlreadyExists(id)
        }
        
        logger.info("Creating container", metadata: [
            "id": "\(id)",
            "policy": "\(policy.name)",
            "rootfs": "\(rootfs.path)"
        ])
        
        let rootfsMount = Mount.block(
            format: "ext4",
            source: rootfs.path,
            destination: "/"
        )
        
        let container = try LinuxContainer(id, rootfs: rootfsMount, vmm: vmm) { config in
            CapabilityEnforcer.configure(
                config: &config,
                policy: policy,
                command: command
            )
        }
        
        containers[id] = container
        containerInfo[id] = ContainerMetadata(
            policyName: policy.name,
            command: command,
            pid: generateContainerPid(id),
            startedAt: Date()
        )
        
        try await container.create()
        logger.info("Container created", metadata: ["id": "\(id)"])
        
        try await container.start()
        logger.info("Container started", metadata: ["id": "\(id)"])
        
        Task {
            let status = try await container.wait()
            await handleContainerExit(id: id, exitCode: Int(status.exitCode))
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
        rootfs: URL
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
                    
                    logger.info("Creating container with streaming", metadata: [
                        "id": "\(id)",
                        "policy": "\(policy.name)",
                        "rootfs": "\(rootfs.path)"
                    ])
                    
                    let rootfsMount = Mount.block(
                        format: "ext4",
                        source: rootfs.path,
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
                    
                    let container = try LinuxContainer(id, rootfs: rootfsMount, vmm: vmm) { config in
                        CapabilityEnforcer.configure(
                            config: &config,
                            policy: policy,
                            command: command,
                            stdout: stdoutWriter,
                            stderr: stderrWriter
                        )
                    }
                    
                    containers[id] = container
                    containerInfo[id] = ContainerMetadata(
                        policyName: policy.name,
                        command: command,
                        pid: generateContainerPid(id),
                        startedAt: Date()
                    )
                    
                    try await container.create()
                    logger.info("Container created", metadata: ["id": "\(id)"])
                    
                    try await container.start()
                    logger.info("Container started", metadata: ["id": "\(id)"])
                    
                    let status = try await container.wait()
                    let exitCode = Int(status.exitCode)
                    
                    await handleContainerExit(id: id, exitCode: exitCode)
                    
                    continuation.yield(StreamingOutputChunk(
                        sandboxId: id,
                        type: .exit,
                        data: Data(),
                        timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                        exitCode: Int32(exitCode)
                    ))
                    
                    continuation.finish()
                } catch {
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
        logger.info("Container exited", metadata: [
            "id": "\(id)",
            "exitCode": "\(exitCode)"
        ])
        
        containers.removeValue(forKey: id)
        
        if var info = containerInfo[id] {
            info.finishedAt = Date()
            info.exitCode = exitCode
            containerInfo[id] = info
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
        
        logger.debug("Streamed output chunk", metadata: [
            "sandboxId": "\(sandboxId)",
            "type": "\(type)",
            "bytes": "\(data.count)"
        ])
    }
    
    func close() throws {
        logger.debug("Closing writer", metadata: [
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
    
    init(sandboxId: String, type: StreamingOutputType, data: Data, timestamp: Int64, exitCode: Int32? = nil) {
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
}

extension SandboxManagerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .vmmNotInitialized:
            return "Virtual Machine Manager not initialized. The daemon may not have started correctly."
        case .containerAlreadyExists(let id):
            return "Container '\(id)' already exists. Choose a different container ID or stop the existing container."
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
        }
    }
}

extension UInt64 {
    func mib() -> UInt64 {
        return self * 1024 * 1024
    }
}
