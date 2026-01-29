import Foundation

public struct Policy: Codable, Sendable, Equatable {
    public var name: String
    public var version: String
    public var description: String?
    public var capabilities: CapabilityGrant
    public var sandbox: SandboxConfig
    public var metadata: [String: String]
    
    public var resources: ResourceLimits? {
        get { capabilities.resourceLimits }
        set { 
            if let newValue = newValue {
                capabilities.resourceLimits = newValue
            }
        }
    }
    
    public init(
        name: String,
        version: String = "1.0.0",
        description: String? = nil,
        capabilities: CapabilityGrant = .default,
        sandbox: SandboxConfig = SandboxConfig(),
        metadata: [String: String] = [:]
    ) {
        self.name = name
        self.version = version
        self.description = description
        self.capabilities = capabilities
        self.sandbox = sandbox
        self.metadata = metadata
    }
    
    public static var `default`: Policy {
        Policy(
            name: "default",
            version: "1.0.0",
            description: "Default sandbox policy",
            capabilities: .default,
            sandbox: .default,
            metadata: [:]
        )
    }
    
    public static func load(fromTOMLFile path: String) throws -> Policy {
        let parser = PolicyParser()
        return try parser.parse(fromFile: path)
    }
}

public struct SandboxConfig: Codable, Sendable, Equatable {
    public var rootPath: String
    public var mounts: [MountConfig]
    public var hostname: String?
    public var workingDirectory: String
    public var environment: [String: String]
    
    public init(
        rootPath: String = "/",
        mounts: [MountConfig] = [],
        hostname: String? = nil,
        workingDirectory: String = "/",
        environment: [String: String] = [:]
    ) {
        self.rootPath = rootPath
        self.mounts = mounts
        self.hostname = hostname
        self.workingDirectory = workingDirectory
        self.environment = environment
    }
    
    public static var `default`: SandboxConfig {
        SandboxConfig(
            rootPath: "/",
            mounts: [
                .bind(source: "/usr", destination: "/usr", mode: .readOnly),
                .bind(source: "/lib", destination: "/lib", mode: .readOnly),
                .bind(source: "/bin", destination: "/bin", mode: .readOnly),
                .tmpfs(destination: "/tmp", size: "100m"),
                .init(source: "/dev/null", destination: "/dev/null", type: .bind),
                .init(source: "/dev/zero", destination: "/dev/zero", type: .bind),
                .init(source: "/dev/random", destination: "/dev/random", type: .bind),
                .init(source: "/dev/urandom", destination: "/dev/urandom", type: .bind)
            ],
            hostname: "sandbox",
            workingDirectory: "/",
            environment: [
                "PATH": "/usr/bin:/bin",
                "HOME": "/root"
            ]
        )
    }
}
