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
        print("No profiles found.")
        print("Create your first profile with: hops profile create <name>")
        return
      }

      print("Available profiles:")
      for profile in profiles {
        let modDate = try? profile.path.resourceValues(forKeys: [.contentModificationDateKey])
          .contentModificationDate

        if let date = modDate {
          let formatter = DateFormatter()
          formatter.dateStyle = .medium
          formatter.timeStyle = .short
          print(
            "  \(profile.name) (\(profile.location.rawValue), modified: \(formatter.string(from: date)))"
          )
        } else {
          print("  \(profile.name) (\(profile.location.rawValue))")
        }
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
        print("Profile: \(name)")
        print("Location: \(profileInfo.location.rawValue)")
        print("Path: \(profileInfo.path.path)")
        print()
        print("Name: \(policy.name)")
        print("Version: \(policy.version)")
        if let description = policy.description {
          print("Description: \(description)")
        }
        if let rootfs = policy.rootfs {
          print("Rootfs: \(rootfs)")
        }
        if let ociImage = policy.ociImage {
          print("OCI Image: \(ociImage)")
        }
        print()
        print("Network: \(policy.capabilities.network)")
        print(
          "Filesystem: \(policy.capabilities.filesystem.map { $0.rawValue }.sorted().joined(separator: ", "))"
        )
        if !policy.capabilities.allowedPaths.isEmpty {
          print(
            "Allowed paths: \(policy.capabilities.allowedPaths.sorted().joined(separator: ", "))")
        }
        if !policy.capabilities.deniedPaths.isEmpty {
          print("Denied paths: \(policy.capabilities.deniedPaths.sorted().joined(separator: ", "))")
        }
        print()
        let limits = policy.capabilities.resourceLimits
        if limits.cpus != nil || limits.memoryBytes != nil || limits.maxProcesses != nil {
          print("Resource Limits:")
          if let cpus = limits.cpus {
            print("  CPUs: \(cpus)")
          }
          if let memory = limits.memoryBytes {
            print("  Memory: \(formatBytes(memory))")
          }
          if let maxProcs = limits.maxProcesses {
            print("  Max Processes: \(maxProcs)")
          }
        }
        print()
        print("Sandbox:")
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

    @Flag(name: .long, help: "Overwrite if profile already exists")
    var force: Bool = false

    func run() async throws {
      let profileDir = profileDirectory()
      try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)

      let profilePath = profileDir.appendingPathComponent("\(name).toml")

      if FileManager.default.fileExists(atPath: profilePath.path) && !force {
        throw ValidationError("Profile '\(name)' already exists. Use --force to overwrite.")
      }

      let toml = templateToml(template ?? "default", name: name)

      try toml.write(to: profilePath, atomically: true, encoding: .utf8)

      print("Created profile '\(name)' at \(profilePath.path)")
      print()
      print("Edit the profile:")
      print("  $EDITOR \(profilePath.path)")
      print()
      print("Use the profile:")
      print("  hops run --profile \(name) ./project -- command")
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
