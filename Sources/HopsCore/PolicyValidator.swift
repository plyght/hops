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
  case resourceLimitTooLow(String, UInt64)
  case insecureMountConfiguration(String)
  case rootfsNotFound(String)

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
    case .resourceLimitTooLow(let resource, let value):
      return
        "Resource limit too low for \(resource): \(value). Minimum: cpus=1, memory=1MB, max_processes=1"
    case .insecureMountConfiguration(let reason):
      return "Insecure mount configuration: \(reason)"
    case .rootfsNotFound(let path):
      return """
        Rootfs image not found: \(path)

        Available rootfs images should be in ~/.hops/rootfs/ directory.
        Example: ~/.hops/rootfs/alpine.ext4, ~/.hops/rootfs/ubuntu.ext4

        Or use absolute/tilde paths in the policy rootfs field.
        """
    }
  }
}

public struct PolicyValidator: Sendable {
  public let maxMemoryBytes: UInt64
  public let maxCPUs: UInt
  public let maxProcesses: UInt
  public let minMemoryBytes: UInt64
  public let minCPUs: UInt
  public let minProcesses: UInt

  private let sensitivePaths = [
    "/etc/shadow",
    "/etc/sudoers",
    "/etc/passwd",
    "/etc/master.passwd",
    "/root/.ssh",
    "/var/root/.ssh",
    "/var/run/docker.sock",
    "/var/db/dslocal",
    "/Library/Keychains",
    "/System/Library/Security"
  ]

  public init(
    maxMemoryBytes: UInt64 = 8_589_934_592,
    maxCPUs: UInt = 16,
    maxProcesses: UInt = 1024,
    minMemoryBytes: UInt64 = 1_048_576,
    minCPUs: UInt = 1,
    minProcesses: UInt = 1
  ) {
    self.maxMemoryBytes = maxMemoryBytes
    self.maxCPUs = maxCPUs
    self.maxProcesses = maxProcesses
    self.minMemoryBytes = minMemoryBytes
    self.minCPUs = minCPUs
    self.minProcesses = minProcesses
  }

  private func canonicalizePath(_ path: String) -> String {
    let expandedPath = NSString(string: path).expandingTildeInPath
    return URL(fileURLWithPath: expandedPath).standardized.path
  }

  public func validate(_ policy: Policy) throws {
    try validateBasicFields(policy)
    try validateCapabilities(policy.capabilities)
    try validateSandbox(policy.sandbox)
    try validateRootfs(policy.rootfs)
  }

  private func validateBasicFields(_ policy: Policy) throws {
    if policy.name.isEmpty {
      throw PolicyValidationError.emptyName
    }

    let versionPattern = "^\\d+\\.\\d+\\.\\d+$"
    guard let regex = try? NSRegularExpression(pattern: versionPattern, options: []) else {
      throw PolicyValidationError.invalidVersion(policy.version)
    }
    let range = NSRange(policy.version.startIndex..., in: policy.version)
    if regex.firstMatch(in: policy.version, options: [], range: range) == nil {
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
        let canonAllowed = canonicalizePath(allowedPath)
        let canonDenied = canonicalizePath(deniedPath)
        if canonAllowed.hasPrefix(canonDenied) || canonDenied.hasPrefix(canonAllowed) {
          throw PolicyValidationError.conflictingPaths(allowedPath, deniedPath)
        }
      }
    }

