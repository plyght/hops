import ArgumentParser
import Foundation
import Containerization
import ContainerizationArchive
import HopsCore

struct RootfsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rootfs",
        abstract: "Manage filesystem images",
        discussion: """
            Rootfs images are ext4 filesystem images used as container root filesystems.
            They are stored in ~/.hops/rootfs/ and can be created from tarballs.
            
            Examples:
              hops rootfs list
              hops rootfs create alpine --from alpine-minirootfs.tar.gz
              hops rootfs create ubuntu --from ubuntu-base.tar.gz --size 1G
              hops rootfs delete alpine --force
            """,
        subcommands: [
            ListRootfs.self,
            CreateRootfs.self,
            DeleteRootfs.self
        ]
    )
}

extension RootfsCommand {
    struct ListRootfs: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List available rootfs images"
        )
        
        func run() async throws {
            let rootfsDir = rootfsDirectory()
            
            guard FileManager.default.fileExists(atPath: rootfsDir.path) else {
                print("No rootfs images found. Directory does not exist.")
                print("Create your first rootfs with: hops rootfs create <name> --from <tarball>")
                return
            }
            
            let contents = try FileManager.default.contentsOfDirectory(
                at: rootfsDir,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: .skipsHiddenFiles
            )
            
            let rootfsImages = contents.filter { $0.pathExtension == "ext4" }
            
            if rootfsImages.isEmpty {
                print("No rootfs images found.")
                print("Create your first rootfs with: hops rootfs create <name> --from <tarball>")
                return
            }
            
            print("Available rootfs images:")
            for image in rootfsImages.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = image.deletingPathExtension().lastPathComponent
                let attrs = try image.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                
                var output = "  \(name)"
                
                if let size = attrs.fileSize {
                    let sizeMB = Double(size) / (1024 * 1024)
                    output += String(format: "  %.0fM", sizeMB)
                }
                
                if let date = attrs.contentModificationDate {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "MMM dd yyyy"
                    output += "  \(formatter.string(from: date))"
                }
                
                print(output)
            }
        }
        
        private func rootfsDirectory() -> URL {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return home.appendingPathComponent(".hops/rootfs")
        }
    }
    
    struct CreateRootfs: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Create a rootfs image from a tarball"
        )
        
        @Argument(help: "Name for the rootfs image")
        var name: String
        
        @Option(name: .long, help: "Path to source tarball (tar.gz)")
        var from: String
        
        @Option(name: .long, help: "Rootfs size (default: 512M, supports K/M/G suffix)")
        var size: String = "512M"
        
        @Flag(name: .long, help: "Overwrite if rootfs already exists")
        var force: Bool = false
        
        func run() async throws {
            let tarballPath = URL(fileURLWithPath: (from as NSString).expandingTildeInPath)
            
            guard FileManager.default.fileExists(atPath: tarballPath.path) else {
                throw ValidationError("Tarball not found at \(tarballPath.path)")
            }
            
            let rootfsDir = rootfsDirectory()
            try FileManager.default.createDirectory(at: rootfsDir, withIntermediateDirectories: true)
            
            let rootfsPath = rootfsDir.appendingPathComponent("\(name).ext4")
            
            if FileManager.default.fileExists(atPath: rootfsPath.path) && !force {
                throw ValidationError("Rootfs '\(name)' already exists. Use --force to overwrite.")
            }
            
            if FileManager.default.fileExists(atPath: rootfsPath.path) {
                try FileManager.default.removeItem(at: rootfsPath)
            }
            
            let sizeBytes = try parseSizeString(size)
            
            try checkDiskSpace(requiredBytes: UInt64(sizeBytes), at: rootfsDir)
            
            print("Creating ext4 rootfs from tarball...")
            print("  Source: \(tarballPath.path)")
            print("  Output: \(rootfsPath.path)")
            print("  Size: \(size)")
            print("  This may take a minute...")
            
            let unpacker = EXT4Unpacker(blockSizeInBytes: UInt64(sizeBytes))
            try unpacker.unpack(archive: tarballPath, compression: ContainerizationArchive.Filter.gzip, at: rootfsPath)
            
            try setFilePermissions(at: rootfsPath, permissions: 0o644)
            
            print("Successfully created rootfs '\(name)'!")
            
            let attrs = try FileManager.default.attributesOfItem(atPath: rootfsPath.path)
            if let fileSize = attrs[.size] as? UInt64 {
                let sizeMB = Double(fileSize) / (1024 * 1024)
                print("  Size: \(String(format: "%.1f", sizeMB)) MB")
            }
            print("  Path: \(rootfsPath.path)")
        }
        
        private func rootfsDirectory() -> URL {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return home.appendingPathComponent(".hops/rootfs")
        }
        
        private func parseSizeString(_ sizeStr: String) throws -> Int {
            let str = sizeStr.uppercased()
            var multiplier = 1
            var numStr = str
            
            if str.hasSuffix("K") {
                multiplier = 1024
                numStr = String(str.dropLast())
            } else if str.hasSuffix("M") {
                multiplier = 1024 * 1024
                numStr = String(str.dropLast())
            } else if str.hasSuffix("G") {
                multiplier = 1024 * 1024 * 1024
                numStr = String(str.dropLast())
            }
            
            guard let num = Int(numStr) else {
                throw ValidationError("Invalid size format: \(sizeStr). Use format like 512M, 1G, 2048K")
            }
            
            return num * multiplier
        }
        
        private func checkDiskSpace(requiredBytes: UInt64, at directory: URL) throws {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: directory.path)
            
            guard let freeSpace = attrs[.systemFreeSize] as? UInt64 else {
                throw ValidationError("Unable to determine available disk space")
            }
            
            let requiredWithBuffer = UInt64(Double(requiredBytes) * 1.2)
            
            if freeSpace < requiredWithBuffer {
                let freeMB = Double(freeSpace) / (1024 * 1024)
                let requiredMB = Double(requiredWithBuffer) / (1024 * 1024)
                throw ValidationError("""
                    Insufficient disk space.
                    
                    Required: \(String(format: "%.0f", requiredMB)) MB (with 20% buffer)
                    Available: \(String(format: "%.0f", freeMB)) MB
                    
                    Free up space or use a smaller --size value.
                    """)
            }
        }
        
        private func setFilePermissions(at path: URL, permissions: mode_t) throws {
            let result = chmod(path.path, permissions)
            if result != 0 {
                throw ValidationError("Failed to set file permissions: \(String(cString: strerror(errno)))")
            }
        }
    }
    
    struct DeleteRootfs: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Delete a rootfs image"
        )
        
        @Argument(help: "Name of the rootfs to delete")
        var name: String
        
        @Flag(name: .long, help: "Skip confirmation prompt")
        var force: Bool = false
        
        func run() async throws {
            let rootfsDir = rootfsDirectory()
            let rootfsPath = rootfsDir.appendingPathComponent("\(name).ext4")
            
            guard FileManager.default.fileExists(atPath: rootfsPath.path) else {
                throw ValidationError("Rootfs '\(name)' not found")
            }
            
            try checkLastRootfs(at: rootfsDir, deletingName: name)
            
            let profilesUsingRootfs = try checkProfileReferences(rootfsName: name)
            if !profilesUsingRootfs.isEmpty {
                print("Warning: The following profiles reference this rootfs:")
                for profile in profilesUsingRootfs {
                    print("  - \(profile)")
                }
                print()
            }
            
            if !force {
                print("Delete rootfs '\(name)'? (y/N): ", terminator: "")
                guard let response = readLine()?.lowercased(), response == "y" || response == "yes" else {
                    print("Cancelled.")
                    return
                }
            }
            
            try FileManager.default.removeItem(at: rootfsPath)
            print("Deleted rootfs '\(name)'")
            
            if !profilesUsingRootfs.isEmpty {
                print()
                print("Note: Update affected profiles to reference a different rootfs.")
            }
        }
        
        private func rootfsDirectory() -> URL {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return home.appendingPathComponent(".hops/rootfs")
        }
        
        private func checkLastRootfs(at directory: URL, deletingName: String) throws {
            guard FileManager.default.fileExists(atPath: directory.path) else {
                return
            }
            
            let contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            
            let rootfsImages = contents.filter { $0.pathExtension == "ext4" }
            
            if rootfsImages.count == 1 && rootfsImages.first?.deletingPathExtension().lastPathComponent == deletingName {
                throw ValidationError("""
                    Cannot delete the last remaining rootfs.
                    
                    At least one rootfs must exist for containers to function.
                    Create a new rootfs before deleting '\(deletingName)':
                      hops rootfs create <name> --from <tarball>
                    """)
            }
        }
        
        private func checkProfileReferences(rootfsName: String) throws -> [String] {
            let profileDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hops/profiles")
            
            guard FileManager.default.fileExists(atPath: profileDir.path) else {
                return []
            }
            
            let contents = try FileManager.default.contentsOfDirectory(
                at: profileDir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            
            let profileFiles = contents.filter { $0.pathExtension == "toml" }
            
            var referencingProfiles: [String] = []
            
            for profileFile in profileFiles {
                do {
                    let parser = PolicyParser()
                    let policy = try parser.parse(fromFile: profileFile.path)
                    
                    if let rootfs = policy.rootfs, rootfs == rootfsName || rootfs == "\(rootfsName).ext4" {
                        referencingProfiles.append(profileFile.deletingPathExtension().lastPathComponent)
                    }
                } catch {
                    continue
                }
            }
            
            return referencingProfiles
        }
    }
}
