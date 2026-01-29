import Foundation

public enum PathUtils {
  public static func resolveRootfsPath(_ rootfs: String?) -> URL? {
    guard let rootfs = rootfs else {
      return nil
    }
    
    let homeDir = FileManager.default.homeDirectoryForCurrentUser
    
    if rootfs.hasPrefix("/") || rootfs.hasPrefix("~") {
      let expandedPath = NSString(string: rootfs).expandingTildeInPath
      return URL(fileURLWithPath: expandedPath)
    } else {
      return homeDir
        .appendingPathComponent(".hops")
        .appendingPathComponent(rootfs)
    }
  }
}
