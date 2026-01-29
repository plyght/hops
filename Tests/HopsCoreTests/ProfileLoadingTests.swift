import XCTest

@testable import HopsCore

final class ProfileLoadingTests: XCTestCase {
  var parser: PolicyParser!

  override func setUp() {
    super.setUp()
    parser = PolicyParser()
  }

  func testLoadDefaultProfile() throws {
    let policy = try Policy.load(fromTOMLFile: "config/default.toml")
    XCTAssertEqual(policy.name, "default")
    XCTAssertEqual(policy.version, "1.0.0")
    XCTAssertEqual(policy.capabilities.network, .disabled)
    XCTAssertTrue(policy.capabilities.filesystem.contains(.read))
    XCTAssertTrue(policy.capabilities.filesystem.contains(.execute))
    XCTAssertEqual(policy.capabilities.resourceLimits?.cpus, 2)
    XCTAssertEqual(policy.capabilities.resourceLimits?.memoryBytes, 536_870_912)
    XCTAssertEqual(policy.capabilities.resourceLimits?.maxProcesses, 100)
  }

  func testLoadUntrustedProfile() throws {
    let policy = try Policy.load(fromTOMLFile: "config/examples/untrusted.toml")
    XCTAssertEqual(policy.name, "untrusted")
    XCTAssertEqual(policy.capabilities.network, .disabled)
    XCTAssertTrue(policy.capabilities.filesystem.contains(.read))
    XCTAssertEqual(policy.capabilities.resourceLimits?.cpus, 1)
    XCTAssertEqual(policy.capabilities.resourceLimits?.memoryBytes, 268_435_456)
    XCTAssertEqual(policy.capabilities.resourceLimits?.maxProcesses, 10)
    XCTAssertEqual(policy.sandbox.workingDirectory, "/sandbox")
  }

  func testLoadBuildProfile() throws {
    let policy = try Policy.load(fromTOMLFile: "config/examples/build.toml")
    XCTAssertEqual(policy.name, "build")
    XCTAssertEqual(policy.capabilities.network, .outbound)
    XCTAssertTrue(policy.capabilities.filesystem.contains(.read))
    XCTAssertTrue(policy.capabilities.filesystem.contains(.write))
    XCTAssertTrue(policy.capabilities.filesystem.contains(.execute))
    XCTAssertNotNil(policy.capabilities.resourceLimits)
    XCTAssertEqual(policy.capabilities.resourceLimits?.cpus, 8)
    XCTAssertEqual(policy.capabilities.resourceLimits?.memoryBytes, 8_589_934_592)
    XCTAssertEqual(policy.capabilities.resourceLimits?.maxProcesses, 512)
    XCTAssertEqual(policy.sandbox.hostname, "build-sandbox")
  }

  func testLoadMinimalProfile() throws {
    let policy = try Policy.load(fromTOMLFile: "config/examples/minimal.toml")
    XCTAssertEqual(policy.name, "minimal")
    XCTAssertEqual(policy.capabilities.network, .disabled)
  }

  func testLoadDevelopmentProfile() throws {
    let policy = try Policy.load(fromTOMLFile: "config/examples/development.toml")
    XCTAssertEqual(policy.name, "development")
  }

  func testLoadNetworkAllowedProfile() throws {
    let policy = try Policy.load(fromTOMLFile: "config/examples/network-allowed.toml")
    XCTAssertEqual(policy.name, "network-allowed")
    XCTAssertNotEqual(policy.capabilities.network, .disabled)
  }

  func testLoadCIProfile() throws {
    let policy = try Policy.load(fromTOMLFile: "config/examples/ci.toml")
    XCTAssertEqual(policy.name, "ci")
  }

  func testProfileWithRootfsField() throws {
    let toml = """
      name = "custom-rootfs"
      version = "1.0.0"
      rootfs = "alpine-rootfs.ext4"

      [capabilities]
      network = "disabled"

      [sandbox]
      root_path = "/"
      """

    let policy = try parser.parse(fromString: toml)
    XCTAssertEqual(policy.name, "custom-rootfs")
    XCTAssertEqual(policy.rootfs, "alpine-rootfs.ext4")
  }

  func testProfileWithAbsoluteRootfsPath() throws {
    let toml = """
      name = "absolute-rootfs"
      version = "1.0.0"
      rootfs = "/custom/path/rootfs.ext4"

      [capabilities]
      network = "disabled"

      [sandbox]
      root_path = "/"
      """

    let policy = try parser.parse(fromString: toml)
    XCTAssertEqual(policy.rootfs, "/custom/path/rootfs.ext4")
  }

  func testProfileWithTildeRootfsPath() throws {
    let toml = """
      name = "tilde-rootfs"
      version = "1.0.0"
      rootfs = "~/custom/rootfs.ext4"

      [capabilities]
      network = "disabled"

      [sandbox]
      root_path = "/"
      """

    let policy = try parser.parse(fromString: toml)
    XCTAssertEqual(policy.rootfs, "~/custom/rootfs.ext4")
  }

  func testProfileWithoutRootfsField() throws {
    let toml = """
      name = "no-rootfs"
      version = "1.0.0"

      [capabilities]
      network = "disabled"

      [sandbox]
      root_path = "/"
      """

    let policy = try parser.parse(fromString: toml)
    XCTAssertNil(policy.rootfs)
  }

  func testLoadNonexistentProfile() {
    XCTAssertThrowsError(try Policy.load(fromTOMLFile: "config/nonexistent.toml")) { error in
      if case PolicyParserError.fileNotFound = error {
        return
      }
      XCTFail("Expected fileNotFound error, got \(error)")
    }
  }
}
