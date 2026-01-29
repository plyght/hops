import Foundation
import HopsCore
#if canImport(Containerization)
import Containerization
#endif

enum CapabilityEnforcer {
    #if canImport(Containerization)
    static func configure(
        config: inout LinuxContainer.Configuration,
        policy: Policy,
        command: [String]
    ) {
        let capabilities = policy.capabilities
        let sandbox = policy.sandbox
        
        config.hostname = sandbox.hostname ?? policy.name
        config.process.arguments = command.isEmpty ? ["/bin/sh"] : command
        config.process.workingDirectory = sandbox.workingDirectory
        
        for (key, value) in sandbox.environment {
            config.process.environment[key] = value
        }
        
        configureResources(config: &config, limits: capabilities.resourceLimits)
        configureNetwork(config: &config, capability: capabilities.network)
        configureMounts(config: &config, policy: policy)
    }
    
    private static func configureResources(
        config: inout LinuxContainer.Configuration,
        limits: ResourceLimits
    ) {
        if let cpus = limits.cpus {
            config.cpus = Int(cpus)
            print("Resource limit: CPUs = \(cpus)")
        }
        
        if let memory = limits.memoryBytes {
            config.memoryInBytes = memory
            print("Resource limit: Memory = \(memory / 1024 / 1024) MB")
        }
    }
    
    private static func configureNetwork(
        config: inout LinuxContainer.Configuration,
        capability: NetworkCapability
    ) {
        switch capability {
        case .disabled, .loopback:
            config.interfaces = []
            print("Network: disabled")
            
        case .outbound:
            let natInterface = NATInterface(
                address: "10.0.0.5/24",
                gateway: "10.0.0.1"
            )
            config.interfaces = [natInterface]
            print("Network: outbound only (NAT)")
            
        case .full:
            let natInterface = NATInterface(
                address: "10.0.0.5/24",
                gateway: "10.0.0.1"
            )
            config.interfaces = [natInterface]
            print("Network: full (NAT with port forwarding)")
        }
    }
    
    private static func configureMounts(
        config: inout LinuxContainer.Configuration,
        policy: Policy
    ) {
        let sandbox = policy.sandbox
        let capabilities = policy.capabilities
        
        for mountConfig in sandbox.mounts {
            let mount = translateMount(mountConfig: mountConfig, capabilities: capabilities)
            config.mounts.append(mount)
            
            print("Mount: \(mountConfig.source) -> \(mountConfig.destination) (\(mountConfig.mode.rawValue))")
        }
        
        for path in capabilities.allowedPaths {
            if !sandbox.mounts.contains(where: { $0.destination == path }) {
                let isWritable = capabilities.filesystem.contains(.write)
                let mount = Mount.share(
                    source: path,
                    destination: path,
                    readonly: !isWritable
                )
                config.mounts.append(mount)
                
                print("Capability mount: \(path) (\(isWritable ? "rw" : "ro"))")
            }
        }
        
        if !capabilities.deniedPaths.isEmpty {
            print("DENIED paths (enforced by policy): \(capabilities.deniedPaths.sorted().joined(separator: ", "))")
        }
    }
    
    private static func translateMount(
        mountConfig: MountConfig,
        capabilities: CapabilityGrant
    ) -> Mount {
        let isDenied = capabilities.deniedPaths.contains(mountConfig.destination)
        
        if isDenied {
            print("WARNING: Mount \(mountConfig.destination) is in denied paths, skipping")
            return Mount.share(source: "/dev/null", destination: "/dev/null", readonly: true)
        }
        
        switch mountConfig.type {
        case .bind:
            let readonly = mountConfig.mode == .readOnly
            return Mount.share(
                source: mountConfig.source,
                destination: mountConfig.destination,
                readonly: readonly
            )
            
        case .tmpfs:
            return Mount.tmpfs(destination: mountConfig.destination)
            
        case .devtmpfs, .proc, .sysfs:
            return Mount.share(
                source: mountConfig.source,
                destination: mountConfig.destination,
                readonly: mountConfig.mode == .readOnly
            )
        }
    }
    #endif
}
