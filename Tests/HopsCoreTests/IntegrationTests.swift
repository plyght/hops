import XCTest
@testable import HopsCore

final class IntegrationTests: XCTestCase {
    var parser: PolicyParser!
    var validator: PolicyValidator!
    
    override func setUp() {
        super.setUp()
        parser = PolicyParser()
        validator = PolicyValidator()
    }
    
    func testEndToEndParseAndValidate() throws {
        let toml = """
        name = "integration-test"
        version = "1.0.0"
        description = "End-to-end integration test"
        
        [capabilities]
        network = "outbound"
        filesystem = ["read", "write"]
        allowed_paths = ["/usr", "/tmp"]
        denied_paths = ["/etc/shadow"]
        
        [capabilities.resource_limits]
        cpus = 4
        memory_bytes = 2147483648
        max_processes = 128
        
        [sandbox]
        root_path = "/"
        hostname = "integration-sandbox"
        working_directory = "/tmp"
        
        [[sandbox.mounts]]
        source = "tmpfs"
        destination = "/tmp"
        type = "tmpfs"
        mode = "rw"
        
        [sandbox.environment]
        PATH = "/usr/bin"
        """
        
        let policy = try parser.parse(fromString: toml)
        XCTAssertNoThrow(try validator.validate(policy))
        
        XCTAssertEqual(policy.name, "integration-test")
        XCTAssertEqual(policy.capabilities.network, .outbound)
        XCTAssertTrue(policy.capabilities.allowedPaths.contains("/usr"))
    }
    
