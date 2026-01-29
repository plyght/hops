import Foundation
import Containerization
import ContainerizationArchive

let homeDir = FileManager.default.homeDirectoryForCurrentUser
let hopsDir = homeDir.appendingPathComponent(".hops")
let alpineTarball = hopsDir.appendingPathComponent("alpine-minirootfs.tar.gz")
let alpineRootfs = hopsDir.appendingPathComponent("alpine-rootfs.ext4")

guard FileManager.default.fileExists(atPath: alpineTarball.path) else {
    print("Error: Alpine tarball not found at \(alpineTarball.path)")
    exit(1)
}

if FileManager.default.fileExists(atPath: alpineRootfs.path) {
    print("⚠️  Alpine rootfs already exists at \(alpineRootfs.path)")
    print("   Delete it first if you want to recreate it")
    exit(0)
}

print("Creating ext4 rootfs from Alpine tarball...")
print("  Source: \(alpineTarball.path)")
print("  Output: \(alpineRootfs.path)")
print("  This may take a minute...")

let unpacker = EXT4Unpacker(blockSizeInBytes: 512 * 1024 * 1024)
try unpacker.unpack(archive: alpineTarball, compression: ContainerizationArchive.Filter.gzip, at: alpineRootfs)

print("✅ Successfully created Alpine rootfs!")

let attrs = try FileManager.default.attributesOfItem(atPath: alpineRootfs.path)
if let fileSize = attrs[.size] as? UInt64 {
    let sizeMB = Double(fileSize) / (1024 * 1024)
    print("   Size: \(String(format: "%.1f", sizeMB)) MB")
}
print("   Path: \(alpineRootfs.path)")
