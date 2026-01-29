import XCTest

@testable import HopsCore

final class PolicyParserTests: XCTestCase {
  var parser: PolicyParser!

  override func setUp() {
    super.setUp()
    parser = PolicyParser()
  }

  func testParseValidBasicTOML() throws {
    let toml = """
      name = "test"
      version = "1.0.0"
      description = "Test policy"

      [capabilities]
      network = "disabled"
      filesystem = ["read"]
      """

    let policy = try parser.parse(fromString: toml)
    XCTAssertEqual(policy.name, "test")
    XCTAssertEqual(policy.version, "1.0.0")
    XCTAssertEqual(policy.description, "Test policy")
    XCTAssertEqual(policy.capabilities.network, .disabled)
    XCTAssertEqual(policy.capabilities.filesystem, [.read])
  }

  func testParseFullFeaturedTOML() throws {
    let toml = """
      name = "full-test"
      version = "2.1.3"
      description = "Full featured test"

      [capabilities]
      network = "outbound"
      filesystem = ["read", "write", "execute"]
      allowed_paths = ["/usr", "/tmp"]
      denied_paths = ["/etc/shadow"]

      [capabilities.resource_limits]
      cpus = 4
      memory_bytes = 4294967296
      max_processes = 256

      [sandbox]
      root_path = "/custom"
      hostname = "test-host"
      working_directory = "/work"

      [[sandbox.mounts]]
      source = "/usr"
      destination = "/usr"
      type = "bind"
      mode = "ro"

      [sandbox.environment]
      PATH = "/usr/bin"
      HOME = "/root"

      [metadata]
      author = "tester"
      """

    let policy = try parser.parse(fromString: toml)
    XCTAssertEqual(policy.name, "full-test")
    XCTAssertEqual(policy.version, "2.1.3")
    XCTAssertEqual(policy.capabilities.network, .outbound)
    XCTAssertEqual(policy.capabilities.filesystem, [.read, .write, .execute])
    XCTAssertTrue(policy.capabilities.allowedPaths.contains("/usr"))
    XCTAssertTrue(policy.capabilities.deniedPaths.contains("/etc/shadow"))
    XCTAssertEqual(policy.capabilities.resourceLimits.cpus, 4)
    XCTAssertEqual(policy.capabilities.resourceLimits.memoryBytes, 4_294_967_296)
    XCTAssertEqual(policy.capabilities.resourceLimits.maxProcesses, 256)
    XCTAssertEqual(policy.sandbox.rootPath, "/custom")
    XCTAssertEqual(policy.sandbox.hostname, "test-host")
    XCTAssertEqual(policy.sandbox.workingDirectory, "/work")
    XCTAssertEqual(policy.sandbox.mounts.count, 1)
    XCTAssertEqual(policy.sandbox.environment["PATH"], "/usr/bin")
    XCTAssertEqual(policy.metadata["author"], "tester")
  }

  func testParseMissingNameThrowsError() {
    let toml = """
      version = "1.0.0"
      description = "No name field"
      """

    XCTAssertThrowsError(try parser.parse(fromString: toml)) { error in
      if case PolicyParserError.missingRequiredField(let field) = error {
        XCTAssertEqual(field, "name")
      } else {
        XCTFail("Expected missingRequiredField error")
      }
    }
  }

  func testParseMissingVersionDefaultsTo1_0_0() throws {
    let toml = """
      name = "test"
      """

    let policy = try parser.parse(fromString: toml)
    XCTAssertEqual(policy.version, "1.0.0")
  }

  func testParseInvalidNetworkCapabilityThrowsError() {
    let toml = """
      name = "test"

      [capabilities]
      network = "invalid_network_type"
      """

    XCTAssertThrowsError(try parser.parse(fromString: toml)) { error in
      if case PolicyParserError.invalidFieldValue(let field, _) = error {
        XCTAssertEqual(field, "capabilities.network")
      } else {
        XCTFail("Expected invalidFieldValue error")
      }
    }
  }

