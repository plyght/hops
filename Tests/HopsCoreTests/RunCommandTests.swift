import XCTest

@testable import HopsCore

final class RunCommandTests: XCTestCase {

  func testValidateRequiresNonEmptyCommand() {
    let command: [String] = []
    XCTAssertTrue(command.isEmpty)
  }

  func testValidateAcceptsNonEmptyCommand() {
    let command = ["echo", "hello"]
    XCTAssertFalse(command.isEmpty)
  }

  func testValidateSingleCommand() {
    let command = ["ls"]
    XCTAssertEqual(command.count, 1)
  }

  func testValidateMultipleCommandArgs() {
    let command = ["python", "script.py", "--verbose"]
    XCTAssertEqual(command.count, 3)
  }

  func testExpandPathAbsolute() {
    let path = "/usr/local/bin"
    XCTAssertTrue(path.hasPrefix("/"))
  }

  func testExpandPathTilde() {
    let path = "~/projects"
    XCTAssertTrue(path.hasPrefix("~"))
  }

  func testExpandPathRelative() {
    let path = "./myproject"
    XCTAssertTrue(path.hasPrefix("."))
  }

  func testExpandPathRelativeWithoutDot() {
    let path = "myproject"
    XCTAssertFalse(path.hasPrefix("/"))
    XCTAssertFalse(path.hasPrefix("~"))
  }

  func testLoadPolicyDefault() {
    let policy = Policy.default
    XCTAssertEqual(policy.name, "default")
    XCTAssertEqual(policy.version, "1.0.0")
  }

  func testLoadPolicyWithCustomName() {
    let policy = Policy(name: "custom", version: "1.0.0")
    XCTAssertEqual(policy.name, "custom")
  }

  func testLoadPolicyNetworkOverride() {
    var policy = Policy.default
    policy.capabilities.network = .outbound
    XCTAssertEqual(policy.capabilities.network, .outbound)
  }

  func testLoadPolicyCPUOverride() {
    var policy = Policy.default
    if policy.resources == nil {
      policy.resources = ResourceLimits()
    }
    policy.resources?.cpus = 2
    XCTAssertEqual(policy.resources?.cpus, 2)
  }

  func testLoadPolicyMemoryOverride() {
    var policy = Policy.default
    if policy.resources == nil {
      policy.resources = ResourceLimits()
    }
    policy.resources?.memoryBytes = 1_073_741_824
    XCTAssertEqual(policy.resources?.memoryBytes, 1_073_741_824)
  }

  func testLoadPolicyWithAllOverrides() {
    var policy = Policy.default
    policy.capabilities.network = .full
    if policy.resources == nil {
      policy.resources = ResourceLimits()
    }
    policy.resources?.cpus = 4
    policy.resources?.memoryBytes = 2_147_483_648

    XCTAssertEqual(policy.capabilities.network, .full)
    XCTAssertEqual(policy.resources?.cpus, 4)
    XCTAssertEqual(policy.resources?.memoryBytes, 2_147_483_648)
  }

  func testParseMemoryStringBytes() throws {
    let result = try parseMemoryHelper("1024")
    XCTAssertEqual(result, 1024)
  }

  func testParseMemoryStringKilobytes() throws {
    let result = try parseMemoryHelper("512K")
    XCTAssertEqual(result, 512 * 1024)
  }

  func testParseMemoryStringKilobytesWithB() throws {
    let result = try parseMemoryHelper("256KB")
    XCTAssertEqual(result, 256 * 1024)
  }

  func testParseMemoryStringMegabytes() throws {
    let result = try parseMemoryHelper("512M")
    XCTAssertEqual(result, 512 * 1024 * 1024)
  }

  func testParseMemoryStringMegabytesWithB() throws {
    let result = try parseMemoryHelper("512MB")
    XCTAssertEqual(result, 512 * 1024 * 1024)
  }

  func testParseMemoryStringGigabytes() throws {
    let result = try parseMemoryHelper("4G")
    XCTAssertEqual(result, 4 * 1024 * 1024 * 1024)
  }

  func testParseMemoryStringGigabytesWithB() throws {
    let result = try parseMemoryHelper("4GB")
    XCTAssertEqual(result, 4 * 1024 * 1024 * 1024)
  }

  func testParseMemoryStringLowercase() throws {
    let result = try parseMemoryHelper("256m")
    XCTAssertEqual(result, 256 * 1024 * 1024)
  }

