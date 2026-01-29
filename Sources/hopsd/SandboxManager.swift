import Foundation
import HopsCore
#if canImport(Containerization)
import Containerization
#endif

actor SandboxManager {
    #if canImport(Containerization)
    private var vmm: VirtualMachineManager?
    private var containers: [String: LinuxContainer] = [:]
    private var containerInfo: [String: ContainerMetadata] = [:]
    #endif
    
    init() async throws {
        #if canImport(Containerization)
        try await initializeVMM()
        #endif
    }
    
    #if canImport(Containerization)
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
        vmm = VirtualMachineManager(kernel: kernel, initfs: initfsPath)
        
        print("VirtualMachineManager initialized")
    }
    #endif
    
    func runSandbox(
        id: String,
        policy: Policy,
        command: [String],
        rootfs: URL
    ) async throws -> SandboxStatus {
        #if canImport(Containerization)
        guard let vmm = vmm else {
            throw SandboxManagerError.vmmNotInitialized
        }
        
        if containers[id] != nil {
            throw SandboxManagerError.containerAlreadyExists(id)
        }
        
        let container = try LinuxContainer(id, rootfs: rootfs, vmm: vmm) { config in
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
        try await container.start()
        
        Task {
            let status = try await container.wait()
            await handleContainerExit(id: id, exitCode: status)
        }
        
        return SandboxStatus(
            id: id,
            state: "running",
            exitCode: nil,
            startedAt: containerInfo[id]?.startedAt,
            finishedAt: nil
        )
        #else
        throw SandboxManagerError.notSupported
        #endif
    }
    
    func stopSandbox(id: String) async throws {
        #if canImport(Containerization)
        guard let container = containers[id] else {
            throw SandboxManagerError.containerNotFound(id)
        }
        
        try await container.stop()
        containers.removeValue(forKey: id)
        
        if var info = containerInfo[id] {
            info.finishedAt = Date()
            info.exitCode = nil
            containerInfo[id] = info
        }
        #else
        throw SandboxManagerError.notSupported
        #endif
    }
    
    func listSandboxes() -> [SandboxInfo] {
        #if canImport(Containerization)
        return containerInfo.map { id, metadata in
            SandboxInfo(
                id: id,
                policyName: metadata.policyName,
                state: containers[id] != nil ? "running" : "stopped",
                startedAt: metadata.startedAt
            )
        }
        #else
        return []
        #endif
    }
    
    func getStatus(id: String) async throws -> SandboxStatus {
        #if canImport(Containerization)
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
        #else
        throw SandboxManagerError.notSupported
        #endif
    }
    
    func cleanup() async {
        #if canImport(Containerization)
        for (id, container) in containers {
            print("Cleaning up container \(id)")
            try? await container.stop()
        }
        containers.removeAll()
        vmm = nil
        #endif
    }
    
    #if canImport(Containerization)
    private func handleContainerExit(id: String, exitCode: Int) async {
        print("Container \(id) exited with code \(exitCode)")
        
        containers.removeValue(forKey: id)
        
        if var info = containerInfo[id] {
            info.finishedAt = Date()
            info.exitCode = exitCode
            containerInfo[id] = info
        }
    }
    #endif
}

#if canImport(Containerization)
private struct ContainerMetadata {
    let policyName: String
    let startedAt: Date
    var finishedAt: Date?
    var exitCode: Int?
}
#endif

enum SandboxManagerError: Error {
    case vmmNotInitialized
    case containerAlreadyExists(String)
    case containerNotFound(String)
    case missingKernel(String)
    case missingInitfs(String)
    case notSupported
}

#if canImport(Containerization)
extension UInt64 {
    func mib() -> UInt64 {
        return self * 1024 * 1024
    }
}
#endif
