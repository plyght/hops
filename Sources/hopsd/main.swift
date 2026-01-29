import Dispatch
import Foundation

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
fflush(stdout)

Task {
  do {
    try await daemon.start()
    print("hopsd started successfully")
    fflush(stdout)
  } catch {
    print("Fatal error starting daemon: \(error)")
    fflush(stdout)
    exit(1)
  }
}

print("Entering main loop...")
fflush(stdout)

dispatchMain()
