import Foundation
import HopsCore
import Containerization
import ContainerizationExtras
import Logging

enum CapabilityEnforcer {
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
            config.process.environmentVariables.append("\(key)=\(value)")
        }
        
        configureResources(config: &config, limits: capabilities.resourceLimits)
        configureNetwork(config: &config, capability: capabilities.network)
        configureMounts(config: &config, policy: policy)
        configureSysctl(config: &config)
    }
    
    private static func configureResources(
        config: inout LinuxContainer.Configuration,
        limits: ResourceLimits
    ) {
        if let cpus = limits.cpus {
            config.cpus = Int(cpus)
        }
        
        if let memory = limits.memoryBytes {
            config.memoryInBytes = memory
        }
    }
    
    private static func configureNetwork(
        config: inout LinuxContainer.Configuration,
        capability: NetworkCapability
    ) {
        switch capability {
        case .disabled, .loopback:
            config.interfaces = []
            
        case .outbound:
            let natInterface = try! NATInterface(
                ipv4Address: CIDRv4("10.0.0.5/24"),
                ipv4Gateway: IPv4Address("10.0.0.1")
            )
            config.interfaces = [natInterface]
            config.dns = DNS(nameservers: ["8.8.8.8", "8.8.4.4"])
            
        case .full:
            let natInterface = try! NATInterface(
                ipv4Address: CIDRv4("10.0.0.5/24"),
                ipv4Gateway: IPv4Address("10.0.0.1")
            )
            config.interfaces = [natInterface]
            config.dns = DNS(nameservers: ["8.8.8.8", "8.8.4.4"])
        }
    }
    
    private static func configureMounts(
        config: inout LinuxContainer.Configuration,
        policy: Policy
    ) {
        let sandbox = policy.sandbox
        let capabilities = policy.capabilities
        
        for mountConfig in sandbox.mounts {
            if let mount = translateMount(mountConfig: mountConfig, capabilities: capabilities) {
                config.mounts.append(mount)
            }
        }
        
        for path in capabilities.allowedPaths {
            if !sandbox.mounts.contains(where: { $0.destination == path }) {
                let isWritable = capabilities.filesystem.contains(.write)
                let options = isWritable ? [] : ["ro"]
                let mount = Mount.share(
                    source: path,
                    destination: path,
                    options: options
                )
                config.mounts.append(mount)
            }
        }
    }
    
    private static func translateMount(
        mountConfig: MountConfig,
        capabilities: CapabilityGrant
    ) -> Mount? {
        let isDenied = capabilities.deniedPaths.contains(mountConfig.destination)
        
        if isDenied {
            return nil
        }
        
        switch mountConfig.type {
        case .bind:
            let options = mountConfig.mode == .readOnly ? ["ro"] : []
            return Mount.share(
                source: mountConfig.source,
                destination: mountConfig.destination,
                options: options
            )
            
        case .tmpfs:
            return Mount.any(
                type: "tmpfs",
                source: "tmpfs",
                destination: mountConfig.destination
            )
            
        case .devtmpfs, .proc, .sysfs:
            let options = mountConfig.mode == .readOnly ? ["ro"] : []
            return Mount.share(
                source: mountConfig.source,
                destination: mountConfig.destination,
                options: options
            )
        }
    }
    
    private static func configureSysctl(
        config: inout LinuxContainer.Configuration
    ) {
        config.sysctl = [
            "net.ipv4.ip_forward": "1",
            "net.ipv4.conf.all.forwarding": "1"
        ]
    }
}
