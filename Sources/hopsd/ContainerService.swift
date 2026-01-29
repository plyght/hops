import Foundation
import HopsCore
import HopsProto
import GRPC
import NIO
import SwiftProtobuf

actor ContainerService: Hops_HopsServiceAsyncProvider {
    private let socketPath: String
    private weak var sandboxManager: SandboxManager?
    private weak var daemon: HopsDaemon?
    private var isRunning = false
    private var server: Server?
    private var group: MultiThreadedEventLoopGroup?
    
    nonisolated var interceptors: Hops_HopsServiceServerInterceptorFactoryProtocol? {
        return nil
    }
    
    init(socketPath: String, sandboxManager: SandboxManager?, daemon: HopsDaemon?) {
        self.socketPath = socketPath
        self.sandboxManager = sandboxManager
        self.daemon = daemon
    }
    
    func start() async throws {
        guard !isRunning else { return }
        
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        self.group = eventLoopGroup
        
        let server = try await Server.insecure(group: eventLoopGroup)
            .withServiceProviders([self])
            .bind(unixDomainSocketPath: socketPath)
            .get()
        
        self.server = server
        self.isRunning = true
        
        print("gRPC server started on unix://\(socketPath)")
    }
    
    func stop() async {
        guard isRunning else { return }
        
        if let server = server {
            _ = server.initiateGracefulShutdown().always { _ in
                print("gRPC server stopped")
            }
            self.server = nil
        }
        
        if let group = group {
            try? await group.shutdownGracefully()
            self.group = nil
        }
        
        isRunning = false
    }
    
    nonisolated func runSandbox(
        request: Hops_RunRequest,
        context: GRPCAsyncServerCallContext
    ) async throws -> Hops_RunResponse {
        guard let manager = await sandboxManager else {
            var response = Hops_RunResponse()
            response.success = false
            response.error = "Sandbox manager not available"
            return response
        }
        
        do {
            let sandboxId = UUID().uuidString
            
            var policy = Policy.default
            if request.hasInlinePolicy {
                policy = try convertProtoPolicy(request.inlinePolicy)
            }
            
            let rootfs = URL(fileURLWithPath: request.workingDirectory)
            
            let status = try await manager.runSandbox(
                id: sandboxId,
                policy: policy,
                command: request.command,
                rootfs: rootfs
            )
            
            var response = Hops_RunResponse()
            response.sandboxID = sandboxId
            response.pid = status.pid
            response.success = true
            
            return response
        } catch {
            var response = Hops_RunResponse()
            response.success = false
            response.error = error.localizedDescription
            return response
        }
    }
    
    nonisolated func runSandboxStreaming(
        request: Hops_RunRequest,
        responseStream: GRPCAsyncResponseStreamWriter<Hops_OutputChunk>,
        context: GRPCAsyncServerCallContext
    ) async throws {
        guard let manager = await sandboxManager else {
            throw ContainerServiceError.managerNotAvailable
        }
        
        let sandboxId = UUID().uuidString
        
        var policy = Policy.default
        if request.hasInlinePolicy {
            policy = try convertProtoPolicy(request.inlinePolicy)
        }
        
        let rootfs = URL(fileURLWithPath: request.workingDirectory)
        
        let stream = await manager.runSandboxStreaming(
            id: sandboxId,
            policy: policy,
            command: request.command,
            rootfs: rootfs
        )
        
        for try await chunk in stream {
            var protoChunk = Hops_OutputChunk()
            protoChunk.sandboxID = chunk.sandboxId
            protoChunk.data = chunk.data
            protoChunk.timestamp = chunk.timestamp
            
            switch chunk.type {
            case .stdout:
                protoChunk.type = .stdout
            case .stderr:
                protoChunk.type = .stderr
            case .exit:
                protoChunk.type = .exit
                if let exitCode = chunk.exitCode {
                    protoChunk.exitCode = exitCode
                }
            }
            
            try await responseStream.send(protoChunk)
        }
    }
    
    nonisolated func stopSandbox(
        request: Hops_StopRequest,
        context: GRPCAsyncServerCallContext
    ) async throws -> Hops_StopResponse {
        guard let manager = await sandboxManager else {
            var response = Hops_StopResponse()
            response.success = false
            response.error = "Sandbox manager not available"
            return response
        }
        
        do {
            try await manager.stopSandbox(id: request.sandboxID)
            
            var response = Hops_StopResponse()
            response.success = true
            return response
        } catch {
            var response = Hops_StopResponse()
            response.success = false
            response.error = error.localizedDescription
            return response
        }
    }
    
    nonisolated func listSandboxes(
        request: Hops_ListRequest,
        context: GRPCAsyncServerCallContext
    ) async throws -> Hops_ListResponse {
        guard let manager = await sandboxManager else {
            return Hops_ListResponse()
        }
        
        let sandboxes = await manager.listSandboxes()
        
        var response = Hops_ListResponse()
        response.sandboxes = sandboxes.map { info in
            var protoInfo = Hops_SandboxInfo()
            protoInfo.sandboxID = info.id
            protoInfo.pid = info.pid
            protoInfo.state = info.state == "running" ? .running : .stopped
            protoInfo.command = info.command
            return protoInfo
        }
        
        return response
    }
    
    nonisolated func getStatus(
        request: Hops_StatusRequest,
        context: GRPCAsyncServerCallContext
    ) async throws -> Hops_SandboxStatus {
        guard let manager = await sandboxManager else {
            var status = Hops_SandboxStatus()
            status.sandboxID = request.sandboxID
            status.state = .unknown
            return status
        }
        
        do {
            let status = try await manager.getStatus(id: request.sandboxID)
            let info = await manager.listSandboxes().first { $0.id == request.sandboxID }
            
            var protoStatus = Hops_SandboxStatus()
            protoStatus.sandboxID = status.id
            protoStatus.pid = status.pid
            protoStatus.state = status.state == "running" ? .running : .stopped
            protoStatus.command = info?.command ?? []
            protoStatus.startTime = Int64(status.startedAt?.timeIntervalSince1970 ?? 0)
            
            return protoStatus
        } catch {
            var status = Hops_SandboxStatus()
            status.sandboxID = request.sandboxID
            status.state = .failed
            return status
        }
    }
    
    private nonisolated func convertProtoPolicy(_ protoPolicy: Hops_Policy) throws -> Policy {
        var capabilities = CapabilityGrant.default
        
        if protoPolicy.hasCapabilities {
            let protoCaps = protoPolicy.capabilities
            capabilities.network = convertNetworkAccess(protoCaps.network)
            
            if protoCaps.hasFilesystem {
                let fs = protoCaps.filesystem
                capabilities.allowedPaths = Set(fs.read + fs.write + fs.execute)
            }
        }
        
        if protoPolicy.hasResources {
            let protoRes = protoPolicy.resources
            var resourceLimits = ResourceLimits()
            
            if protoRes.cpus > 0 {
                resourceLimits.cpus = UInt(protoRes.cpus)
            }
            
            if !protoRes.memory.isEmpty {
                resourceLimits.memoryBytes = parseMemoryString(protoRes.memory)
            }
            
            if protoRes.maxProcesses > 0 {
                resourceLimits.maxProcesses = UInt(protoRes.maxProcesses)
            }
            
            capabilities.resourceLimits = resourceLimits
        }
        
        return Policy(
            name: "grpc-policy",
            version: "1.0.0",
            capabilities: capabilities
        )
    }
    
    private nonisolated func convertNetworkAccess(_ access: Hops_NetworkAccess) -> NetworkCapability {
        switch access {
        case .disabled:
            return .disabled
        case .outbound:
            return .outbound
        case .loopback:
            return .loopback
        case .full:
            return .full
        case .UNRECOGNIZED:
            return .disabled
        }
    }
    
    private nonisolated func parseMemoryString(_ memory: String) -> UInt64 {
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
            print("WARNING: Invalid memory string '\(memory)', defaulting to 512MB")
            return 512 * 1024 * 1024
        }
        
        return value * multiplier
    }
    
    nonisolated func getDaemonStatus(
        request: Hops_DaemonStatusRequest,
        context: GRPCAsyncServerCallContext
    ) async throws -> Hops_DaemonStatusResponse {
        guard let daemon = await daemon else {
            var response = Hops_DaemonStatusResponse()
            response.pid = ProcessInfo.processInfo.processIdentifier
            response.startTime = Int64(Date().timeIntervalSince1970)
            response.activeSandboxes = 0
            return response
        }
        
        let status = await daemon.getDaemonStatus()
        
        var response = Hops_DaemonStatusResponse()
        response.pid = status.pid
        response.startTime = Int64(status.startTime.timeIntervalSince1970)
        response.activeSandboxes = Int32(status.activeSandboxes)
        
        return response
    }
}

enum ContainerServiceError: Error {
    case managerNotAvailable
}

public struct SandboxInfo: Codable, Sendable {
    public let id: String
    public let policyName: String
    public let command: [String]
    public let pid: Int32
    public let state: String
    public let startedAt: Date?
    
    public init(id: String, policyName: String, command: [String], pid: Int32, state: String, startedAt: Date?) {
        self.id = id
        self.policyName = policyName
        self.command = command
        self.pid = pid
        self.state = state
        self.startedAt = startedAt
    }
}

public struct SandboxStatus: Codable, Sendable {
    public let id: String
    public let pid: Int32
    public let state: String
    public let exitCode: Int?
    public let startedAt: Date?
    public let finishedAt: Date?
    
    public init(
        id: String,
        pid: Int32,
        state: String,
        exitCode: Int?,
        startedAt: Date?,
        finishedAt: Date?
    ) {
        self.id = id
        self.pid = pid
        self.state = state
        self.exitCode = exitCode
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}