  func testParseAllNetworkCapabilities() throws {
    for capability in NetworkCapability.allCases {
      let toml = """
        name = "test"

        [capabilities]
        network = "\(capability.rawValue)"
        """

      let policy = try parser.parse(fromString: toml)
      XCTAssertEqual(policy.capabilities.network, capability)
    }
  }

  func testParseInvalidFilesystemCapabilityThrowsError() {
    let toml = """
      name = "test"

      [capabilities]
      filesystem = ["read", "invalid_fs_type"]
      """

    XCTAssertThrowsError(try parser.parse(fromString: toml)) { error in
      if case PolicyParserError.invalidFieldValue(let field, _) = error {
        XCTAssertEqual(field, "capabilities.filesystem")
      } else {
        XCTFail("Expected invalidFieldValue error")
      }
    }
  }

  func testParseAllFilesystemCapabilities() throws {
    let capabilities = FilesystemCapability.allCases.map { $0.rawValue }.joined(separator: "\", \"")
    let toml = """
      name = "test"

      [capabilities]
      filesystem = ["\(capabilities)"]
      """

    let policy = try parser.parse(fromString: toml)
    XCTAssertEqual(policy.capabilities.filesystem.count, FilesystemCapability.allCases.count)
  }

  func testParseEmptyFilesystemArray() throws {
    let toml = """
      name = "test"

      [capabilities]
      filesystem = []
      """

    let policy = try parser.parse(fromString: toml)
    XCTAssertTrue(policy.capabilities.filesystem.isEmpty)
  }

  func testParseEmptyAllowedPaths() throws {
    let toml = """
      name = "test"

      [capabilities]
      allowed_paths = []
      """

    let policy = try parser.parse(fromString: toml)
    XCTAssertTrue(policy.capabilities.allowedPaths.isEmpty)
  }

  func testParseEmptyDeniedPaths() throws {
    let toml = """
      name = "test"

      [capabilities]
      denied_paths = []
      """

    let policy = try parser.parse(fromString: toml)
    XCTAssertTrue(policy.capabilities.deniedPaths.isEmpty)
  }

  func testParseMalformedTOMLThrowsError() {
    let toml = """
      name = "test
      this is not valid TOML
      [unclosed
      """

    XCTAssertThrowsError(try parser.parse(fromString: toml)) { error in
      if case PolicyParserError.invalidTOML = error {
        XCTAssertTrue(true)
      } else {
        XCTFail("Expected invalidTOML error")
      }
    }
  }

  func testParseEmptyStringThrowsError() {
    XCTAssertThrowsError(try parser.parse(fromString: "")) { error in
      if case PolicyParserError.missingRequiredField = error {
        XCTAssertTrue(true)
      } else {
        XCTFail("Expected missingRequiredField error")
      }
    }
  }

  func testParseWhitespaceOnlyThrowsError() {
    let toml = "   \n   \n   "
    XCTAssertThrowsError(try parser.parse(fromString: toml)) { error in
      if case PolicyParserError.missingRequiredField = error {
        XCTAssertTrue(true)
      } else {
        XCTFail("Expected missingRequiredField error")
      }
    }
  }

  func testParseResourceLimitsAllFields() throws {
    let toml = """
      name = "test"

      [capabilities.resource_limits]
      cpus = 8
      memory_bytes = 8589934592
      max_processes = 512
      """

    let policy = try parser.parse(fromString: toml)
    XCTAssertEqual(policy.capabilities.resourceLimits.cpus, 8)
    XCTAssertEqual(policy.capabilities.resourceLimits.memoryBytes, 8_589_934_592)
    XCTAssertEqual(policy.capabilities.resourceLimits.maxProcesses, 512)
  }

  func testParseResourceLimitsPartialFields() throws {
    let toml = """
      name = "test"

      [capabilities.resource_limits]
      cpus = 2
      """

    let policy = try parser.parse(fromString: toml)
    XCTAssertEqual(policy.capabilities.resourceLimits.cpus, 2)
    XCTAssertNil(policy.capabilities.resourceLimits.memoryBytes)
    XCTAssertNil(policy.capabilities.resourceLimits.maxProcesses)
  }

