import Foundation

public struct OCIImageReference: Codable, Sendable, Equatable {
  public let registry: String
  public let repository: String
  public let tag: String

  public init(registry: String = "docker.io", repository: String, tag: String = "latest") {
    self.registry = registry
    self.repository = repository
    self.tag = tag
  }

  public static func parse(_ imageString: String) throws -> OCIImageReference {
    let components = imageString.split(separator: ":")
    let tag = components.count > 1 ? String(components[1]) : "latest"
    let repoString = String(components[0])

    let parts = repoString.split(separator: "/")
    let repository: String
    let registry: String

    if parts.count == 1 {
      registry = "docker.io"
      repository = "library/\(parts[0])"
    } else if parts.count == 2 {
      registry = "docker.io"
      repository = repoString
    } else {
      registry = String(parts[0])
      repository = parts.dropFirst().joined(separator: "/")
    }

    return OCIImageReference(registry: registry, repository: repository, tag: tag)
  }

  public var cacheKey: String {
    "\(registry)/\(repository)/\(tag)".replacingOccurrences(of: "/", with: "_")
  }
}

public struct OCIManifest: Codable, Sendable {
  public let schemaVersion: Int
  public let mediaType: String?
  public let config: OCIDescriptor
  public let layers: [OCIDescriptor]

  public init(
    schemaVersion: Int, mediaType: String?, config: OCIDescriptor, layers: [OCIDescriptor]
  ) {
    self.schemaVersion = schemaVersion
    self.mediaType = mediaType
    self.config = config
    self.layers = layers
  }
}

public struct OCIDescriptor: Codable, Sendable {
  public let mediaType: String
  public let size: Int64
  public let digest: String

  public init(mediaType: String, size: Int64, digest: String) {
    self.mediaType = mediaType
    self.size = size
    self.digest = digest
  }
}

public struct OCIImageConfig: Codable, Sendable {
  public struct Config: Codable, Sendable {
    public let env: [String]?
    public let cmd: [String]?
    public let workingDir: String?
    public let entrypoint: [String]?
    public let user: String?

    enum CodingKeys: String, CodingKey {
      case env = "Env"
      case cmd = "Cmd"
      case workingDir = "WorkingDir"
      case entrypoint = "Entrypoint"
      case user = "User"
    }

    public init(
      env: [String]?, cmd: [String]?, workingDir: String?, entrypoint: [String]?, user: String?
    ) {
      self.env = env
      self.cmd = cmd
      self.workingDir = workingDir
      self.entrypoint = entrypoint
      self.user = user
    }
  }

  public let config: Config

  public init(config: Config) {
    self.config = config
  }
}

