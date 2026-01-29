import Foundation
import Containerization

actor HopsDaemon {
    private let socketPath: String
    private var sandboxManager: SandboxManager?
    private var containerService: ContainerService?
    private var isRunning = false
    private var startTime: Date?
    private var activeSandboxCount: Int = 0
    
    init(socketPath: String? = nil) {
        if let socketPath = socketPath {
            self.socketPath = socketPath
        } else {
            let homeDir = FileManager.default.homeDirectoryForCurrentUser
            let hopsDir = homeDir.appendingPathComponent(".hops")
            self.socketPath = hopsDir.appendingPathComponent("hops.sock").path
        }
    }
    
    func start() async throws {
        guard !isRunning else {
            print("hopsd already running")
            return
        }
        
        try prepareSocketDirectory()
        removeExistingSocket()
        try writePidFile()
        startTime = Date()
        
        do {
            sandboxManager = try await SandboxManager(daemon: self)
            print("Sandbox manager initialized")
            fflush(stdout)
        } catch let error as SandboxManagerError {
            print("Error: \(error.localizedDescription)")
            fflush(stdout)
            removePidFile()
            throw error
        } catch {
            print("Failed to initialize sandbox manager: \(error)")
            fflush(stdout)
            removePidFile()
            throw error
        }
        
        print("Creating container service...")
        fflush(stdout)
        
        containerService = ContainerService(
            socketPath: socketPath,
            sandboxManager: sandboxManager,
            daemon: self
        )
        
        print("Starting gRPC server...")
        fflush(stdout)
        
        try await containerService?.start()
        
        print("Setting socket permissions...")
        fflush(stdout)
        
        try setSocketPermissions()
        
        isRunning = true
        
        print("hopsd listening on unix://\(socketPath)")
        fflush(stdout)
    }
    
    func shutdown() async {
        guard isRunning else { return }
        
        print("hopsd shutting down...")
        
        await containerService?.stop()
        await sandboxManager?.cleanup()
        
        removeExistingSocket()
        removePidFile()
        isRunning = false
        
        print("hopsd stopped")
    }
    
    private func prepareSocketDirectory() throws {
        let socketURL = URL(fileURLWithPath: socketPath)
        let directory = socketURL.deletingLastPathComponent()
        
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }
    
    func setSocketPermissions() throws {
        guard FileManager.default.fileExists(atPath: socketPath) else {
            return
        }
        
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: socketPath
        )
    }
    
    private func removeExistingSocket() {
        if FileManager.default.fileExists(atPath: socketPath) {
            try? FileManager.default.removeItem(atPath: socketPath)
        }
    }
    
    private func writePidFile() throws {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let pidFile = homeDir.appendingPathComponent(".hops/hopsd.pid")
        let pid = ProcessInfo.processInfo.processIdentifier
        try String(pid).write(to: pidFile, atomically: true, encoding: .utf8)
    }
    
    private func removePidFile() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let pidFile = homeDir.appendingPathComponent(".hops/hopsd.pid")
        try? FileManager.default.removeItem(at: pidFile)
    }
    
    func getDaemonStatus() async -> DaemonStatusInfo {
        let pid = ProcessInfo.processInfo.processIdentifier
        return DaemonStatusInfo(
            pid: pid,
            startTime: startTime ?? Date(),
            activeSandboxes: activeSandboxCount
        )
    }
    
    func incrementActiveSandboxCount() {
        activeSandboxCount += 1
    }
    
    func decrementActiveSandboxCount() {
        if activeSandboxCount > 0 {
            activeSandboxCount -= 1
        }
    }
}

struct DaemonStatusInfo {
    let pid: Int32
    let startTime: Date
    let activeSandboxes: Int
}
