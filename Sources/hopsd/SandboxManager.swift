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
            state: "running",
            exitCode: nil,
            startedAt: containerInfo[id]?.startedAt,
            finishedAt: nil
        )
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
                state: containers[id] != nil ? "running" : "stopped",
                startedAt: metadata.startedAt
            )
        }
    }
    
    func getStatus(id: String) async throws -> SandboxStatus {
        guard let metadata = containerInfo[id] else {
            throw SandboxManagerError.containerNotFound(id)
        }
        
        let isRunning = containers[id] != nil
        
        return SandboxStatus(
            id: id,
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

private struct ContainerMetadata {
    let policyName: String
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

enum SandboxManagerError: Error {
    case vmmNotInitialized
    case containerAlreadyExists(String)
    case containerNotFound(String)
    case missingKernel(String)
    case missingInitfs(String)
}

extension UInt64 {
    func mib() -> UInt64 {
        return self * 1024 * 1024
    }
}