public actor OCIImageManager {
  private let cacheDirectory: URL

  public init(cacheDirectory: URL? = nil) {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser
    self.cacheDirectory =
      cacheDirectory
      ?? homeDir
      .appendingPathComponent(".hops")
      .appendingPathComponent("cache")
      .appendingPathComponent("oci")
  }

  public func resolveImage(_ imageString: String) async throws -> URL {
    let imageRef = try OCIImageReference.parse(imageString)
    let imageCacheDir = cacheDirectory.appendingPathComponent(imageRef.cacheKey)
    let rootfsPath = imageCacheDir.appendingPathComponent("rootfs.ext4")

    if FileManager.default.fileExists(atPath: rootfsPath.path) {
      return rootfsPath
    }

    try FileManager.default.createDirectory(at: imageCacheDir, withIntermediateDirectories: true)

    let manifest = try await fetchManifest(imageRef: imageRef)
    let layers = try await downloadLayers(
      imageRef: imageRef, manifest: manifest, cacheDir: imageCacheDir)

    let mergedTar = try await mergeLayers(layers: layers, outputDir: imageCacheDir)
    let rootfs = try await convertToExt4(tarPath: mergedTar, outputPath: rootfsPath)

    return rootfs
  }

  public func getImageConfig(_ imageString: String) async throws -> OCIImageConfig? {
    let imageRef = try OCIImageReference.parse(imageString)
    let imageCacheDir = cacheDirectory.appendingPathComponent(imageRef.cacheKey)
    let configPath = imageCacheDir.appendingPathComponent("config.json")

    guard FileManager.default.fileExists(atPath: configPath.path) else {
      return nil
    }

    let data = try Data(contentsOf: configPath)
    return try JSONDecoder().decode(OCIImageConfig.self, from: data)
  }

  private func fetchManifest(imageRef: OCIImageReference) async throws -> OCIManifest {
    let url = manifestURL(imageRef: imageRef)
    var request = URLRequest(url: url)
    request.setValue(
      "application/vnd.docker.distribution.manifest.v2+json", forHTTPHeaderField: "Accept")
    request.setValue("application/vnd.oci.image.manifest.v1+json", forHTTPHeaderField: "Accept")

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
      throw OCIImageError.fetchFailed(
        "Failed to fetch manifest: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
    }

    return try JSONDecoder().decode(OCIManifest.self, from: data)
  }

  private func downloadLayers(imageRef: OCIImageReference, manifest: OCIManifest, cacheDir: URL)
    async throws -> [URL] {
    let layersDir = cacheDir.appendingPathComponent("layers")
    try FileManager.default.createDirectory(at: layersDir, withIntermediateDirectories: true)

    var layerPaths: [URL] = []

    for (index, layer) in manifest.layers.enumerated() {
      let digest = layer.digest.replacingOccurrences(of: "sha256:", with: "")
      let layerPath = layersDir.appendingPathComponent("\(index)-\(digest).tar.gz")

      if !FileManager.default.fileExists(atPath: layerPath.path) {
        let url = blobURL(imageRef: imageRef, digest: layer.digest)
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
          throw OCIImageError.fetchFailed(
            "Failed to download layer: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        try data.write(to: layerPath)
      }

      layerPaths.append(layerPath)
    }

    let configPath = cacheDir.appendingPathComponent("config.json")
    if !FileManager.default.fileExists(atPath: configPath.path) {
      let url = blobURL(imageRef: imageRef, digest: manifest.config.digest)
      let (data, response) = try await URLSession.shared.data(from: url)

      guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        throw OCIImageError.fetchFailed(
          "Failed to download config: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
      }

      try data.write(to: configPath)
    }

    return layerPaths
  }

  private func mergeLayers(layers: [URL], outputDir: URL) async throws -> URL {
    let mergedDir = outputDir.appendingPathComponent("merged")
    try FileManager.default.createDirectory(at: mergedDir, withIntermediateDirectories: true)

    for layer in layers {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
      process.arguments = ["-xzf", layer.path, "-C", mergedDir.path]

      try process.run()
      process.waitUntilExit()

      guard process.terminationStatus == 0 else {
        throw OCIImageError.extractionFailed("Failed to extract layer: \(layer.lastPathComponent)")
      }
    }

    let mergedTarPath = outputDir.appendingPathComponent("merged.tar")
    let tarProcess = Process()
    tarProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    tarProcess.arguments = ["-cf", mergedTarPath.path, "-C", mergedDir.path, "."]

    try tarProcess.run()
    tarProcess.waitUntilExit()

    guard tarProcess.terminationStatus == 0 else {
      throw OCIImageError.extractionFailed("Failed to create merged tarball")
    }

    try FileManager.default.removeItem(at: mergedDir)

    return mergedTarPath
  }

  private func convertToExt4(tarPath: URL, outputPath: URL) async throws -> URL {
    let createProcess = Process()
    createProcess.executableURL = URL(fileURLWithPath: "/usr/bin/dd")
    createProcess.arguments = ["if=/dev/zero", "of=\(outputPath.path)", "bs=1m", "count=1024"]

    try createProcess.run()
    createProcess.waitUntilExit()

    guard createProcess.terminationStatus == 0 else {
      throw OCIImageError.conversionFailed("Failed to create disk image")
    }

    let mkfsProcess = Process()
    mkfsProcess.executableURL = URL(fileURLWithPath: "/sbin/mkfs.ext4")
    mkfsProcess.arguments = ["-F", outputPath.path]

    try mkfsProcess.run()
    mkfsProcess.waitUntilExit()

    guard mkfsProcess.terminationStatus == 0 else {
      throw OCIImageError.conversionFailed("Failed to format ext4 filesystem")
    }

    let mountPoint = outputPath.deletingPathExtension().appendingPathExtension("mnt")
    try? FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

    let mountProcess = Process()
    mountProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    mountProcess.arguments = ["mount", "-o", "loop", outputPath.path, mountPoint.path]

    try mountProcess.run()
    mountProcess.waitUntilExit()

    guard mountProcess.terminationStatus == 0 else {
      throw OCIImageError.conversionFailed("Failed to mount ext4 filesystem")
    }

    let extractProcess = Process()
    extractProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    extractProcess.arguments = ["tar", "-xf", tarPath.path, "-C", mountPoint.path]

    try extractProcess.run()
    extractProcess.waitUntilExit()

    guard extractProcess.terminationStatus == 0 else {
      _ = try? Process.run(
        URL(fileURLWithPath: "/usr/bin/sudo"), arguments: ["umount", mountPoint.path])
      throw OCIImageError.conversionFailed("Failed to extract tarball to filesystem")
    }

    let umountProcess = Process()
    umountProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    umountProcess.arguments = ["umount", mountPoint.path]

    try umountProcess.run()
    umountProcess.waitUntilExit()

    try? FileManager.default.removeItem(at: mountPoint)

    return outputPath
  }

  private func manifestURL(imageRef: OCIImageReference) -> URL {
    let baseURL = "https://registry-1.docker.io"
    return URL(string: "\(baseURL)/v2/\(imageRef.repository)/manifests/\(imageRef.tag)")!
  }

  private func blobURL(imageRef: OCIImageReference, digest: String) -> URL {
    let baseURL = "https://registry-1.docker.io"
    return URL(string: "\(baseURL)/v2/\(imageRef.repository)/blobs/\(digest)")!
  }
}

public enum OCIImageError: Error {
  case invalidImageFormat(String)
  case fetchFailed(String)
  case extractionFailed(String)
  case conversionFailed(String)
}

extension OCIImageError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidImageFormat(let message):
      return "Invalid OCI image format: \(message)"
    case .fetchFailed(let message):
      return "Failed to fetch OCI image: \(message)"
    case .extractionFailed(let message):
      return "Failed to extract OCI layers: \(message)"
    case .conversionFailed(let message):
      return "Failed to convert OCI image to ext4: \(message)"
    }
  }
}
