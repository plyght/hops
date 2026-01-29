import ArgumentParser
import Foundation

struct ShellCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "shell",
    abstract: "Start an interactive shell in a sandboxed environment",
    discussion: """
      Shortcut for 'hops run -- /bin/sh' with interactive TTY enabled.

      Examples:
        hops shell
        hops shell --profile untrusted
        hops shell --network disabled --path /tmp
      """
  )

  @Option(name: .long, help: "Root directory for the sandbox (defaults to current directory or /tmp)")
  var path: String?

  @Option(name: .long, help: "Named profile to use (default, untrusted, build, etc.)")
  var profile: String?

  @Option(name: .long, help: "Network capability: disabled, outbound, loopback, full")
  var network: String?

  @Option(name: .long, help: "CPU limit (number of cores, e.g., 2 or 0.5)")
  var cpus: Double?

  @Option(name: .long, help: "Memory limit (e.g., 512M, 2G)")
  var memory: String?

  @Option(name: .long, help: "Maximum number of processes")
  var maxProcesses: UInt?

  @Option(name: .long, help: "OCI image to use (e.g., alpine:3.19, ubuntu:22.04)")
  var image: String?

  @Flag(name: .long, help: "Enable verbose output")
  var verbose: Bool = false

  @Flag(name: .long, help: "Keep container directory after execution")
  var keep: Bool = false

  @Flag(name: .long, help: "Disable automatic daemon startup")
  var noAutoStart: Bool = false

  mutating func run() async throws {
    var runCommand = RunCommand()
    runCommand.path = path
    runCommand.profile = profile
    runCommand.network = network
    runCommand.cpus = cpus
    runCommand.memory = memory
    runCommand.maxProcesses = maxProcesses
    runCommand.image = image
    runCommand.verbose = verbose
    runCommand.stream = true
    runCommand.keep = keep
    runCommand.interactive = true
    runCommand.noAutoStart = noAutoStart
    runCommand.command = ["/bin/sh"]

    try await runCommand.run()
  }
}
