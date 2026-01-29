import Foundation

public enum PolicyValidationError: Error, CustomStringConvertible {
    case emptyName
    case invalidVersion(String)
    case invalidRootPath(String)
    case invalidWorkingDirectory(String)
    case mountSourceNotAbsolute(String)
    case mountDestinationNotAbsolute(String)
    case conflictingPaths(String, String)
    case resourceLimitTooHigh(String, UInt64)
    case insecureMountConfiguration(String)
    
    public var description: String {
        switch self {
        case .emptyName:
            return "Policy name cannot be empty"
        case .invalidVersion(let version):
            return "Invalid version format: \(version)"
        case .invalidRootPath(let path):
            return "Invalid root path: \(path)"
        case .invalidWorkingDirectory(let path):
            return "Invalid working directory: \(path)"
        case .mountSourceNotAbsolute(let source):
            return "Mount source must be absolute path: \(source)"
        case .mountDestinationNotAbsolute(let destination):
            return "Mount destination must be absolute path: \(destination)"
        case .conflictingPaths(let path1, let path2):
            return "Conflicting paths: \(path1) and \(path2)"
        case .resourceLimitTooHigh(let resource, let value):
            return "Resource limit too high for \(resource): \(value)"
        case .insecureMountConfiguration(let reason):
            return "Insecure mount configuration: \(reason)"
        }
    }
}

public struct PolicyValidator: Sendable {
    public let maxMemoryBytes: UInt64
    public let maxCPUs: UInt
    public let maxProcesses: UInt
    
    public init(
        maxMemoryBytes: UInt64 = 8_589_934_592,
        maxCPUs: UInt = 16,
        maxProcesses: UInt = 1024
    ) {
        self.maxMemoryBytes = maxMemoryBytes
        self.maxCPUs = maxCPUs
        self.maxProcesses = maxProcesses
    }
    
    public func validate(_ policy: Policy) throws {
        try validateBasicFields(policy)
        try validateCapabilities(policy.capabilities)
        try validateSandbox(policy.sandbox)
    }
    
    private func validateBasicFields(_ policy: Policy) throws {
        if policy.name.isEmpty {
            throw PolicyValidationError.emptyName
        }
        
        let versionPattern = /^\d+\.\d+\.\d+$/
        if policy.version.firstMatch(of: versionPattern) == nil {
            throw PolicyValidationError.invalidVersion(policy.version)
        }
    }
    
    private func validateCapabilities(_ capabilities: CapabilityGrant) throws {
        if let allowedPath = capabilities.allowedPaths.first(where: { !$0.hasPrefix("/") }) {
            throw PolicyValidationError.mountSourceNotAbsolute(allowedPath)
        }
        
        if let deniedPath = capabilities.deniedPaths.first(where: { !$0.hasPrefix("/") }) {
            throw PolicyValidationError.mountSourceNotAbsolute(deniedPath)
        }
        
        for allowedPath in capabilities.allowedPaths {
            for deniedPath in capabilities.deniedPaths {
                if allowedPath.hasPrefix(deniedPath) || deniedPath.hasPrefix(allowedPath) {
                    throw PolicyValidationError.conflictingPaths(allowedPath, deniedPath)
                }
            }
        }
        
        try validateResourceLimits(capabilities.resourceLimits)
    }
    
    private func validateResourceLimits(_ limits: ResourceLimits) throws {
        if let cpus = limits.cpus, cpus > maxCPUs {
            throw PolicyValidationError.resourceLimitTooHigh("cpus", UInt64(cpus))
        }
        
        if let memory = limits.memoryBytes, memory > maxMemoryBytes {
            throw PolicyValidationError.resourceLimitTooHigh("memory", memory)
        }
        
        if let processes = limits.maxProcesses, processes > maxProcesses {
            throw PolicyValidationError.resourceLimitTooHigh("max_processes", UInt64(processes))
        }
    }
    
    private func validateSandbox(_ sandbox: SandboxConfig) throws {
        if !sandbox.rootPath.hasPrefix("/") {
            throw PolicyValidationError.invalidRootPath(sandbox.rootPath)
        }
        
        if !sandbox.workingDirectory.hasPrefix("/") {
            throw PolicyValidationError.invalidWorkingDirectory(sandbox.workingDirectory)
        }
        
        for mount in sandbox.mounts {
            try validateMount(mount)
        }
        
        try validateMountConflicts(sandbox.mounts)
    }
    
    private func validateMount(_ mount: MountConfig) throws {
        if mount.type == .bind && !mount.source.hasPrefix("/") {
            throw PolicyValidationError.mountSourceNotAbsolute(mount.source)
        }
        
        if !mount.destination.hasPrefix("/") {
            throw PolicyValidationError.mountDestinationNotAbsolute(mount.destination)
        }
        
        let sensitivePaths = ["/etc/shadow", "/etc/sudoers", "/root/.ssh"]
        if mount.mode == .readWrite {
            for sensitivePath in sensitivePaths {
                if mount.destination.hasPrefix(sensitivePath) {
                    throw PolicyValidationError.insecureMountConfiguration(
                        "Read-write access to \(sensitivePath) is not allowed"
                    )
                }
            }
        }
    }
    
    private func validateMountConflicts(_ mounts: [MountConfig]) throws {
        let destinations = mounts.map { $0.destination }
        for i in 0..<destinations.count {
            for j in (i+1)..<destinations.count {
                let dest1 = destinations[i]
                let dest2 = destinations[j]
                if dest1.hasPrefix(dest2) || dest2.hasPrefix(dest1) {
                    throw PolicyValidationError.conflictingPaths(dest1, dest2)
                }
            }
        }
    }
}
