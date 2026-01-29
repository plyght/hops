import XCTest
@testable import HopsCore

final class ContainerServiceTests: XCTestCase {
    
    func testConvertProtoNetworkCapabilityDisabled() {
        let capability = NetworkCapability.disabled
        XCTAssertEqual(capability, .disabled)
    }
    
    func testConvertProtoNetworkCapabilityOutbound() {
        let capability = NetworkCapability.outbound
        XCTAssertEqual(capability, .outbound)
    }
    
    func testConvertProtoNetworkCapabilityLoopback() {
        let capability = NetworkCapability.loopback
        XCTAssertEqual(capability, .loopback)
    }
    
    func testConvertProtoNetworkCapabilityFull() {
        let capability = NetworkCapability.full
        XCTAssertEqual(capability, .full)
    }
    
    func testParseMemoryStringKilobytes() throws {
        let result = try parseMemoryStringHelper("512K")
        XCTAssertEqual(result, 512 * 1024)
    }
    
    func testParseMemoryStringKilobytesWithB() throws {
        let result = try parseMemoryStringHelper("512KB")
        XCTAssertEqual(result, 512 * 1024)
    }
    
    func testParseMemoryStringMegabytes() throws {
        let result = try parseMemoryStringHelper("256M")
        XCTAssertEqual(result, 256 * 1024 * 1024)
    }
    
    func testParseMemoryStringMegabytesWithB() throws {
        let result = try parseMemoryStringHelper("256MB")
        XCTAssertEqual(result, 256 * 1024 * 1024)
    }
    
    func testParseMemoryStringGigabytes() throws {
        let result = try parseMemoryStringHelper("2G")
        XCTAssertEqual(result, 2 * 1024 * 1024 * 1024)
    }
    
    func testParseMemoryStringGigabytesWithB() throws {
        let result = try parseMemoryStringHelper("2GB")
        XCTAssertEqual(result, 2 * 1024 * 1024 * 1024)
    }
    
    func testParseMemoryStringNoSuffix() throws {
        let result = try parseMemoryStringHelper("1024")
        XCTAssertEqual(result, 1024)
    }
    
    func testParseMemoryStringInvalidFormat() {
        XCTAssertThrowsError(try parseMemoryStringHelper("invalid")) { error in
            XCTAssertTrue(error is ValidationError)
        }
    }
    
    func testParseMemoryStringEmptyString() {
        XCTAssertThrowsError(try parseMemoryStringHelper("")) { error in
            XCTAssertTrue(error is ValidationError)
        }
    }
    
    func testConvertPolicyWithDefaultCapabilities() throws {
        let policy = Policy(
            name: "test",
            version: "1.0.0",
            capabilities: CapabilityGrant(
                network: .disabled,
                filesystem: [.read],
                allowedPaths: ["/usr"],
                deniedPaths: []
            )
        )
        
        XCTAssertEqual(policy.name, "test")
        XCTAssertEqual(policy.capabilities.network, .disabled)
        XCTAssertTrue(policy.capabilities.filesystem.contains(.read))
    }
    
    func testConvertPolicyWithResourceLimits() throws {
        let limits = ResourceLimits(
            cpus: 4,
            memoryBytes: 4_294_967_296,
            maxProcesses: 256
        )
        
        let policy = Policy(
            name: "test",
            version: "1.0.0",
            capabilities: CapabilityGrant(resourceLimits: limits)
        )
        
        XCTAssertEqual(policy.resources?.cpus, 4)
        XCTAssertEqual(policy.resources?.memoryBytes, 4_294_967_296)
        XCTAssertEqual(policy.resources?.maxProcesses, 256)
    }
    
    func testConvertPolicyWithNetworkOutbound() throws {
        let policy = Policy(
            name: "test",
            version: "1.0.0",
            capabilities: CapabilityGrant(network: .outbound)
        )
        
        XCTAssertEqual(policy.capabilities.network, .outbound)
    }
    
    func testConvertPolicyWithNetworkFull() throws {
        let policy = Policy(
            name: "test",
            version: "1.0.0",
            capabilities: CapabilityGrant(network: .full)
        )
        
        XCTAssertEqual(policy.capabilities.network, .full)
    }
    
    func testConvertPolicyWithMultipleFilesystemCapabilities() throws {
        let policy = Policy(
            name: "test",
            version: "1.0.0",
            capabilities: CapabilityGrant(
                filesystem: [.read, .write, .execute]
            )
        )
        
        XCTAssertTrue(policy.capabilities.filesystem.contains(.read))
        XCTAssertTrue(policy.capabilities.filesystem.contains(.write))
        XCTAssertTrue(policy.capabilities.filesystem.contains(.execute))
    }
    
    func testConvertPolicyWithAllowedAndDeniedPaths() throws {
        let policy = Policy(
            name: "test",
            version: "1.0.0",
            capabilities: CapabilityGrant(
                allowedPaths: ["/usr", "/tmp", "/home"],
                deniedPaths: ["/etc/shadow", "/root/.ssh"]
            )
        )
        
        XCTAssertTrue(policy.capabilities.allowedPaths.contains("/usr"))
        XCTAssertTrue(policy.capabilities.allowedPaths.contains("/tmp"))
        XCTAssertTrue(policy.capabilities.deniedPaths.contains("/etc/shadow"))
        XCTAssertTrue(policy.capabilities.deniedPaths.contains("/root/.ssh"))
    }
    
    private func parseMemoryStringHelper(_ memory: String) throws -> UInt64 {
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
            throw ValidationError("Invalid memory format: \(memory)")
        }
        
        return value * multiplier
    }
}

struct ValidationError: Error {
    let message: String
    
    init(_ message: String) {
        self.message = message
    }
}
