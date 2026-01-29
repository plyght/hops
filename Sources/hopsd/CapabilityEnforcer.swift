import Containerization
import ContainerizationExtras
import ContainerizationOCI
import Foundation
import HopsCore
import Logging

enum CapabilityEnforcer {
  static func configure(
    config: inout LinuxContainer.Configuration,
    policy: Policy,
    command: [String],
    stdout: (any Writer)? = nil,
    stderr: (any Writer)? = nil,
    stdin: (any ReaderStream)? = nil,
    allocateTty: Bool = false
  ) {
    let capabilities = policy.capabilities
    let sandbox = policy.sandbox

    config.hostname = sandbox.hostname ?? policy.name
    
    let processedCommand = processCommand(command: command, allocateTty: allocateTty)
    let needsDNS = capabilities.network == .outbound || capabilities.network == .full
    
    if needsDNS && !processedCommand.isEmpty {
      let dnsSetup = "echo 'nameserver 8.8.8.8' > /etc/resolv.conf && echo 'nameserver 8.8.4.4' >> /etc/resolv.conf"
      
      if processedCommand.count >= 2 && processedCommand[0] == "/bin/sh" && processedCommand[1] == "-c" {
        let userScript = processedCommand.count > 2 ? processedCommand[2] : ""
        config.process.arguments = ["/bin/sh", "-c", "\(dnsSetup) && \(userScript)"]
      } else {
        let escapedCommand = processedCommand.map { arg in
          arg.contains(" ") || arg.contains("\"") || arg.contains("'") ? "\"\(arg.replacingOccurrences(of: "\"", with: "\\\""))\"" : arg
        }.joined(separator: " ")
        config.process.arguments = ["/bin/sh", "-c", "\(dnsSetup) && exec \(escapedCommand)"]
      }
    } else if needsDNS && processedCommand.isEmpty {
      let dnsSetup = "echo 'nameserver 8.8.8.8' > /etc/resolv.conf && echo 'nameserver 8.8.4.4' >> /etc/resolv.conf"
      config.process.arguments = ["/bin/sh", "-c", "\(dnsSetup) && exec /bin/sh -i"]
    } else {
      config.process.arguments = processedCommand.isEmpty ? ["/bin/sh", "-i"] : processedCommand
    }
    
    config.process.workingDirectory = sandbox.workingDirectory

    var environmentVars = sandbox.environment
    if allocateTty {
      if !environmentVars.keys.contains("PS1") {
        environmentVars["PS1"] = "\\w $ "
      }
      if !environmentVars.keys.contains("TERM") {
        environmentVars["TERM"] = "xterm-256color"
      }
    }
    
    for (key, value) in environmentVars {
      config.process.environmentVariables.append("\(key)=\(value)")
    }

    if allocateTty {
      config.process.terminal = true
      if let stdin = stdin {
        config.process.stdin = stdin
      }
    } else {
      if let stdout = stdout {
        config.process.stdout = stdout
      }

      if let stderr = stderr {
        config.process.stderr = stderr
      }

      if let stdin = stdin {
        config.process.stdin = stdin
      }
    }

    configureResources(config: &config, limits: capabilities.resourceLimits)
    configureNetwork(config: &config, capability: capabilities.network)
    configureMounts(config: &config, policy: policy)
    configureSysctl(config: &config)
  }

  private static func processCommand(command: [String], allocateTty: Bool) -> [String] {
    guard allocateTty, !command.isEmpty else {
      return command
    }
    
    let firstArg = command[0]
    let isShell = firstArg.hasSuffix("/sh") || 
                  firstArg.hasSuffix("/bash") || 
                  firstArg.hasSuffix("/ash") ||
                  firstArg.hasSuffix("/dash") ||
                  firstArg.hasSuffix("/zsh")
    
    guard isShell else {
      return command
    }
    
    if command.count == 1 {
      return [firstArg, "-i"]
    }
    
    if command.count > 1 && (command[1] == "-c" || command[1].hasPrefix("-")) {
      return command
    }
    
    return [firstArg, "-i"] + command.dropFirst()
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

    if let maxProcs = limits.maxProcesses {
      config.process.rlimits.append(
        POSIXRlimit(type: "RLIMIT_NPROC", hard: UInt64(maxProcs), soft: UInt64(maxProcs))
      )
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
      do {
        let natInterface = try NATInterface(
          ipv4Address: CIDRv4("192.168.65.5/24"),
          ipv4Gateway: IPv4Address("192.168.65.1")
        )
        config.interfaces = [natInterface]
      } catch {
        fatalError("Failed to create NAT interface: \(error)")
      }

    case .full:
      do {
        let natInterface = try NATInterface(
          ipv4Address: CIDRv4("192.168.65.5/24"),
          ipv4Gateway: IPv4Address("192.168.65.1")
        )
        config.interfaces = [natInterface]
      } catch {
        fatalError("Failed to create NAT interface: \(error)")
      }
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

    for path in capabilities.allowedPaths where !sandbox.mounts.contains(where: { $0.destination == path }) {
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

  private static func translateMount(
    mountConfig: MountConfig,
    capabilities: CapabilityGrant
  ) -> Containerization.Mount? {
    let isDenied = capabilities.deniedPaths.contains(mountConfig.destination)

    if isDenied {
      return nil
    }

    switch mountConfig.type {
    case .bind:
      let options = mountConfig.mode == .readOnly ? ["ro"] : []
      return Containerization.Mount.share(
        source: mountConfig.source,
        destination: mountConfig.destination,
        options: options
      )

    case .tmpfs:
      return Containerization.Mount.any(
        type: "tmpfs",
        source: "tmpfs",
        destination: mountConfig.destination
      )

    case .overlay:
      guard let lowerDir = mountConfig.overlayLowerDir,
        let upperDir = mountConfig.overlayUpperDir,
        let workDir = mountConfig.overlayWorkDir
      else {
        return nil
      }

      let overlayOptions = "lowerdir=\(lowerDir),upperdir=\(upperDir),workdir=\(workDir)"
      return Containerization.Mount.any(
        type: "overlay",
        source: "overlay",
        destination: mountConfig.destination,
        options: [overlayOptions]
      )

    case .devtmpfs, .proc, .sysfs:
      let options = mountConfig.mode == .readOnly ? ["ro"] : []
      return Containerization.Mount.share(
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
