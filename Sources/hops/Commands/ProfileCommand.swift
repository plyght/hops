import ArgumentParser
import Foundation
import HopsCore

struct ProfileCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "profile",
    abstract: "Manage sandbox profiles",
    discussion: """
      Profiles are reusable sandbox configurations stored as TOML files.
      They define filesystem access, network capabilities, and resource limits.

      Profiles are stored in ~/.hops/profiles/

      Examples:
        hops profile list
        hops profile show default
        hops profile create restrictive
        hops profile delete untrusted
      """,
    subcommands: [
      ListProfiles.self,
      ShowProfile.self,
      CreateProfile.self,
      DeleteProfile.self
    ]
  )
}

extension ProfileCommand {
  struct ListProfiles: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "list",
      abstract: "List all available profiles"
    )

    func run() async throws {
      let manager = ProfileManager()
      let profiles = try manager.listProfiles()

      if profiles.isEmpty {
        ColoredOutput.info("No profiles found.")
        print("Create your first profile with: hops profile create <name>")
        return
      }

      ColoredOutput.print("Available Profiles", color: .cyan, style: .bold)
      print()
      
      let nameWidth = 20
      let networkWidth = 12
      let cpuWidth = 8
      let memoryWidth = 12
      
      let header = String(format: "%-\(nameWidth)s %-\(networkWidth)s %-\(cpuWidth)s %-\(memoryWidth)s", "NAME", "NETWORK", "CPUS", "MEMORY")
      ColoredOutput.print(header, color: .white, style: .bold)
      print(String(repeating: "-", count: nameWidth + networkWidth + cpuWidth + memoryWidth + 3))

      for profileInfo in profiles {
        guard let policy = try? manager.loadProfile(named: profileInfo.name) else {
          continue
        }
        
        let networkColor: Color
        let networkStr: String
        switch policy.capabilities.network {
        case .disabled:
          networkColor = .red
          networkStr = "disabled"
        case .loopback:
          networkColor = .yellow
          networkStr = "loopback"
        case .outbound:
          networkColor = .cyan
          networkStr = "outbound"
        case .full:
          networkColor = .green
          networkStr = "full"
        }
        
        let cpuStr = policy.resources?.cpus.map { "\($0)" } ?? "∞"
        let memStr = policy.resources?.memoryBytes.map { formatBytes($0) } ?? "∞"
        
        let namePart = String(format: "%-\(nameWidth)s", profileInfo.name)
        let cpuPart = String(format: "%-\(cpuWidth)s", cpuStr)
        let memPart = String(format: "%-\(memoryWidth)s", memStr)
        
        print(namePart, terminator: " ")
        print(ColoredOutput.format(String(format: "%-\(networkWidth)s", networkStr), color: networkColor), terminator: " ")
        print(cpuPart, terminator: " ")
        print(memPart)
      }
      
      print()
      ColoredOutput.info("Use 'hops profile show <name>' for detailed configuration")
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
      let kb = Double(bytes) / 1024.0
      let mb = kb / 1024.0
      let gb = mb / 1024.0

      if gb >= 1.0 {
        return String(format: "%.1fG", gb)
      } else if mb >= 1.0 {
        return String(format: "%.0fM", mb)
      } else if kb >= 1.0 {
        return String(format: "%.0fK", kb)
      } else {
        return "\(bytes)B"
      }
    }
  }

  struct ShowProfile: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "show",
      abstract: "Display the contents of a profile"
    )

    @Argument(help: "Name of the profile to show")
    var name: String

    @Flag(name: .long, help: "Show raw TOML instead of parsed policy")
    var raw: Bool = false

    func run() async throws {
      let manager = ProfileManager()
      guard let profileInfo = manager.findProfile(named: name) else {
        throw ValidationError("Profile '\(name)' not found in any profile directory")
      }

      if raw {
        let contents = try String(contentsOf: profileInfo.path, encoding: .utf8)
        print("Profile: \(name)")
        print("Location: \(profileInfo.location.rawValue)")
        print("Path: \(profileInfo.path.path)")
        print()
        print(contents)
      } else {
        let policy = try manager.loadProfile(named: name)
        ColoredOutput.print("Profile: \(name)", color: .cyan, style: .bold)
        print("Location: \(profileInfo.location.rawValue)")
        print("Path: \(profileInfo.path.path)")
        print()
        
        ColoredOutput.print("METADATA", color: .white, style: .bold)
        print("  Name: \(policy.name)")
        print("  Version: \(policy.version)")
        if let description = policy.description {
          print("  Description: \(description)")
        }
        if let rootfs = policy.rootfs {
          print("  Rootfs: \(rootfs)")
        }
        if let ociImage = policy.ociImage {
          print("  OCI Image: \(ociImage)")
        }
        print()
        
        ColoredOutput.print("CAPABILITIES", color: .white, style: .bold)
        
        let networkColor: Color
        switch policy.capabilities.network {
        case .disabled: networkColor = .red
        case .loopback: networkColor = .yellow
        case .outbound: networkColor = .green
        case .full: networkColor = .magenta
        }
        
        print("  Network: ", terminator: "")
        ColoredOutput.print("\(policy.capabilities.network)", color: networkColor)
        
        print(
          "  Filesystem: \(policy.capabilities.filesystem.map { $0.rawValue }.sorted().joined(separator: ", "))"
        )
        if !policy.capabilities.allowedPaths.isEmpty {
          print("  Allowed paths:")
          for path in policy.capabilities.allowedPaths.sorted() {
             print("    • \(path)")
          }
        }
        if !policy.capabilities.deniedPaths.isEmpty {
          print("  Denied paths:")
          for path in policy.capabilities.deniedPaths.sorted() {
             ColoredOutput.print("    • \(path)", color: .red)
          }
        }
        print()
        
        let limits = policy.capabilities.resourceLimits
        if limits.cpus != nil || limits.memoryBytes != nil || limits.maxProcesses != nil {
          ColoredOutput.print("RESOURCE LIMITS", color: .white, style: .bold)
          if let cpus = limits.cpus {
            let bar = String(repeating: "█", count: Int(cpus)) + String(repeating: "░", count: 16 - Int(cpus))
            print("  CPUs: \(bar) \(cpus)/16")
          }
          if let memory = limits.memoryBytes {
            print("  Memory: \(formatBytes(memory))")
          }
          if let maxProcs = limits.maxProcesses {
            print("  Max Processes: \(maxProcs)")
          }
          print()
        }
        
        ColoredOutput.print("SANDBOX CONFIG", color: .white, style: .bold)
        print("  Root: \(policy.sandbox.rootPath)")
        print("  Working Directory: \(policy.sandbox.workingDirectory)")
        if let hostname = policy.sandbox.hostname {
          print("  Hostname: \(hostname)")
        }
        if !policy.sandbox.mounts.isEmpty {
          print("  Mounts:")
          for mount in policy.sandbox.mounts {
            print(
              "    \(mount.source) -> \(mount.destination) (\(mount.type.rawValue), \(mount.mode.rawValue))"
            )
          }
        }
        if !policy.sandbox.environment.isEmpty {
          print("  Environment:")
          for (key, value) in policy.sandbox.environment.sorted(by: { $0.key < $1.key }) {
            print("    \(key)=\(value)")
          }
        }
      }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
      let kb = Double(bytes) / 1024.0
      let mb = kb / 1024.0
      let gb = mb / 1024.0

      if gb >= 1.0 {
        return String(format: "%.1fGB", gb)
      } else if mb >= 1.0 {
        return String(format: "%.1fMB", mb)
      } else if kb >= 1.0 {
        return String(format: "%.1fKB", kb)
      } else {
        return "\(bytes)B"
      }
    }
  }

  struct CreateProfile: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "create",
      abstract: "Create a new profile from a template or interactively"
    )

    @Argument(help: "Name of the profile to create")
    var name: String

    @Option(name: .long, help: "Template to use: default, restrictive, build, network-only")
    var template: String?

    @Flag(name: .long, help: "Create profile interactively with guided prompts")
    var interactive: Bool = false

    @Flag(name: .long, help: "Overwrite if profile already exists")
    var force: Bool = false

    func run() async throws {
      let profileDir = profileDirectory()
      try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)

      let profilePath = profileDir.appendingPathComponent("\(name).toml")

      if FileManager.default.fileExists(atPath: profilePath.path) && !force {
        throw ValidationError("Profile '\(name)' already exists. Use --force to overwrite.")
      }

      let toml: String
      if interactive {
        toml = try interactiveProfileCreation(name: name)
      } else {
        toml = templateToml(template ?? "default", name: name)
      }

      try toml.write(to: profilePath, atomically: true, encoding: .utf8)

      ColoredOutput.success("Created profile '\(name)' at \(profilePath.path)")
      print()
      print("Edit the profile:")
      print("  $EDITOR \(profilePath.path)")
      print()
      print("Use the profile:")
      print("  hops run --profile \(name) ./project -- command")
    }
    
    private func interactiveProfileCreation(name: String) throws -> String {
      ColoredOutput.print("=== Interactive Profile Creation ===", color: .cyan, style: .bold)
      print()
      
      ColoredOutput.print("Profile Name:", color: .white, style: .bold)
      print("  \(name)")
      print()
      
      let description = prompt("Description", defaultValue: "Custom profile")
      print()
      
      ColoredOutput.print("Network Access:", color: .white, style: .bold)
      print("  1. disabled  - No network access")
      print("  2. loopback  - Only localhost connections")
      print("  3. outbound  - Outbound connections allowed")
      print("  4. full      - Full network access")
      let networkChoice = prompt("Choose (1-4)", defaultValue: "1")
      let networkIndex = (Int(networkChoice) ?? 1) - 1
      let network = ["disabled", "loopback", "outbound", "full"][max(0, min(3, networkIndex))]
      print()
      
      ColoredOutput.print("Filesystem Permissions:", color: .white, style: .bold)
      let fsRead = promptYesNo("Allow read access?", defaultValue: true)
      let fsWrite = promptYesNo("Allow write access?", defaultValue: false)
      let fsExec = promptYesNo("Allow execute access?", defaultValue: true)
      print()
      
      var fsPerms: [String] = []
      if fsRead { fsPerms.append("\"read\"") }
      if fsWrite { fsPerms.append("\"write\"") }
      if fsExec { fsPerms.append("\"execute\"") }
      
      ColoredOutput.print("Resource Limits:", color: .white, style: .bold)
      let cpus = prompt("CPU cores (leave empty for unlimited)", defaultValue: "")
      let memory = prompt("Memory (e.g., 512M, 2G, leave empty for unlimited)", defaultValue: "")
      let maxProcs = prompt("Max processes (leave empty for unlimited)", defaultValue: "")
      print()
      
      var resourcesSection = ""
      if !cpus.isEmpty || !memory.isEmpty || !maxProcs.isEmpty {
        resourcesSection = "\n[capabilities.resource_limits]"
        if !cpus.isEmpty, let cpuValue = UInt32(cpus) {
          resourcesSection += "\ncpus = \(cpuValue)"
        }
        if !memory.isEmpty {
          if let memBytes = parseMemoryString(memory) {
            resourcesSection += "\nmemory_bytes = \(memBytes)"
          }
        }
        if !maxProcs.isEmpty, let maxValue = UInt32(maxProcs) {
          resourcesSection += "\nmax_processes = \(maxValue)"
        }
      }
      
      ColoredOutput.success("Profile configuration complete!")
      print()
      
      return """
        name = "\(name)"
        version = "1.0.0"
        description = "\(description)"
        rootfs = "alpine-rootfs.ext4"
        
        [capabilities]
        network = "\(network)"
        filesystem = [\(fsPerms.joined(separator: ", "))]
        allowed_paths = []
        denied_paths = []\(resourcesSection)
        
        [sandbox]
        root_path = "/"
        hostname = "\(name)-sandbox"
        working_directory = "/"
        
        [[sandbox.mounts]]
        source = "tmpfs"
        destination = "/tmp"
        type = "tmpfs"
        mode = "rw"
        """
    }
    
    private func prompt(_ message: String, defaultValue: String) -> String {
      if !defaultValue.isEmpty {
        print("\(message) [\(defaultValue)]: ", terminator: "")
      } else {
        print("\(message): ", terminator: "")
      }
      fflush(stdout)
      
      guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
        return defaultValue
      }
      
      return input.isEmpty ? defaultValue : input
    }
    
    private func promptYesNo(_ message: String, defaultValue: Bool) -> Bool {
      let defaultStr = defaultValue ? "Y/n" : "y/N"
      print("\(message) [\(defaultStr)]: ", terminator: "")
      fflush(stdout)
      
      guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
        return defaultValue
      }
      
      if input.isEmpty {
        return defaultValue
      }
      
      return input == "y" || input == "yes"
    }
    
    private func parseMemoryString(_ str: String) -> UInt64? {
      let cleaned = str.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
      let numberStr = cleaned.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)
      
      guard let value = Double(numberStr) else {
        return nil
      }
      
      if cleaned.hasSuffix("G") || cleaned.hasSuffix("GB") {
        return UInt64(value * 1024 * 1024 * 1024)
      } else if cleaned.hasSuffix("M") || cleaned.hasSuffix("MB") {
        return UInt64(value * 1024 * 1024)
      } else if cleaned.hasSuffix("K") || cleaned.hasSuffix("KB") {
        return UInt64(value * 1024)
      } else {
        return UInt64(value)
      }
    }

    private func profileDirectory() -> URL {
      let home = FileManager.default.homeDirectoryForCurrentUser
      return home.appendingPathComponent(".hops/profiles")
    }

    private func templateToml(_ template: String, name: String) -> String {
      switch template {
      case "restrictive":
        return """
          name = "\(name)"
          version = "1.0.0"
          description = "Restrictive sandbox profile with minimal permissions"
          rootfs = "alpine-rootfs.ext4"

          [capabilities]
          network = "disabled"
          filesystem = []
          allowed_paths = ["."]
          denied_paths = ["/etc/shadow", "/etc/passwd", "/root/.ssh"]

          [capabilities.resource_limits]
          cpus = 1
          memory_bytes = 536870912
          max_processes = 50

          [sandbox]
          root_path = "/"
          working_directory = "/"
          hostname = "sandbox"
          """

      case "build":
        return """
          name = "\(name)"
          version = "1.0.0"
          description = "Build environment with network access for package downloads"
          rootfs = "alpine-rootfs.ext4"

          [capabilities]
          network = "outbound"
          filesystem = ["read", "write", "execute"]
          allowed_paths = ["/usr", "/lib", "/bin", "."]
          denied_paths = ["/etc/shadow", "/root/.ssh"]

          [capabilities.resource_limits]
          cpus = 4
          memory_bytes = 4294967296
          max_processes = 256

          [sandbox]
          root_path = "/"
          working_directory = "/"
          hostname = "build-sandbox"
          """

      case "network-only":
        return """
          name = "\(name)"
          version = "1.0.0"
          description = "Full network access with restricted filesystem"
          rootfs = "alpine-rootfs.ext4"

          [capabilities]
          network = "full"
          filesystem = ["read"]
          allowed_paths = ["."]
          denied_paths = ["/etc/shadow", "/etc/passwd", "/root/.ssh", "/var/run/docker.sock"]

          [capabilities.resource_limits]
          cpus = 2
          memory_bytes = 1073741824
          max_processes = 100

          [sandbox]
          root_path = "/"
          working_directory = "/"
          hostname = "network-sandbox"
          """

      default:
        return """
          name = "\(name)"
          version = "1.0.0"
          description = "Default sandbox profile"
          rootfs = "alpine-rootfs.ext4"

          [capabilities]
          network = "disabled"
          filesystem = ["read", "execute"]
          allowed_paths = ["."]
          denied_paths = ["/etc/shadow", "/etc/passwd"]

          [capabilities.resource_limits]
          cpus = 2
          memory_bytes = 536870912
          max_processes = 100

          [sandbox]
          root_path = "/"
          working_directory = "/"
          hostname = "sandbox"
          """
      }
    }
  }

  struct DeleteProfile: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "delete",
      abstract: "Delete a profile"
    )

    @Argument(help: "Name of the profile to delete")
    var name: String

    @Flag(name: .long, help: "Skip confirmation prompt")
    var yes: Bool = false

    func run() async throws {
      let profilePath = profileDirectory().appendingPathComponent("\(name).toml")

      guard FileManager.default.fileExists(atPath: profilePath.path) else {
        throw ValidationError("Profile '\(name)' not found")
      }

      if !yes {
        print("Delete profile '\(name)'? (y/N): ", terminator: "")
        guard let response = readLine()?.lowercased(), response == "y" || response == "yes" else {
          print("Cancelled.")
          return
        }
      }

      try FileManager.default.removeItem(at: profilePath)
      print("Deleted profile '\(name)'")
    }

    private func profileDirectory() -> URL {
      let home = FileManager.default.homeDirectoryForCurrentUser
      return home.appendingPathComponent(".hops/profiles")
    }
  }
}
