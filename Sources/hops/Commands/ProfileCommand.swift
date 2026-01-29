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