    func testEndToEndWithInvalidVersion() throws {
        let toml = """
        name = "bad-version"
        version = "invalid"
        
        [capabilities]
        network = "disabled"
        """
        
        let policy = try parser.parse(fromString: toml)
        
        XCTAssertThrowsError(try validator.validate(policy)) { error in
            if case PolicyValidationError.invalidVersion = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("Expected invalidVersion error")
            }
        }
    }
    
    func testEndToEndWithConflictingPaths() throws {
        let toml = """
        name = "conflicting-paths"
        version = "1.0.0"
        
        [capabilities]
        allowed_paths = ["/usr/local"]
        denied_paths = ["/usr"]
        """
        
        let policy = try parser.parse(fromString: toml)
        
        XCTAssertThrowsError(try validator.validate(policy)) { error in
            if case PolicyValidationError.conflictingPaths = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("Expected conflictingPaths error")
            }
        }
    }
    
    func testEndToEndWithResourceLimitExceeded() throws {
        let toml = """
        name = "resource-exceed"
        version = "1.0.0"
        
        [capabilities.resource_limits]
        cpus = 999
        """
        
        let policy = try parser.parse(fromString: toml)
        
        XCTAssertThrowsError(try validator.validate(policy)) { error in
            if case PolicyValidationError.resourceLimitTooHigh = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("Expected resourceLimitTooHigh error")
            }
        }
    }
    
    func testPolicyRoundTrip() throws {
        let originalTOML = """
        name = "roundtrip-test"
        version = "1.2.3"
        description = "Testing round-trip serialization"
        
        [capabilities]
        network = "loopback"
        filesystem = ["read", "execute"]
        allowed_paths = ["/usr", "/bin"]
        denied_paths = []
        
        [capabilities.resource_limits]
        cpus = 2
        memory_bytes = 1073741824
        max_processes = 64
        
        [sandbox]
        root_path = "/"
        hostname = "roundtrip"
        working_directory = "/"
        
        [[sandbox.mounts]]
        source = "tmpfs"
        destination = "/tmp"
        type = "tmpfs"
        mode = "rw"
        
        [sandbox.environment]
        PATH = "/usr/bin"
        HOME = "/root"
        
        [metadata]
        test = "value"
        """
        
        let policy = try parser.parse(fromString: originalTOML)
        XCTAssertNoThrow(try validator.validate(policy))
        
        XCTAssertEqual(policy.name, "roundtrip-test")
        XCTAssertEqual(policy.version, "1.2.3")
        XCTAssertEqual(policy.description, "Testing round-trip serialization")
        XCTAssertEqual(policy.capabilities.network, .loopback)
        XCTAssertEqual(policy.capabilities.filesystem, [.read, .execute])
        XCTAssertEqual(policy.capabilities.resourceLimits.cpus, 2)
        XCTAssertEqual(policy.sandbox.hostname, "roundtrip")
        XCTAssertEqual(policy.metadata["test"], "value")
    }
    
    func testErrorPropagationFromParser() throws {
        let toml = """
        name = "test"
        
        [capabilities]
        network = "invalid_value"
        """
        
        XCTAssertThrowsError(try parser.parse(fromString: toml)) { error in
            XCTAssertTrue(error is PolicyParserError)
            
            if case PolicyParserError.invalidFieldValue(let field, let reason) = error {
                XCTAssertEqual(field, "capabilities.network")
                XCTAssertTrue(reason.contains("invalid_value"))
            } else {
                XCTFail("Expected invalidFieldValue error")
            }
        }
    }
    
    func testErrorPropagationFromValidator() throws {
        let toml = """
        name = ""
        version = "1.0.0"
        """
        
        let policy = try parser.parse(fromString: toml)
        
        XCTAssertThrowsError(try validator.validate(policy)) { error in
            XCTAssertTrue(error is PolicyValidationError)
            
            if case PolicyValidationError.emptyName = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("Expected emptyName error")
            }
        }
    }
    
    func testLoadFromTOMLFileIntegration() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test_integration.toml")
        
        let content = """
        name = "test-full"
        version = "2.1.3"
        description = "Full featured test policy"
        
        [capabilities]
        network = "outbound"
        filesystem = ["read", "write"]
        allowed_paths = ["/usr", "/tmp"]
        denied_paths = []
        
        [capabilities.resource_limits]
        cpus = 4
        memory_bytes = 2147483648
        max_processes = 256
        
        [sandbox]
        root_path = "/"
        hostname = "test-sandbox"
        working_directory = "/tmp"
        """
        
        try content.write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }
        
        let policy = try Policy.load(fromTOMLFile: testFile.path)
        XCTAssertNoThrow(try validator.validate(policy))
        
        XCTAssertEqual(policy.name, "test-full")
        XCTAssertEqual(policy.version, "2.1.3")
    }
    
    func testComplexPolicyWithAllFeatures() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testMount = tempDir.appendingPathComponent("integration_mount").path
        try FileManager.default.createDirectory(atPath: testMount, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: testMount) }
        
        let toml = """
        name = "complex-policy"
        version = "3.2.1"
        description = "Complex policy with all features enabled"
        
        [capabilities]
        network = "full"
        filesystem = ["read", "write", "execute"]
        allowed_paths = ["/usr", "/bin", "/lib", "/tmp"]
        denied_paths = []
        
        [capabilities.resource_limits]
        cpus = 8
        memory_bytes = 4294967296
        max_processes = 512
        
        [sandbox]
        root_path = "/"
        hostname = "complex-sandbox"
        working_directory = "/work"
        
        [[sandbox.mounts]]
        source = "\(testMount)"
        destination = "/mnt/data"
        type = "bind"
        mode = "rw"
        
        [[sandbox.mounts]]
        source = "tmpfs"
        destination = "/tmp"
        type = "tmpfs"
        mode = "rw"
        options = ["size=500m", "noexec"]
        
        [sandbox.environment]
        PATH = "/usr/bin:/bin:/usr/local/bin"
        HOME = "/root"
        USER = "sandbox"
        LANG = "en_US.UTF-8"
        
        [metadata]
        author = "integration-test"
        version_control = "git"
        """
        
        let policy = try parser.parse(fromString: toml)
        XCTAssertNoThrow(try validator.validate(policy))
        
        XCTAssertEqual(policy.name, "complex-policy")
        XCTAssertEqual(policy.capabilities.network, .full)
        XCTAssertEqual(policy.capabilities.filesystem.count, 3)
        XCTAssertEqual(policy.sandbox.mounts.count, 2)
        XCTAssertEqual(policy.sandbox.environment.count, 4)
    }
    
    func testDefaultPolicyValidatesBasicFields() throws {
        let policy = Policy.default
        XCTAssertEqual(policy.name, "default")
        XCTAssertEqual(policy.version, "1.0.0")
    }
    
    func testParserAndValidatorWithMinimalConfig() throws {
        let toml = """
        name = "minimal"
        """
        
        let policy = try parser.parse(fromString: toml)
        XCTAssertEqual(policy.name, "minimal")
        XCTAssertEqual(policy.version, "1.0.0")
    }
    
    func testMultipleValidationErrors() throws {
        let toml = """
        name = ""
        version = "invalid-version"
        
        [capabilities]
        allowed_paths = ["relative/path"]
        
        [capabilities.resource_limits]
        cpus = 9999
        
        [sandbox]
        root_path = "not-absolute"
        """
        
        let policy = try parser.parse(fromString: toml)
        
        XCTAssertThrowsError(try validator.validate(policy)) { error in
            XCTAssertTrue(error is PolicyValidationError)
        }
    }
}
