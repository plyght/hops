import Foundation

public enum NetworkCapability: String, Codable, Sendable, CaseIterable {
    case disabled
    case outbound
    case loopback
    case full
}

public enum FilesystemCapability: String, Codable, Sendable, CaseIterable {
    case read
    case write
    case execute
}

public struct ResourceLimits: Codable, Sendable, Equatable {
    public var cpus: UInt?
    public var memoryBytes: UInt64?
    public var maxProcesses: UInt?
    
    public init(
        cpus: UInt? = nil,
        memoryBytes: UInt64? = nil,
        maxProcesses: UInt? = nil
    ) {
        self.cpus = cpus
        self.memoryBytes = memoryBytes
        self.maxProcesses = maxProcesses
    }
}

public struct CapabilityGrant: Codable, Sendable, Equatable {
    public var network: NetworkCapability
    public var filesystem: Set<FilesystemCapability>
    public var allowedPaths: Set<String>
    public var deniedPaths: Set<String>
    public var resourceLimits: ResourceLimits
    
    public init(
        network: NetworkCapability = .disabled,
        filesystem: Set<FilesystemCapability> = [],
        allowedPaths: Set<String> = [],
        deniedPaths: Set<String> = [],
        resourceLimits: ResourceLimits = ResourceLimits()
    ) {
        self.network = network
        self.filesystem = filesystem
        self.allowedPaths = allowedPaths
        self.deniedPaths = deniedPaths
        self.resourceLimits = resourceLimits
    }
    
    public static var `default`: CapabilityGrant {
        CapabilityGrant(
            network: .disabled,
            filesystem: [],
            allowedPaths: [],
            deniedPaths: [],
            resourceLimits: ResourceLimits()
        )
    }
}