  func testParseMountMissingSourceThrowsError() {
    let toml = """
      name = "test"

      [[sandbox.mounts]]
      destination = "/mnt"
      type = "bind"
      """

    XCTAssertThrowsError(try parser.parse(fromString: toml)) { error in
      if case PolicyParserError.missingRequiredField(let field) = error {
        XCTAssertEqual(field, "mount.source")
      } else {
        XCTFail("Expected missingRequiredField error")
      }
    }
  }

  func testParseMountMissingDestinationThrowsError() {
    let toml = """
      name = "test"

      [[sandbox.mounts]]
      source = "/usr"
      type = "bind"
      """

    XCTAssertThrowsError(try parser.parse(fromString: toml)) { error in
      if case PolicyParserError.missingRequiredField(let field) = error {
        XCTAssertEqual(field, "mount.destination")
      } else {
        XCTFail("Expected missingRequiredField error")
      }
    }
  }

  func testParseMountInvalidTypeThrowsError() {
    let toml = """
      name = "test"

      [[sandbox.mounts]]
      source = "/usr"
      destination = "/mnt"
      type = "invalid_type"
      """

    XCTAssertThrowsError(try parser.parse(fromString: toml)) { error in
      if case PolicyParserError.invalidFieldValue(let field, _) = error {
        XCTAssertEqual(field, "mount.type")
      } else {
        XCTFail("Expected invalidFieldValue error")
      }
    }
  }

  func testParseMountInvalidModeThrowsError() {
    let toml = """
      name = "test"

      [[sandbox.mounts]]
      source = "/usr"
      destination = "/mnt"
      type = "bind"
      mode = "invalid_mode"
      """

    XCTAssertThrowsError(try parser.parse(fromString: toml)) { error in
      if case PolicyParserError.invalidFieldValue(let field, _) = error {
        XCTAssertEqual(field, "mount.mode")
      } else {
        XCTFail("Expected invalidFieldValue error")
      }
    }
  }

  func testParseMountDefaultsToBindAndReadOnly() throws {
    let toml = """
      name = "test"

      [[sandbox.mounts]]
      source = "/usr"
      destination = "/mnt"
      """

    let policy = try parser.parse(fromString: toml)
    XCTAssertEqual(policy.sandbox.mounts[0].type, .bind)
    XCTAssertEqual(policy.sandbox.mounts[0].mode, .readOnly)
  }

  func testParseMountWithOptions() throws {
    let toml = """
      name = "test"

      [[sandbox.mounts]]
      source = "tmpfs"
      destination = "/tmp"
      type = "tmpfs"
      mode = "rw"
      options = ["size=100m", "noexec"]
      """

    let policy = try parser.parse(fromString: toml)
    XCTAssertEqual(policy.sandbox.mounts[0].options, ["size=100m", "noexec"])
  }

  func testParseMultipleMounts() throws {
    let toml = """
      name = "test"

      [[sandbox.mounts]]
      source = "/usr"
      destination = "/usr"
      type = "bind"

      [[sandbox.mounts]]
      source = "tmpfs"
      destination = "/tmp"
      type = "tmpfs"
      mode = "rw"
      """

    let policy = try parser.parse(fromString: toml)
    XCTAssertEqual(policy.sandbox.mounts.count, 2)
    XCTAssertEqual(policy.sandbox.mounts[0].source, "/usr")
    XCTAssertEqual(policy.sandbox.mounts[1].source, "tmpfs")
  }

  func testParseSandboxEnvironment() throws {
    let toml = """
      name = "test"

      [sandbox.environment]
      PATH = "/usr/bin:/bin"
      HOME = "/root"
      CUSTOM = "value"
      """

    let policy = try parser.parse(fromString: toml)
    XCTAssertEqual(policy.sandbox.environment["PATH"], "/usr/bin:/bin")
    XCTAssertEqual(policy.sandbox.environment["HOME"], "/root")
    XCTAssertEqual(policy.sandbox.environment["CUSTOM"], "value")
  }

