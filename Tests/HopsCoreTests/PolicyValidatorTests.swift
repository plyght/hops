import XCTest

@testable import HopsCore

final class PolicyValidatorTests: XCTestCase {
  var validator: PolicyValidator!

  override func setUp() {
    super.setUp()
    validator = PolicyValidator()
  }

  func testValidPolicyPasses() throws {
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      capabilities: CapabilityGrant(
        network: .disabled,
        filesystem: [.read],
        allowedPaths: ["/usr"],
        deniedPaths: [],
        resourceLimits: ResourceLimits(cpus: 2, memoryBytes: 1_073_741_824, maxProcesses: 100)
      ),
      sandbox: SandboxConfig(
        rootPath: "/",
        mounts: [],
        hostname: "test",
        workingDirectory: "/"
      )
    )

    XCTAssertNoThrow(try validator.validate(policy))
  }

  func testEmptyNameThrowsError() {
    let policy = Policy(
      name: "",
      version: "1.0.0"
    )

    XCTAssertThrowsError(try validator.validate(policy)) { error in
      XCTAssertTrue(error is PolicyValidationError)
      if case PolicyValidationError.emptyName = error {
        XCTAssertTrue(true)
      } else {
        XCTFail("Expected emptyName error")
      }
    }
  }

  func testInvalidVersionFormatThrowsError() {
    let invalidVersions = ["1.0", "v1.0.0", "1.0.0.0", "abc", "1.0.0-beta", ""]

    for version in invalidVersions {
      let policy = Policy(name: "test", version: version)
      XCTAssertThrowsError(try validator.validate(policy)) { error in
        if case PolicyValidationError.invalidVersion = error {
          XCTAssertTrue(true)
        } else {
          XCTFail("Expected invalidVersion error for: \(version)")
        }
      }
    }
  }

  func testValidVersionFormatsPass() throws {
    let validVersions = ["1.0.0", "0.0.1", "999.999.999", "1.2.3"]

    for version in validVersions {
      let policy = Policy(name: "test", version: version)
      XCTAssertNoThrow(try validator.validate(policy), "Version should be valid: \(version)")
    }
  }

  func testNonAbsoluteAllowedPathThrowsError() {
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      capabilities: CapabilityGrant(allowedPaths: ["relative/path"])
    )

    XCTAssertThrowsError(try validator.validate(policy)) { error in
      if case PolicyValidationError.mountSourceNotAbsolute = error {
        XCTAssertTrue(true)
      } else {
        XCTFail("Expected mountSourceNotAbsolute error")
      }
    }
  }

  func testNonAbsoluteDeniedPathThrowsError() {
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      capabilities: CapabilityGrant(deniedPaths: ["../somewhere"])
    )

    XCTAssertThrowsError(try validator.validate(policy)) { error in
      if case PolicyValidationError.mountSourceNotAbsolute = error {
        XCTAssertTrue(true)
      } else {
        XCTFail("Expected mountSourceNotAbsolute error")
      }
    }
  }

  func testConflictingAllowedDeniedPathsThrowsError() {
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      capabilities: CapabilityGrant(
        allowedPaths: ["/usr/local"],
        deniedPaths: ["/usr"]
      )
    )

    XCTAssertThrowsError(try validator.validate(policy)) { error in
      if case PolicyValidationError.conflictingPaths = error {
        XCTAssertTrue(true)
      } else {
        XCTFail("Expected conflictingPaths error")
      }
    }
  }

  func testConflictingPathsReversedThrowsError() {
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      capabilities: CapabilityGrant(
        allowedPaths: ["/usr"],
        deniedPaths: ["/usr/local"]
      )
    )

    XCTAssertThrowsError(try validator.validate(policy)) { error in
      if case PolicyValidationError.conflictingPaths = error {
        XCTAssertTrue(true)
      } else {
        XCTFail("Expected conflictingPaths error")
      }
    }
  }

  func testCPULimitTooHighThrowsError() {
    let validator = PolicyValidator(maxCPUs: 8)
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      capabilities: CapabilityGrant(
        resourceLimits: ResourceLimits(cpus: 16)
      )
    )

    XCTAssertThrowsError(try validator.validate(policy)) { error in
      if case PolicyValidationError.resourceLimitTooHigh(let resource, let value) = error {
        XCTAssertEqual(resource, "cpus")
        XCTAssertEqual(value, 16)
      } else {
        XCTFail("Expected resourceLimitTooHigh error")
      }
    }
  }

  func testMemoryLimitTooHighThrowsError() {
    let validator = PolicyValidator(maxMemoryBytes: 1_073_741_824)
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      capabilities: CapabilityGrant(
        resourceLimits: ResourceLimits(memoryBytes: 2_147_483_648)
      )
    )

    XCTAssertThrowsError(try validator.validate(policy)) { error in
      if case PolicyValidationError.resourceLimitTooHigh(let resource, let value) = error {
        XCTAssertEqual(resource, "memory")
        XCTAssertEqual(value, 2_147_483_648)
      } else {
        XCTFail("Expected resourceLimitTooHigh error")
      }
    }
  }

  func testProcessLimitTooHighThrowsError() {
    let validator = PolicyValidator(maxProcesses: 100)
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      capabilities: CapabilityGrant(
        resourceLimits: ResourceLimits(maxProcesses: 200)
      )
    )

    XCTAssertThrowsError(try validator.validate(policy)) { error in
      if case PolicyValidationError.resourceLimitTooHigh(let resource, let value) = error {
        XCTAssertEqual(resource, "max_processes")
        XCTAssertEqual(value, 200)
      } else {
        XCTFail("Expected resourceLimitTooHigh error")
      }
    }
  }

  func testCPULimitTooLowThrowsError() {
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      capabilities: CapabilityGrant(
        resourceLimits: ResourceLimits(cpus: 0)
      )
    )

    XCTAssertThrowsError(try validator.validate(policy)) { error in
      if case PolicyValidationError.resourceLimitTooLow(let resource, let value) = error {
        XCTAssertEqual(resource, "cpus")
        XCTAssertEqual(value, 0)
      } else {
        XCTFail("Expected resourceLimitTooLow error")
      }
    }
  }

  func testMemoryLimitTooLowThrowsError() {
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      capabilities: CapabilityGrant(
        resourceLimits: ResourceLimits(memoryBytes: 1024)
      )
    )

    XCTAssertThrowsError(try validator.validate(policy)) { error in
      if case PolicyValidationError.resourceLimitTooLow(let resource, let value) = error {
        XCTAssertEqual(resource, "memory")
        XCTAssertEqual(value, 1024)
      } else {
        XCTFail("Expected resourceLimitTooLow error")
      }
    }
  }

  func testProcessLimitTooLowThrowsError() {
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      capabilities: CapabilityGrant(
        resourceLimits: ResourceLimits(maxProcesses: 0)
      )
    )

    XCTAssertThrowsError(try validator.validate(policy)) { error in
      if case PolicyValidationError.resourceLimitTooLow(let resource, let value) = error {
        XCTAssertEqual(resource, "max_processes")
        XCTAssertEqual(value, 0)
      } else {
        XCTFail("Expected resourceLimitTooLow error")
      }
    }
  }

  func testMinimumResourceLimitsBoundaryPass() throws {
    let validator = PolicyValidator(
      minMemoryBytes: 1_048_576,
      minCPUs: 1,
      minProcesses: 1
    )
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      capabilities: CapabilityGrant(
        resourceLimits: ResourceLimits(
          cpus: 1,
          memoryBytes: 1_048_576,
          maxProcesses: 1
        )
      )
    )

    XCTAssertNoThrow(try validator.validate(policy))
  }

  func testResourceLimitsWithinBoundariesPass() throws {
    let validator = PolicyValidator(
      maxMemoryBytes: 8_589_934_592,
      maxCPUs: 16,
      maxProcesses: 1024
    )
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      capabilities: CapabilityGrant(
        resourceLimits: ResourceLimits(
          cpus: 16,
          memoryBytes: 8_589_934_592,
          maxProcesses: 1024
        )
      )
    )

    XCTAssertNoThrow(try validator.validate(policy))
  }

  func testNonAbsoluteRootPathThrowsError() {
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      sandbox: SandboxConfig(rootPath: "relative/path")
    )

    XCTAssertThrowsError(try validator.validate(policy)) { error in
      if case PolicyValidationError.invalidRootPath = error {
        XCTAssertTrue(true)
      } else {
        XCTFail("Expected invalidRootPath error")
      }
    }
  }

  func testNonAbsoluteWorkingDirectoryThrowsError() {
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      sandbox: SandboxConfig(workingDirectory: "relative/path")
    )

    XCTAssertThrowsError(try validator.validate(policy)) { error in
      if case PolicyValidationError.invalidWorkingDirectory = error {
        XCTAssertTrue(true)
      } else {
        XCTFail("Expected invalidWorkingDirectory error")
      }
    }
  }

  func testNonAbsoluteMountSourceThrowsError() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let testPath = tempDir.appendingPathComponent("test_mount").path
    try FileManager.default.createDirectory(atPath: testPath, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: testPath) }

    let policy = Policy(
      name: "test",
      version: "1.0.0",
      sandbox: SandboxConfig(
        mounts: [
          MountConfig(
            source: "relative/path",
            destination: "/mnt",
            type: .bind
          )
        ]
      )
    )

    XCTAssertThrowsError(try validator.validate(policy)) { error in
      if case PolicyValidationError.mountSourceNotAbsolute = error {
        XCTAssertTrue(true)
      } else {
        XCTFail("Expected mountSourceNotAbsolute error")
      }
    }
  }

  func testNonAbsoluteMountDestinationThrowsError() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let testPath = tempDir.appendingPathComponent("test_mount_src").path
    try FileManager.default.createDirectory(atPath: testPath, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: testPath) }

    let policy = Policy(
      name: "test",
      version: "1.0.0",
      sandbox: SandboxConfig(
        mounts: [
          MountConfig(
            source: testPath,
            destination: "relative/dest",
            type: .bind
          )
        ]
      )
    )

    XCTAssertThrowsError(try validator.validate(policy)) { error in
      if case PolicyValidationError.mountDestinationNotAbsolute = error {
        XCTAssertTrue(true)
      } else {
        XCTFail("Expected mountDestinationNotAbsolute error")
      }
    }
  }

  func testMountSourceNotExistsThrowsError() {
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      sandbox: SandboxConfig(
        mounts: [
          MountConfig(
            source: "/nonexistent/path/12345",
            destination: "/mnt",
            type: .bind
          )
        ]
      )
    )

    XCTAssertThrowsError(try validator.validate(policy)) { error in
      if case PolicyValidationError.invalidRootPath = error {
        XCTAssertTrue(true)
      } else {
        XCTFail("Expected invalidRootPath error for non-existent mount source")
      }
    }
  }

  func testConflictingMountDestinationsThrowsError() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let testPath1 = tempDir.appendingPathComponent("test_mount1").path
    let testPath2 = tempDir.appendingPathComponent("test_mount2").path
    try FileManager.default.createDirectory(atPath: testPath1, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(atPath: testPath2, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(atPath: testPath1)
      try? FileManager.default.removeItem(atPath: testPath2)
    }

    let policy = Policy(
      name: "test",
      version: "1.0.0",
      sandbox: SandboxConfig(
        mounts: [
          MountConfig(source: testPath1, destination: "/mnt", type: .bind),
          MountConfig(source: testPath2, destination: "/mnt/sub", type: .bind)
        ]
      )
    )

    XCTAssertThrowsError(try validator.validate(policy)) { error in
      if case PolicyValidationError.conflictingPaths = error {
        XCTAssertTrue(true)
      } else {
        XCTFail("Expected conflictingPaths error")
      }
    }
  }

  func testTmpfsMountDoesNotRequireExistingSource() throws {
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      sandbox: SandboxConfig(
        mounts: [
          MountConfig(source: "tmpfs", destination: "/tmp", type: .tmpfs, mode: .readWrite)
        ]
      )
    )

    XCTAssertNoThrow(try validator.validate(policy))
  }

  func testReadWriteAccessToSensitivePathThrowsError() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let testPath = tempDir.appendingPathComponent("test_sensitive").path
    try FileManager.default.createDirectory(atPath: testPath, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: testPath) }

    let policy = Policy(
      name: "test",
      version: "1.0.0",
      sandbox: SandboxConfig(
        mounts: [
          MountConfig(
            source: testPath,
            destination: "/etc/shadow",
            type: .bind,
            mode: .readWrite
          )
        ]
      )
    )

    XCTAssertThrowsError(try validator.validate(policy)) { error in
      if case PolicyValidationError.insecureMountConfiguration = error {
        XCTAssertTrue(true)
      } else {
        XCTFail("Expected insecureMountConfiguration error")
      }
    }
  }

  func testReadOnlyAccessToSensitivePathAllowed() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let testPath = tempDir.appendingPathComponent("test_ro_sensitive").path
    try FileManager.default.createDirectory(atPath: testPath, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: testPath) }

    let policy = Policy(
      name: "test",
      version: "1.0.0",
      sandbox: SandboxConfig(
        mounts: [
          MountConfig(
            source: testPath,
            destination: "/etc/passwd",
            type: .bind,
            mode: .readOnly
          )
        ]
      )
    )

    XCTAssertNoThrow(try validator.validate(policy))
  }

  func testMountingToSudoersDirectoryThrowsError() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let testPath = tempDir.appendingPathComponent("test_sudoers").path
    try FileManager.default.createDirectory(atPath: testPath, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: testPath) }

    let policy = Policy(
      name: "test",
      version: "1.0.0",
      sandbox: SandboxConfig(
        mounts: [
          MountConfig(
            source: testPath,
            destination: "/etc/sudoers",
            type: .bind,
            mode: .readWrite
          )
        ]
      )
    )

    XCTAssertThrowsError(try validator.validate(policy)) { error in
      if case PolicyValidationError.insecureMountConfiguration = error {
        XCTAssertTrue(true)
      } else {
        XCTFail("Expected insecureMountConfiguration error")
      }
    }
  }

  func testSymlinkToSensitivePathThrowsError() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let linkPath = tempDir.appendingPathComponent("symlink_test").path

    if FileManager.default.fileExists(atPath: linkPath) {
      try FileManager.default.removeItem(atPath: linkPath)
    }

    try FileManager.default.createSymbolicLink(
      atPath: linkPath,
      withDestinationPath: "/etc/shadow"
    )
    defer { try? FileManager.default.removeItem(atPath: linkPath) }

    let policy = Policy(
      name: "test",
      version: "1.0.0",
      sandbox: SandboxConfig(
        mounts: [
          MountConfig(
            source: linkPath,
            destination: "/mnt",
            type: .bind
          )
        ]
      )
    )

    XCTAssertThrowsError(try validator.validate(policy)) { error in
      XCTAssertTrue(error is PolicyValidationError)
    }
  }

  func testMountSourceOverlappingSensitivePathThrowsError() throws {
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      sandbox: SandboxConfig(
        mounts: [
          MountConfig(
            source: "/etc/shadow",
            destination: "/mnt",
            type: .bind
          )
        ]
      )
    )

    XCTAssertThrowsError(try validator.validate(policy)) { error in
      XCTAssertTrue(error is PolicyValidationError)
    }
  }

  func testMultipleValidMountsPass() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let testPath1 = tempDir.appendingPathComponent("valid_mount1").path
    let testPath2 = tempDir.appendingPathComponent("valid_mount2").path
    try FileManager.default.createDirectory(atPath: testPath1, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(atPath: testPath2, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(atPath: testPath1)
      try? FileManager.default.removeItem(atPath: testPath2)
    }

    let policy = Policy(
      name: "test",
      version: "1.0.0",
      sandbox: SandboxConfig(
        mounts: [
          MountConfig(source: testPath1, destination: "/mnt1", type: .bind),
          MountConfig(source: testPath2, destination: "/mnt2", type: .bind),
          MountConfig(source: "tmpfs", destination: "/tmp", type: .tmpfs, mode: .readWrite)
        ]
      )
    )

    XCTAssertNoThrow(try validator.validate(policy))
  }
}
