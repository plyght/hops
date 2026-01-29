import ArgumentParser
import Foundation
import HopsCore
import HopsProto
import GRPC
import NIO
import SwiftProtobuf

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run a command in a sandboxed environment",
        discussion: """
            Execute a command with filesystem, network, and resource isolation.
            
            The sandbox root directory is specified with <path>. All filesystem
            access is restricted to this directory unless additional mounts are configured.
            
            Examples:
              hops run ./myproject -- ./build.sh
              hops run --profile untrusted ./code -- python script.py
              hops run --network disabled --memory 512M ./project -- npm test
              hops run --cpus 2 ./workdir -- cargo build --release
            """
    )
    
    @Argument(help: "Root directory for the sandbox")
    var path: String
    
    @Option(name: .long, help: "Named profile to use (default, untrusted, build, etc.)")
    var profile: String?
    
    @Option(name: .long, help: "Network capability: disabled, outbound, loopback, full")
    var network: String?
    
    @Option(name: .long, help: "CPU limit (number of cores, e.g., 2 or 0.5)")
    var cpus: Double?
    
    @Option(name: .long, help: "Memory limit (e.g., 512M, 2G)")
    var memory: String?
    
    @Option(name: .long, help: "Path to custom policy TOML file")
    var policyFile: String?
    
    @Flag(name: .long, help: "Enable verbose output")
    var verbose: Bool = false
    
    @Flag(name: .long, help: "Enable streaming output (default: true)")
    var stream: Bool = true
    
    @Argument(parsing: .remaining, help: "Command to execute inside the sandbox")
    var command: [String] = []
    
    func validate() throws {
        guard !command.isEmpty else {
            throw ValidationError("No command specified. Use -- to separate the command from options.")
        }
    }
    
    mutating func run() async throws {
        let sandboxPath = expandPath(path)
        
        if verbose {
            print("Hops: Preparing sandbox environment...")
            print("  Root: \(sandboxPath)")
            if let profile = profile {
                print("  Profile: \(profile)")
            }
            print("  Command: \(command.joined(separator: " "))")
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
            }
        }
        
        let exitCode = try await executeViaDaemon(
            sandboxPath: sandboxPath,
            command: command,
            policy: policy
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
            let profilePath = profileDirectory().appendingPathComponent("\(profileName).toml")
            if FileManager.default.fileExists(atPath: profilePath.path) {
                policy = try Policy.load(fromTOMLFile: profilePath.path)
            } else {
                throw ValidationError("Profile '\(profileName)' not found at \(profilePath.path)")
            }
        } else {
            policy = Policy.default
        }
        
        if let networkOverride = network {
            guard let capability = NetworkCapability(rawValue: networkOverride) else {
                throw ValidationError("Invalid network capability: \(networkOverride). Use: disabled, outbound, loopback, full")
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
        
        return policy
    }
    
    private func executeViaDaemon(
        sandboxPath: String,
        command: [String],
        policy: Policy
    ) async throws -> Int32 {
        let client = try await DaemonClient.connect()
        
        if stream {
            return try await client.executeStreaming(
                sandboxPath: sandboxPath,
                command: command,
                policy: policy
            )
        } else {
            return try await client.execute(
                sandboxPath: sandboxPath,
                command: command,
                policy: policy
            )
        }
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
    
    private func profileDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".hops/profiles")
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
}

struct DaemonClient {
    private let client: Hops_HopsServiceAsyncClient
    private let group: MultiThreadedEventLoopGroup
    private let channel: GRPCChannel
    
    private init(client: Hops_HopsServiceAsyncClient, group: MultiThreadedEventLoopGroup, channel: GRPCChannel) {
        self.client = client
        self.group = group
        self.channel = channel
    }
    
    static func connect() async throws -> DaemonClient {
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
        
        return DaemonClient(client: client, group: group, channel: channel)
    }
    
    func execute(
        sandboxPath: String,
        command: [String],
        policy: Policy
    ) async throws -> Int32 {
        var runRequest = Hops_RunRequest()
        runRequest.command = command
        runRequest.workingDirectory = sandboxPath
        runRequest.inlinePolicy = buildProtoPolicy(policy)
        
        let response = try await client.runSandbox(runRequest)
        
        guard response.success else {
            throw DaemonClientError.executionFailed(response.error)
        }
        
        return 0
    }
    
    func executeStreaming(
        sandboxPath: String,
        command: [String],
        policy: Policy
    ) async throws -> Int32 {
        var runRequest = Hops_RunRequest()
        runRequest.command = command
        runRequest.workingDirectory = sandboxPath
        runRequest.inlinePolicy = buildProtoPolicy(policy)
        
        let responseStream = client.runSandboxStreaming(runRequest)
        var exitCode: Int32 = 1
        
        for try await chunk in responseStream {
            switch chunk.type {
            case .stdout:
                if !chunk.data.isEmpty {
                    FileHandle.standardOutput.write(chunk.data)
                }
            case .stderr:
                if !chunk.data.isEmpty {
                    FileHandle.standardError.write(chunk.data)
                }
            case .exit:
                if chunk.hasExitCode {
                    exitCode = chunk.exitCode
                }
            case .UNRECOGNIZED:
                break
            }
        }
        
        return exitCode
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

enum DaemonClientError: Error {
    case executionFailed(String)
}
