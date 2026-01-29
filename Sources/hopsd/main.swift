import Foundation
import Dispatch

@main
struct HopsdMain {
    static func main() async throws {
        let daemon = HopsDaemon()
        
        let signalSource = DispatchSource.makeSignalSource(
            signal: SIGTERM,
            queue: .main
        )
        signalSource.setEventHandler {
            Task {
                await daemon.shutdown()
                exit(0)
            }
        }
        signalSource.resume()
        
        let intSource = DispatchSource.makeSignalSource(
            signal: SIGINT,
            queue: .main
        )
        intSource.setEventHandler {
            Task {
                await daemon.shutdown()
                exit(0)
            }
        }
        intSource.resume()
        
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        
        print("hopsd starting...")
        try await daemon.start()
        
        try await Task.sleep(for: .seconds(Int.max))
    }
}