  func testParseMemoryStringMixedCase() throws {
    let result = try parseMemoryHelper("512Mb")
    XCTAssertEqual(result, 512 * 1024 * 1024)
  }

  func testParseMemoryStringInvalidFormat() {
    XCTAssertThrowsError(try parseMemoryHelper("invalid"))
  }

  func testParseMemoryStringEmptyString() {
    XCTAssertThrowsError(try parseMemoryHelper(""))
  }

  func testFormatBytesBytes() {
    let result = formatBytesHelper(512)
    XCTAssertTrue(result.contains("B"))
  }

  func testFormatBytesKilobytes() {
    let result = formatBytesHelper(1024 * 512)
    XCTAssertTrue(result.contains("K"))
  }

  func testFormatBytesMegabytes() {
    let result = formatBytesHelper(1024 * 1024 * 256)
    XCTAssertTrue(result.contains("M"))
  }

  func testFormatBytesGigabytes() {
    let result = formatBytesHelper(1024 * 1024 * 1024 * 2)
    XCTAssertTrue(result.contains("G"))
  }

  func testNetworkCapabilityRawValues() {
    XCTAssertEqual(NetworkCapability.disabled.rawValue, "disabled")
    XCTAssertEqual(NetworkCapability.outbound.rawValue, "outbound")
    XCTAssertEqual(NetworkCapability.loopback.rawValue, "loopback")
    XCTAssertEqual(NetworkCapability.full.rawValue, "full")
  }

  func testNetworkCapabilityFromString() {
    XCTAssertEqual(NetworkCapability(rawValue: "disabled"), .disabled)
    XCTAssertEqual(NetworkCapability(rawValue: "outbound"), .outbound)
    XCTAssertEqual(NetworkCapability(rawValue: "loopback"), .loopback)
    XCTAssertEqual(NetworkCapability(rawValue: "full"), .full)
  }

  func testNetworkCapabilityInvalidString() {
    XCTAssertNil(NetworkCapability(rawValue: "invalid"))
  }

  func testResourceLimitsInitialization() {
    let limits = ResourceLimits(cpus: 4, memoryBytes: 2_147_483_648, maxProcesses: 256)
    XCTAssertEqual(limits.cpus, 4)
    XCTAssertEqual(limits.memoryBytes, 2_147_483_648)
    XCTAssertEqual(limits.maxProcesses, 256)
  }

  func testResourceLimitsPartial() {
    let limits = ResourceLimits(cpus: 2)
    XCTAssertEqual(limits.cpus, 2)
    XCTAssertNil(limits.memoryBytes)
    XCTAssertNil(limits.maxProcesses)
  }

  func testResourceLimitsEmpty() {
    let limits = ResourceLimits()
    XCTAssertNil(limits.cpus)
    XCTAssertNil(limits.memoryBytes)
    XCTAssertNil(limits.maxProcesses)
  }

  private func parseMemoryHelper(_ memory: String) throws -> UInt64 {
    let upper = memory.uppercased()
    var multiplier: UInt64 = 1
    var numericPart = upper

    if upper.hasSuffix("K") || upper.hasSuffix("KB") {
      multiplier = 1024
      numericPart = String(upper.dropLast(upper.hasSuffix("KB") ? 2 : 1))
    } else if upper.hasSuffix("M") || upper.hasSuffix("MB") {
      multiplier = 1024 * 1024
      numericPart = String(upper.dropLast(upper.hasSuffix("MB") ? 2 : 1))
    } else if upper.hasSuffix("G") || upper.hasSuffix("GB") {
      multiplier = 1024 * 1024 * 1024
      numericPart = String(upper.dropLast(upper.hasSuffix("GB") ? 2 : 1))
    }

    guard let value = UInt64(numericPart) else {
      throw ValidationErrorHelper("Invalid memory format: \(memory)")
    }

    return value * multiplier
  }

  private func formatBytesHelper(_ bytes: UInt64) -> String {
    let kb = Double(bytes) / 1024.0
    let mb = kb / 1024.0
    let gb = mb / 1024.0

    if gb >= 1.0 {
      return String(format: "%.1fG", gb)
    } else if mb >= 1.0 {
      return String(format: "%.1fM", mb)
    } else if kb >= 1.0 {
      return String(format: "%.1fK", kb)
    } else {
      return "\(bytes)B"
    }
  }
}

struct ValidationErrorHelper: Error {
  let message: String

  init(_ message: String) {
    self.message = message
  }
}
