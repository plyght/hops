import Foundation
import HopsCore

actor ContainerService {
    private let socketPath: String
    private weak var sandboxManager: SandboxManager?
    private var isRunning = false
    
    init(socketPath: String, sandboxManager: SandboxManager?) {
        self.socketPath = socketPath
        self.sandboxManager = sandboxManager
    }
    
    func start() async throws {
        guard !isRunning else { return }
        isRunning = true
    }
    
    func stop() async {
        guard isRunning else { return }
        isRunning = false
    }
    
    func runSandbox(
        id: String,
        policy: Policy,
        command: [String],
        rootfs: URL
    ) async throws -> SandboxStatus {
        guard let manager = sandboxManager else {
            throw ContainerServiceError.managerNotAvailable
        }
        
        print("Running sandbox \(id) with policy: \(policy.name)")
        
        let capabilities = policy.capabilities
        logCapabilities(id: id, capabilities: capabilities)
        
        return try await manager.runSandbox(
            id: id,
            policy: policy,
            command: command,
            rootfs: rootfs
        )
    }
    
    func stopSandbox(id: String) async throws {
        guard let manager = sandboxManager else {
            throw ContainerServiceError.managerNotAvailable
        }
        
        print("Stopping sandbox \(id)")
        try await manager.stopSandbox(id: id)
    }
    
    func listSandboxes() async throws -> [SandboxInfo] {
        guard let manager = sandboxManager else {
            throw ContainerServiceError.managerNotAvailable
        }
        
        return await manager.listSandboxes()
    }
    
    func getStatus(id: String) async throws -> SandboxStatus {
        guard let manager = sandboxManager else {
            throw ContainerServiceError.managerNotAvailable
        }
        
        return try await manager.getStatus(id: id)
    }
    
    private func logCapabilities(id: String, capabilities: CapabilityGrant) {
        print("Sandbox \(id) capabilities:")
        print("  Network: \(capabilities.network.rawValue)")
        print("  Filesystem: \(capabilities.filesystem.map { $0.rawValue }.joined(separator: ", "))")
        print("  Allowed paths: \(capabilities.allowedPaths.sorted().joined(separator: ", "))")
        if !capabilities.deniedPaths.isEmpty {
            print("  DENIED paths: \(capabilities.deniedPaths.sorted().joined(separator: ", "))")
        }
        if let cpus = capabilities.resourceLimits.cpus {
            print("  CPUs: \(cpus)")
        }
        if let memory = capabilities.resourceLimits.memoryBytes {
            print("  Memory: \(memory / 1024 / 1024) MB")
        }
    }
}

enum ContainerServiceError: Error {
    case managerNotAvailable
}

public struct SandboxInfo: Codable, Sendable {
    public let id: String
    public let policyName: String
    public let state: String
    public let startedAt: Date?
    
    public init(id: String, policyName: String, state: String, startedAt: Date?) {
        self.id = id
        self.policyName = policyName
        self.state = state
        self.startedAt = startedAt
    }
}

public struct SandboxStatus: Codable, Sendable {
    public let id: String
    public let state: String
    public let exitCode: Int?
    public let startedAt: Date?
    public let finishedAt: Date?
    
    public init(
        id: String,
        state: String,
        exitCode: Int?,
        startedAt: Date?,
        finishedAt: Date?
    ) {
        self.id = id
        self.state = state
        self.exitCode = exitCode
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}
