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
            let profileDir = profileDirectory()
            
            guard FileManager.default.fileExists(atPath: profileDir.path) else {
                print("No profiles found. Profile directory does not exist.")
                print("Create your first profile with: hops profile create <name>")
                return
            }
            
            let contents = try FileManager.default.contentsOfDirectory(
                at: profileDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            )
            
            let profiles = contents.filter { $0.pathExtension == "toml" }
            
            if profiles.isEmpty {
                print("No profiles found.")
                print("Create your first profile with: hops profile create <name>")
                return
            }
            
            print("Available profiles:")
            for profile in profiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = profile.deletingPathExtension().lastPathComponent
                let modDate = try? profile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                
                if let date = modDate {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .short
                    print("  \(name) (modified: \(formatter.string(from: date)))")
                } else {
                    print("  \(name)")
                }
            }
        }
        
        private func profileDirectory() -> URL {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return home.appendingPathComponent(".hops/profiles")
        }
    }
    
    struct ShowProfile: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "Display the contents of a profile"
        )
        
        @Argument(help: "Name of the profile to show")
        var name: String
        
        func run() async throws {
            let profilePath = profileDirectory().appendingPathComponent("\(name).toml")
            
            guard FileManager.default.fileExists(atPath: profilePath.path) else {
                throw ValidationError("Profile '\(name)' not found at \(profilePath.path)")
            }
            
            let contents = try String(contentsOf: profilePath, encoding: .utf8)
            
            print("Profile: \(name)")
            print("Path: \(profilePath.path)")
            print()
            print(contents)
        }
        
        private func profileDirectory() -> URL {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return home.appendingPathComponent(".hops/profiles")
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
            
            let policy = templatePolicy(template ?? "default")
            let toml = policy.toTOML()
            
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
        
        private func templatePolicy(_ template: String) -> Policy {
            switch template {
            case "restrictive":
                return Policy(
                    sandbox: SandboxConfig(
                        root: ".",
                        mounts: [],
                        workdir: "/"
                    ),
                    capabilities: CapabilityGrants(
                        network: .disabled,
                        filesystem: .restricted,
                        ipc: .none,
                        processes: .none
                    ),
                    resources: ResourceLimits(
                        cpus: 1.0,
                        memoryBytes: 512 * 1024 * 1024,
                        diskBytes: 1024 * 1024 * 1024
                    )
                )
            
            case "build":
                return Policy(
                    sandbox: SandboxConfig(
                        root: ".",
                        mounts: [],
                        workdir: "/"
                    ),
                    capabilities: CapabilityGrants(
                        network: .outbound,
                        filesystem: .restricted,
                        ipc: .local,
                        processes: .spawn
                    ),
                    resources: ResourceLimits(
                        cpus: 4.0,
                        memoryBytes: 4 * 1024 * 1024 * 1024,
                        diskBytes: nil
                    )
                )
            
            case "network-only":
                return Policy(
                    sandbox: SandboxConfig(
                        root: ".",
                        mounts: [],
                        workdir: "/"
                    ),
                    capabilities: CapabilityGrants(
                        network: .full,
                        filesystem: .restricted,
                        ipc: .none,
                        processes: .none
                    ),
                    resources: ResourceLimits(
                        cpus: 2.0,
                        memoryBytes: 1024 * 1024 * 1024,
                        diskBytes: nil
                    )
                )
            
            default:
                return Policy.default
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
