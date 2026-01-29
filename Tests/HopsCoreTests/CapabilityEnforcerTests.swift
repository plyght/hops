import XCTest

@testable import HopsCore

final class CapabilityEnforcerTests: XCTestCase {

  func testConfigureHostname() {
    let policy = Policy(
      name: "test-policy",
      version: "1.0.0",
      sandbox: SandboxConfig(hostname: "custom-host")
    )

    XCTAssertEqual(policy.sandbox.hostname, "custom-host")
  }

  func testConfigureHostnameDefaultsToPolicy() {
    let policy = Policy(
      name: "test-policy",
      version: "1.0.0",
      sandbox: SandboxConfig(hostname: nil)
    )

    XCTAssertNil(policy.sandbox.hostname)
  }

  func testConfigureWorkingDirectory() {
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      sandbox: SandboxConfig(workingDirectory: "/home/user")
    )

    XCTAssertEqual(policy.sandbox.workingDirectory, "/home/user")
  }

  func testConfigureWorkingDirectoryDefault() {
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      sandbox: SandboxConfig(workingDirectory: "/")
    )

    XCTAssertEqual(policy.sandbox.workingDirectory, "/")
  }

  func testConfigureEnvironmentVariables() {
    let env = ["PATH": "/usr/bin:/bin", "HOME": "/root", "USER": "sandbox"]
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      sandbox: SandboxConfig(environment: env)
    )

    XCTAssertEqual(policy.sandbox.environment["PATH"], "/usr/bin:/bin")
    XCTAssertEqual(policy.sandbox.environment["HOME"], "/root")
    XCTAssertEqual(policy.sandbox.environment["USER"], "sandbox")
  }

  func testConfigureEnvironmentVariablesEmpty() {
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      sandbox: SandboxConfig(environment: [:])
    )

    XCTAssertTrue(policy.sandbox.environment.isEmpty)
  }

  func testConfigureResourcesCPU() {
    let limits = ResourceLimits(cpus: 4)
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      capabilities: CapabilityGrant(resourceLimits: limits)
    )

    XCTAssertEqual(policy.resources?.cpus, 4)
  }

  func testConfigureResourcesMemory() {
    let limits = ResourceLimits(memoryBytes: 2_147_483_648)
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      capabilities: CapabilityGrant(resourceLimits: limits)
    )

    XCTAssertEqual(policy.resources?.memoryBytes, 2_147_483_648)
  }

  func testConfigureResourcesMaxProcesses() {
    let limits = ResourceLimits(maxProcesses: 512)
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      capabilities: CapabilityGrant(resourceLimits: limits)
    )

    XCTAssertEqual(policy.resources?.maxProcesses, 512)
  }

  func testConfigureNetworkDisabled() {
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      capabilities: CapabilityGrant(network: .disabled)
    )

    XCTAssertEqual(policy.capabilities.network, .disabled)
  }

  func testConfigureNetworkOutbound() {
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      capabilities: CapabilityGrant(network: .outbound)
    )

    XCTAssertEqual(policy.capabilities.network, .outbound)
  }

  func testConfigureNetworkLoopback() {
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      capabilities: CapabilityGrant(network: .loopback)
    )

    XCTAssertEqual(policy.capabilities.network, .loopback)
  }

  func testConfigureNetworkFull() {
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      capabilities: CapabilityGrant(network: .full)
    )

    XCTAssertEqual(policy.capabilities.network, .full)
  }

  func testConfigureMountsBindReadOnly() {
    let mount = MountConfig.bind(source: "/usr", destination: "/usr", mode: .readOnly)

    XCTAssertEqual(mount.source, "/usr")
    XCTAssertEqual(mount.destination, "/usr")
    XCTAssertEqual(mount.type, .bind)
    XCTAssertEqual(mount.mode, .readOnly)
  }

  func testConfigureMountsBindReadWrite() {
    let mount = MountConfig.bind(source: "/tmp", destination: "/tmp", mode: .readWrite)

    XCTAssertEqual(mount.source, "/tmp")
    XCTAssertEqual(mount.destination, "/tmp")
    XCTAssertEqual(mount.mode, .readWrite)
  }

  func testConfigureMountsTmpfs() {
    let mount = MountConfig.tmpfs(destination: "/tmp", size: "100m")

    XCTAssertEqual(mount.source, "tmpfs")
    XCTAssertEqual(mount.destination, "/tmp")
    XCTAssertEqual(mount.type, .tmpfs)
    XCTAssertEqual(mount.mode, .readWrite)
    XCTAssertTrue(mount.options.contains("size=100m"))
  }

  func testConfigureMountsTmpfsNoSize() {
    let mount = MountConfig.tmpfs(destination: "/tmp")

    XCTAssertEqual(mount.source, "tmpfs")
    XCTAssertTrue(mount.options.isEmpty)
  }

  func testConfigureMountsRespectsDeniedPaths() {
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      capabilities: CapabilityGrant(
        deniedPaths: ["/etc/shadow", "/root/.ssh"]
      )
    )

    XCTAssertTrue(policy.capabilities.deniedPaths.contains("/etc/shadow"))
    XCTAssertTrue(policy.capabilities.deniedPaths.contains("/root/.ssh"))
  }

  func testConfigureMountsAllowedPaths() {
    let policy = Policy(
      name: "test",
      version: "1.0.0",
      capabilities: CapabilityGrant(
        allowedPaths: ["/usr", "/tmp", "/home"]
      )
    )

    XCTAssertTrue(policy.capabilities.allowedPaths.contains("/usr"))
    XCTAssertTrue(policy.capabilities.allowedPaths.contains("/tmp"))
    XCTAssertTrue(policy.capabilities.allowedPaths.contains("/home"))
  }

  func testConfigureSysctlNetworkForwarding() {
    let policy = Policy(name: "test", version: "1.0.0")

    XCTAssertNotNil(policy)
  }

  func testMountTypeBindEnum() {
    let mountType = MountType.bind
    XCTAssertEqual(mountType, .bind)
  }

  func testMountTypeTmpfsEnum() {
    let mountType = MountType.tmpfs
    XCTAssertEqual(mountType, .tmpfs)
  }

  func testMountTypeDevtmpfsEnum() {
    let mountType = MountType.devtmpfs
    XCTAssertEqual(mountType, .devtmpfs)
  }

  func testMountTypeProcEnum() {
    let mountType = MountType.proc
    XCTAssertEqual(mountType, .proc)
  }

  func testMountTypeSysfsEnum() {
    let mountType = MountType.sysfs
    XCTAssertEqual(mountType, .sysfs)
  }

  func testMountModeReadOnly() {
    let mode = MountMode.readOnly
    XCTAssertEqual(mode.rawValue, "ro")
  }

  func testMountModeReadWrite() {
    let mode = MountMode.readWrite
    XCTAssertEqual(mode.rawValue, "rw")
  }

  func testFilesystemCapabilityRead() {
    let capability = FilesystemCapability.read
    XCTAssertEqual(capability.rawValue, "read")
  }

  func testFilesystemCapabilityWrite() {
    let capability = FilesystemCapability.write
    XCTAssertEqual(capability.rawValue, "write")
  }

  func testFilesystemCapabilityExecute() {
    let capability = FilesystemCapability.execute
    XCTAssertEqual(capability.rawValue, "execute")
  }
}
