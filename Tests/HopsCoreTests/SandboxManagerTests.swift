import XCTest

@testable import HopsCore

final class SandboxManagerTests: XCTestCase {

  func testSandboxStatusInitialization() {
    let status = SandboxStatus(
      id: "test-123",
      state: "running",
      exitCode: nil,
      startedAt: Date(),
      finishedAt: nil
    )

    XCTAssertEqual(status.id, "test-123")
    XCTAssertEqual(status.state, "running")
    XCTAssertNil(status.exitCode)
    XCTAssertNotNil(status.startedAt)
    XCTAssertNil(status.finishedAt)
  }

  func testSandboxStatusWithExitCode() {
    let status = SandboxStatus(
      id: "test-456",
      state: "stopped",
      exitCode: 0,
      startedAt: Date(),
      finishedAt: Date()
    )

    XCTAssertEqual(status.id, "test-456")
    XCTAssertEqual(status.state, "stopped")
    XCTAssertEqual(status.exitCode, 0)
    XCTAssertNotNil(status.finishedAt)
  }

  func testSandboxStatusWithNonZeroExitCode() {
    let status = SandboxStatus(
      id: "test-789",
      state: "stopped",
      exitCode: 127,
      startedAt: Date(),
      finishedAt: Date()
    )

    XCTAssertEqual(status.exitCode, 127)
  }

  func testSandboxInfoInitialization() {
    let info = SandboxInfo(
      id: "sandbox-1",
      policyName: "default",
      state: "running",
      startedAt: Date()
    )

    XCTAssertEqual(info.id, "sandbox-1")
    XCTAssertEqual(info.policyName, "default")
    XCTAssertEqual(info.state, "running")
    XCTAssertNotNil(info.startedAt)
  }

  func testSandboxInfoWithStoppedState() {
    let info = SandboxInfo(
      id: "sandbox-2",
      policyName: "restrictive",
      state: "stopped",
      startedAt: Date()
    )

    XCTAssertEqual(info.state, "stopped")
    XCTAssertEqual(info.policyName, "restrictive")
  }

  func testStreamingOutputChunkStdout() {
    let data = Data("Hello, World!".utf8)
    let chunk = StreamingOutputChunk(
      sandboxId: "test-1",
      type: .stdout,
      data: data,
      timestamp: 1000,
      exitCode: nil
    )

    XCTAssertEqual(chunk.sandboxId, "test-1")
    XCTAssertEqual(chunk.type, .stdout)
    XCTAssertEqual(chunk.data, data)
    XCTAssertEqual(chunk.timestamp, 1000)
    XCTAssertNil(chunk.exitCode)
  }

  func testStreamingOutputChunkStderr() {
    let data = Data("Error message".utf8)
    let chunk = StreamingOutputChunk(
      sandboxId: "test-2",
      type: .stderr,
      data: data,
      timestamp: 2000,
      exitCode: nil
    )

    XCTAssertEqual(chunk.type, .stderr)
    XCTAssertEqual(chunk.data, data)
  }

  func testStreamingOutputChunkExit() {
    let chunk = StreamingOutputChunk(
      sandboxId: "test-3",
      type: .exit,
      data: Data(),
      timestamp: 3000,
      exitCode: 0
    )

    XCTAssertEqual(chunk.type, .exit)
    XCTAssertEqual(chunk.exitCode, 0)
  }

  func testStreamingOutputChunkExitWithNonZeroCode() {
    let chunk = StreamingOutputChunk(
      sandboxId: "test-4",
      type: .exit,
      data: Data(),
      timestamp: 4000,
      exitCode: 1
    )

    XCTAssertEqual(chunk.exitCode, 1)
  }

  func testSandboxManagerErrorVmmNotInitialized() {
    let error = SandboxManagerError.vmmNotInitialized
    XCTAssertNotNil(error)
  }

  func testSandboxManagerErrorContainerAlreadyExists() {
    let error = SandboxManagerError.containerAlreadyExists("test-id")
    XCTAssertNotNil(error)
  }

  func testSandboxManagerErrorContainerNotFound() {
    let error = SandboxManagerError.containerNotFound("missing-id")
    XCTAssertNotNil(error)
  }

  func testSandboxManagerErrorMissingKernel() {
    let error = SandboxManagerError.missingKernel("/path/to/vmlinux")
    XCTAssertNotNil(error)
  }

  func testSandboxManagerErrorMissingInitfs() {
    let error = SandboxManagerError.missingInitfs("/path/to/initfs")
    XCTAssertNotNil(error)
  }

  func testStreamingOutputTypeStdout() {
    let type = StreamingOutputType.stdout
    XCTAssertEqual(type, .stdout)
  }

  func testStreamingOutputTypeStderr() {
    let type = StreamingOutputType.stderr
    XCTAssertEqual(type, .stderr)
  }

  func testStreamingOutputTypeExit() {
    let type = StreamingOutputType.exit
    XCTAssertEqual(type, .exit)
  }
}

public struct SandboxStatus: Codable, Sendable {
  public let id: String
  public let state: String
  public let exitCode: Int?
  public let startedAt: Date?
  public let finishedAt: Date?

  public init(id: String, state: String, exitCode: Int?, startedAt: Date?, finishedAt: Date?) {
    self.id = id
    self.state = state
    self.exitCode = exitCode
    self.startedAt = startedAt
    self.finishedAt = finishedAt
  }
}

public struct SandboxInfo: Codable, Sendable {
  public let id: String
  public let policyName: String
  public let state: String
  public let startedAt: Date?

  public init(id: String, policyName: String, state: String, startedAt: Date?) {
    self.id = id
    self.policyName = policyName
    self.state = state
    self.startedAt = startedAt
  }
}

enum StreamingOutputType: Sendable {
  case stdout
  case stderr
  case exit
}

struct StreamingOutputChunk: Sendable {
  let sandboxId: String
  let type: StreamingOutputType
  let data: Data
  let timestamp: Int64
  let exitCode: Int32?
}

enum SandboxManagerError: Error {
  case vmmNotInitialized
  case containerAlreadyExists(String)
  case containerNotFound(String)
  case missingKernel(String)
  case missingInitfs(String)
}