    try validateResourceLimits(capabilities.resourceLimits)
  }

  private func validateResourceLimits(_ limits: ResourceLimits) throws {
    if let cpus = limits.cpus {
      if cpus < minCPUs {
        throw PolicyValidationError.resourceLimitTooLow("cpus", UInt64(cpus))
      }
      if cpus > maxCPUs {
        throw PolicyValidationError.resourceLimitTooHigh("cpus", UInt64(cpus))
      }
    }

    if let memory = limits.memoryBytes {
      if memory < minMemoryBytes {
        throw PolicyValidationError.resourceLimitTooLow("memory", memory)
      }
      if memory > maxMemoryBytes {
        throw PolicyValidationError.resourceLimitTooHigh("memory", memory)
      }
    }

    if let processes = limits.maxProcesses {
      if processes < minProcesses {
        throw PolicyValidationError.resourceLimitTooLow("max_processes", UInt64(processes))
      }
      if processes > maxProcesses {
        throw PolicyValidationError.resourceLimitTooHigh("max_processes", UInt64(processes))
      }
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

    if mount.type == .bind {
      let canonSource = canonicalizePath(mount.source)

      if !FileManager.default.fileExists(atPath: canonSource) {
        throw PolicyValidationError.invalidRootPath("Mount source does not exist: \(mount.source)")
      }

      var isSymlink = false
      if let attrs = try? FileManager.default.attributesOfItem(atPath: canonSource),
        let fileType = attrs[.type] as? FileAttributeType,
        fileType == .typeSymbolicLink {
        isSymlink = true
      }

      if isSymlink {
        let resolvedSource = try FileManager.default.destinationOfSymbolicLink(atPath: canonSource)
        let resolvedCanon = canonicalizePath(resolvedSource)

        for sensitivePath in sensitivePaths {
          let canonSensitive = canonicalizePath(sensitivePath)
          if resolvedCanon.hasPrefix(canonSensitive) || canonSensitive.hasPrefix(resolvedCanon) {
            throw PolicyValidationError.insecureMountConfiguration(
              "Mount source is a symlink to sensitive path: \(mount.source) -> \(resolvedSource)"
            )
          }
        }
      }

      for sensitivePath in sensitivePaths {
        let canonSensitive = canonicalizePath(sensitivePath)
        if canonSource.hasPrefix(canonSensitive) || canonSensitive.hasPrefix(canonSource) {
          throw PolicyValidationError.insecureMountConfiguration(
            "Mount source overlaps with sensitive path: \(mount.source)"
          )
        }
      }
    }

    let canonDestination = canonicalizePath(mount.destination)

    for sensitivePath in sensitivePaths {
      let canonSensitive = canonicalizePath(sensitivePath)

      if mount.mode == .readWrite {
        if canonDestination.hasPrefix(canonSensitive) || canonSensitive.hasPrefix(canonDestination) {
          throw PolicyValidationError.insecureMountConfiguration(
            "Read-write access to sensitive path not allowed: \(mount.destination)"
          )
        }
      }

      if canonDestination.hasPrefix(canonSensitive) {
        if mount.mode == .readOnly {
          continue
        }
      }
    }
  }

  private func validateMountConflicts(_ mounts: [MountConfig]) throws {
    let destinations = mounts.map { canonicalizePath($0.destination) }
    for index1 in 0..<destinations.count {
      for index2 in (index1 + 1)..<destinations.count {
        let dest1 = destinations[index1]
        let dest2 = destinations[index2]
        if dest1.hasPrefix(dest2) || dest2.hasPrefix(dest1) {
          throw PolicyValidationError.conflictingPaths(mounts[index1].destination, mounts[index2].destination)
        }
      }
    }
  }

  private func validateRootfs(_ rootfs: String?) throws {
    guard let rootfs = rootfs else {
      return
    }

    let resolvedPath: String
    if rootfs.hasPrefix("/") || rootfs.hasPrefix("~") {
      let expandedPath = NSString(string: rootfs).expandingTildeInPath
      resolvedPath = expandedPath
    } else {
      let homeDir = FileManager.default.homeDirectoryForCurrentUser
      resolvedPath =
        homeDir
        .appendingPathComponent(".hops")
        .appendingPathComponent(rootfs)
        .path
    }

    guard FileManager.default.fileExists(atPath: resolvedPath) else {
      throw PolicyValidationError.rootfsNotFound(resolvedPath)
    }
  }
}
