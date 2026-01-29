import ArgumentParser
import Foundation

struct ExecCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "exec",
    abstract: "Execute a command in a sandboxed environment (simplified interface)",
    discussion: """
      Simpler alternative to 'hops run' that doesn't require the -- separator.

      Examples:
        hops exec echo "Hello"
        hops exec python script.py
        hops exec --profile untrusted npm test
        hops exec --network disabled cargo build
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

  @Option(name: .long, help: "Path to custom policy TOML file")
  var policyFile: String?

  @Option(name: .long, help: "OCI image to use (e.g., alpine:3.19, ubuntu:22.04)")
  var image: String?

  @Flag(name: .long, help: "Enable verbose output")
  var verbose: Bool = false

  @Flag(name: .long, inversion: .prefixedNo, help: "Enable streaming output")
  var stream: Bool = true

  @Flag(name: .long, help: "Keep container directory after execution")
  var keep: Bool = false

  @Flag(name: .long, inversion: .prefixedNo, help: "Allocate TTY for interactive sessions (automatic when using a terminal)")
  var interactive: Bool = true

  @Flag(name: .long, help: "Disable automatic daemon startup")
  var noAutoStart: Bool = false

  @Argument(parsing: .remaining, help: "Command to execute inside the sandbox")
  var command: [String] = []

  func validate() throws {
    guard !command.isEmpty else {
      throw ValidationError("No command specified. Provide the command to execute.")
    }
  }

  mutating func run() async throws {
    var runCommand = RunCommand()
    runCommand.path = path
    runCommand.profile = profile
    runCommand.network = network
    runCommand.cpus = cpus
    runCommand.memory = memory
    runCommand.maxProcesses = maxProcesses
    runCommand.policyFile = policyFile
    runCommand.image = image
    runCommand.verbose = verbose
    runCommand.stream = stream
    runCommand.keep = keep
    runCommand.interactive = interactive
    runCommand.noAutoStart = noAutoStart
    runCommand.command = command

    try await runCommand.run()
  }
}
