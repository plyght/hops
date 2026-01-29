import Foundation

public struct DaemonManager {
  private let homeDir = FileManager.default.homeDirectoryForCurrentUser
  
  public init() {}
  
  public func isRunning() async -> Bool {
    let pidFile = homeDir.appendingPathComponent(".hops/hopsd.pid")
    
    guard FileManager.default.fileExists(atPath: pidFile.path),
      let pidString = try? String(contentsOf: pidFile, encoding: .utf8),
      let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines))
    else {
      return false
    }
    
    return kill(pid, 0) == 0
  }
  
  public func ensureRunning(verbose: Bool = false) async throws {
    if await isRunning() {
      return
    }
    
    if verbose {
      print("Hops: Starting daemon...")
    }
    
    try await startDaemon()
    
    for attempt in 0..<20 {
      try await Task.sleep(nanoseconds: 250_000_000)
      
      if await isRunning() {
        if verbose {
          print("Hops: Daemon started successfully")
        }
        return
      }
      
      if attempt == 19 {
        throw DaemonManagerError.startTimeout
      }
    }
  }
  
  private func startDaemon() async throws {
    let hopsdPath = findHopsdBinary()
    
    guard FileManager.default.fileExists(atPath: hopsdPath) else {
      throw DaemonManagerError.binaryNotFound(hopsdPath)
    }
    
    let process = Process()
    process.executableURL = URL(fileURLWithPath: hopsdPath)
    process.arguments = ["--daemon"]
    
    let logDir = homeDir.appendingPathComponent(".hops/logs")
    try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    
    let logFile = logDir.appendingPathComponent("hopsd.log")
    FileManager.default.createFile(atPath: logFile.path, contents: nil)
    
    let logHandle = try FileHandle(forWritingTo: logFile)
    process.standardOutput = logHandle
    process.standardError = logHandle
    
    try process.run()
    process.waitUntilExit()
  }
  
  private func findHopsdBinary() -> String {
    let searchPaths = [
      "/usr/local/bin/hopsd",
      "/usr/bin/hopsd",
      homeDir.appendingPathComponent(".local/bin/hopsd").path,
      ".build/debug/hopsd",
      ".build/release/hopsd"
    ]
    
    for path in searchPaths where FileManager.default.fileExists(atPath: path) {
      return path
    }
    
    return "hopsd"
  }
}

public enum DaemonManagerError: Error, LocalizedError {
  case binaryNotFound(String)
  case startTimeout
  case notRunning
  
  public var errorDescription: String? {
    switch self {
    case .binaryNotFound(let path):
      return """
        hopsd binary not found at \(path)
        
        Install hopsd:
        1. Build: swift build
        2. Sign: codesign -s - --entitlements hopsd.entitlements --force .build/debug/hopsd
        3. Install: sudo cp .build/debug/hopsd /usr/local/bin/
        """
      
    case .startTimeout:
      return """
        Daemon failed to start within 5 seconds
        
        Check logs at ~/.hops/logs/hopsd.log for errors
        Required files:
          - ~/.hops/vmlinux (Linux kernel)
          - ~/.hops/initfs (init filesystem)
          - ~/.hops/alpine-rootfs.ext4 (rootfs)
        """
      
    case .notRunning:
      return """
        Daemon is not running
        
        Start it with: hops system start
        Or it will start automatically on next run
        """
    }
  }
}
