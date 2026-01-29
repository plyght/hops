import Foundation
import Containerization

actor HopsDaemon {
    private let socketPath: String
    private var sandboxManager: SandboxManager?
    private var containerService: ContainerService?
    private var isRunning = false
    
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
        
        sandboxManager = try await SandboxManager()
        print("Sandbox manager initialized")
        
        containerService = ContainerService(
            socketPath: socketPath,
            sandboxManager: sandboxManager
        )
        
        try await containerService?.start()
        
        try setSocketPermissions()
        
        isRunning = true
        
        print("hopsd listening on unix://\(socketPath)")
    }
    
    func shutdown() async {
        guard isRunning else { return }
        
        print("hopsd shutting down...")
        
        await containerService?.stop()
        await sandboxManager?.cleanup()
        
        removeExistingSocket()
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
}
