import Foundation

public struct ProfileInfo: Sendable {
  public let name: String
  public let path: URL
  public let location: ProfileLocation

  public init(name: String, path: URL, location: ProfileLocation) {
    self.name = name
    self.path = path
    self.location = location
  }
}

public enum ProfileLocation: String, Sendable {
  case user
  case config
  case examples
}

public struct ProfileManager: Sendable {
  public init() {}

  public func profileDirectories() -> [(ProfileLocation, URL)] {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    return [
      (.user, home.appendingPathComponent(".hops/profiles")),
      (.config, current.appendingPathComponent("config/profiles")),
      (.examples, current.appendingPathComponent("config/examples"))
    ]
  }

  public func listProfiles() throws -> [ProfileInfo] {
    var profiles: [ProfileInfo] = []

    for (location, directory) in profileDirectories() {
      guard FileManager.default.fileExists(atPath: directory.path) else {
        continue
      }

      let contents = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: .skipsHiddenFiles
      )

      for file in contents where file.pathExtension == "toml" {
        let name = file.deletingPathExtension().lastPathComponent
        profiles.append(ProfileInfo(name: name, path: file, location: location))
      }
    }

    return profiles.sorted { $0.name < $1.name }
  }

  public func findProfile(named name: String) -> ProfileInfo? {
    for (location, directory) in profileDirectories() {
      let candidate = directory.appendingPathComponent("\(name).toml")
      if FileManager.default.fileExists(atPath: candidate.path) {
        return ProfileInfo(name: name, path: candidate, location: location)
      }
    }
    return nil
  }

  public func loadProfile(named name: String) throws -> Policy {
    guard let profileInfo = findProfile(named: name) else {
      throw ProfileManagerError.profileNotFound(name)
    }
    return try Policy.load(fromTOMLFile: profileInfo.path.path)
  }
}

public enum ProfileManagerError: Error, CustomStringConvertible {
  case profileNotFound(String)

  public var description: String {
    switch self {
    case .profileNotFound(let name):
      return "Profile '\(name)' not found in any profile directory"
    }
  }
}
