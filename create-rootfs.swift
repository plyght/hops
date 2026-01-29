#!/usr/bin/env swift

import Foundation
import ContainerizationEXT4

let homeDir = FileManager.default.homeDirectoryForCurrentUser
let hopsDir = homeDir.appendingPathComponent(".hops")
let alpineTarball = hopsDir.appendingPathComponent("alpine-minirootfs.tar.gz")
let alpineRootfs = hopsDir.appendingPathComponent("alpine-rootfs.ext4")

guard FileManager.default.fileExists(atPath: alpineTarball.path) else {
    print("Error: Alpine tarball not found at \(alpineTarball.path)")
    exit(1)
}

print("Creating ext4 rootfs from Alpine tarball...")
print("  Source: \(alpineTarball.path)")
print("  Output: \(alpineRootfs.path)")

let unpacker = EXT4Unpacker(blockSizeInBytes: 512 * 1024 * 1024)
try unpacker.unpack(archive: alpineTarball, compression: .gzip, at: alpineRootfs)

print("✅ Successfully created Alpine rootfs at \(alpineRootfs.path)")

let fileSize = try FileManager.default.attributesOfItem(atPath: alpineRootfs.path)[.size] as! UInt64
let sizeMB = Double(fileSize) / (1024 * 1024)
print("   Size: \(String(format: "%.1f", sizeMB)) MB")
