import ArgumentParser
import Foundation

@main
struct Hops: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "hops",
    abstract: "Hops - Lightweight sandboxing for untrusted code",
    discussion: """
      Hops provides process isolation with fine-grained capability control.
      Run untrusted code safely with filesystem, network, and resource restrictions.

      Examples:
        hops run ./project -- python script.py
        hops run --profile untrusted ./code -- npm test
        hops profile list
        hops system start
      """,
    version: "0.1.0",
    subcommands: [
      RunCommand.self,
      ProfileCommand.self,
      SystemCommand.self,
      RootfsCommand.self
    ]
  )
}