  func testParseSandboxDefaults() throws {
    let toml = """
      name = "test"
      """

    let policy = try parser.parse(fromString: toml)
    XCTAssertEqual(policy.sandbox.rootPath, "/")
    XCTAssertEqual(policy.sandbox.workingDirectory, "/")
  }

  func testParseMetadata() throws {
    let toml = """
      name = "test"

      [metadata]
      author = "John Doe"
      created = "2024-01-01"
      purpose = "testing"
      """

    let policy = try parser.parse(fromString: toml)
    XCTAssertEqual(policy.metadata["author"], "John Doe")
    XCTAssertEqual(policy.metadata["created"], "2024-01-01")
    XCTAssertEqual(policy.metadata["purpose"], "testing")
  }

  func testParseFileNotFoundThrowsError() {
    let path = "/nonexistent/path/policy.toml"
    XCTAssertThrowsError(try parser.parse(fromFile: path)) { error in
      if case PolicyParserError.fileNotFound(let filePath) = error {
        XCTAssertEqual(filePath, path)
      } else {
        XCTFail("Expected fileNotFound error")
      }
    }
  }

  func testParseValidFileFromFixtures() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let testFile = tempDir.appendingPathComponent("test_valid_basic.toml")

    let content = """
      name = "test-basic"
      version = "1.0.0"
      description = "Basic test policy"

      [capabilities]
      network = "disabled"
      filesystem = ["read"]
      allowed_paths = ["/usr"]
      denied_paths = []

      [sandbox]
      root_path = "/"
      working_directory = "/"
      """

    try content.write(to: testFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: testFile) }

    let policy = try parser.parse(fromFile: testFile.path)
    XCTAssertEqual(policy.name, "test-basic")
    XCTAssertEqual(policy.version, "1.0.0")
  }

  func testParseFullFileFromFixtures() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let testFile = tempDir.appendingPathComponent("test_valid_full.toml")

    let content = """
      name = "test-full"
      version = "2.1.3"
      description = "Full featured test policy"

      [capabilities]
      network = "outbound"
      filesystem = ["read", "write", "execute"]
      allowed_paths = ["/usr", "/tmp", "/var"]
      denied_paths = ["/etc/shadow"]

      [capabilities.resource_limits]
      cpus = 4
      memory_bytes = 4294967296
      max_processes = 256

      [sandbox]
      root_path = "/"
      hostname = "test-sandbox"
      working_directory = "/tmp"
      """

    try content.write(to: testFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: testFile) }

    let policy = try parser.parse(fromFile: testFile.path)
    XCTAssertEqual(policy.name, "test-full")
    XCTAssertEqual(policy.version, "2.1.3")
    XCTAssertEqual(policy.capabilities.network, .outbound)
    XCTAssertTrue(policy.capabilities.filesystem.contains(.read))
    XCTAssertTrue(policy.capabilities.filesystem.contains(.write))
  }

  func testParseRootfsFieldRelativePath() throws {
    let toml = """
      name = "test"
      rootfs = "alpine-rootfs.ext4"
      """

    let policy = try parser.parse(fromString: toml)
    XCTAssertEqual(policy.rootfs, "alpine-rootfs.ext4")
  }

  func testParseRootfsFieldAbsolutePath() throws {
    let toml = """
      name = "test"
      rootfs = "/custom/path/to/rootfs.ext4"
      """

    let policy = try parser.parse(fromString: toml)
    XCTAssertEqual(policy.rootfs, "/custom/path/to/rootfs.ext4")
  }

  func testParseRootfsFieldTildePath() throws {
    let toml = """
      name = "test"
      rootfs = "~/.hops/custom-rootfs.ext4"
      """

    let policy = try parser.parse(fromString: toml)
    XCTAssertEqual(policy.rootfs, "~/.hops/custom-rootfs.ext4")
  }

  func testParseRootfsFieldOptional() throws {
    let toml = """
      name = "test"
      """

    let policy = try parser.parse(fromString: toml)
    XCTAssertNil(policy.rootfs)
  }
}
